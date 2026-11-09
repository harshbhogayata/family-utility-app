import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Feature 041 — Crop with ratios.
///
/// Pure Dart, on the phone. The screen edits a [CropSpec] (quarter turns,
/// a straighten angle and a crop rectangle in 0–1 units of the straightened
/// frame); nothing touches the original until [CropEngine.apply] runs on Save.

enum CropRatio {
  free('Free', null),
  square('1:1', 1),
  r4x3('4:3', 4 / 3),
  r3x4('3:4', 3 / 4),
  r16x9('16:9', 16 / 9),
  r9x16('9:16', 9 / 16),
  circle('Circle', 1);

  const CropRatio(this.label, this.value);

  final String label;

  /// Width over height in pixels; null for free.
  final double? value;

  bool get isCircle => this == CropRatio.circle;
}

enum CropCorner { topLeft, topRight, bottomLeft, bottomRight }

/// A rectangle in 0–1 units of the frame.
@immutable
class NormRect {
  const NormRect(this.left, this.top, this.width, this.height);

  static const NormRect full = NormRect(0, 0, 1, 1);

  final double left;
  final double top;
  final double width;
  final double height;

  double get right => left + width;
  double get bottom => top + height;

  @override
  bool operator ==(Object other) =>
      other is NormRect &&
      other.left == left &&
      other.top == top &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(left, top, width, height);

  @override
  String toString() => 'NormRect($left, $top, $width, $height)';
}

@immutable
class PixelSize {
  const PixelSize(this.width, this.height);
  final int width;
  final int height;

  double get aspect => height == 0 ? 1 : width / height;
}

/// Everything the person chose. Immutable, so Undo is a stack of these.
@immutable
class CropSpec {
  const CropSpec({
    this.quarterTurns = 0,
    this.angle = 0,
    this.rect = NormRect.full,
    this.ratio = CropRatio.free,
  });

  /// Clockwise 90° turns, 0–3.
  final int quarterTurns;

  /// Straighten angle in degrees, −45 to 45, clockwise positive.
  final double angle;

  /// Crop in 0–1 units of the straightened frame.
  final NormRect rect;
  final CropRatio ratio;

  bool get isIdentity =>
      quarterTurns == 0 && angle == 0 && rect == NormRect.full && ratio == CropRatio.free;

