import 'dart:math';
import 'dart:typed_data';

import 'package:family_utility_app/app/theme.dart';
import 'package:family_utility_app/engines/convert/pdf_to_word.dart';
import 'package:family_utility_app/engines/pdf/pdf_text_search.dart';
import 'package:family_utility_app/engines/platform/one_search.dart';
import 'package:family_utility_app/engines/share/share_engine.dart';
import 'package:family_utility_app/tools/pdf_search/pdf_search_screen.dart';
import 'package:family_utility_app/tools/pdf_viewer/pdf_viewer_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

PdfTextPiece piece(String t, double left) => PdfTextPiece(t, left: left, bottom: 700, right: left + t.length * 6, top: 712);

List<PdfTextPiece> line(String text) {
  final List<PdfTextPiece> out = <PdfTextPiece>[];
  double x = 72;
  for (final String w in text.split(' ')) {
    out.add(piece(w, x));
    x += w.length * 6 + 4;
  }
  return out;
}

/// Three pages of a policy document as PDFium would hand them over.
final List<List<PdfTextPiece>> policyPages = <List<PdfTextPiece>>[
  line('Home insurance policy for the Shah family'),
  line('The policy number is HX-2041. Renewal date is in March.'),
  <PdfTextPiece>[],
];

class FakeTextSource implements PdfTextSource {
  FakeTextSource(this.pages);

  final List<List<PdfTextPiece>> pages;
  int calls = 0;

  @override
  Future<List<List<PdfTextPiece>>> read(Uint8List pdf) async {
    calls++;
    return pages;
  }
}

class FakeChooser implements PdfChooser {
  FakeChooser(this.path);

  final String? path;

  @override
  Future<String?> pick() async => path;
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
  group('in-file search', () {
    final PdfFileSearch file = PdfFileSearch(<PdfPageText>[
      for (int i = 0; i < policyPages.length; i++) PdfPageText(i + 1, policyPages[i]),
    ]);

    test('finds every hit in page order, ignoring case', () {
      final List<PdfHit> hits = file.find('POLICY');
      expect(hits.map((PdfHit h) => h.page).toList(), <int>[1, 2]);
      expect(PdfFileSearch.pagesWithHits(hits), <int>[1, 2]);
      expect(file.find('nothing here'), isEmpty);
      expect(file.find('   '), isEmpty);
    });

    test('a phrase matches across any white space', () {
      final PdfFileSearch f = PdfFileSearch(<PdfPageText>[PdfPageText.plain(1, 'renewal\n  date is near')]);
      expect(f.find('renewal date').single.page, 1);
    });

    test('the snippet marks the match and the boxes are the words to highlight', () {
      final PdfHit h = file.find('hx-2041').single;
      expect(h.page, 2);
      expect(h.snippet.substring(h.snippetStart, h.snippetEnd).toLowerCase(), 'hx-2041');
      expect(h.boxes.map((PdfTextPiece p) => p.text).toList(), <String>['HX-2041.']);
      final PdfHit two = file.find('shah family').single;
      expect(two.boxes.map((PdfTextPiece p) => p.text).toList(), <String>['Shah', 'family']);
    });

    test('special characters in the query are literal', () {
      final PdfFileSearch f = PdfFileSearch(<PdfPageText>[PdfPageText.plain(1, 'Total (incl. tax): 1.5*2')]);
      expect(f.find('(incl.').length, 1);
      expect(f.find('1.5*2').length, 1);
    });

    test('a page with no text has no hits and a scan-only file reports no text', () {
      expect(PdfFileSearch(<PdfPageText>[PdfPageText(1, const <PdfTextPiece>[])]).hasText, isFalse);
      expect(file.hasText, isTrue);
      expect(PdfFileSearch.asText('policy.pdf', 'policy', file.find('policy')), contains('Page 2:'));
    });
  });

