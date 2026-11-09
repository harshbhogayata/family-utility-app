import 'dart:convert';
import 'dart:typed_data';

import 'package:family_utility_app/engines/convert/word_document.dart';
import 'package:family_utility_app/engines/convert/word_pdf_renderer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  test('Word font names map to PDF families', () {
    expect(WordPdfRenderer.familyFor('Times New Roman'), 'times');
    expect(WordPdfRenderer.familyFor('Georgia'), 'times');
    expect(WordPdfRenderer.familyFor('Consolas'), 'courier');
    expect(WordPdfRenderer.familyFor('Calibri'), 'helvetica');
    expect(WordPdfRenderer.familyFor('Open Sans'), 'helvetica');
    expect(WordPdfRenderer.familyFor(null), 'helvetica');
  });

  test('DOCX model to PDF: fonts, a table, a picture, and pages flow', () async {
    final img.Image pic = img.Image(width: 40, height: 20);
    img.fill(pic, color: img.ColorRgb8(30, 120, 200));
    final Uint8List png = img.encodePng(pic);
    final WordDocument d = WordDocument(<DocBlock>[
      const DocParagraph(<DocRun>[DocRun('Family budget')], headingLevel: 1),
      const DocParagraph(<DocRun>[
        DocRun('Rent '),
        DocRun('due', bold: true, color: 'C00000'),
        DocRun(' soon', italic: true, font: 'Georgia'),
        DocRun(' code', font: 'Consolas', underline: true),
      ], align: DocAlign.justify),
      const DocTable(<List<List<DocParagraph>>>[
        <List<DocParagraph>>[
          <DocParagraph>[DocParagraph(<DocRun>[DocRun('Item')])],
          <DocParagraph>[DocParagraph(<DocRun>[DocRun('Amount')])],
        ],
        <List<DocParagraph>>[
          <DocParagraph>[DocParagraph(<DocRun>[DocRun('Milk')])],
        ],
      ]),
      DocImage(png, widthPt: 2000, heightPt: 1000),
      DocImage(Uint8List.fromList(<int>[1, 2, 3]), widthPt: 10, heightPt: 10),
      for (int i = 0; i < 120; i++) DocParagraph(<DocRun>[DocRun('Line $i of the notes.')]),
    ]);
    final Uint8List pdf = await WordPdfRenderer(compress: false).render(d);
    final String t = latin1.decode(pdf);
    expect(t.startsWith('%PDF'), isTrue);
    expect(t, matches(RegExp(r'/BaseFont\s*/Helvetica-Bold')));
    expect(t, matches(RegExp(r'/BaseFont\s*/Times-Italic')));
    expect(t, matches(RegExp(r'/BaseFont\s*/Courier\b')));
    expect(t, matches(RegExp(r'/Subtype\s*/Image')));
    expect(RegExp(r'/Type\s*/Page\b(?!s)').allMatches(t).length, greaterThanOrEqualTo(2));
  });
}
