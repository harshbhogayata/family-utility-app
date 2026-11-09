import 'dart:convert';
import 'dart:typed_data';

import 'package:family_utility_app/app/theme.dart';
import 'package:family_utility_app/engines/pdf/pdf_ocr.dart';
import 'package:family_utility_app/engines/pdf/pdf_text_search.dart';
import 'package:family_utility_app/engines/pdf/pdf_to_images.dart';
import 'package:family_utility_app/engines/share/share_engine.dart';
import 'package:family_utility_app/tools/ocr_scan/ocr_scan_screen.dart';
import 'package:family_utility_app/tools/pdf_viewer/pdf_viewer_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// Two "scanned" pages: plain white images at 200 dpi.
class FakeRasterizer implements PdfRasterizer {
  int renders = 0;

  @override
  Future<int> pageCount(Uint8List pdf) async => 2;

  @override
  Future<img.Image> render(Uint8List pdf, int index, int dpi) async {
    renders++;
    return img.Image(width: 400, height: 560)..clear(img.ColorRgb8(255, 255, 255));
  }
}

/// What ML Kit would return: Latin words on page 1, Devanagari on page 2.
class FakeRecognizer implements TextRecognizerEngine {
  final List<OcrScript> scripts = <OcrScript>[];
  int page = 0;

  @override
  Future<List<OcrWord>> recognize(img.Image image, Uint8List jpeg, OcrScript script) async {
    scripts.add(script);
    page++;
    if (page == 1) {
      return const <OcrWord>[
        OcrWord('Electricity', left: 40, top: 40, right: 160, bottom: 60),
        OcrWord('bill', left: 170, top: 42, right: 210, bottom: 60),
        OcrWord('October', left: 40, top: 80, right: 130, bottom: 100),
      ];
    }
    return const <OcrWord>[
      OcrWord('बिजली', left: 40, top: 40, right: 120, bottom: 64),
      OcrWord('बिल', left: 130, top: 40, right: 180, bottom: 64),
    ];
  }
}

/// Reads the invisible text back out of a PDF the way a viewer does: the
/// hex strings shown with Tj, through the font's ToUnicode map.
List<String> extractText(Uint8List pdf) {
  final String s = latin1.decode(pdf);
  final Map<String, String> map = <String, String>{};
  for (final RegExpMatch m in RegExp(r'<([0-9a-f]{4})> <([0-9a-f]+)>').allMatches(s)) {
    final String hex = m.group(2)!;
    final List<int> units = <int>[
      for (int i = 0; i < hex.length; i += 4) int.parse(hex.substring(i, i + 4), radix: 16),
    ];
    map[m.group(1)!] = String.fromCharCodes(units);
  }
  final List<String> pages = <String>[];
  for (final RegExpMatch c in RegExp(r'cm /Im0 Do Q\n([\s\S]*?)\nendstream').allMatches(s)) {
    final StringBuffer b = StringBuffer();
    for (final RegExpMatch t in RegExp(r'<([0-9a-f]+)> Tj').allMatches(c.group(1)!)) {
      final String hex = t.group(1)!;
      for (int i = 0; i < hex.length; i += 4) {
        b.write(map[hex.substring(i, i + 4)] ?? '?');
      }
    }
    pages.add(b.toString().trim());
  }
  return pages;
}

class FakeChooser implements PdfChooser {
  @override
  Future<String?> pick() async => '/docs/bill-scan.pdf';
}

class RecordingSheet implements ShareSheet {
  final List<ShareRequest> sent = <ShareRequest>[];

  @override
  Future<ShareOutcome> share(ShareRequest request) async {
    sent.add(request);
    return const ShareOutcome.dismissed();
  }
}

