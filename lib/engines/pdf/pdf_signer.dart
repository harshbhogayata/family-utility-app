import 'dart:io' show ZLibCodec;
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import 'pdf_compressor.dart';

/// Feature 010 — Sign PDF.
///
/// Signatures, initials and date stamps are transparent PNGs. Placing one
/// records where it sits on a page (in 0–1 units, top-left origin) and its
/// rotation. [PdfSigner.sign] draws each one into the page content itself, so
/// the result is flat: there is no annotation for the receiver to move.

enum StampKind { signature, initials, date }

@immutable
class StrokePoint {
  const StrokePoint(this.x, this.y);

  /// 0–1 units of the drawing pad.
  final double x;
  final double y;
}

/// One stamp on one page.
@immutable
class Placement {
  const Placement({
    required this.page,
    required this.png,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    this.rotation = 0,
  });

  /// 0-based page index.
  final int page;
  final Uint8List png;

  /// 0–1 units of the page, top-left origin.
  final double left;
  final double top;
  final double width;
  final double height;

  /// Clockwise degrees.
  final double rotation;

  Placement copyWith({double? left, double? top, double? width, double? height, double? rotation}) {
    return Placement(
      page: page,
      png: png,
      left: left ?? this.left,
      top: top ?? this.top,
      width: width ?? this.width,
      height: height ?? this.height,
      rotation: rotation ?? this.rotation,
    );
  }
}

@immutable
class PageBox {
  const PageBox(this.x0, this.y0, this.x1, this.y1);
  final double x0;
  final double y0;
  final double x1;
  final double y1;

  double get width => x1 - x0;
  double get height => y1 - y0;
}

class SignError implements Exception {
  const SignError(this.message);
  final String message;

  @override
  String toString() => message;
}

abstract final class SignatureArt {
  static const int padWidth = 600;
  static const int padHeight = 240;

  /// Turns finger strokes into a transparent PNG with dark ink, trimmed.
  static Uint8List fromStrokes(List<List<StrokePoint>> strokes, {int width = padWidth, int height = padHeight}) {
    if (strokes.every((List<StrokePoint> s) => s.isEmpty)) {
      throw const SignError('Draw a signature first');
    }
    final img.Image im = img.Image(width: width, height: height, numChannels: 4);
    final img.Color ink = img.ColorRgba8(18, 24, 64, 255);
    const int r = 3;
    for (final List<StrokePoint> s in strokes) {
      for (int i = 0; i < s.length; i++) {
        final int x = (s[i].x * (width - 1)).round();
        final int y = (s[i].y * (height - 1)).round();
        img.fillCircle(im, x: x, y: y, radius: r, color: ink);
        if (i > 0) {
          final int px = (s[i - 1].x * (width - 1)).round();
          final int py = (s[i - 1].y * (height - 1)).round();
          img.drawLine(im, x1: px, y1: py, x2: x, y2: y, color: ink, thickness: r * 2);
        }
      }
    }
    return img.encodePng(trim(im));
  }

  /// Makes an imported image usable as a stamp: near-white becomes
  /// transparent when the picture has no transparency of its own; trimmed.
  static Uint8List fromImport(Uint8List bytes) {
    final img.Image? decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw const SignError('This file is not a PNG or JPG image');
    }
    img.Image im = decoded.convert(numChannels: 4, alpha: decoded.maxChannelValue);
    if (!_hasTransparency(im)) {
      for (final img.Pixel p in im) {
        if (p.rNormalized > 0.92 && p.gNormalized > 0.92 && p.bNormalized > 0.92) {
          p.a = 0;
        }
      }
    }
    im = trim(im);
    final int longest = math.max(im.width, im.height);
    if (longest > 1200) {
      im = im.width >= im.height ? img.copyResize(im, width: 1200) : img.copyResize(im, height: 1200);
    }
    return img.encodePng(im);
  }

  static bool _hasTransparency(img.Image im) {
    for (final img.Pixel p in im) {
      if (p.a < p.maxChannelValue) {
        return true;
      }
    }
    return false;
  }

  /// Crops away fully transparent borders, keeping a small margin.
  static img.Image trim(img.Image im) {
    int minX = im.width, minY = im.height, maxX = -1, maxY = -1;
    for (final img.Pixel p in im) {
      if (p.a > 0) {
        if (p.x < minX) minX = p.x;
        if (p.y < minY) minY = p.y;
        if (p.x > maxX) maxX = p.x;
        if (p.y > maxY) maxY = p.y;
      }
    }
    if (maxX < 0) {
      return im;
    }
    const int m = 4;
    final int x = math.max(0, minX - m);
    final int y = math.max(0, minY - m);
    return img.copyCrop(
      im,
      x: x,
      y: y,
      width: math.min(im.width, maxX + m + 1) - x,
      height: math.min(im.height, maxY + m + 1) - y,
    );
  }

  /// Width over height of a stamp PNG.
  static double aspect(Uint8List png) {
    final img.Image? d = img.decodePng(png);
    return d == null || d.height == 0 ? 3 : d.width / d.height;
  }
}

