import 'dart:convert';
import 'dart:typed_data';

import 'package:family_utility_app/app/theme.dart';
import 'package:family_utility_app/engines/archive/zip_codec.dart';
import 'package:family_utility_app/engines/convert/convert_registry.dart';
import 'package:family_utility_app/engines/convert/file_kind.dart';
import 'package:family_utility_app/engines/convert/pdf_to_word.dart';
import 'package:family_utility_app/engines/convert/sheet_converters.dart';
import 'package:family_utility_app/engines/convert/word_document.dart';
import 'package:family_utility_app/tools/convert_anything/convert_anything_screen.dart';
import 'package:family_utility_app/tools/excel_pdf/excel_pdf_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeChooser implements ConvertFileChooser {
  FakeChooser(this.input);
  ConvertInput input;

  @override
  Future<ConvertInput?> pick() async => input;
}

class FakeSink implements ConvertSink {
  final Map<String, ConvertOutput> files = <String, ConvertOutput>{};

  @override
  Future<String> write(ConvertOutput out) async {
    final String p = '/converted/${out.name}';
    files[p] = out;
    return p;
  }

  @override
  Future<void> remove(String path) async => files.remove(path);
}

/// Stands in for PDFium: a title and a three-column table on one page.
class FakeTextSource implements PdfTextSource {
  int calls = 0;

  @override
  Future<List<List<PdfTextPiece>>> read(Uint8List pdf) async {
    calls++;
    PdfTextPiece at(String t, double left, double bottom) =>
        PdfTextPiece(t, left: left, bottom: bottom, right: left + t.length * 5.0, top: bottom + 10);
    return <List<PdfTextPiece>>[
      <PdfTextPiece>[
        const PdfTextPiece('Household budget', left: 72, bottom: 760, right: 260, top: 784),
        at('Item', 72, 700),
        at('Month', 200, 700),
        at('Amount', 330, 700),
        at('Rent', 72, 684),
        at('November', 200, 684),
        at('18000', 330, 684),
        at('Milk', 72, 668),
        at('November', 200, 668),
        at('1240.5', 330, 668),
      ],
    ];
  }
}

Uint8List xml(String s) => Uint8List.fromList(utf8.encode(s));

/// A workbook laid out the way Excel saves one: shared strings, a
/// relationship file, cells with gaps, numbers, booleans and inline text.
Uint8List excelStyleWorkbook() => ZipWriter().build(<ZipInput>[
      ZipInput('[Content_Types].xml', xml('<Types/>')),
      ZipInput(
        'xl/workbook.xml',
        xml('<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
            'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>'
            '<sheet name="Budget" sheetId="1" r:id="rId7"/><sheet name="Notes" sheetId="2" r:id="rId8"/>'
            '</sheets></workbook>'),
      ),
      ZipInput(
        'xl/_rels/workbook.xml.rels',
        xml('<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
            '<Relationship Id="rId7" Type="x" Target="worksheets/sheetA.xml"/>'
            '<Relationship Id="rId8" Type="x" Target="/xl/worksheets/sheetB.xml"/></Relationships>'),
      ),
      ZipInput(
        'xl/sharedStrings.xml',
        xml('<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
            '<si><t>Item</t></si><si><t>Amount</t></si><si><r><t>Ri</t></r><r><t>ce</t></r></si></sst>'),
      ),
      ZipInput(
        'xl/worksheets/sheetA.xml',
        xml('<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>'
            '<row r="1"><c r="A1" t="s"><v>0</v></c><c r="C1" t="s"><v>1</v></c></row>'
            '<row r="2"><c r="A2" t="s"><v>2</v></c><c r="B2" t="b"><v>1</v></c><c r="C2"><v>3.5</v></c></row>'
            '<row r="4"><c r="A4" t="inlineStr"><is><t>Total</t></is></c><c r="C4"><v>12</v></c></row>'
            '</sheetData></worksheet>'),
      ),
      ZipInput(
        'xl/worksheets/sheetB.xml',
        xml('<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>'
            '<row r="1"><c r="B1" t="str"><v>Pay by the 5th</v></c></row></sheetData></worksheet>'),
      ),
    ]);

