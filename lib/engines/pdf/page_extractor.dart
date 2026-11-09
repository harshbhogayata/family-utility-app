import 'dart:typed_data';

import 'pdf_compressor.dart';
import 'pdf_splitter.dart';

/// Feature 004 — Extract pages: the pages the person taps, in the order
/// they tapped them, become a new PDF. Pure Dart on the phone; nothing is
/// uploaded. Built on the split engine (003), so each page keeps its size,
/// rotation and resources.

/// Pages tapped so far, in tap order. Tapping a chosen page again drops it
/// and the pages after it move up one place.
class PageSelection {
  final List<int> _order = <int>[];

  /// Pages counted from 1, in the order they were chosen.
  List<int> get order => List<int>.unmodifiable(_order);

  bool get isEmpty => _order.isEmpty;
  int get length => _order.length;

  bool contains(int page) => _order.contains(page);

  /// 1-based place of [page] in the output, or null when not chosen.
  int? placeOf(int page) {
    final int i = _order.indexOf(page);
    return i < 0 ? null : i + 1;
  }

  void toggle(int page) {
    if (!_order.remove(page)) {
      _order.add(page);
    }
  }

  void selectAll(int pageCount) {
    for (int p = 1; p <= pageCount; p++) {
      if (!_order.contains(p)) {
        _order.add(p);
      }
    }
  }

  void clear() => _order.clear();

  void restore(List<int> order) {
    _order
      ..clear()
      ..addAll(order);
  }
}

class ExtractResult {
  const ExtractResult({required this.name, required this.bytes, required this.pages, required this.sourcePages});

  final String name;
  final Uint8List bytes;

  /// The pages taken, in output order.
  final List<int> pages;
  final int sourcePages;
}

/// Everything an extract needs, sendable to an isolate.
class ExtractRequest {
  const ExtractRequest({required this.bytes, required this.name, required this.pages});
  final Uint8List bytes;
  final String name;
  final List<int> pages;
}

abstract final class PageExtractor {
  /// "report pages 3, 1, 5.pdf"; long picks are shortened with the count.
  static String outputName(String name, List<int> pages) {
    final String stem = PdfSplitter.stem(name);
    final String list = pages.length <= 6
        ? pages.join(', ')
        : '${pages.take(5).join(', ')} and ${pages.length - 5} more';
    return '$stem ${pages.length == 1 ? 'page' : 'pages'} $list.pdf';
  }

  /// Pages counted from 1, in output order; repeats are dropped.
  static ExtractResult extract(Uint8List bytes, String name, List<int> pages) {
    final List<int> order = <int>[];
    for (final int p in pages) {
      if (!order.contains(p)) {
        order.add(p);
      }
    }
    if (order.isEmpty) {
      throw const SplitError('Tap the pages to take first.');
    }
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
    for (final int p in order) {
      if (p < 1 || p > src.pageCount) {
        throw SplitError('Page $p is not in this PDF (it has ${src.pageCount}).');
      }
    }
    return ExtractResult(
      name: outputName(name, order),
      bytes: src.buildPages(order),
      pages: order,
      sourcePages: src.pageCount,
    );
  }

  /// Runs [r]; top level so it can go to an isolate.
  static ExtractResult run(ExtractRequest r) => extract(r.bytes, r.name, r.pages);
}