  group('library index', () {
    PdfLibraryIndex sample() => PdfLibraryIndex(MemoryPdfIndexBackend())
      ..put(const IndexedPdf(path: '/docs/insurance.pdf', pages: <String>['Home insurance policy', 'Renewal in March']))
      ..put(const IndexedPdf(path: '/docs/school.pdf', pages: <String>['School fees receipt', 'Term two fees paid']))
      ..put(const IndexedPdf(path: '/docs/car.pdf', pages: <String>['Car insurance renewal notice']));

    test('every word must match, as a prefix, and the phrase ranks first', () {
      final PdfLibraryIndex idx = sample();
      final LibraryOutcome o = idx.search('insurance renewal');
      expect(o.hits.map((LibraryHit h) => h.name).toList(), <String>['car.pdf', 'insurance.pdf']);
      expect(o.hits.last.pages, <int>[1, 2]);
      expect(idx.search('fee').hits.single.name, 'school.pdf');
      expect(idx.search('fee').hits.single.pages, <int>[1, 2]);
      expect(idx.search('insurance school').hits, isEmpty);
      expect(idx.search('').hits, isEmpty);
      expect(o.filesSearched, 3);
      final LibraryHit car = o.hits.first;
      expect(car.snippet.substring(car.snippetStart, car.snippetEnd).toLowerCase(), 'insurance renewal');
    });

    test('OCR text from scans is searched, follows the OCR store, and is not doubled in One search', () async {
      final PdfLibraryIndex idx = sample();
      idx.syncOcr(<String, String>{'/scans/aadhaar.jpg': 'Government of India address card'});
      final LibraryHit h = idx.search('address').hits.single;
      expect(h.ocr, isTrue);
      expect(h.path, '/scans/aadhaar.jpg');
      final List<SearchDoc> docs = await idx.collect();
      expect(docs.map((SearchDoc d) => d.ref), isNot(contains('/scans/aadhaar.jpg')));
      expect(docs.length, 3);
      expect(docs.every((SearchDoc d) => d.kind == SearchKind.text), isTrue);
      idx.syncOcr(const <String, String>{});
      expect(idx.search('address').hits, isEmpty);
    });

    test('OCR does not replace a PDF that has its own text', () {
      final PdfLibraryIndex idx = sample();
      idx.syncOcr(<String, String>{'/docs/car.pdf': 'scanned words'});
      expect(idx.search('scanned').hits, isEmpty);
      expect(idx.search('car').hits.single.ocr, isFalse);
    });

    test('saves and loads the text, and remove drops a file', () async {
      final PdfLibraryIndex idx = sample();
      await idx.save();
      final PdfLibraryIndex again = PdfLibraryIndex(idx.backend);
      await again.load();
      expect(again.fileCount, 3);
      expect(again.search('receipt').hits.single.name, 'school.pdf');
      expect(again.remove('/docs/school.pdf'), isTrue);
      expect(again.search('receipt').hits, isEmpty);
      final PdfLibraryIndex broken = PdfLibraryIndex(MemoryPdfIndexBackend()..value = '{not json');
      await broken.load();
      expect(broken.fileCount, 0);
    });

    test('searches 500 files in under a second', () {
      final Random r = Random(16);
      final List<String> vocab = <String>[for (int i = 0; i < 4000; i++) 'w${i.toRadixString(36)}x'];
      final PdfLibraryIndex idx = PdfLibraryIndex(MemoryPdfIndexBackend());
      for (int f = 0; f < 500; f++) {
        idx.put(IndexedPdf(path: '/docs/file$f.pdf', pages: <String>[
          for (int p = 0; p < 4; p++)
            List<String>.generate(150, (_) => vocab[r.nextInt(vocab.length)]).join(' ') +
                (f == 321 && p == 2 ? ' passport renewal form' : ''),
        ]));
      }
      idx.warm();
      final Stopwatch w = Stopwatch()..start();
      final LibraryOutcome rare = idx.search('passport renewal');
      final LibraryOutcome common = idx.search('w1');
      final LibraryOutcome two = idx.search('${vocab[7]} ${vocab[9]}');
      w.stop();
      expect(rare.hits.single.path, '/docs/file321.pdf');
      expect(rare.hits.single.pages, <int>[3]);
      expect(common.hits, isNotEmpty);
      expect(two.filesSearched, 500);
      expect(w.elapsed, lessThan(const Duration(seconds: 1)));
      expect(rare.elapsed, lessThan(const Duration(seconds: 1)));
    });
  });

  group('indexer', () {
    test('reads new and changed files, skips unchanged, drops missing, survives a bad file', () async {
      final PdfLibraryIndex idx = PdfLibraryIndex(MemoryPdfIndexBackend());
      List<PdfOnDisk> disk = <PdfOnDisk>[const PdfOnDisk('/a.pdf', 1), const PdfOnDisk('/b.pdf', 1), const PdfOnDisk('/bad.pdf', 1)];
      final List<String> reads = <String>[];
      final PdfLibraryIndexer indexer = PdfLibraryIndexer(
        index: idx,
        list: () async => disk,
        pageTexts: (String p) async {
          reads.add(p);
          if (p == '/bad.pdf') {
            throw const FormatException('damaged');
          }
          return <String>['text of $p version ${disk.firstWhere((PdfOnDisk d) => d.path == p).modified}'];
        },
      );
      expect(await indexer.refresh(), 2);
      expect(idx.fileCount, 3);
      reads.clear();
      expect(await indexer.refresh(), 0);
      expect(reads, isEmpty);
      disk = <PdfOnDisk>[const PdfOnDisk('/a.pdf', 2)];
      expect(await indexer.refresh(), 1);
      expect(reads, <String>['/a.pdf']);
      expect(idx.fileCount, 1);
      expect(idx.search('version 2').hits.single.path, '/a.pdf');
      expect((idx.backend as MemoryPdfIndexBackend).value, contains('/a.pdf'));
    });

    test('page texts join the positioned pieces', () {
      expect(pageTextsOf(policyPages).first, 'Home insurance policy for the Shah family');
    });
  });