abstract final class PdfSigner {
  static final ZLibCodec _deflate = ZLibCodec(level: 6);

  /// Page boxes in order. Throws [SignError] for files it cannot read.
  static List<PageBox> pages(Uint8List pdf) {
    final PdfDocumentModel doc = _parse(pdf);
    return _pages(doc).map((_Page p) => p.box).toList();
  }

  /// Draws every placement into its page and returns the new, flat PDF.
  static Uint8List sign(Uint8List pdf, List<Placement> placements) {
    if (placements.isEmpty) {
      throw const SignError('Place a signature first');
    }
    final PdfDocumentModel doc = _parse(pdf);
    final List<_Page> pages = _pages(doc);
    int next = doc.objects.keys.fold<int>(0, math.max) + 1;
    int stampNo = 0;

    final Map<int, List<Placement>> byPage = <int, List<Placement>>{};
    for (final Placement p in placements) {
      if (p.page < 0 || p.page >= pages.length) {
        throw SignError('Page ${p.page + 1} does not exist');
      }
      byPage.putIfAbsent(p.page, () => <Placement>[]).add(p);
    }

    final Map<Uint8List, int> imageObjects = <Uint8List, int>{};
    byPage.forEach((int index, List<Placement> list) {
      final _Page page = pages[index];
      final PdfDict pageDict = page.obj.value as PdfDict;

      // Resources: copy so shared dictionaries on other pages stay untouched.
      final Object? res = doc.resolve(pageDict['Resources']) ?? page.inheritedResources;
      final PdfDict resources = PdfDict(res is PdfDict ? Map<String, Object>.of(res.entries) : <String, Object>{});
      final Object? xo = doc.resolve(resources['XObject']);
      final PdfDict xobjects = PdfDict(xo is PdfDict ? Map<String, Object>.of(xo.entries) : <String, Object>{});

      final StringBuffer ops = StringBuffer('Q\n');
      for (final Placement p in list) {
        final int imageNum = imageObjects.putIfAbsent(p.png, () {
          final int n = next;
          next = _addImage(doc, n, p.png);
          return n;
        });
        String name;
        do {
          stampNo++;
          name = 'FuaSig$stampNo';
        } while (xobjects.entries.containsKey(name));
        xobjects.entries[name] = PdfRef(imageNum, 0);
        ops.write('q ${matrix(p, page.box).map(_n).join(' ')} cm /$name Do Q\n');
      }
      resources.entries['XObject'] = xobjects;
      pageDict.entries['Resources'] = resources;

      final int pushNum = next++;
      doc.objects[pushNum] = PdfObject(pushNum, 0, PdfDict(<String, Object>{}),
          stream: Uint8List.fromList('q\n'.codeUnits));
      final int stampNum = next++;
      doc.objects[stampNum] = PdfObject(stampNum, 0, PdfDict(<String, Object>{}),
          stream: Uint8List.fromList(ops.toString().codeUnits));

      final Object? old = pageDict['Contents'];
      final List<Object> contents = <Object>[PdfRef(pushNum, 0)];
      if (old is PdfArray) {
        contents.addAll(old.items);
      } else {
        final Object? resolvedOld = doc.resolve(old);
        if (resolvedOld is PdfArray) {
          contents.addAll(resolvedOld.items);
        } else if (old != null) {
          contents.add(old);
        }
      }
      contents.add(PdfRef(stampNum, 0));
      pageDict.entries['Contents'] = PdfArray(contents);
    });
    return doc.write();
  }

