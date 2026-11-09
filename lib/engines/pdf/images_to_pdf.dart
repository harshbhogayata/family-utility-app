import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

import '../convert/convert_registry.dart';
import '../convert/file_kind.dart';

/// Feature 021 — Images to PDF.
///
/// Any images into one PDF, one per page, with page size, orientation and
/// margins. JPEGs go in as they are (DCTDecode, no re-encode), which keeps
/// 20 phone photos well under two seconds; other formats are decoded once
/// and written as JPEG. HEIC goes through the phone's own decoder.

enum PdfPageSize {
  a4('A4', 595.28, 841.89),
  letter('Letter', 612, 792),
  fit('Fit to image', 0, 0);

  const PdfPageSize(this.label, this.width, this.height);
  final String label;
  final double width;
  final double height;
}

enum PdfOrientation {
  auto('Auto'),
  portrait('Portrait'),
  landscape('Landscape');

  const PdfOrientation(this.label);
  final String label;
}

class ImagesToPdfOptions {
  const ImagesToPdfOptions({
    this.pageSize = PdfPageSize.a4,
    this.orientation = PdfOrientation.auto,
    this.marginPt = 24,
    this.jpegQuality = 88,
  });

  final PdfPageSize pageSize;
  final PdfOrientation orientation;

  /// Margin on every side, in points (72 per inch).
  final double marginPt;
  final int jpegQuality;
}

/// Decodes HEIC with the phone's own codec; returns JPEG bytes, or null when
/// the phone has none.
abstract class HeicDecoder {
  Future<Uint8List?> toJpeg(Uint8List heic);
}

class ChannelHeicDecoder implements HeicDecoder {
  const ChannelHeicDecoder();

  static const MethodChannel _channel = MethodChannel('app.family/heic');

  @override
  Future<Uint8List?> toJpeg(Uint8List heic) async {
    try {
      return await _channel.invokeMethod<Uint8List>('toJpeg', <String, Object?>{'bytes': heic});
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }
}

/// A JPEG ready to embed: its bytes and pixel size.
class PreparedImage {
  const PreparedImage({required this.jpeg, required this.width, required this.height, required this.components});

  final Uint8List jpeg;
  final int width;
  final int height;
  final int components;
}

/// Size and colour components from a JPEG's SOF marker; null if not found.
({int width, int height, int components})? jpegInfo(Uint8List b) {
  int i = 2;
  while (i + 9 < b.length) {
    if (b[i] != 0xFF) {
      i++;
      continue;
    }
    final int marker = b[i + 1];
    if (marker == 0xD8 || marker == 0x01 || (marker >= 0xD0 && marker <= 0xD7) || marker == 0xFF) {
      i += marker == 0xFF ? 1 : 2;
      continue;
    }
    final int len = (b[i + 2] << 8) | b[i + 3];
    final bool sof = marker >= 0xC0 && marker <= 0xCF && marker != 0xC4 && marker != 0xC8 && marker != 0xCC;
    if (sof) {
      return (
        height: (b[i + 5] << 8) | b[i + 6],
        width: (b[i + 7] << 8) | b[i + 8],
        components: b[i + 9],
      );
    }
    i += 2 + len;
  }
  return null;
}

/// EXIF orientation (1–8) of a JPEG; 1 when absent.
int jpegOrientation(Uint8List b) {
  int i = 2;
  while (i + 4 < b.length && b[i] == 0xFF) {
    final int marker = b[i + 1];
    final int len = (b[i + 2] << 8) | b[i + 3];
    if (marker == 0xDA) {
      break;
    }
    if (marker == 0xE1 && i + 10 < b.length && latin1.decode(b.sublist(i + 4, i + 8)) == 'Exif') {
      final int t = i + 10;
      if (t + 8 > b.length) {
        return 1;
      }
      final bool le = b[t] == 0x49;
      int u16(int o) => le ? b[o] | (b[o + 1] << 8) : (b[o] << 8) | b[o + 1];
      int u32(int o) => le
          ? b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24)
          : (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];
      final int ifd = t + u32(t + 4);
      if (ifd + 2 > b.length) {
        return 1;
      }
      final int n = u16(ifd);
      for (int k = 0; k < n; k++) {
        final int e = ifd + 2 + k * 12;
        if (e + 12 > b.length) {
          break;
        }
        if (u16(e) == 0x0112) {
          final int v = u16(e + 8);
          return v >= 1 && v <= 8 ? v : 1;
        }
      }
      return 1;
    }
    i += 2 + len;
  }
  return 1;
}

class ImagesToPdf {
  ImagesToPdf({this.heic = const ChannelHeicDecoder()});

  final HeicDecoder heic;

