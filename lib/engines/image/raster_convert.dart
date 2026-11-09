import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Feature 027 — Raster any to any. PNG, JPG, GIF, BMP and TIFF in any
/// direction, pure Dart on the phone. A multi-page TIFF becomes one picture
/// per page. Nothing leaves the phone.

enum RasterFormat {
  png('PNG', 'png', lossy: false, keepsAlpha: true),
  jpg('JPG', 'jpg', lossy: true, keepsAlpha: false),
  gif('GIF', 'gif', lossy: false, keepsAlpha: false),
  bmp('BMP', 'bmp', lossy: false, keepsAlpha: false),
  tiff('TIFF', 'tiff', lossy: false, keepsAlpha: true);

  const RasterFormat(this.label, this.extension, {required this.lossy, required this.keepsAlpha});
  final String label;
  final String extension;

  /// True when a quality setting changes the output.
  final bool lossy;

  /// True when see-through parts survive in this format.
  final bool keepsAlpha;

  /// File extensions the picker accepts.
  static const List<String> readable = <String>['png', 'jpg', 'jpeg', 'gif', 'bmp', 'tif', 'tiff', 'webp'];

  /// The format a file name points at, or null.
  static RasterFormat? fromName(String name) {
    final int dot = name.lastIndexOf('.');
    if (dot < 0) {
      return null;
    }
    final String ext = name.substring(dot + 1).toLowerCase();
    switch (ext) {
      case 'png':
        return RasterFormat.png;
      case 'jpg':
      case 'jpeg':
        return RasterFormat.jpg;
      case 'gif':
        return RasterFormat.gif;
      case 'bmp':
        return RasterFormat.bmp;
      case 'tif':
      case 'tiff':
        return RasterFormat.tiff;
    }
    return null;
  }
}

class RasterConvertError implements Exception {
  const RasterConvertError(this.message);
  final String message;
  @override
  String toString() => message;
}

class RasterPage {
  const RasterPage(this.name, this.bytes);
  final String name;
  final Uint8List bytes;
}

class RasterResult {
  const RasterResult(this.pages, {required this.hadAlpha, required this.keptAlpha});

  /// One entry per output picture; several for a multi-page TIFF.
  final List<RasterPage> pages;
  final bool hadAlpha;
  final bool keptAlpha;
}

class RasterConverter {
  const RasterConverter();

  static const int defaultQuality = 85;

  /// A sensible target: JPG for photos, PNG for everything else.
  static RasterFormat defaultTarget(String name) {
    final RasterFormat? from = RasterFormat.fromName(name);
    return from == RasterFormat.jpg ? RasterFormat.png : RasterFormat.jpg;
  }

  static bool _isTiff(Uint8List b) =>
      b.length > 4 &&
      ((b[0] == 0x49 && b[1] == 0x49 && b[2] == 0x2A && b[3] == 0x00) ||
          (b[0] == 0x4D && b[1] == 0x4D && b[2] == 0x00 && b[3] == 0x2A));

  /// Every page of the input, each a plain 8-bit RGBA picture.
  static List<img.Image> pagesOf(Uint8List input) {
    final List<img.Image> pages = <img.Image>[];
    if (_isTiff(input)) {
      final img.Image? tiff = img.decodeTiff(input);
      if (tiff == null) {
        throw const RasterConvertError('This TIFF could not be read');
      }
      final List<img.Image> frames = tiff.frames;
      if (frames.isEmpty) {
        pages.add(_rgba(tiff));
      } else {
        for (final img.Image f in frames) {
          pages.add(_rgba(f));
        }
      }
      return pages;
    }
    final img.Image? decoded = img.decodeImage(input);
    if (decoded == null) {
      throw const RasterConvertError('This file is not a picture the app can read');
    }
    pages.add(_rgba(img.bakeOrientation(decoded)));
    return pages;
  }

  /// Copies any bit depth or palette into 8-bit RGBA.
  static img.Image _rgba(img.Image src) {
    final img.Image out = img.Image(width: src.width, height: src.height, numChannels: 4);
    for (final img.Pixel p in src) {
      out.setPixelRgba(
        p.x,
        p.y,
        (p.rNormalized * 255).round(),
        (p.gNormalized * 255).round(),
        (p.bNormalized * 255).round(),
        src.hasAlpha ? (p.aNormalized * 255).round() : 255,
      );
    }
    return out;
  }

  static bool _hasAlpha(img.Image im) {
    for (final img.Pixel p in im) {
      if (p.a < 255) {
        return true;
      }
    }
    return false;
  }

  static img.Image _flatten(img.Image src) {
    final img.Image flat = img.Image(width: src.width, height: src.height);
    img.fill(flat, color: img.ColorRgb8(255, 255, 255));
    img.compositeImage(flat, src);
    return flat;
  }

  static Uint8List encode(img.Image page, RasterFormat target, {int quality = defaultQuality}) {
    switch (target) {
      case RasterFormat.png:
        return img.encodePng(page);
      case RasterFormat.jpg:
        return img.encodeJpg(_flatten(page), quality: quality < 1 ? 1 : (quality > 100 ? 100 : quality));
      case RasterFormat.gif:
        return img.encodeGif(_flatten(page));
      case RasterFormat.bmp:
        return img.encodeBmp(_flatten(page));
      case RasterFormat.tiff:
        return img.encodeTiff(page);
    }
  }

  RasterResult convert(Uint8List input, String name, RasterFormat target, {int quality = defaultQuality}) {
    final List<img.Image> pages = pagesOf(input);
    final int dot = name.lastIndexOf('.');
    final String stem = dot > 0 ? name.substring(0, dot) : name;
    bool alpha = false;
    final List<RasterPage> out = <RasterPage>[];
    for (int i = 0; i < pages.length; i++) {
      final img.Image page = pages[i];
      alpha = alpha || _hasAlpha(page);
      final String file = pages.length == 1 ? '$stem.${target.extension}' : '${stem}_p${i + 1}.${target.extension}';
      out.add(RasterPage(file, encode(page, target, quality: quality)));
    }
    return RasterResult(out, hadAlpha: alpha, keptAlpha: alpha && target.keepsAlpha);
  }
}