  CropSpec copyWith({int? quarterTurns, double? angle, NormRect? rect, CropRatio? ratio}) {
    return CropSpec(
      quarterTurns: quarterTurns ?? this.quarterTurns,
      angle: angle ?? this.angle,
      rect: rect ?? this.rect,
      ratio: ratio ?? this.ratio,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CropSpec &&
      other.quarterTurns == quarterTurns &&
      other.angle == angle &&
      other.rect == rect &&
      other.ratio == ratio;

  @override
  int get hashCode => Object.hash(quarterTurns, angle, rect, ratio);
}

@immutable
class CropResult {
  const CropResult({required this.bytes, required this.width, required this.height, required this.isPng});

  final Uint8List bytes;
  final int width;
  final int height;
  final bool isPng;

  String get extension => isPng ? 'png' : 'jpg';
}

class CropError implements Exception {
  const CropError(this.message);
  final String message;

  @override
  String toString() => message;
}

abstract final class CropEngine {
  /// Smallest crop side, as a share of the frame.
  static const double minSide = 0.05;

  /// Size of the photo as shown (EXIF orientation applied).
  static PixelSize measure(Uint8List input) {
    final img.Image? decoded = img.decodeImage(input);
    if (decoded == null) {
      throw const CropError('This file is not a JPG, PNG or WebP image');
    }
    final img.Image baked = img.bakeOrientation(decoded);
    return PixelSize(baked.width, baked.height);
  }

  /// Frame size after the quarter turns.
  static PixelSize frame(PixelSize source, int quarterTurns) {
    return quarterTurns.isOdd ? PixelSize(source.height, source.width) : source;
  }

  /// How much a w×h picture rotated by [degrees] must shrink so a w×h-shaped
  /// window inside it shows no empty corners. 1 at 0°.
  static double straightenScale(int width, int height, double degrees) {
    final double t = degrees.abs() * math.pi / 180;
    if (t == 0) {
      return 1;
    }
    final double c = math.cos(t);
    final double s = math.sin(t);
    final double w = width.toDouble();
    final double h = height.toDouble();
    return math.min(w / (w * c + h * s), h / (w * s + h * c));
  }

  /// The largest centred rectangle with [ratio] inside a frame of [frame].
  static NormRect fitRatio(CropRatio ratio, PixelSize frame) {
    final double? a = ratio.value;
    if (a == null) {
      return NormRect.full;
    }
    final double fa = frame.aspect;
    if (fa > a) {
      final double w = a / fa;
      return NormRect((1 - w) / 2, 0, w, 1);
    }
    final double h = fa / a;
    return NormRect(0, (1 - h) / 2, 1, h);
  }

  /// Drags one corner by (dx, dy) in 0–1 units; the opposite corner stays put.
  /// With a fixed ratio the height follows the width.
  static NormRect dragCorner(
    NormRect rect,
    CropCorner corner,
    double dx,
    double dy,
    CropRatio ratio,
    PixelSize frame,
  ) {
    final bool right = corner == CropCorner.topRight || corner == CropCorner.bottomRight;
    final bool bottom = corner == CropCorner.bottomLeft || corner == CropCorner.bottomRight;
    final double ax = right ? rect.left : rect.right;
    final double ay = bottom ? rect.top : rect.bottom;
    final double maxW = right ? 1 - ax : ax;
    final double maxH = bottom ? 1 - ay : ay;
    double w = right ? rect.right + dx - ax : ax - (rect.left + dx);
    double h = bottom ? rect.bottom + dy - ay : ay - (rect.top + dy);
    w = w.clamp(math.min(minSide, maxW), maxW).toDouble();
    h = h.clamp(math.min(minSide, maxH), maxH).toDouble();
    final double? a = ratio.value;
    if (a != null) {
      final double fa = frame.aspect;
      h = w * fa / a;
      if (h > maxH) {
        h = maxH;
        w = h * a / fa;
      }
    }
    return NormRect(right ? ax : ax - w, bottom ? ay : ay - h, w, h);
  }

  /// Moves the whole rectangle, kept inside the frame.
  static NormRect move(NormRect rect, double dx, double dy) {
    final double l = (rect.left + dx).clamp(0, 1 - rect.width).toDouble();
    final double t = (rect.top + dy).clamp(0, 1 - rect.height).toDouble();
    return NormRect(l, t, rect.width, rect.height);
  }

  /// Applies the spec to the original bytes. Pure and synchronous, so it can
  /// run in an isolate. Circle crops and PNG inputs come out as PNG.
  static CropResult apply(Uint8List input, CropSpec spec) {
    final img.Image? decoded = img.decodeImage(input);
    if (decoded == null) {
      throw const CropError('This file is not a JPG, PNG or WebP image');
    }
    img.Image im = img.bakeOrientation(decoded);
    final int turns = spec.quarterTurns % 4;
    if (turns != 0) {
      im = img.copyRotate(im, angle: 90 * turns);
    }
    if (spec.angle != 0) {
      final int w = im.width;
      final int h = im.height;
      final double s = straightenScale(w, h, spec.angle);
      final img.Image rotated = img.copyRotate(im, angle: spec.angle, interpolation: img.Interpolation.linear);
      final int cw = math.max(1, (w * s).floor());
      final int ch = math.max(1, (h * s).floor());
      im = img.copyCrop(
        rotated,
        x: (rotated.width - cw) ~/ 2,
        y: (rotated.height - ch) ~/ 2,
        width: cw,
        height: ch,
      );
    }
    final NormRect r = spec.rect;
    final int x = (r.left * im.width).round().clamp(0, im.width - 1);
    final int y = (r.top * im.height).round().clamp(0, im.height - 1);
    int cw = (r.width * im.width).round().clamp(1, im.width - x);
    int ch = (r.height * im.height).round().clamp(1, im.height - y);
    final double? a = spec.ratio.value;
    if (a != null) {
      // Rounding can leave a fixed ratio a pixel off; make it exact.
      final int fromWidth = math.max(1, (cw / a).round());
      if (fromWidth <= im.height - y) {
        ch = fromWidth;
      } else {
        cw = math.max(1, math.min(im.width - x, (ch * a).round()));
      }
    }
    im = img.copyCrop(im, x: x, y: y, width: cw, height: ch);

    final bool png = spec.ratio.isCircle || isPng(input);
    if (spec.ratio.isCircle) {
      im = _circleMask(im);
    }
    final Uint8List bytes = png ? img.encodePng(im, level: 6) : img.encodeJpg(_opaque(im), quality: 92);
    return CropResult(bytes: bytes, width: im.width, height: im.height, isPng: png);
  }

  static img.Image _circleMask(img.Image src) {
    final img.Image out = src.convert(numChannels: 4, alpha: src.maxChannelValue);
    final double r = out.width / 2;
    final double r2 = r * r;
    for (final img.Pixel p in out) {
      final double dx = p.x + 0.5 - r;
      final double dy = p.y + 0.5 - r;
      if (dx * dx + dy * dy > r2) {
        p.a = 0;
      }
    }
    return out;
  }

  static img.Image _opaque(img.Image src) {
    if (!src.hasAlpha) {
      return src;
    }
    final img.Image bg = img.Image(width: src.width, height: src.height);
    img.fill(bg, color: img.ColorRgb8(255, 255, 255));
    return img.compositeImage(bg, src);
  }

  static bool isPng(Uint8List b) =>
      b.length > 8 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47;

  /// `photo.jpg` → `photo-crop.jpg`.
  static String outputName(String original, CropResult result) {
    final String name = original.split('/').last;
    final int dot = name.lastIndexOf('.');
    final String stem = dot > 0 ? name.substring(0, dot) : name;
    return '$stem-crop.${result.extension}';
  }
}
