import 'dart:typed_data';

import 'pdf_compressor.dart';
import 'pdf_splitter.dart';

/// Feature 007 — Rotate pages: turn single pages or the whole file in
/// 90-degree steps. The turn is written into each page's /Rotate entry, so
/// every viewer shows it, not just this app. Pure Dart on the phone; built
/// on the split engine (003), so pages keep their content, size and
/// resources untouched. Nothing is uploaded.

/// Quarter turns clockwise (0–3) to add to each page, counted from 1.
class PageTurns {
  PageTurns(int pageCount) : _turns = List<int>.filled(pageCount, 0);

  PageTurns.of(List<int> turns) : _turns = <int>[for (final int t in turns) t % 4];

  final List<int> _turns;

  int get length => _turns.length;
  List<int> get turns => List<int>.unmodifiable(_turns);

  /// Quarter turns clockwise added to [page] (counted from 1).
  int of(int page) => _turns[page - 1];

  /// Degrees clockwise added to [page]: 0, 90, 180 or 270.
  int degreesOf(int page) => _turns[page - 1] * 90;

  /// Pages that end up turned.
  int get turned => _turns.where((int t) => t != 0).length;

  bool get isOriginal => turned == 0;

  /// Turns [page] a quarter: clockwise (right) or counter-clockwise (left).
  void rotate(int page, {bool clockwise = true}) {
    if (page < 1 || page > _turns.length) {
      return;
    }
    _turns[page - 1] = (_turns[page - 1] + (clockwise ? 1 : 3)) % 4;
  }

  /// Turns every page a quarter the same way.
  void rotateAll({bool clockwise = true}) {
    for (int p = 1; p <= _turns.length; p++) {
      rotate(p, clockwise: clockwise);
    }
  }
}

class RotateResult {
  const RotateResult({required this.name, required this.bytes, required this.turned, required this.pageCount});
  final String name;
  final Uint8List bytes;

  /// How many pages were turned.
  final int turned;
  final int pageCount;
}

/// Everything a rotation needs, sendable to an isolate.
class RotateRequest {
  const RotateRequest({required this.bytes, required this.name, required this.turns});
  final Uint8List bytes;
  final String name;

  /// Quarter turns clockwise per page, counted from page 1.
  final List<int> turns;
}

abstract final class PageRotator {
  static String outputName(String name) => '${PdfSplitter.stem(name)} (rotated).pdf';

  static PdfSplitSource open(Uint8List bytes) {
    try {
      return PdfSplitSource.parse(bytes);
    } on SplitError {
      rethrow;
    } on PdfCompressError catch (e) {
      throw SplitError(e.message);
    } catch (_) {
      throw const SplitError('This file could not be read as a PDF.');
    }
  }

  static RotateResult apply(Uint8List bytes, String name, List<int> turns) {
    final PdfSplitSource src = open(bytes);
    if (turns.length != src.pageCount) {
      throw SplitError('This PDF has ${src.pageCount} pages; pick the turns again.');
    }
    final Map<int, int> byPage = <int, int>{};
    for (int i = 0; i < turns.length; i++) {
      final int t = turns[i] % 4;
      if (t != 0) {
        byPage[i + 1] = t;
      }
    }
    if (byPage.isEmpty) {
      throw const SplitError('Turn a page first.');
    }
    final List<int> all = <int>[for (int p = 1; p <= src.pageCount; p++) p];
    return RotateResult(
      name: outputName(name),
      bytes: src.buildPages(all, turns: byPage),
      turned: byPage.length,
      pageCount: src.pageCount,
    );
  }

  static RotateResult run(RotateRequest r) => apply(r.bytes, r.name, r.turns);
}
