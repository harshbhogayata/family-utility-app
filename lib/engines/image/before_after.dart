import 'image_compressor.dart';

/// Feature 039 — Before and after preview. The numbers and limits behind the
/// comparison view; pure Dart so they are easy to test.

enum CompareMode { slider, sideBySide }

class SizeSaving {
  const SizeSaving(this.before, this.after);

  final int before;
  final int after;

  /// Bytes saved; negative when the copy is bigger.
  int get saved => before - after;

  /// Whole percent saved; negative when the copy is bigger.
  int get percent => before == 0 ? 0 : (saved * 100 / before).round();

  bool get smaller => after < before;

  /// "Saved 1.2 MB (64%)", or what happened when nothing was saved.
  String get label {
    if (saved > 0) {
      return 'Saved ${ImageCompressor.formatSize(saved)} ($percent%)';
    }
    if (saved == 0) {
      return 'Same size';
    }
    return 'Bigger by ${ImageCompressor.formatSize(-saved)} (${-percent}%): the original will be kept';
  }

  /// "2.0 MB → 700 KB".
  String get sizes => '${ImageCompressor.formatSize(before)} → ${ImageCompressor.formatSize(after)}';
}

class CompareLimits {
  CompareLimits._();

  static const double minZoom = 1;
  static const double maxZoom = 6;

  /// Keeps the divider inside the picture, a little away from the edges so
  /// its handle stays reachable.
  static double clampSplit(double v) => v < 0.02 ? 0.02 : (v > 0.98 ? 0.98 : v);

  /// Divider position from a drag at [dx] across a view [width] wide.
  static double splitAt(double dx, double width) => width <= 0 ? 0.5 : clampSplit(dx / width);
}
