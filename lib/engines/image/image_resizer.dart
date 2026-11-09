import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Feature 040 — Resize: pixels, percent or a preset, with aspect lock.
/// Pure Dart on the phone; the picture never leaves it.

enum ResizeMode { pixels, percent, preset }

/// A named size a form asks for. [exact] presets crop to fill the box
/// (centred) so the result is exactly that size; the others fit inside it.
@immutable
class ResizePreset {
  const ResizePreset(this.id, this.label, this.width, this.height, {this.exact = true});

  final String id;
  final String label;
  final int width;
  final int height;
  final bool exact;
}

const List<ResizePreset> resizePresets = <ResizePreset>[
  ResizePreset('passport', 'Passport photo 35×45 mm', 413, 531),
  ResizePreset('square-2in', 'Visa / OCI photo 2×2 in', 600, 600),
  ResizePreset('exam-photo', 'Exam form photo', 200, 230),
  ResizePreset('exam-sign', 'Exam form signature', 140, 60),
  ResizePreset('profile', 'Profile picture', 400, 400),
  ResizePreset('hd', 'Full HD', 1920, 1080, exact: false),
  ResizePreset('email', 'Email friendly', 1280, 1280, exact: false),
];

@immutable
class ResizeSpec {
  const ResizeSpec.pixels({this.width, this.height, this.lockAspect = true})
      : mode = ResizeMode.pixels,
        percent = 100,
        preset = null;

  const ResizeSpec.percent(this.percent)
      : mode = ResizeMode.percent,
        width = null,
        height = null,
        lockAspect = true,
        preset = null;

  const ResizeSpec.preset(ResizePreset this.preset)
      : mode = ResizeMode.preset,
        width = null,
        height = null,
        percent = 100,
        lockAspect = true;

  final ResizeMode mode;
  final int? width;
  final int? height;
  final double percent;
  final bool lockAspect;
  final ResizePreset? preset;
}

@immutable
class ResizeResult {
  const ResizeResult(this.bytes, this.width, this.height, this.extension);

  final Uint8List bytes;
  final int width;
  final int height;
  final String extension;
}

class ResizeError implements Exception {
  const ResizeError(this.message);
  final String message;

  @override
  String toString() => message;
}

abstract final class ImageResizer {
  static int _atLeast1(double v) => v.round() < 1 ? 1 : v.round();

  /// The output size for a [w]×[h] picture. With a crop preset, also the
  /// size of the scaled picture before the centred crop.
  static ({int width, int height}) targetSize(int w, int h, ResizeSpec s) {
    switch (s.mode) {
      case ResizeMode.percent:
        final double f = s.percent / 100;
        return (width: _atLeast1(w * f), height: _atLeast1(h * f));
      case ResizeMode.preset:
        final ResizePreset p = s.preset!;
        if (p.exact) {
          return (width: p.width, height: p.height);
        }
        final double f = <double>[p.width / w, p.height / h, 1].reduce((double a, double b) => a < b ? a : b);
        return (width: _atLeast1(w * f), height: _atLeast1(h * f));
      case ResizeMode.pixels:
        final int? tw = s.width;
        final int? th = s.height;
        if (tw == null && th == null) {
          return (width: w, height: h);
        }
        if (!s.lockAspect) {
          return (width: tw ?? w, height: th ?? h);
        }
        if (tw != null && th != null) {
          final double f = (tw / w) < (th / h) ? tw / w : th / h;
          return (width: _atLeast1(w * f), height: _atLeast1(h * f));
        }
        if (tw != null) {
          return (width: tw, height: _atLeast1(h * tw / w));
        }
        return (width: _atLeast1(w * th! / h), height: th);
    }
  }

  /// Resizes one picture. PNG stays PNG (keeping transparency); everything
  /// else is written as a high-quality JPG.
  static ResizeResult resize(Uint8List input, ResizeSpec spec) {
    final img.Image? decoded = img.decodeImage(input);
    if (decoded == null) {
      throw const ResizeError('This file is not a picture the app can read');
    }
    final img.Image src = img.bakeOrientation(decoded);
    final ({int width, int height}) t = targetSize(src.width, src.height, spec);
    if (t.width > 20000 || t.height > 20000) {
      throw const ResizeError('That size is too large; keep each side under 20,000 pixels');
    }
    img.Image out;
    final ResizePreset? p = spec.preset;
    if (spec.mode == ResizeMode.preset && p != null && p.exact) {
      // Scale to cover the box, then crop the middle.
      final double f = (p.width / src.width) > (p.height / src.height) ? p.width / src.width : p.height / src.height;
      final int sw = _atLeast1(src.width * f);
      final int sh = _atLeast1(src.height * f);
      final img.Image scaled = img.copyResize(src, width: sw, height: sh, interpolation: img.Interpolation.average);
      out = img.copyCrop(scaled, x: (sw - p.width) ~/ 2, y: (sh - p.height) ~/ 2, width: p.width, height: p.height);
    } else {
      out = img.copyResize(src,
          width: t.width,
          height: t.height,
          interpolation: t.width < src.width ? img.Interpolation.average : img.Interpolation.cubic);
    }
    final bool png = input.length > 4 && input[0] == 0x89 && input[1] == 0x50 && input[2] == 0x4E && input[3] == 0x47;
    if (png) {
      return ResizeResult(img.encodePng(out, level: 6), out.width, out.height, 'png');
    }
    if (out.hasAlpha) {
      final img.Image bg = img.Image(width: out.width, height: out.height);
      img.fill(bg, color: img.ColorRgb8(255, 255, 255));
      out = img.compositeImage(bg, out);
    }
    return ResizeResult(img.encodeJpg(out, quality: 90), out.width, out.height, 'jpg');
  }
}
