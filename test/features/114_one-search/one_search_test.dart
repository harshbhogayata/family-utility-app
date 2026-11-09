import 'dart:io';

import 'package:family_utility_app/app/theme.dart';
import 'package:family_utility_app/engines/platform/action_history.dart';
import 'package:family_utility_app/engines/platform/file_manager.dart';
import 'package:family_utility_app/engines/platform/one_search.dart';
import 'package:family_utility_app/engines/security/secure_notes.dart';
import 'package:family_utility_app/engines/share/share_engine.dart';
import 'package:family_utility_app/tools/one_search/one_search_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// An in-memory disk: paths to contents, plus folders.
class MemorySource implements FileSource {
  MemorySource(this.files, this.dirs);

  final Map<String, String> files;
  final Set<String> dirs;

  @override
  Future<List<FileNode>> list(String dir) async {
    if (!dirs.contains(dir)) {
      throw FileSystemException('no such folder', dir);
    }
    final List<FileNode> out = <FileNode>[];
    for (final String d in dirs) {
      if (d != dir && parentOf(d) == dir) {
        out.add(FileNode(path: d, isDir: true, modified: DateTime(2026)));
      }
    }
    files.forEach((String p, String c) {
      if (parentOf(p) == dir) {
        out.add(FileNode(path: p, isDir: false, size: c.length, modified: DateTime(2026)));
      }
    });
    return out;
  }

  @override
  Future<FileNode?> stat(String path) async => null;

  @override
  Future<String?> readText(String path, int maxBytes) async => files[path];

  @override
  Future<void> rename(String from, String to) async {}

  @override
  Future<void> createFolder(String path) async {}
}

class NoTrash implements TrashBin {
  @override
  Future<String> moveIn(String path, String id) async => path;

  @override
  Future<String> moveOut(String trashedPath, String originalPath) async => originalPath;

  @override
  Future<void> purge(String trashedPath) async {}
}

class ListSource implements SearchSource {
  ListSource(this.docs);

  final List<SearchDoc> docs;
  int calls = 0;

  @override
  Future<List<SearchDoc>> collect() async {
    calls++;
    return docs;
  }
}

class RecordingSheet implements ShareSheet {
  final List<ShareRequest> sent = <ShareRequest>[];

  @override
  Future<ShareOutcome> share(ShareRequest request) async {
    sent.add(request);
    return const ShareOutcome.dismissed();
  }
}

const List<SearchDoc> sample = <SearchDoc>[
  SearchDoc(kind: SearchKind.tool, ref: 'pdf-viewer', title: 'PDF viewer', subtitle: 'PDF'),
  SearchDoc(kind: SearchKind.tool, ref: 'compress-images', title: 'Compress images', subtitle: 'Compress'),
  SearchDoc(kind: SearchKind.file, ref: '/docs/passport.pdf', title: 'passport.pdf', subtitle: 'App files · /'),
  SearchDoc(
    kind: SearchKind.text,
    ref: '/docs/bill.jpg',
    title: 'bill.jpg',
    subtitle: 'Scanned text',
    body: 'Electricity bill for October, amount due 2,340',
  ),
  SearchDoc(kind: SearchKind.history, ref: 'h1', title: 'Compress images', subtitle: 'beach.jpg'),
  SearchDoc(kind: SearchKind.record, ref: 'n1', title: 'Car insurance', subtitle: 'Policy number'),
];