  group('screen', () {
    Future<(RecordingSheet, List<String>, PdfLibraryIndex)> pump(WidgetTester tester) async {
      final RecordingSheet sheet = RecordingSheet();
      final List<String> saved = <String>[];
      final PdfLibraryIndex idx = PdfLibraryIndex(MemoryPdfIndexBackend())
        ..put(const IndexedPdf(path: '/docs/school.pdf', pages: <String>['School fees receipt', 'fees paid']));
      final FakeTextSource source = FakeTextSource(policyPages);
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: PdfSearchScreen(
          chooser: FakeChooser('/docs/policy.pdf'),
          readBytes: (String p) async => Uint8List(0),
          textSource: source,
          index: idx,
          indexer: PdfLibraryIndexer(
            index: idx,
            list: () async => <PdfOnDisk>[const PdfOnDisk('/docs/school.pdf', 5), const PdfOnDisk('/docs/bank.pdf', 5)],
            pageTexts: (String p) async =>
                p == '/docs/bank.pdf' ? <String>['Bank statement October'] : <String>['School fees receipt'],
          ),
          saver: (String t) async {
            saved.add(t);
            return '/app/pdf-search-results.txt';
          },
          share: ShareEngine(sheet, MemoryShareTargetStore()),
        ),
      ));
      await tester.pumpAndSettle();
      return (sheet, saved, idx);
    }

    testWidgets('open, find with hit list and highlights; share, save, undo', (WidgetTester tester) async {
      final (RecordingSheet sheet, List<String> saved, PdfLibraryIndex idx) = await pump(tester);
      await tester.tap(find.byKey(const Key('pdf-search-open')));
      await tester.pumpAndSettle();
      expect(find.textContaining('policy.pdf · 3 pages'), findsOneWidget);
      // Opening a file puts its text in the library index.
      expect(idx.search('shah').hits.single.path, '/docs/policy.pdf');

      await tester.enterText(find.byKey(const Key('pdf-search-box')), 'policy');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(find.text('2 hits on 2 pages'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('pdf-hit-0')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('pdf-hit-1')), findsOneWidget);
      expect(find.byKey(const Key('pdf-search-page')), findsOneWidget);
      expect(find.text('Page 1'), findsOneWidget);

      // The highlighted run in the page panel is the match.
      final Iterable<RichText> rich = tester.widgetList<RichText>(find.descendant(
        of: find.byKey(const Key('pdf-search-page')),
        matching: find.byType(RichText),
      ));
      final List<String> marked = <String>[];
      for (final RichText t in rich) {
        t.text.visitChildren((InlineSpan s) {
          if (s is TextSpan && s.style?.backgroundColor != null) {
            marked.add(s.text ?? '');
          }
          return true;
        });
      }
      expect(marked, <String>['policy']);

      await tester.tap(find.byKey(const ValueKey<String>('pdf-hit-1')));
      await tester.pumpAndSettle();
      expect(find.text('Page 2'), findsOneWidget);

      await tester.tap(find.byKey(const Key('result-share')));
      await tester.pumpAndSettle();
      expect(sheet.sent.single.text, contains('"policy" in policy.pdf: 2 hits'));

      await tester.tap(find.byKey(const Key('result-save')));
      await tester.pumpAndSettle();
      expect(saved.single, contains('Page 2:'));

      await tester.enterText(find.byKey(const Key('pdf-search-box')), 'march');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(find.text('1 hit on 1 page'), findsOneWidget);
      await tester.tap(find.byKey(const Key('result-undo')));
      await tester.pumpAndSettle();
      expect(find.text('2 hits on 2 pages'), findsOneWidget);
    });

    testWidgets('all PDFs: update the index, search, and open a hit in the file view', (WidgetTester tester) async {
      await pump(tester);
      await tester.tap(find.text('All PDFs'));
      await tester.pumpAndSettle();
      expect(find.text('1 file indexed'), findsOneWidget);
      await tester.tap(find.byKey(const Key('pdf-library-refresh')));
      await tester.pumpAndSettle();
      expect(find.text('Read 2 files'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('pdf-search-box')), 'statement');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey<String>('pdf-library-hit-0')), findsOneWidget);
      expect(find.text('bank.pdf'), findsOneWidget);
      expect(find.textContaining('1 of 2 files'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey<String>('pdf-library-hit-0')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('pdf-search-count')), findsOneWidget);
    });

    testWidgets('hits are labelled for screen readers and at least 44 px tall', (WidgetTester tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await pump(tester);
      await tester.tap(find.byKey(const Key('pdf-search-open')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('pdf-search-box')), 'renewal');
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel(RegExp(r'^Page 2: .*Renewal')), findsOneWidget);
      expect(tester.getSize(find.byKey(const ValueKey<String>('pdf-hit-0'))).height, greaterThanOrEqualTo(44));
      for (final String k in <String>['result-share', 'result-save', 'result-undo', 'pdf-library-refresh']) {
        if (k == 'pdf-library-refresh') {
          await tester.tap(find.text('All PDFs'));
          await tester.pumpAndSettle();
        }
        expect(tester.getSize(find.byKey(Key(k))).height, greaterThanOrEqualTo(44));
      }
      handle.dispose();
    });
  });
}
