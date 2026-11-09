import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:family_utility_app/engines/convert/truetype_font.dart';
import 'package:family_utility_app/engines/convert/word_document.dart';
import 'package:family_utility_app/engines/convert/word_pdf_renderer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  final Uint8List picture = img.encodePng(img.Image(width: 8, height: 4));

  WordDocument sample() => WordDocument(<DocBlock>[
        const DocParagraph(<DocRun>[DocRun('Family budget 2026')], headingLevel: 1),
        const DocParagraph(<DocRun>[
          DocRun('Rent is '),
          DocRun('due (on) the 1st', bold: true, color: 'C00000'),
          DocRun(' and ', italic: true),
          DocRun('serif words', font: 'Georgia', underline: true),
          DocRun(' code', font: 'Consolas'),
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
        DocImage(picture, widthPt: 144, heightPt: 72),
        DocImage(Uint8List.fromList(<int>[1, 2, 3]), widthPt: 50, heightPt: 50),
      ]);

  test('fonts follow the run: bold, italic, serif and mono map to base fonts', () {
    expect(fontFamilyFor('Georgia'), PdfFontFamily.times);
    expect(fontFamilyFor('Open Sans'), PdfFontFamily.helvetica);
    expect(fontFamilyFor('Consolas'), PdfFontFamily.courier);
    expect(baseFontName(PdfFontFamily.times, bold: true, italic: true), 'Times-BoldItalic');
    expect(baseFontName(PdfFontFamily.helvetica, bold: false, italic: true), 'Helvetica-Oblique');
    expect(baseFontName(PdfFontFamily.courier, bold: true, italic: false), 'Courier-Bold');
    expect(textWidth('ab', PdfFontFamily.courier, 10), closeTo(12, 0.001));
    expect(winAnsi('“Hi” – café'), '"Hi" - café');
  });

  test('a document renders to a valid PDF with text, table, picture and fonts', () async {
    final Uint8List pdf = await WordPdfRenderer().render(sample());
    final String s = latin1.decode(pdf);
    expect(s.startsWith('%PDF-1.4'), isTrue);
    expect(s.trimRight().endsWith('%%EOF'), isTrue);
    expect(s, contains('(Family budget 2026) Tj'));
    expect(s, contains(r'(due \(on\) the 1st) Tj'));
    expect(s, contains('/BaseFont /Helvetica-Bold'));
    expect(s, contains('/BaseFont /Helvetica-Oblique'));
    expect(s, contains('/BaseFont /Times-Roman'));
    expect(s, contains('/BaseFont /Courier'));
    expect(s, contains('0.753 0.000 0.000 rg'));
    expect(s, contains('re S'), reason: 'table cells are ruled');
    expect(s, contains('(Groceries) Tj'));
    expect(s, contains('/Subtype /Image'));
    expect(s, contains(r'(\[image\]) Tj'), reason: 'an unreadable picture becomes a labelled box');
    expect(RegExp('/Type /Page ').allMatches(s).length, 1);
    // The xref offsets point at their objects.
    final int start = int.parse(RegExp(r'startxref\n(\d+)').firstMatch(s)!.group(1)!);
    expect(s.substring(start, start + 4), 'xref');
    final List<String> rows = s.substring(start).split('\n').skip(3).takeWhile((String l) => l.endsWith(' n ')).toList();
    for (int i = 0; i < rows.length; i++) {
      final int off = int.parse(rows[i].substring(0, 10));
      expect(s.substring(off).startsWith('${i + 1} 0 obj'), isTrue);
    }
  });

  test('long text wraps within the margins and flows onto new pages', () async {
    final String para = List<String>.filled(60, 'household paperwork').join(' ');
    final WordDocument doc = WordDocument(<DocBlock>[
      for (int i = 0; i < 20; i++) DocParagraph(<DocRun>[DocRun(para)], align: DocAlign.justify),
    ]);
    final Uint8List pdf = await WordPdfRenderer().render(doc);
    final String s = latin1.decode(pdf);
    expect(RegExp('/Type /Page ').allMatches(s).length, greaterThan(3));
    for (final RegExpMatch m in RegExp(r'Tf ([\d.]+) ([\d.]+) Td').allMatches(s)) {
      final double x = double.parse(m.group(1)!);
      final double y = double.parse(m.group(2)!);
      expect(x, inInclusiveRange(71.9, 523.3));
      expect(y, inInclusiveRange(60, 770));
    }
  });

  test('line breaks inside a run start a new line', () async {
    const WordDocument doc = WordDocument(<DocBlock>[
      DocParagraph(<DocRun>[DocRun('first\nsecond')]),
    ]);
    final String s = latin1.decode(await WordPdfRenderer().render(doc));
    final List<double> ys = <double>[
      for (final RegExpMatch m in RegExp(r'Td \((first|second)\)').allMatches(s))
        double.parse(RegExp(r'([\d.]+) Td \(' + m.group(1)!).firstMatch(s)!.group(1)!),
    ];
    expect(ys.length, 2);
    expect(ys[0], greaterThan(ys[1]));
  });

  test('text the base fonts cannot draw is embedded with the bundled font', () async {
    final TrueTypeFont inter = TrueTypeFont.parse(File('assets/fonts/Inter.ttf').readAsBytesSync());
    expect(inter.covers('Ж'.runes.first), isTrue);
    expect(inter.glyphFor('A'.runes.first), isNot(0));
    expect(inter.textWidth('Hello', 10), inInclusiveRange(20, 40));

    const WordDocument doc = WordDocument(<DocBlock>[
      DocParagraph(<DocRun>[DocRun('Plain words and Привет мир')]),
    ]);
    final Uint8List pdf = await WordPdfRenderer(unicodeFont: inter).render(doc);
    final String s = latin1.decode(pdf);
    expect(s, contains('/Subtype /Type0'));
    expect(s, contains('/CIDToGIDMap /Identity'));
    expect(s, contains('/FontFile2'));
    expect(s, contains('beginbfchar'));
    expect(s, contains('<041f>'), reason: 'ToUnicode maps glyphs back to П');
    expect(s, contains('(Plain words and ) Tj'));
    expect(RegExp(r'Td <[0-9a-f]+> Tj').hasMatch(s), isTrue, reason: 'non-Latin text is drawn as glyph ids');

    // Without the font, the same text degrades to question marks but still renders.
    final String bare = latin1.decode(await WordPdfRenderer().render(doc));
    expect(bare, contains('(??????'));
    expect(bare, isNot(contains('/Type0')));
  });
}
