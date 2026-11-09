import 'dart:convert';
import 'dart:typed_data';

import 'package:family_utility_app/app/theme.dart';
import 'package:family_utility_app/engines/archive/zip_codec.dart';
import 'package:family_utility_app/engines/convert/convert_registry.dart';
import 'package:family_utility_app/engines/convert/file_kind.dart';
import 'package:family_utility_app/engines/convert/pdf_to_word.dart';
import 'package:family_utility_app/engines/convert/word_converters.dart';
import 'package:family_utility_app/engines/convert/word_document.dart';
import 'package:family_utility_app/tools/convert_anything/convert_anything_screen.dart';
import 'package:family_utility_app/tools/word_pdf/word_pdf_screen.dart';
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

/// Stands in for PDFium: two lines of text on one page.
class FakeTextSource implements PdfTextSource {
  int calls = 0;

  @override
  Future<List<List<PdfTextPiece>>> read(Uint8List pdf) async {
    calls++;
    return <List<PdfTextPiece>>[
      <PdfTextPiece>[
        const PdfTextPiece('Minutes', left: 72, bottom: 740, right: 150, top: 760),
        const PdfTextPiece('Everyone agreed.', left: 72, bottom: 700, right: 160, top: 710),
      ],
    ];
  }
}

Uint8List sampleDocx() => const DocxWriter().write(
      const WordDocument(<DocBlock>[
        DocParagraph(<DocRun>[DocRun('Packing list')], headingLevel: 1),
        DocParagraph(<DocRun>[DocRun('Passports, chargers and snacks.')]),
      ]),
      now: DateTime(2026, 11, 9),
    );

void main() {
  test('Word files are told apart from plain ZIPs and old .doc files', () {
    expect(sniffFileKind(sampleDocx()), FileKind.docx);
    expect(sniffFileKind(ZipWriter().build(<ZipInput>[ZipInput('a.txt', utf8.encode('a'))])), FileKind.zip);
    final Uint8List ole = Uint8List.fromList(<int>[
      0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1, 0, 0, //
      for (final int c in ascii.encode('WordDocument')) ...<int>[c, 0],
    ]);
    expect(sniffFileKind(ole), FileKind.doc);
  });

  test('the converters plug into Convert anything in both directions', () async {
    final ConvertRegistry r = ConvertRegistry.builtIn();
    final FakeTextSource source = FakeTextSource();
    registerWordConverters(r, source);
    expect(r.targetsFor(FileKind.docx).map((Converter c) => c.id), contains('docx-to-pdf'));
    expect(r.targetsFor(FileKind.pdf).map((Converter c) => c.id), contains('pdf-to-docx'));

    final ConvertOutput pdf = await r.convert(ConvertInput(name: 'trip.docx', bytes: sampleDocx()), 'docx-to-pdf');
    expect(pdf.name, 'trip.pdf');
    expect(sniffFileKind(pdf.bytes), FileKind.pdf);
    expect(latin1.decode(pdf.bytes), contains('(Packing list) Tj'));

    final ConvertOutput docx = await r.convert(ConvertInput(name: 'trip.pdf', bytes: pdf.bytes), 'pdf-to-docx');
    expect(docx.name, 'trip.docx');
    expect(source.calls, 1);
    final WordDocument back = const DocxReader().read(docx.bytes);
    expect((back.blocks.first as DocParagraph).headingLevel, 1);
    expect(back.plainText, 'Minutes\nEveryone agreed.');
  });

  testWidgets('pick a DOCX, get a PDF; pick a .doc, get a plain refusal; undo removes it', (WidgetTester tester) async {
    final ConvertRegistry r = ConvertRegistry.builtIn();
    registerWordConverters(r, FakeTextSource());
    final FakeSink sink = FakeSink();
    final FakeChooser chooser = FakeChooser(ConvertInput(name: 'packing.docx', bytes: sampleDocx()));
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: WordPdfScreen(chooser: chooser, sink: sink, registry: r),
    ));
    expect(tester.getSize(find.byKey(const Key('word-pdf-pick'))).height, greaterThanOrEqualTo(44));
    await tester.tap(find.byKey(const Key('word-pdf-pick')));
    await tester.pumpAndSettle();
    expect(sink.files.keys, <String>['/converted/packing.pdf']);
    expect(find.textContaining('Made packing.pdf'), findsOneWidget);
    expect(find.byKey(const Key('result-share')), findsOneWidget);
    expect(find.byKey(const Key('result-save')), findsOneWidget);

    await tester.tap(find.byKey(const Key('result-undo')));
    await tester.pumpAndSettle();
    expect(sink.files, isEmpty);

    chooser.input = ConvertInput(
      name: 'old.doc',
      bytes: Uint8List.fromList(<int>[
        0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1, //
        for (final int c in ascii.encode('WordDocument')) ...<int>[c, 0],
      ]),
    );
    await tester.tap(find.byKey(const Key('word-pdf-pick')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Save it as .docx'), findsOneWidget);
    expect(sink.files, isEmpty);
  });
}
