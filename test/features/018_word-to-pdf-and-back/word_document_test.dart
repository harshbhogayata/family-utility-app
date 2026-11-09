import 'dart:convert';
import 'dart:typed_data';

import 'package:family_utility_app/engines/archive/zip_codec.dart';
import 'package:family_utility_app/engines/convert/convert_registry.dart';
import 'package:family_utility_app/engines/convert/word_document.dart';
import 'package:flutter_test/flutter_test.dart';

final Uint8List png = Uint8List.fromList(<int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3, 4]);

const String w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';

/// A DOCX laid out the way Word saves one, with a localised heading style id.
Uint8List wordStyleDocx() {
  const String doc = '<?xml version="1.0" encoding="UTF-8"?>'
      '<w:document xmlns:w="$w" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
      '<w:body>'
      '<w:p><w:pPr><w:pStyle w:val="Kop2"/></w:pPr><w:r><w:t>Notulen</w:t></w:r></w:p>'
      '<w:p><w:pPr><w:jc w:val="both"/></w:pPr>'
      '<w:r><w:rPr><w:b w:val="0"/></w:rPr><w:t xml:space="preserve">Plain </w:t></w:r>'
      '<w:hyperlink r:id="rId9"><w:r><w:rPr><w:u w:val="single"/></w:rPr><w:t>link</w:t></w:r></w:hyperlink>'
      '<w:r><w:tab/><w:t>after tab</w:t><w:br/><w:t>next line</w:t></w:r>'
      '</w:p>'
      '<w:sectPr/></w:body></w:document>';
  const String styles = '<?xml version="1.0"?><w:styles xmlns:w="$w">'
      '<w:style w:type="paragraph" w:styleId="Kop2"><w:name w:val="heading 2"/></w:style>'
      '</w:styles>';
  return ZipWriter().build(<ZipInput>[
    ZipInput('word/document.xml', utf8.encode(doc)),
    ZipInput('word/styles.xml', utf8.encode(styles)),
  ]);
}

void main() {
  final WordDocument sample = WordDocument(<DocBlock>[
    const DocParagraph(<DocRun>[DocRun('Family budget 2026')], headingLevel: 1),
    const DocParagraph(<DocRun>[
      DocRun('Rent is '),
      DocRun('due on the 1st', bold: true, color: 'C00000'),
      DocRun(' & ', italic: true),
      DocRun('<always>', sizePt: 14, font: 'Georgia', underline: true),
    ], align: DocAlign.center),
    const DocTable(<List<List<DocParagraph>>>[
      <List<DocParagraph>>[
        <DocParagraph>[DocParagraph(<DocRun>[DocRun('Item', bold: true)])],
        <DocParagraph>[DocParagraph(<DocRun>[DocRun('Amount', bold: true)])],
      ],
      <List<DocParagraph>>[
        <DocParagraph>[DocParagraph(<DocRun>[DocRun('Groceries')])],
        <DocParagraph>[DocParagraph(<DocRun>[DocRun('12,000')])],
      ],
    ]),
    DocImage(png, widthPt: 144, heightPt: 72),
    const DocParagraph(<DocRun>[DocRun('Notes')], headingLevel: 2),
  ]);

  test('a written DOCX reads back with headings, runs, tables and pictures intact', () {
    final Uint8List docx = const DocxWriter().write(sample, now: DateTime(2026, 11, 9));
    final List<String> names = ZipReader(docx).entries.map((ZipEntry e) => e.name).toList();
    expect(names, containsAll(<String>[
      '[Content_Types].xml',
      '_rels/.rels',
      'word/document.xml',
      'word/styles.xml',
      'word/_rels/document.xml.rels',
      'word/media/image1.png',
    ]));

    final WordDocument back = const DocxReader().read(docx);
    expect(back.blocks, hasLength(5));
    final DocParagraph title = back.blocks[0] as DocParagraph;
    expect(title.headingLevel, 1);
    expect(title.text, 'Family budget 2026');

    final DocParagraph body = back.blocks[1] as DocParagraph;
    expect(body.align, DocAlign.center);
    expect(body.text, 'Rent is due on the 1st & <always>');
    expect(body.runs[1].bold, isTrue);
    expect(body.runs[1].color, 'C00000');
    expect(body.runs[2].italic, isTrue);
    expect(body.runs[3].sizePt, 14);
    expect(body.runs[3].font, 'Georgia');
    expect(body.runs[3].underline, isTrue);
    expect(body.runs[0].bold, isFalse);

    final DocTable table = back.blocks[2] as DocTable;
    expect(table.columns, 2);
    expect(table.rows[1][1].single.text, '12,000');
    expect(table.rows[0][0].single.runs.single.bold, isTrue);

    final DocImage im = back.blocks[3] as DocImage;
    expect(im.bytes, png);
    expect(im.widthPt, 144);
    expect(im.heightPt, 72);
    expect((back.blocks[4] as DocParagraph).headingLevel, 2);
    expect(back.plainText, contains('Groceries\t12,000'));
  });

  test('reads Word files: localised heading styles, hyperlinks, tabs, breaks, off toggles', () {
    final WordDocument d = const DocxReader().read(wordStyleDocx());
    expect(d.blocks, hasLength(2));
    final DocParagraph h = d.blocks[0] as DocParagraph;
    expect(h.headingLevel, 2);
    final DocParagraph p = d.blocks[1] as DocParagraph;
    expect(p.align, DocAlign.justify);
    expect(p.text, 'Plain link\tafter tab\nnext line');
    expect(p.runs.first.bold, isFalse);
    expect(p.runs[1].underline, isTrue);
  });

  test('not a DOCX is refused plainly', () {
    expect(() => const DocxReader().read(Uint8List.fromList(utf8.encode('%PDF-1.4'))),
        throwsA(isA<ConvertException>()));
    final Uint8List zipNoWord = ZipWriter().build(<ZipInput>[ZipInput('a.txt', utf8.encode('hi'))]);
    expect(() => const DocxReader().read(zipNoWord), throwsA(isA<ConvertException>()));
  });
}