void main() {
  group('index', () {
    test('tokenize splits on punctuation and lower-cases any script', () {
      expect(tokenize('Hello, World! passport-2026.pdf'), <String>['hello', 'world', 'passport', '2026', 'pdf']);
      expect(tokenize('बिजली बिल'), <String>['बिजली', 'बिल']);
      expect(tokenize('   '), isEmpty);
    });

    test('finds tools, files, OCR text, history and records from one box', () {
      final SearchIndex idx = SearchIndex(sample);
      expect(idx.query('pdf').map((SearchResult r) => r.doc.ref), containsAll(<String>['pdf-viewer', '/docs/passport.pdf']));
      expect(idx.query('electric').single.doc.ref, '/docs/bill.jpg');
      expect(idx.query('electric').single.snippet, contains('Electricity bill'));
      expect(idx.query('insur').single.doc.kind, SearchKind.record);
      expect(idx.query('beach').single.doc.kind, SearchKind.history);
    });

    test('every word must match, as a prefix', () {
      final SearchIndex idx = SearchIndex(sample);
      expect(idx.query('compress ima').length, 2);
      expect(idx.query('compress pdf'), isEmpty);
      expect(idx.query(''), isEmpty);
      expect(idx.query('zzz'), isEmpty);
    });

    test('exact title and tools rank first', () {
      final SearchIndex idx = SearchIndex(sample);
      final List<SearchResult> r = idx.query('compress images');
      expect(r.first.doc.kind, SearchKind.tool);
      final SearchIndex idx2 = SearchIndex(const <SearchDoc>[
        SearchDoc(kind: SearchKind.file, ref: 'a', title: 'notes.txt', body: 'receipt for the fridge'),
        SearchDoc(kind: SearchKind.file, ref: 'b', title: 'receipt.pdf'),
      ]);
      expect(idx2.query('receipt').first.doc.ref, 'b');
    });

    test('queries 20,000 documents in under 300 ms', () {
      final List<SearchDoc> many = <SearchDoc>[
        for (int i = 0; i < 20000; i++)
          SearchDoc(
            kind: SearchKind.values[i % SearchKind.values.length],
            ref: 'r$i',
            title: 'Document $i invoice ${i % 97}',
            body: 'scanned page $i with words alpha${i % 13} beta${i % 31} gamma',
          ),
      ];
      final SearchIndex idx = SearchIndex(many);
      final Stopwatch w = Stopwatch()..start();
      final List<SearchResult> a = idx.query('invoice alpha1');
      final List<SearchResult> b = idx.query('gam');
      final List<SearchResult> c = idx.query('document 1999');
      w.stop();
      expect(a, isNotEmpty);
      expect(b.length, 50);
      expect(c.first.doc.ref, 'r1999');
      expect(w.elapsedMilliseconds, lessThan(300));
    });
  });

  group('sources', () {
    test('files: names under every root and words inside text files, offline', () async {
      final FileManager fm = FileManager(
        source: MemorySource(
          <String, String>{
            '/app/passport.pdf': '%PDF',
            '/app/bills/water.txt': 'Water board receipt 2026',
            '/app/.cache/hidden.txt': 'secret',
          },
          <String>{'/app', '/app/bills', '/app/.cache'},
        ),
        history: ActionHistory(store: MemoryHistoryStore(), bin: NoTrash()),
        store: MemoryFileManagerStore(),
        roots: const <FileRoot>[FileRoot('App files', '/app')],
      );
      final List<SearchDoc> docs = await FileSearchSource(fm).collect();
      expect(docs.map((SearchDoc d) => d.title), unorderedEquals(<String>['passport.pdf', 'water.txt']));
      final SearchIndex idx = SearchIndex(docs);
      expect(idx.query('board').single.doc.ref, '/app/bills/water.txt');
      expect(idx.query('passport').single.doc.subtitle, 'App files · /');
    });

    test('history entries are found by tool and file name', () async {
      final ActionHistory h = ActionHistory(store: MemoryHistoryStore(), bin: NoTrash());
      await h.record(
        toolId: 'compress-images',
        toolName: 'Compress images',
        inputs: <String>['/p/beach.jpg'],
        outputs: <String>['/p/beach-small.jpg'],
      );
      final SearchIndex idx = SearchIndex(await HistorySearchSource(h).collect());
      expect(idx.query('beach').single.doc.title, 'Compress images');
    });

    test('records: titles and labels match, secret values never enter the index', () async {
      final SecureNotes notes = SecureNotes(
        keyStore: MemoryKeyStore(),
        blobStore: MemoryNoteBlobStore(),
        clipboard: MemoryClipboard(),
      );
      await notes.load();
      await notes.save(SecureNote(
        id: 'n1',
        title: 'Home wifi',
        fields: const <NoteField>[
          NoteField(label: 'Network', value: 'Sharma5G', secret: false),
          NoteField(label: 'Password', value: 'hunter2xyz'),
        ],
        updatedAt: DateTime(2026),
      ));
      final List<SearchDoc> docs = await RecordSearchSource(notes).collect();
      final SearchIndex idx = SearchIndex(docs);
      expect(idx.query('wifi').single.doc.kind, SearchKind.record);
      expect(idx.query('sharma5g'), hasLength(1));
      expect(idx.query('hunter2xyz'), isEmpty);
      expect(docs.single.body, isNot(contains('hunter2xyz')));
    });

    test('OCR text store persists and is searchable', () async {
      final MemoryOcrBackend backend = MemoryOcrBackend();
      final OcrTextStore store = OcrTextStore(backend);
      await store.put('/scans/receipt.jpg', 'Grocery total 812');
      final OcrTextStore again = OcrTextStore(backend);
      await again.load();
      final SearchIndex idx = SearchIndex(await again.collect());
      expect(idx.query('grocery').single.doc.ref, '/scans/receipt.jpg');
      await again.remove('/scans/receipt.jpg');
      expect(again.all, isEmpty);
    });

    test('OneSearch merges sources, skips a failing one, and rebuilds when stale', () async {
      final ListSource ok = ListSource(sample);
      final OneSearch s = OneSearch(<SearchSource>[ok, _Broken(), ListSource(sample)]);
      final SearchOutcome o = await s.search('pdf');
      expect(o.results.length, 2);
      expect(s.index.size, sample.length);
      await s.search('pdf');
      expect(ok.calls, 1);
      s.invalidate();
      await s.search('pdf');
      expect(ok.calls, 2);
      expect(o.asText(), contains('PDF viewer'));
      expect(o.grouped.keys, <SearchKind>[SearchKind.tool, SearchKind.file]);
    });
  });

  group('screen', () {
    Future<(OneSearch, List<SearchDoc>, RecordingSheet, List<String>)> pump(WidgetTester tester) async {
      final OneSearch s = OneSearch(<SearchSource>[ListSource(sample)]);
      final List<SearchDoc> opened = <SearchDoc>[];
      final RecordingSheet sheet = RecordingSheet();
      final List<String> saved = <String>[];
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: OneSearchScreen(
          search: s,
          opener: (BuildContext _, SearchDoc d) async => opened.add(d),
          saver: (String t) async {
            saved.add(t);
            return '/app/search-results.txt';
          },
          share: ShareEngine(sheet, MemoryShareTargetStore()),
        ),
      ));
      await tester.pumpAndSettle();
      return (s, opened, sheet, saved);
    }

    testWidgets('typing shows grouped hits; tapping opens; share, save and undo work', (WidgetTester tester) async {
      final (_, List<SearchDoc> opened, RecordingSheet sheet, List<String> saved) = await pump(tester);
      expect(find.textContaining('runs on this phone'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('one-search-box')), 'pdf');
      await tester.pumpAndSettle();
      expect(find.text('Tools'), findsOneWidget);
      expect(find.text('Files'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('hit-tool:pdf-viewer')), findsOneWidget);
      expect(find.byKey(const Key('one-search-count')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey<String>('hit-file:/docs/passport.pdf')));
      await tester.pumpAndSettle();
      expect(opened.single.ref, '/docs/passport.pdf');

      await tester.tap(find.byKey(const Key('result-share')));
      await tester.pumpAndSettle();
      expect(sheet.sent.single.text, contains('passport.pdf'));

      await tester.tap(find.byKey(const Key('result-save')));
      await tester.pumpAndSettle();
      expect(saved.single, contains('PDF viewer'));
      expect(find.text('Saved search-results.txt in Files'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('one-search-box')), 'insurance');
      await tester.pumpAndSettle();
      expect(find.text('Car insurance'), findsOneWidget);
      await tester.tap(find.byKey(const Key('result-undo')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey<String>('hit-tool:pdf-viewer')), findsOneWidget);
      expect(find.text('Car insurance'), findsNothing);

      await tester.enterText(find.byKey(const Key('one-search-box')), 'nothinghere');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('one-search-empty')), findsOneWidget);
    });

    testWidgets('hits are labelled for screen readers and at least 44 px tall', (WidgetTester tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await pump(tester);
      await tester.enterText(find.byKey(const Key('one-search-box')), 'electric');
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel(RegExp(r'^Text in files: bill\.jpg')), findsOneWidget);
      final Size size = tester.getSize(find.byKey(const ValueKey<String>('hit-text:/docs/bill.jpg')));
      expect(size.height, greaterThanOrEqualTo(44));
      for (final String k in <String>['result-share', 'result-save', 'result-undo']) {
        expect(tester.getSize(find.byKey(Key(k))).height, greaterThanOrEqualTo(44));
      }
      handle.dispose();
    });
  });
}

class _Broken implements SearchSource {
  @override
  Future<List<SearchDoc>> collect() async => throw const FileSystemException('denied');
}
