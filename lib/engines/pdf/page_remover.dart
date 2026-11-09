import 'dart:typed_data';

import 'pdf_compressor.dart';
import 'pdf_splitter.dart';

/// Feature 005 — Remove pages: the pages the person marks are left out of a
/// new PDF; every other page keeps its place. Pure Dart on the phone;
/// nothing is uploaded. Built on the split engine (003), so the kept pages
/// keep their size, rotation and resources.

class RemoveResult {
  const RemoveResult({
    required this.name,
    required this.bytes,
    required this.kept,
    required this.removed,
    required this.sourcePages,
  });

  final String name;
  final Uint8List bytes;

  /// Pages left in, counted from 1, in their original order.
  final List<int> kept;

  /// Pages taken out, ascending.
  final List<int> removed;
  final int sourcePages;
}

/// Everything a removal needs, sendable to an isolate.
class RemoveRequest {
  const RemoveRequest({required this.bytes, required this.name, required this.pages});
  final Uint8List bytes;
  final String name;
  final List<int> pages;
}

abstract final class PageRemover {
  /// "report (pages removed).pdf" for the copy kept next to the original.
  static String outputName(String name) => '${PdfSplitter.stem(name)} (pages removed).pdf';

  /// Leaves [pages] (counted from 1) out of the PDF.
  static RemoveResult remove(Uint8List bytes, String name, Iterable<int> pages) {
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
    final List<int> removed = pages.toSet().toList()..sort();
    if (removed.isEmpty) {
      throw const SplitError('Tap the pages to remove first.');
    }
    for (final int p in removed) {
      if (p < 1 || p > src.pageCount) {
        throw SplitError('Page $p is not in this PDF (it has ${src.pageCount}).');
      }
    }
    final List<int> kept = <int>[
      for (int p = 1; p <= src.pageCount; p++)
        if (!removed.contains(p)) p,
    ];
    if (kept.isEmpty) {
      throw const SplitError('A PDF needs at least one page. Leave one page in.');
    }
    return RemoveResult(
      name: outputName(name),
      bytes: src.buildPages(kept),
      kept: kept,
      removed: removed,
      sourcePages: src.pageCount,
    );
  }

  /// Runs [r]; top level so it can go to an isolate.
  static RemoveResult run(RemoveRequest r) => remove(r.bytes, r.name, r.pages);
}