Uint8List longWorkbook() => const XlsxWriter().write(<SheetData>[
      SheetData('Expenses', <List<String>>[
        <String>['Date', 'Item', 'Amount'],
        for (int i = 1; i <= 120; i++) <String>['2026-11-${(i % 28 + 1).toString().padLeft(2, '0')}', 'Line $i', '${i * 10}'],
      ]),
    ], now: DateTime(2026, 11, 9));

int pageCount(Uint8List pdf) => int.parse(RegExp(r'/Count (\d+)').firstMatch(latin1.decode(pdf))!.group(1)!);

void main() {
  group('reading and writing workbooks', () {
    test('column letters both ways', () {
      expect(columnLetters(0), 'A');
      expect(columnLetters(25), 'Z');
      expect(columnLetters(26), 'AA');
      expect(columnLetters(27), 'AB');
      expect(columnOf('A1'), 0);
      expect(columnOf('AB12'), 27);
    });

    test('reads an Excel-style workbook: sheet names, shared strings, gaps, numbers', () {
      expect(sniffFileKind(excelStyleWorkbook()), FileKind.xlsx);
      final List<SheetData> sheets = const XlsxReader().read(excelStyleWorkbook());
      expect(sheets.map((SheetData s) => s.name), <String>['Budget', 'Notes']);
      expect(sheets[0].rows, <List<String>>[
        <String>['Item', '', 'Amount'],
        <String>['Rice', 'TRUE', '3.5'],
        <String>['', '', ''],
        <String>['Total', '', '12'],
      ]);
      expect(sheets[1].rows, <List<String>>[
        <String>['', 'Pay by the 5th'],
      ]);
    });

    test('a written workbook reads back the same', () {
      const List<SheetData> sheets = <SheetData>[
        SheetData('Bills & dues', <List<String>>[
          <String>['Name', 'Due', 'Amount'],
          <String>['Power <MSEB>', '5 Dec', '1240.5'],
          <String>['Water', '', '300'],
        ]),
      ];
      final Uint8List bytes = const XlsxWriter().write(sheets, now: DateTime(2026, 11, 9));
      expect(sniffFileKind(bytes), FileKind.xlsx);
      final List<SheetData> back = const XlsxReader().read(bytes);
      expect(back.single.name, 'Bills & dues');
      expect(back.single.rows, sheets.single.rows);
      final String sheetXml = utf8.decode(ZipReader(bytes).extract(
          ZipReader(bytes).entries.firstWhere((ZipEntry e) => e.name == 'xl/worksheets/sheet1.xml')));
      // Numbers are stored as numbers, words as text.
      expect(sheetXml, contains('<c r="C2"><v>1240.5</v></c>'));
      expect(sheetXml, contains('Power &lt;MSEB&gt;'));
    });

    test('not a workbook, and old .xls files, are said plainly', () {
      expect(() => const XlsxReader().read(ZipWriter().build(<ZipInput>[ZipInput('a.txt', utf8.encode('a'))])),
          throwsA(isA<ConvertException>()));
      final Uint8List ole = Uint8List.fromList(<int>[
        0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1, 0, 0, //
        for (final int c in ascii.encode('Workbook')) ...<int>[c, 0],
      ]);
      expect(sniffFileKind(ole), FileKind.xls);
    });
  });

  group('to PDF', () {
    test('long sheets run on to more landscape pages', () async {
      final ConvertRegistry r = ConvertRegistry.builtIn();
      registerSheetConverters(r, FakeTextSource());
      expect(r.targetsFor(FileKind.xlsx).map((Converter c) => c.id), contains('xlsx-to-pdf'));
      final ConvertOutput pdf = await r.convert(ConvertInput(name: 'expenses.xlsx', bytes: longWorkbook()), 'xlsx-to-pdf');
      expect(pdf.name, 'expenses.pdf');
      expect(sniffFileKind(pdf.bytes), FileKind.pdf);
      final String s = latin1.decode(pdf.bytes);
      expect(s, contains('841.89'));
      expect(pageCount(pdf.bytes), greaterThan(1));
      expect(s, contains('(Line 1) Tj'));
      expect(s, contains('(Line 120) Tj'));
    });

    test('wide sheets print in column blocks that fit the page', () {
      final List<String> header = <String>[for (int c = 0; c < 12; c++) 'Col${c + 1}'];
      final WordDocument doc = sheetsToDocument(<SheetData>[
        SheetData('Wide', <List<String>>[header, header]),
      ]);
      final List<DocTable> tables = doc.blocks.whereType<DocTable>().toList();
      expect(tables, hasLength(2));
      expect(tables[0].rows.first, hasLength(sheetColumnsPerBlock));
      expect(tables[1].rows.first, hasLength(12 - sheetColumnsPerBlock));
      final List<String> headings = doc.blocks
          .whereType<DocParagraph>()
          .map((DocParagraph p) => p.runs.map((DocRun r) => r.text).join())
          .toList();
      expect(headings, <String>['Wide, columns A–H', 'Wide, columns I–L']);
    });
  });

  group('from PDF', () {
    test('a PDF table lands one cell per cell', () async {
      final ConvertRegistry r = ConvertRegistry.builtIn();
      final FakeTextSource source = FakeTextSource();
      registerSheetConverters(r, source);
      expect(r.targetsFor(FileKind.pdf).map((Converter c) => c.id), contains('pdf-to-xlsx'));
      final ConvertOutput out = await r.convert(ConvertInput(name: 'budget.pdf', bytes: Uint8List(0)), 'pdf-to-xlsx');
      expect(out.name, 'budget.xlsx');
      expect(out.kind, FileKind.xlsx);
      expect(source.calls, 1);
      final List<SheetData> sheets = const XlsxReader().read(out.bytes);
      expect(sheets.single.name, 'Table 1');
      expect(sheets.single.rows, <List<String>>[
        <String>['Item', 'Month', 'Amount'],
        <String>['Rent', 'November', '18000'],
        <String>['Milk', 'November', '1240.5'],
      ]);
    });

    test('a PDF with no text says so', () {
      expect(() => pdfToSheets(<List<PdfTextPiece>>[<PdfTextPiece>[]]), throwsA(isA<ConvertException>()));
    });
  });

  testWidgets('pick a workbook, get a PDF; pick an .xls, get a plain refusal; undo removes it',
      (WidgetTester tester) async {
    final ConvertRegistry r = ConvertRegistry.builtIn();
    registerSheetConverters(r, FakeTextSource());
    final FakeSink sink = FakeSink();
    final FakeChooser chooser = FakeChooser(ConvertInput(name: 'expenses.xlsx', bytes: longWorkbook()));
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: ExcelPdfScreen(chooser: chooser, sink: sink, registry: r),
    ));
    expect(tester.getSize(find.byKey(const Key('excel-pdf-pick'))).height, greaterThanOrEqualTo(44));
    await tester.tap(find.byKey(const Key('excel-pdf-pick')));
    await tester.pumpAndSettle();
    expect(sink.files.keys, <String>['/converted/expenses.pdf']);
    expect(find.textContaining('Made expenses.pdf'), findsOneWidget);
    expect(find.byKey(const Key('result-share')), findsOneWidget);
    expect(find.byKey(const Key('result-save')), findsOneWidget);

    await tester.tap(find.byKey(const Key('result-undo')));
    await tester.pumpAndSettle();
    expect(sink.files, isEmpty);

    chooser.input = ConvertInput(
      name: 'old.xls',
      bytes: Uint8List.fromList(<int>[
        0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1, //
        for (final int c in ascii.encode('Workbook')) ...<int>[c, 0],
      ]),
    );
    await tester.tap(find.byKey(const Key('excel-pdf-pick')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Save it as .xlsx'), findsOneWidget);
    expect(sink.files, isEmpty);
  });
}
