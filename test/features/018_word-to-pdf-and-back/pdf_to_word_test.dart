import 'dart:convert';
import 'dart:typed_data';

import 'package:family_utility_app/engines/convert/pdf_to_word.dart';
import 'package:family_utility_app/engines/convert/word_document.dart';
import 'package:family_utility_app/engines/convert/word_pdf_renderer.dart';
import 'package:flutter_test/flutter_test.dart';

/// Reads the text the renderer drew straight from its content streams, the
/// way PDFium reports fragments on the phone.
class RenderedTextSource implements PdfTextSource {
  @override
  Future<List<List<PdfTextPiece>>> read(Uint8List pdf) async {
    final String s = latin1.decode(pdf);
    final List<List<PdfTextPiece>> pages = <List<PdfTextPiece>>[];
    final RegExp stream = RegExp(r'stream\n(.*?)\nendstream', dotAll: true);
    final RegExp text = RegExp(r'/F(\w+) ([\d.]+) Tf ([\d.]+) ([\d.]+) Td \(((?:\\.|[^\\)])*)\) Tj');
    for (final RegExpMatch m in stream.allMatches(s)) {
      final String body = m.group(1)!;
      if (!body.contains(' Tj')) {
        continue;
      }
      pages.add(<PdfTextPiece>[
        for (final RegExpMatch t in text.allMatches(body))
          () {
            final double size = double.parse(t.group(2)!);
            final double x = double.parse(t.group(3)!);
            final double y = double.parse(t.group(4)!);
            final String str = t.group(5)!.replaceAllMapped(RegExp(r'\\(.)'), (Match e) => e.group(1)!).trim();
            final PdfFontFamily fam = t.group(1)!.startsWith('Courier')
                ? PdfFontFamily.courier
                : (t.group(1)!.startsWith('Times') ? PdfFontFamily.times : PdfFontFamily.helvetica);
            return PdfTextPiece(str, left: x, bottom: y - size * 0.2, right: x + textWidth(str, fam, size), top: y + size * 0.8);
          }(),
      ]);
    }
    return pages;
  }
}

void main() {
  test('pieces on one baseline join into a line; wide gaps become table cells', () {
    final WordDocument d = const PdfToWord().build(<List<PdfTextPiece>>[
      <PdfTextPiece>[
        const PdfTextPiece('Report', left: 72, bottom: 740, right: 160, top: 760),
        const PdfTextPiece('Hello', left: 72, bottom: 700, right: 98, top: 710),
        const PdfTextPiece('world, this wraps', left: 101, bottom: 700, right: 180, top: 710),
        const PdfTextPiece('onto a sec-', left: 72, bottom: 687, right: 120, top: 697),
        const PdfTextPiece('ond line.', left: 72, bottom: 674, right: 110, top: 684),
        const PdfTextPiece('Name', left: 72, bottom: 640, right: 100, top: 650),
        const PdfTextPiece('Age', left: 300, bottom: 640, right: 320, top: 650),
        const PdfTextPiece('Asha', left: 72, bottom: 625, right: 100, top: 635),
        const PdfTextPiece('9', left: 301, bottom: 625, right: 307, top: 635),
      ],
    ]);
    expect(d.blocks.length, 3);
    final DocParagraph h = d.blocks[0] as DocParagraph;
    expect(h.headingLevel, 1);
    expect(h.text, 'Report');
    final DocParagraph p = d.blocks[1] as DocParagraph;
    expect(p.headingLevel, 0);
    expect(p.text, 'Hello world, this wraps onto a second line.');
    final DocTable t = d.blocks[2] as DocTable;
    expect(t.rows.length, 2);
    expect(t.rows[1][0].first.text, 'Asha');
    expect(t.rows[1][1].first.text, '9');
  });

  test('an empty PDF gives an empty document', () {
    expect(const PdfToWord().build(<List<PdfTextPiece>>[<PdfTextPiece>[]]).blocks, isEmpty);
  });

  test('DOCX model -> PDF -> editable DOCX keeps headings, paragraphs and tables', () async {
    const WordDocument original = WordDocument(<DocBlock>[
      DocParagraph(<DocRun>[DocRun('Family budget')], headingLevel: 1),
      DocParagraph(<DocRun>[
        DocRun('Rent is paid on the first of each month from the joint account, and the electricity '
            'bill is split between the two flats by the meter readings taken on the last Sunday.'),
      ]),
      DocParagraph(<DocRun>[DocRun('Monthly costs')], headingLevel: 2),
      DocTable(<List<List<DocParagraph>>>[
        <List<DocParagraph>>[
          <DocParagraph>[DocParagraph(<DocRun>[DocRun('Item')])],
          <DocParagraph>[DocParagraph(<DocRun>[DocRun('Amount')])],
        ],
        <List<DocParagraph>>[
          <DocParagraph>[DocParagraph(<DocRun>[DocRun('Groceries')])],
          <DocParagraph>[DocParagraph(<DocRun>[DocRun('12,000')])],
        ],
        <List<DocParagraph>>[
          <DocParagraph>[DocParagraph(<DocRun>[DocRun('School fees')])],
          <DocParagraph>[DocParagraph(<DocRun>[DocRun('8,500')])],
        ],
      ]),
      DocParagraph(<DocRun>[DocRun('Reviewed in March.')]),
    ]);
    final Uint8List pdf = await WordPdfRenderer().render(original);
    final List<List<PdfTextPiece>> pages = await RenderedTextSource().read(pdf);
    final WordDocument back = const PdfToWord().build(pages);
    expect(back.blocks.length, 5);
    expect((back.blocks[0] as DocParagraph).headingLevel, 1);
    expect((back.blocks[0] as DocParagraph).text, 'Family budget');
    expect((back.blocks[1] as DocParagraph).text, (original.blocks[1] as DocParagraph).text);
    expect((back.blocks[2] as DocParagraph).headingLevel, 2);
    final DocTable t = back.blocks[3] as DocTable;
    expect(t.rows.length, 3);
    expect(t.rows[2][0].first.text, 'School fees');
    expect(t.rows[2][1].first.text, '8,500');
    expect((back.blocks[4] as DocParagraph).text, 'Reviewed in March.');

    // And it saves as a DOCX that reads back the same.
    final WordDocument reread = const DocxReader().read(const DocxWriter().write(back, now: DateTime(2026, 11, 9)));
    expect(reread.plainText, back.plainText);
  });
}
