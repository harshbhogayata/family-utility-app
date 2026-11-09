import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'word_document.dart';

/// Feature 018 — DOCX to PDF: lays the document model out on A4 pages with
/// the `pdf` package, on the phone. Fonts map by family (serif → Times,
/// monospace → Courier, everything else → Helvetica) with bold and italic
/// faces; [fallback] (the bundled Inter) covers text those fonts cannot.
class WordPdfRenderer {
  WordPdfRenderer({this.fallback, this.compress = true});

  final pw.Font? fallback;

  /// False writes readable content streams (tests).
  final bool compress;

  static const List<String> _serif = <String>[
    'times', 'georgia', 'cambria', 'garamond', 'book antiqua', 'palatino', 'serif', 'baskerville', 'constantia',
  ];
  static const List<String> _mono = <String>['courier', 'consolas', 'mono', 'menlo', 'lucida console'];

  static const List<double> headingSizes = <double>[20, 16, 14, 13, 12, 11];
  static const double bodySize = 11;

  final Map<String, pw.Font> _fonts = <String, pw.Font>{};

  /// The PDF font family a Word font name maps to.
  static String familyFor(String? font) {
    final String f = (font ?? '').toLowerCase();
    if (_mono.any(f.contains)) {
      return 'courier';
    }
    if (_serif.any(f.contains) && !f.contains('sans')) {
      return 'times';
    }
    return 'helvetica';
  }

  pw.Font _font(String family, bool bold, bool italic) {
    final String key = '$family-$bold-$italic';
    return _fonts.putIfAbsent(key, () {
      switch (family) {
        case 'times':
          return bold
              ? (italic ? pw.Font.timesBoldItalic() : pw.Font.timesBold())
              : (italic ? pw.Font.timesItalic() : pw.Font.times());
        case 'courier':
          return bold
              ? (italic ? pw.Font.courierBoldOblique() : pw.Font.courierBold())
              : (italic ? pw.Font.courierOblique() : pw.Font.courier());
        default:
          return bold
              ? (italic ? pw.Font.helveticaBoldOblique() : pw.Font.helveticaBold())
              : (italic ? pw.Font.helveticaOblique() : pw.Font.helvetica());
      }
    });
  }

  pw.TextSpan _span(DocRun r, double baseSize, bool forceBold) {
    final pw.Font? fb = fallback;
    return pw.TextSpan(
      text: r.text,
      style: pw.TextStyle(
        font: _font(familyFor(r.font), r.bold || forceBold, r.italic),
        fontSize: r.sizePt ?? baseSize,
        color: r.color == null ? PdfColors.black : PdfColor.fromHex('#${r.color}'),
        decoration: r.underline ? pw.TextDecoration.underline : pw.TextDecoration.none,
        fontFallback: fb == null ? const <pw.Font>[] : <pw.Font>[fb],
      ),
    );
  }

  pw.Widget _paragraph(DocParagraph p) {
    final bool heading = p.headingLevel > 0;
    final double size = heading ? headingSizes[(p.headingLevel - 1).clamp(0, 5)] : bodySize;
    final pw.TextAlign align = switch (p.align) {
      DocAlign.left => pw.TextAlign.left,
      DocAlign.center => pw.TextAlign.center,
      DocAlign.right => pw.TextAlign.right,
      DocAlign.justify => pw.TextAlign.justify,
    };
    return pw.Padding(
      padding: pw.EdgeInsets.only(top: heading ? 10 : 0, bottom: heading ? 4 : 6),
      child: pw.RichText(
        textAlign: align,
        text: pw.TextSpan(
          children: p.runs.isEmpty
              ? <pw.InlineSpan>[pw.TextSpan(text: ' ', style: pw.TextStyle(font: _font('helvetica', false, false)))]
              : <pw.InlineSpan>[for (final DocRun r in p.runs) _span(r, size, heading)],
        ),
      ),
    );
  }

  pw.Widget _table(DocTable t) {
    final int cols = t.columns;
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 8),
      child: pw.Table(
        border: pw.TableBorder.all(width: 0.5),
        children: <pw.TableRow>[
          for (final List<List<DocParagraph>> row in t.rows)
            pw.TableRow(
              children: <pw.Widget>[
                for (int c = 0; c < cols; c++)
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(4),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: <pw.Widget>[
                        if (c < row.length) ...row[c].map(_paragraph),
                      ],
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  pw.Widget _image(DocImage im, double maxWidth) {
    if (img.decodeImage(im.bytes) == null) {
      return pw.Text('[picture]', style: pw.TextStyle(font: _font('helvetica', false, true)));
    }
    double w = im.widthPt > 0 ? im.widthPt : maxWidth;
    double h = im.heightPt > 0 ? im.heightPt : w * 0.75;
    if (w > maxWidth) {
      h = h * maxWidth / w;
      w = maxWidth;
    }
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 6),
      child: pw.Image(pw.MemoryImage(im.bytes), width: w, height: h),
    );
  }

  Future<Uint8List> render(WordDocument d) async {
    final pw.Document doc = pw.Document(compress: compress, title: 'Converted document');
    const PdfPageFormat format = PdfPageFormat.a4;
    const double margin = 72;
    final double contentWidth = format.width - 2 * margin;
    doc.addPage(pw.MultiPage(
      pageFormat: format,
      margin: const pw.EdgeInsets.all(margin),
      build: (pw.Context context) => <pw.Widget>[
        for (final DocBlock b in d.blocks)
          switch (b) {
            final DocParagraph p => _paragraph(p),
            final DocTable t => _table(t),
            final DocImage im => _image(im, contentWidth),
          },
      ],
    ));
    return doc.save();
  }
}
