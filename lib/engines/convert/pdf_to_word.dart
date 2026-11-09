import 'dart:typed_data';

import 'word_document.dart';

/// Feature 018 — PDF to Word: rebuilds editable paragraphs, headings and
/// tables from the positioned text on each page.
///
/// Reading the text out of the PDF is the job of a [PdfTextSource] (PDFium on
/// the phone); everything after that is plain Dart and runs offline.

/// A piece of text and its box on the page, in PDF points with y growing
/// upwards (so [top] > [bottom]).
class PdfTextPiece {
  const PdfTextPiece(this.text, {required this.left, required this.bottom, required this.right, required this.top});

  final String text;
  final double left;
  final double bottom;
  final double right;
  final double top;

  double get height => top - bottom;
  double get middle => (top + bottom) / 2;
}

/// Pulls positioned text out of a PDF, one list per page.
abstract class PdfTextSource {
  Future<List<List<PdfTextPiece>>> read(Uint8List pdf);
}

class _Line {
  _Line(PdfTextPiece first)
      : pieces = <PdfTextPiece>[first],
        top = first.top,
        bottom = first.bottom;

  final List<PdfTextPiece> pieces;
  double top;
  double bottom;

  double get height => top - bottom;
  double get middle => (top + bottom) / 2;

  /// Text split into cells wherever the gap is wide enough to be a column.
  List<String> cells = <String>[];
  List<double> cellLefts = <double>[];
  String get text => cells.join(' ');
}

class PdfToWord {
  const PdfToWord();

  /// Builds the document from every page's text pieces, in page order.
  WordDocument build(List<List<PdfTextPiece>> pages) {
    final List<_Line> lines = <_Line>[];
    final List<int> pageOf = <int>[];
    for (int p = 0; p < pages.length; p++) {
      for (final _Line l in _lines(pages[p])) {
        lines.add(l);
        pageOf.add(p);
      }
    }
    if (lines.isEmpty) {
      return const WordDocument(<DocBlock>[]);
    }
    final List<double> heights = lines.map((_Line l) => l.height).toList()..sort();
    final double mid = heights[(heights.length - 1) ~/ 2];
    final double body = mid <= 0 ? 10 : mid;

    final List<DocBlock> blocks = <DocBlock>[];
    int i = 0;
    while (i < lines.length) {
      final _Line l = lines[i];
      // A table: two or more lines in a row with the same columns.
      if (l.cells.length >= 2) {
        int j = i + 1;
        while (j < lines.length && pageOf[j] == pageOf[i] && _sameColumns(lines[j], l, body)) {
          j++;
        }
        if (j - i >= 2) {
          blocks.add(DocTable(<List<List<DocParagraph>>>[
            for (int k = i; k < j; k++)
              <List<DocParagraph>>[
                for (final String c in lines[k].cells) <DocParagraph>[DocParagraph(<DocRun>[DocRun(c)])],
              ],
          ]));
          i = j;
          continue;
        }
      }
      final int level = _headingLevel(l.height, body);
      if (level > 0) {
        blocks.add(DocParagraph(<DocRun>[DocRun(l.text, bold: true)], headingLevel: level));
        i++;
        continue;
      }
      // A paragraph: following lines of body size, close below, not a table row.
      final StringBuffer text = StringBuffer(l.text);
      int j = i + 1;
      while (j < lines.length) {
        final _Line prev = lines[j - 1];
        final _Line next = lines[j];
        final bool samePage = pageOf[j] == pageOf[j - 1];
        final double gap = prev.bottom - next.top;
        final bool close = samePage ? gap < body * 0.6 : _endsOpen(prev.text);
        if (!close || _headingLevel(next.height, body) > 0 || (next.cells.length >= 2 && j + 1 < lines.length && _sameColumns(lines[j + 1], next, body))) {
          break;
        }
        final String sofar = text.toString();
        if (sofar.endsWith('-') && next.text.isNotEmpty && next.text[0].toLowerCase() == next.text[0] && next.text[0].toUpperCase() != next.text[0]) {
          text
            ..clear()
            ..write(sofar.substring(0, sofar.length - 1))
            ..write(next.text);
        } else {
          text
            ..write(' ')
            ..write(next.text);
        }
        j++;
      }
      blocks.add(DocParagraph(<DocRun>[DocRun(text.toString())]));
      i = j;
    }
    return WordDocument(blocks);
  }

  static bool _endsOpen(String s) {
    final String t = s.trimRight();
    return t.isNotEmpty && !'.!?:;'.contains(t[t.length - 1]);
  }

  static int _headingLevel(double h, double body) {
    final double r = h / body;
    if (r >= 1.8) {
      return 1;
    }
    if (r >= 1.45) {
      return 2;
    }
    if (r >= 1.2) {
      return 3;
    }
    return 0;
  }

  static bool _sameColumns(_Line a, _Line b, double body) {
    if (a.cells.length != b.cells.length || a.cells.length < 2) {
      return false;
    }
    for (int c = 0; c < a.cells.length; c++) {
      if ((a.cellLefts[c] - b.cellLefts[c]).abs() > body * 1.5) {
        return false;
      }
    }
    return true;
  }

  /// Groups a page's pieces into lines, top to bottom, and splits cells.
  static List<_Line> _lines(List<PdfTextPiece> pieces) {
    final List<PdfTextPiece> sorted = pieces.where((PdfTextPiece p) => p.text.trim().isNotEmpty).toList()
      ..sort((PdfTextPiece a, PdfTextPiece b) => b.middle.compareTo(a.middle));
    final List<_Line> lines = <_Line>[];
    for (final PdfTextPiece p in sorted) {
      _Line? home;
      for (final _Line l in lines.reversed.take(3)) {
        if ((l.middle - p.middle).abs() < (l.height < p.height ? l.height : p.height) * 0.5) {
          home = l;
          break;
        }
      }
      if (home == null) {
        lines.add(_Line(p));
      } else {
        home.pieces.add(p);
        if (p.top > home.top) {
          home.top = p.top;
        }
        if (p.bottom < home.bottom) {
          home.bottom = p.bottom;
        }
      }
    }
    for (final _Line l in lines) {
      l.pieces.sort((PdfTextPiece a, PdfTextPiece b) => a.left.compareTo(b.left));
      final List<String> cells = <String>[];
      final List<double> lefts = <double>[];
      StringBuffer cur = StringBuffer();
      double right = l.pieces.first.left;
      for (final PdfTextPiece p in l.pieces) {
        final double gap = p.left - right;
        if (cur.isNotEmpty && gap > l.height * 1.5) {
          cells.add(cur.toString().trim());
          cur = StringBuffer();
        }
        if (cur.isEmpty) {
          lefts.add(p.left);
        } else if (gap > l.height * 0.15 && !cur.toString().endsWith(' ') && !p.text.startsWith(' ')) {
          cur.write(' ');
        }
        cur.write(p.text);
        if (p.right > right) {
          right = p.right;
        }
      }
      cells.add(cur.toString().trim());
      l.cells = cells;
      l.cellLefts = lefts;
    }
    return lines;
  }
}