void main() {
  group('engine', () {
    test('keeps each page image and adds an invisible text layer', () async {
      final FakeRecognizer rec = FakeRecognizer();
      final OcrResult r = await PdfOcr(rasterizer: FakeRasterizer(), recognizer: rec).run(Uint8List(0), OcrScript.latin);
      final String s = latin1.decode(r.pdf);
      expect(s, startsWith('%PDF-1.4'));
      expect(s, endsWith('%%EOF\n'));
      expect(RegExp('/Subtype /Image').allMatches(s).length, 2);
      expect(RegExp('/Filter /DCTDecode').allMatches(s).length, 2);
      // Render mode 3: the text is there but never drawn.
      expect(RegExp(r'BT 3 Tr').allMatches(s).length, 2);
      expect(s, contains('/ToUnicode 6 0 R'));
      expect(s, contains('/Encoding /Identity-H'));
      expect(r.wordCount, 5);
      expect(rec.scripts, <OcrScript>[OcrScript.latin, OcrScript.latin]);
      // Pages are 400×560 px at 200 dpi.
      expect(s, contains('/MediaBox [0 0 144.00 201.60]'));
    });

    test('the xref points at every object', () async {
      final OcrResult r = await PdfOcr(rasterizer: FakeRasterizer(), recognizer: FakeRecognizer()).run(Uint8List(0), OcrScript.latin);
      final String s = latin1.decode(r.pdf);
      final int start = int.parse(RegExp(r'startxref\n(\d+)').firstMatch(s)!.group(1)!);
      expect(s.substring(start), startsWith('xref'));
      final List<int> offsets = RegExp(r'(\d{10}) 00000 n').allMatches(s).map((RegExpMatch m) => int.parse(m.group(1)!)).toList();
      for (int i = 0; i < offsets.length; i++) {
        expect(s.substring(offsets[i]), startsWith('${i + 1} 0 obj'));
      }
    });

    test('Latin and Devanagari text comes back out and search finds the words', () async {
      final OcrResult r = await PdfOcr(rasterizer: FakeRasterizer(), recognizer: FakeRecognizer()).run(Uint8List(0), OcrScript.devanagari);
      final List<String> pages = extractText(r.pdf);
      expect(pages, hasLength(2));
      expect(pages[0], contains('Electricity bill'));
      expect(pages[1], contains('बिजली बिल'));
      final PdfFileSearch search = PdfFileSearch(<PdfPageText>[
        for (int i = 0; i < pages.length; i++) PdfPageText.plain(i + 1, pages[i]),
      ]);
      expect(search.find('electricity BILL').single.page, 1);
      expect(search.find('बिल').map((PdfHit h) => h.page), <int>[2]);
      expect(r.pageTexts.first, 'Electricity bill\nOctober');
    });

    test('words on one row form a line, rows are in reading order', () {
      expect(
        wordsToText(const <OcrWord>[
          OcrWord('two', left: 60, top: 10, right: 90, bottom: 20),
          OcrWord('three', left: 0, top: 40, right: 40, bottom: 50),
          OcrWord('one', left: 0, top: 11, right: 30, bottom: 21),
        ]),
        'one two\nthree',
      );
      expect(wordsToText(const <OcrWord>[]), '');
    });

    test('names the copy next to the original', () {
      expect(searchableName('/docs/Bill Scan.PDF'), 'Bill Scan-searchable.pdf');
      expect(searchableName('/docs/notes'), 'notes-searchable.pdf');
    });
  });

  group('screen', () {
    Future<(RecordingSheet, Map<String, Uint8List>, PdfLibraryIndex)> pump(WidgetTester tester) async {
      final RecordingSheet sheet = RecordingSheet();
      final Map<String, Uint8List> written = <String, Uint8List>{};
      final PdfLibraryIndex idx = PdfLibraryIndex(MemoryPdfIndexBackend());
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: OcrScanScreen(
          chooser: FakeChooser(),
          readBytes: (String p) async => Uint8List(0),
          rasterizer: FakeRasterizer(),
          recognizer: FakeRecognizer(),
          writer: (String name, Uint8List bytes) async {
            written['/app/$name'] = bytes;
            return '/app/$name';
          },
          index: idx,
          share: ShareEngine(sheet, MemoryShareTargetStore()),
        ),
      ));
      await tester.pumpAndSettle();
      return (sheet, written, idx);
    }

    testWidgets('pick, run, share, search and undo', (WidgetTester tester) async {
      final (RecordingSheet sheet, Map<String, Uint8List> written, PdfLibraryIndex idx) = await pump(tester);
      await tester.tap(find.byKey(const Key('ocr-pick')));
      await tester.pumpAndSettle();
      expect(find.text('bill-scan.pdf'), findsOneWidget);
      await tester.tap(find.text('देवनागरी'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('ocr-run')));
      await tester.pumpAndSettle();
      expect(find.text('5 words on 2 pages'), findsOneWidget);
      expect(written.keys.single, '/app/bill-scan-searchable.pdf');
      expect(idx.search('electricity').hits.single.path, '/app/bill-scan-searchable.pdf');

      await tester.tap(find.byKey(const Key('result-share')));
      await tester.pumpAndSettle();
      expect(sheet.sent.single.files.single.path, '/app/bill-scan-searchable.pdf');

      await tester.tap(find.byKey(const Key('result-save')));
      await tester.pumpAndSettle();
      expect(find.text('Saved bill-scan-searchable.pdf in Files'), findsOneWidget);

      await tester.tap(find.byKey(const Key('result-undo')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('ocr-summary')), findsNothing);
      expect(idx.search('electricity').hits, isEmpty);
    });

    testWidgets('controls are labelled and at least 44 px tall', (WidgetTester tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await pump(tester);
      expect(find.bySemanticsLabel(RegExp('Script of the text')), findsWidgets);
      for (final String k in <String>['ocr-pick', 'ocr-run', 'result-share', 'result-save', 'result-undo']) {
        expect(tester.getSize(find.byKey(Key(k))).height, greaterThanOrEqualTo(44));
      }
      handle.dispose();
    });
  });
}
