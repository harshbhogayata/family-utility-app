import 'package:flutter/foundation.dart';

/// Feature 001 — PDF viewer.
///
/// The reading state behind the viewer: current page, go-to-page, layout
/// (continuous or one page at a time), night mode and the last-read page per
/// file. Rendering lives behind [PdfSurface] in the tool so this stays pure.

enum PdfLayout { continuous, single }

/// Remembers the last page read, per file.
abstract class LastPageStore {
  Future<int?> read(String fileKey);

  Future<void> write(String fileKey, int page);
}

class MemoryLastPageStore implements LastPageStore {
  final Map<String, int> pages = <String, int>{};

  @override
  Future<int?> read(String fileKey) async => pages[fileKey];

  @override
  Future<void> write(String fileKey, int page) async => pages[fileKey] = page;
}

/// Night mode: invert the page, then turn the hues back round, so black
/// text on white becomes light on dark while photos keep their colours'
/// hue instead of turning into negatives.
abstract final class NightMode {
  /// Invert (1 - x) followed by a 180° hue rotation, as one 4×5 matrix.
  static const List<double> matrix = <double>[
    0.574, -1.430, -0.144, 0, 255, //
    -0.426, -0.430, -0.144, 0, 255, //
    -0.426, -1.430, 0.856, 0, 255, //
    0, 0, 0, 1, 0, //
  ];

  /// Applies [matrix] to one opaque RGB colour (0–255 channels), clamped.
  static List<int> apply(int r, int g, int b) {
    int ch(int row) {
      final double v = matrix[row * 5] * r + matrix[row * 5 + 1] * g + matrix[row * 5 + 2] * b + matrix[row * 5 + 4];
      return v.round().clamp(0, 255);
    }

    return <int>[ch(0), ch(1), ch(2)];
  }
}

/// Reads what the person typed in the go-to-page box. Null when it is not a
/// page of this document.
int? parsePageJump(String input, int pageCount) {
  final int? n = int.tryParse(input.trim());
  if (n == null || n < 1 || n > pageCount) {
    return null;
  }
  return n;
}

class PdfReader extends ChangeNotifier {
  PdfReader({required this.fileKey, required LastPageStore store}) : _store = store;

  /// Identifies the file for the last-read memory (its path).
  final String fileKey;
  final LastPageStore _store;

  int _pageCount = 0;
  int _page = 1;
  int? _previous;
  PdfLayout layout = PdfLayout.continuous;
  bool night = false;

  /// Asks the surface to scroll; the surface reports back through [scrolledTo].
  final ValueNotifier<int?> jumpRequest = ValueNotifier<int?>(null);

  int get pageCount => _pageCount;

  int get page => _page;

  /// The page before the last jump, for Undo.
  int? get previous => _previous;

  /// Called when the document has opened. Returns the page to start on: the
  /// last-read page if it still exists, else the first.
  Future<int> opened(int pageCount) async {
    _pageCount = pageCount;
    int start = 1;
    try {
      final int? last = await _store.read(fileKey);
      if (last != null && last >= 1 && last <= pageCount) {
        start = last;
      }
    } catch (_) {
      // Start at the top.
    }
    _page = start;
    if (start != 1) {
      jumpRequest.value = start;
    }
    notifyListeners();
    return start;
  }

  /// A jump the person asked for (page box, thumbnail, Undo).
  bool goTo(int page) {
    if (_pageCount == 0 || page < 1 || page > _pageCount) {
      return false;
    }
    if (page != _page) {
      _previous = _page;
    }
    _page = page;
    jumpRequest.value = page;
    _remember();
    notifyListeners();
    return true;
  }

  /// The surface scrolled on its own (the person swiped).
  void scrolledTo(int page) {
    if (page < 1 || page > _pageCount || page == _page) {
      return;
    }
    _page = page;
    _remember();
    notifyListeners();
  }

  /// Back to where the person was before the last jump.
  bool undoJump() {
    final int? p = _previous;
    if (p == null) {
      return false;
    }
    _previous = null;
    final int from = _page;
    goTo(p);
    _previous = from;
    return true;
  }

  void toggleNight() {
    night = !night;
    notifyListeners();
  }

  void setLayout(PdfLayout next) {
    if (layout == next) {
      return;
    }
    layout = next;
    jumpRequest.value = _page;
    notifyListeners();
  }

  Future<void> _remember() async {
    try {
      await _store.write(fileKey, _page);
    } catch (_) {
      // Not remembered this time.
    }
  }

  /// Saves the place now (the Save action).
  Future<void> savePlace() => _remember();

  @override
  void dispose() {
    jumpRequest.dispose();
    super.dispose();
  }
}
