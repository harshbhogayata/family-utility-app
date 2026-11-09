import 'dart:math' as math;
import 'dart:typed_data';

import 'pdf_compressor.dart';
import 'pdf_splitter.dart';

/// Feature 006 — Reorder pages: drag pages into a new order and add blank
/// pages anywhere. Pure Dart on the phone; nothing is uploaded. Built on
/// the split engine (003), so each page keeps its size, rotation and
/// resources; a blank page takes the size of the page before it.

/// The pages of the new PDF in order: a source page counted from 1, or
/// [PdfSplitSource.blank] for an empty page.
class PageLayout {
  PageLayout(int pageCount) : _slots = <int>[for (int p = 1; p <= pageCount; p++) p];

  PageLayout.of(List<int> slots) : _slots = List<int>.of(slots);

  final List<int> _slots;

  List<int> get slots => List<int>.unmodifiable(_slots);
  int get length => _slots.length;
  int operator [](int index) => _slots[index];

  bool isBlank(int index) => _slots[index] == PdfSplitSource.blank;
  int get blanks => _slots.where((int s) => s == PdfSplitSource.blank).length;

  /// Same pages in the same order, no blanks.
  bool get isOriginal {
    for (int i = 0; i < _slots.length; i++) {
      if (_slots[i] != i + 1) {
        return false;
      }
    }
    return true;
  }

  /// Moves the slot at [from] so it ends up at index [to].
  void move(int from, int to) {
    if (from == to || from < 0 || from >= _slots.length) {
      return;
    }
    final int s = _slots.removeAt(from);
    _slots.insert(_within(to), s);
  }

  /// Puts an empty page at index [at] (0 = first, [length] = last).
  void insertBlank(int at) => _slots.insert(_within(at), PdfSplitSource.blank);

  int _within(int i) => math.min(math.max(i, 0), _slots.length);

  /// Only blank pages can be taken out here; real pages use Remove pages.
  bool removeBlank(int at) {
    if (at < 0 || at >= _slots.length || !isBlank(at)) {
      return false;
    }
    _slots.removeAt(at);
    return true;
  }
}

class ReorderResult {
  const ReorderResult({required this.name, required this.bytes, required this.slots});
  final String name;
  final Uint8List bytes;
  final List<int> slots;
}

/// Everything a reorder needs, sendable to an isolate.
class ReorderRequest {
  const ReorderRequest({required this.bytes, required this.name, required this.slots});
  final Uint8List bytes;
  final String name;
  final List<int> slots;
}

abstract final class PageReorderer {
  static String outputName(String name) => '${PdfSplitter.stem(name)} (reordered).pdf';

  static ReorderResult apply(Uint8List bytes, String name, List<int> slots) {
    final PdfSplitSource src;
    try {
      src = PdfSplitSource.parse(bytes);
    } on SplitError {
      rethrow;
    } on PdfCompressError catch (e) {
      throw SplitError(e.message);
    } catch (_) {
      throw const SplitError('This file could not be read as a PDF.');
    }
    if (slots.isEmpty) {
      throw const SplitError('There are no pages to save.');
    }
    final Set<int> seen = <int>{};
    for (final int p in slots) {
      if (p == PdfSplitSource.blank) {
        continue;
      }
      if (p < 1 || p > src.pageCount) {
        throw SplitError('Page $p is not in this PDF (it has ${src.pageCount}).');
      }
      if (!seen.add(p)) {
        throw SplitError('Page $p appears twice.');
      }
    }
    return ReorderResult(name: outputName(name), bytes: src.buildPages(slots), slots: List<int>.of(slots));
  }

  static ReorderResult run(ReorderRequest r) => apply(r.bytes, r.name, r.slots);
}
