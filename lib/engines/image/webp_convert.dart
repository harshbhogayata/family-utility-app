import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Feature 026 — WebP to JPG or PNG and back. Decoding and JPG/PNG writing
/// are pure Dart; writing WebP uses the phone's own encoder behind
/// [WebpEncoder]. Nothing leaves the phone.

enum ImageTarget {
  jpg('JPG', 'jpg'),
  png('PNG', 'png'),
  webp('WebP', 'webp');

  const ImageTarget(this.label, this.extension);
  final String label;
  final String extension;
}

/// Encodes WebP. The platform codec in the app, a fake in tests.
abstract class WebpEncoder {
  /// [png] keeps any transparency; returns WebP bytes.
  Future<Uint8List> encode(Uint8List png, {int quality = 90});
}

class WebpConvertError implements Exception {
  const WebpConvertError(this.message);
  final String message;
  @override
  String toString() => message;
}

class WebpConverted {
  const WebpConverted(this.name, this.bytes, {required this.keptAlpha, required this.hadAlpha});
  final String name;
  final Uint8List bytes;

  /// True when the source had see-through parts.
  final bool hadAlpha;

  /// True when those parts are still see-through in the output.
  final bool keptAlpha;
}

class WebpConverter {
  const WebpConverter(this.webp);
  final WebpEncoder webp;

  /// WebP in → PNG out (keeps transparency); anything else in → WebP out.
  static ImageTarget defaultTarget(String name) =>
      name.toLowerCase().endsWith('.webp') ? ImageTarget.png : ImageTarget.webp;

  static bool _hasAlpha(img.Image im) {
    if (!im.hasAlpha) {
      return false;
    }
    for (final img.Pixel p in im) {
      if (p.a < p.maxChannelValue) {
        return true;
      }
    }
    return false;
  }

  Future<WebpConverted> convert(Uint8List input, String name, ImageTarget target) async {
    final img.Image? decoded = img.decodeImage(input);
    if (decoded == null) {
      throw const WebpConvertError('This file is not a picture the app can read');
    }
    final img.Image src = img.bakeOrientation(decoded);
    final bool alpha = _hasAlpha(src);
    final int dot = name.lastIndexOf('.');
    final String out = '${dot > 0 ? name.substring(0, dot) : name}.${target.extension}';
    switch (target) {
      case ImageTarget.png:
        final img.Image rgba = src.numChannels == 4 ? src : src.convert(numChannels: alpha ? 4 : 3);
        return WebpConverted(out, img.encodePng(rgba), keptAlpha: alpha, hadAlpha: alpha);
      case ImageTarget.jpg:
        img.Image flat = src;
        if (src.hasAlpha) {
          flat = img.Image(width: src.width, height: src.height);
          img.fill(flat, color: img.ColorRgb8(255, 255, 255));
          img.compositeImage(flat, src);
        }
        return WebpConverted(out, img.encodeJpg(flat, quality: 92), keptAlpha: false, hadAlpha: alpha);
      case ImageTarget.webp:
        final Uint8List bytes = await webp.encode(img.encodePng(src));
        return WebpConverted(out, bytes, keptAlpha: alpha, hadAlpha: alpha);
    }
  }
}
