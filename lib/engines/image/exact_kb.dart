import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Feature 035 — Image to exact KB: the best-looking JPG that fits a size
/// limit (for forms), found by binary search on quality, then on scale.

const List<int> exactKbPresets = <int>[20, 50, 100, 200];

/// Millimetres to pixels at [dpi] (forms usually assume 300).
int mmToPx(double mm, {int dpi = 300}) => (mm / 25.4 * dpi).round();

@immutable
class ExactKbResult {
  const ExactKbResult(this.bytes, this.width, this.height, this.quality, this.targetBytes);

  final Uint8List bytes;
  final int width;
  final int height;
  final int quality;
  final int targetBytes;

  bool get fits => bytes.length <= targetBytes;

  /// Within 5% under the limit: as large (as sharp) as allowed.
  bool get close => fits && bytes.length >= targetBytes * 0.95;
}

class ExactKbError implements Exception {
  const ExactKbError(this.message);
  final String message;

  @override
  String toString() => message;
}

abstract final class ExactKb {
  /// Fits [input] under [targetKb] KB (1 KB = 1024 bytes). With [width] and
  /// [height] the picture is first set to exactly that size and never scaled.
  static ExactKbResult fit(Uint8List input, int targetKb, {int? width, int? height}) {
    if (targetKb < 1) {
      throw const ExactKbError('Choose a size of at least 1 KB');
    }
    final img.Image? decoded = img.decodeImage(input);
    if (decoded == null) {
      throw const ExactKbError('This file is not a picture the app can read');
    }
    img.Image src = img.bakeOrientation(decoded);
    if (src.hasAlpha) {
      final img.Image bg = img.Image(width: src.width, height: src.height);
      img.fill(bg, color: img.ColorRgb8(255, 255, 255));
      src = img.compositeImage(bg, src);
    }
    final bool locked = width != null || height != null;
    if (locked) {
      src = img.copyResize(src, width: width, height: height, interpolation: img.Interpolation.average);
    }
    final int target = targetKb * 1024;
    double scale = 1;
    ExactKbResult? best;
    for (int round = 0; round < 10; round++) {
      final img.Image im = scale >= 1
          ? src
          : img.copyResize(src,
              width: math.max(1, (src.width * scale).round()),
              height: math.max(1, (src.height * scale).round()),
              interpolation: img.Interpolation.average);
      // Largest quality that still fits.
      int lo = 5;
      int hi = 95;
      Uint8List? fitBytes;
      int fitQ = 0;
      final Uint8List smallest = img.encodeJpg(im, quality: lo);
      if (smallest.length <= target) {
        fitBytes = smallest;
        fitQ = lo;
        lo++;
        while (lo <= hi) {
          final int mid = (lo + hi) ~/ 2;
          final Uint8List b = img.encodeJpg(im, quality: mid);
          if (b.length <= target) {
            fitBytes = b;
            fitQ = mid;
            lo = mid + 1;
          } else {
            hi = mid - 1;
          }
        }
      }
      if (fitBytes != null) {
        best = ExactKbResult(fitBytes, im.width, im.height, fitQ, target);
        break;
      }
      if (locked) {
        throw ExactKbError('At ${src.width} × ${src.height} px this picture cannot get under $targetKb KB. '
            'Unlock the size or pick a larger limit.');
      }
      scale *= math.sqrt(target / smallest.length) * 0.9;
    }
    if (best == null) {
      throw ExactKbError('This picture cannot get under $targetKb KB');
    }
    return best;
  }
}