  /// Turns any supported image into an embeddable JPEG.
  Future<PreparedImage> prepare(Uint8List bytes, {int jpegQuality = 88}) async {
    final FileKind kind = sniffFileKind(bytes);
    Uint8List source = bytes;
    if (kind == FileKind.heic) {
      final Uint8List? jpeg = await heic.toJpeg(bytes);
      if (jpeg == null) {
        throw const ConvertException('This phone cannot read HEIC photos. Nothing was uploaded.');
      }
      source = jpeg;
    } else if (!kind.isImage) {
      throw ConvertException('${kind.label} is not an image.');
    }
    if (sniffFileKind(source) == FileKind.jpeg && jpegOrientation(source) == 1) {
      final ({int width, int height, int components})? info = jpegInfo(source);
      if (info != null && (info.components == 1 || info.components == 3)) {
        return PreparedImage(jpeg: source, width: info.width, height: info.height, components: info.components);
      }
    }
    final img.Image? decoded = img.decodeImage(source);
    if (decoded == null) {
      throw const ConvertException('One of the images could not be read.');
    }
    img.Image im = img.bakeOrientation(decoded);
    if (im.hasAlpha) {
      final img.Image bg = img.Image(width: im.width, height: im.height);
      img.fill(bg, color: img.ColorRgb8(255, 255, 255));
      im = img.compositeImage(bg, im);
    }
    final Uint8List jpeg = img.encodeJpg(im, quality: jpegQuality);
    return PreparedImage(jpeg: jpeg, width: im.width, height: im.height, components: 3);
  }

  /// One page per image, in the order given.
  Future<Uint8List> build(List<Uint8List> images, ImagesToPdfOptions o) async {
    if (images.isEmpty) {
      throw const ConvertException('Add at least one image.');
    }
    final List<PreparedImage> prepared = <PreparedImage>[
      for (final Uint8List b in images) await prepare(b, jpegQuality: o.jpegQuality),
    ];
    return writePdf(prepared, o);
  }

  /// Page size for an image of [w]×[h] pixels.
  static (double, double) pageFor(int w, int h, ImagesToPdfOptions o) {
    if (o.pageSize == PdfPageSize.fit) {
      // 96 px per inch, plus the margins.
      return (w * 0.75 + 2 * o.marginPt, h * 0.75 + 2 * o.marginPt);
    }
    final double a = o.pageSize.width;
    final double b = o.pageSize.height;
    final bool landscape = switch (o.orientation) {
      PdfOrientation.landscape => true,
      PdfOrientation.portrait => false,
      PdfOrientation.auto => w > h,
    };
    return landscape ? (b, a) : (a, b);
  }

  static String _n(double v) => v.toStringAsFixed(2);

  static Uint8List writePdf(List<PreparedImage> pages, ImagesToPdfOptions o) {
    final BytesBuilder out = BytesBuilder(copy: false);
    final List<int> offsets = <int>[];
    void add(String s) => out.add(latin1.encode(s));
    void obj(int id, void Function() body) {
      offsets.add(out.length);
      add('$id 0 obj\n');
      body();
      add('\nendobj\n');
    }

    add('%PDF-1.4\n');
    out.add(const <int>[0x25, 0xE2, 0xE3, 0xCF, 0xD3, 0x0A]);
    final int count = pages.length;
    // 1 catalog, 2 pages, then per page: page, image, contents.
    final String kids = <String>[for (int i = 0; i < count; i++) '${3 + i * 3} 0 R'].join(' ');
    obj(1, () => add('<< /Type /Catalog /Pages 2 0 R >>'));
    obj(2, () => add('<< /Type /Pages /Kids [$kids] /Count $count >>'));
    for (int i = 0; i < count; i++) {
      final PreparedImage p = pages[i];
      final int pageId = 3 + i * 3;
      final (double pw, double ph) = pageFor(p.width, p.height, o);
      final double boxW = pw - 2 * o.marginPt;
      final double boxH = ph - 2 * o.marginPt;
      final double scale = (boxW / p.width) < (boxH / p.height) ? boxW / p.width : boxH / p.height;
      final double dw = p.width * scale;
      final double dh = p.height * scale;
      final double x = o.marginPt + (boxW - dw) / 2;
      final double y = o.marginPt + (boxH - dh) / 2;
      final String content = 'q ${_n(dw)} 0 0 ${_n(dh)} ${_n(x)} ${_n(y)} cm /Im0 Do Q';
      obj(pageId, () => add('<< /Type /Page /Parent 2 0 R /MediaBox [0 0 ${_n(pw)} ${_n(ph)}] '
          '/Resources << /XObject << /Im0 ${pageId + 1} 0 R >> >> /Contents ${pageId + 2} 0 R >>'));
      obj(pageId + 1, () {
        add('<< /Type /XObject /Subtype /Image /Width ${p.width} /Height ${p.height} '
            '/ColorSpace ${p.components == 1 ? '/DeviceGray' : '/DeviceRGB'} /BitsPerComponent 8 '
            '/Filter /DCTDecode /Length ${p.jpeg.length} >>\nstream\n');
        out.add(p.jpeg);
        add('\nendstream');
      });
      obj(pageId + 2, () => add('<< /Length ${content.length} >>\nstream\n$content\nendstream'));
    }
    final int xref = out.length;
    final int size = offsets.length + 1;
    final StringBuffer x = StringBuffer('xref\n0 $size\n0000000000 65535 f \n');
    for (final int off in offsets) {
      x.write('${off.toString().padLeft(10, '0')} 00000 n \n');
    }
    x.write('trailer\n<< /Size $size /Root 1 0 R >>\nstartxref\n$xref\n%%EOF\n');
    add(x.toString());
    return out.takeBytes();
  }
}