  /// The `cm` matrix that maps the image's unit square onto the placement.
  static List<double> matrix(Placement p, PageBox box) {
    final double w = p.width * box.width;
    final double h = p.height * box.height;
    final double cx = box.x0 + (p.left + p.width / 2) * box.width;
    final double cy = box.y1 - (p.top + p.height / 2) * box.height;
    final double t = p.rotation * math.pi / 180;
    final double a = w * math.cos(t);
    final double b = -w * math.sin(t);
    final double c = h * math.sin(t);
    final double d = h * math.cos(t);
    return <double>[a, b, c, d, cx - (a + c) / 2, cy - (b + d) / 2];
  }

  static String _n(double v) {
    final String s = v.toStringAsFixed(4);
    return s == '-0.0000' ? '0' : s;
  }

  /// Adds an RGB image with a soft mask. Returns the next free number.
  static int _addImage(PdfDocumentModel doc, int n, Uint8List png) {
    final img.Image? decoded = img.decodePng(png);
    if (decoded == null) {
      throw const SignError('A stamp image could not be read');
    }
    final img.Image im = decoded.convert(numChannels: 4, alpha: decoded.maxChannelValue, format: img.Format.uint8);
    final Uint8List rgb = Uint8List(im.width * im.height * 3);
    final Uint8List alpha = Uint8List(im.width * im.height);
    int i = 0;
    for (final img.Pixel p in im) {
      rgb[i * 3] = p.r.toInt();
      rgb[i * 3 + 1] = p.g.toInt();
      rgb[i * 3 + 2] = p.b.toInt();
      alpha[i] = p.a.toInt();
      i++;
    }
    final int maskNum = n + 1;
    Map<String, Object> common(String space) => <String, Object>{
          'Type': const PdfName('XObject'),
          'Subtype': const PdfName('Image'),
          'Width': PdfNum('${im.width}'),
          'Height': PdfNum('${im.height}'),
          'ColorSpace': PdfName(space),
          'BitsPerComponent': const PdfNum('8'),
          'Filter': const PdfName('FlateDecode'),
        };
    doc.objects[n] = PdfObject(n, 0, PdfDict(common('DeviceRGB')..['SMask'] = PdfRef(maskNum, 0)),
        stream: Uint8List.fromList(_deflate.encode(rgb)));
    doc.objects[maskNum] = PdfObject(maskNum, 0, PdfDict(common('DeviceGray')),
        stream: Uint8List.fromList(_deflate.encode(alpha)));
    return maskNum + 1;
  }

  static PdfDocumentModel _parse(Uint8List pdf) {
    try {
      return PdfDocumentModel.parse(pdf);
    } on PdfCompressError catch (e) {
      throw SignError(e.message);
    }
  }

  static List<_Page> _pages(PdfDocumentModel doc) {
    final Object? root = doc.resolve(doc.trailer['Root']);
    if (root is! PdfDict) {
      throw const SignError('This PDF has no pages');
    }
    final List<_Page> out = <_Page>[];
    void walk(Object? node, PageBox? box, Object? res, int depth) {
      if (depth > 64 || node is! PdfRef) {
        return;
      }
      final PdfObject? obj = doc.objects[node.num];
      final Object? v = obj?.value;
      if (obj == null || v is! PdfDict) {
        return;
      }
      final PageBox? ownBox = _box(doc.resolve(v['MediaBox']));
      final PageBox? useBox = ownBox ?? box;
      final Object? useRes = doc.resolve(v['Resources']) ?? res;
      if (v.name('Type') == 'Page' || (v['Kids'] == null && v['Contents'] != null)) {
        out.add(_Page(obj, useBox ?? const PageBox(0, 0, 612, 792), useRes));
        return;
      }
      final Object? kids = doc.resolve(v['Kids']);
      if (kids is PdfArray) {
        for (final Object k in kids.items) {
          walk(k, useBox, useRes, depth + 1);
        }
      }
    }

    final Object? pagesRef = root['Pages'];
    walk(pagesRef, null, null, 0);
    if (out.isEmpty) {
      throw const SignError('This PDF has no pages');
    }
    return out;
  }

  static PageBox? _box(Object? v) {
    if (v is! PdfArray || v.items.length != 4) {
      return null;
    }
    final List<double> n = v.items.map((Object o) => o is PdfNum ? o.value.toDouble() : 0.0).toList();
    return PageBox(math.min(n[0], n[2]), math.min(n[1], n[3]), math.max(n[0], n[2]), math.max(n[1], n[3]));
  }
}

class _Page {
  _Page(this.obj, this.box, this.inheritedResources);
  final PdfObject obj;
  final PageBox box;
  final Object? inheritedResources;
}
