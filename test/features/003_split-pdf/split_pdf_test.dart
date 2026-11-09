import 'dart:convert';
import 'dart:typed_data';

import 'package:family_utility_app/app/theme.dart';
import 'package:family_utility_app/engines/archive/zip_codec.dart';
import 'package:family_utility_app/engines/pdf/pdf_compressor.dart';
import 'package:family_utility_app/engines/pdf/pdf_splitter.dart';
import 'package:family_utility_app/engines/share/share_engine.dart';
import 'package:family_utility_app/tools/split_pdf/split_pdf_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A classic PDF from object bodies, numbered from 1, with a real xref.
Uint8List classicPdf(List<String> bodies) {
  final StringBuffer b = StringBuffer('%PDF-1.4\n');
  final List<int> offsets = <int>[];
  for (int i = 0; i < bodies.length; i++) {
    offsets.add(b.length);
    b.write('${i + 1} 0 obj\n${bodies[i]}\nendobj\n');
  }
  final int xref = b.length;
  b.write('xref\n0 ${bodies.length + 1}\n0000000000 65535 f \n');
  for (final int o in offsets) {
    b.write('${o.toString().padLeft(10, '0')} 00000 n \n');
  }
  b.write('trailer\n<< /Size ${bodies.length + 1} /Root 1 0 R >>\nstartxref\n$xref\n%%EOF\n');
  return Uint8List.fromList(latin1.encode(b.toString()));
}

/// [n] pages under a nested page tree that holds a landscape MediaBox and
/// the font. Page k draws "Page k" and, when [padding] is set, carries that
/// many bytes of filler in its content stream.
Uint8List pagesPdf(int n, {int padding = 0}) {
  // 1 catalog, 2 root pages, 3 inner pages, 4 font, then page/content pairs.
  final List<String> bodies = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count $n /MediaBox [0 0 842 595] >>',
    '', // filled below
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
  ];
  final List<String> kids = <String>[];
  for (int k = 1; k <= n; k++) {
    final int pageNum = bodies.length + 1;
    final String pad = padding == 0 ? '' : '\n% ${'x' * padding}';
    final String content = 'BT /F1 12 Tf 72 500 Td (Page $k) Tj ET$pad';
    bodies.add('<< /Type /Page /Parent 3 0 R /Contents ${pageNum + 1} 0 R >>');
    bodies.add('<< /Length ${content.length} >>\nstream\n$content\nendstream');
    kids.add('$pageNum 0 R');
  }
  bodies[2] = '<< /Type /Pages /Parent 2 0 R /Kids [${kids.join(' ')}] /Count $n '
      '/Resources << /Font << /F1 4 0 R >> >> >>';
  return classicPdf(bodies);
}

String text(Uint8List b) => latin1.decode(b);

List<PdfDict> pagesOf(PdfDocumentModel d) {
  final PdfDict root = d.resolve(d.trailer['Root'])! as PdfDict;
  final PdfDict pages = d.resolve(root['Pages'])! as PdfDict;
  return <PdfDict>[for (final Object k in (pages['Kids']! as PdfArray).items) d.resolve(k)! as PdfDict];
}

/// Which "Page k" labels a part draws.
List<int> labels(Uint8List part) =>
    RegExp(r'\(Page (\d+)\)').allMatches(text(part)).map((RegExpMatch m) => int.parse(m.group(1)!)).toList();

class FakeFiles implements SplitFiles {
  FakeFiles(this.picked);
  final PickedPdf? picked;
  final Map<String, Uint8List> written = <String, Uint8List>{};

  @override
  Future<PickedPdf?> pick() async => picked;

  @override
  Future<String> write(String set, String name, Uint8List bytes) async {
    final String path = '/split/$set/$name';
    written[path] = bytes;
    return path;
  }

  @override
  Future<void> remove(String path) async => written.remove(path);
}

class FakeSheet implements ShareSheet {
  final List<ShareRequest> requests = <ShareRequest>[];

  @override
  Future<ShareOutcome> share(ShareRequest request) async {
    requests.add(request);
    return const ShareOutcome(completed: true);
  }
}

void main() {
  group('ranges', () {
    test('accepts 1-3, 5, 8-10 and friends', () {
      expect(PageRanges.parse('1-3, 5, 8-10', 10),
          const <PageRange>[PageRange(1, 3), PageRange(5, 5), PageRange(8, 10)]);
      expect(PageRanges.parse(' 2 – 4 ;7', 10), const <PageRange>[PageRange(2, 4), PageRange(7, 7)]);
      expect(PageRanges.parse('8-', 10), const <PageRange>[PageRange(8, 10)]);
      expect(PageRanges.parse('1 to 2', 10), const <PageRange>[PageRange(1, 2)]);
    });

    test('says plainly what is wrong', () {
      expect(() => PageRanges.parse('', 5), throwsA(isA<SplitError>()));
      expect(() => PageRanges.parse('0', 5), throwsA(isA<SplitError>()));
      expect(() => PageRanges.parse('4-9', 5),
          throwsA(isA<SplitError>().having((SplitError e) => e.message, 'message', contains('last page (5)'))));
      expect(() => PageRanges.parse('4-2', 5),
          throwsA(isA<SplitError>().having((SplitError e) => e.message, 'message', contains('2-4'))));
      expect(() => PageRanges.parse('abc', 5), throwsA(isA<SplitError>()));
    });
  });

  group('engine', () {
    test('ranges make one part each with only their pages, keeping inherited size and fonts', () {
      final PdfSplitResult r = PdfSplitter.byRanges(pagesPdf(10), 'report.pdf', '1-3, 5, 8-10');
      expect(r.pageCount, 10);
      expect(r.parts.map((SplitPart p) => p.name), <String>[
        'report part 01 (p1-3).pdf',
        'report part 02 (p5).pdf',
        'report part 03 (p8-10).pdf',
      ]);
      expect(labels(r.parts[0].bytes), <int>[1, 2, 3]);
      expect(labels(r.parts[1].bytes), <int>[5]);
      expect(labels(r.parts[2].bytes), <int>[8, 9, 10]);
      for (final SplitPart p in r.parts) {
        final PdfDocumentModel d = PdfDocumentModel.parse(p.bytes);
        expect(d.pageCount(), p.range.length);
        for (final PdfDict page in pagesOf(d)) {
          final PdfArray box = d.resolve(page['MediaBox'])! as PdfArray;
          expect(box.items.map((Object o) => (o as PdfNum).value.round()), <int>[0, 0, 842, 595]);
          expect(d.resolve(page['Resources']), isA<PdfDict>());
        }
      }
    });

    test('every N numbers parts in order and the last takes what is left', () {
      final PdfSplitResult r = PdfSplitter.everyN(pagesPdf(7), 'scan.pdf', 3);
      expect(r.parts.map((SplitPart p) => p.number), <int>[1, 2, 3]);
      expect(r.parts.map((SplitPart p) => p.range), const <PageRange>[PageRange(1, 3), PageRange(4, 6), PageRange(7, 7)]);
      expect(r.parts.last.name, 'scan part 03 (p7).pdf');
      expect(labels(r.parts[1].bytes), <int>[4, 5, 6]);
      expect(() => PdfSplitter.everyN(pagesPdf(2), 'a.pdf', 0), throwsA(isA<SplitError>()));
    });

    test('numbers are padded so twelve parts sort in order', () {
      final PdfSplitResult r = PdfSplitter.everyN(pagesPdf(12), 'a.pdf', 1);
      expect(r.parts.first.name, 'a part 01 (p1).pdf');
      expect(r.parts.last.name, 'a part 12 (p12).pdf');
      final List<String> sorted = r.parts.map((SplitPart p) => p.name).toList()..sort();
      expect(sorted, r.parts.map((SplitPart p) => p.name).toList());
    });

    test('by size keeps each part under the limit and covers every page once', () {
      final Uint8List src = pagesPdf(9, padding: 3000);
      final int limit = PdfSplitter.everyN(src, 'a.pdf', 3).parts.first.bytes.length + 100;
      final PdfSplitResult r = PdfSplitter.bySize(src, 'big.pdf', limit);
      expect(r.parts.length, greaterThan(1));
      expect(r.overLimit, 0);
      final List<int> all = <int>[for (final SplitPart p in r.parts) ...labels(p.bytes)];
      expect(all, <int>[1, 2, 3, 4, 5, 6, 7, 8, 9]);
      for (final SplitPart p in r.parts) {
        expect(p.bytes.length, lessThanOrEqualTo(limit));
      }
      expect(r.parts.map((SplitPart p) => p.number), List<int>.generate(r.parts.length, (int i) => i + 1));
    });

    test('a page bigger than the limit gets a part of its own, flagged', () {
      final PdfSplitResult r = PdfSplitter.bySize(pagesPdf(2, padding: 4000), 'a.pdf', 2048);
      expect(r.parts.length, 2);
      expect(r.overLimit, 2);
    });

    test('megabytes reads decimals and refuses nonsense', () {
      expect(PdfSplitter.megabytes('5'), 5 * 1024 * 1024);
      expect(PdfSplitter.megabytes('2,5'), (2.5 * 1024 * 1024).round());
      expect(PdfSplitter.megabytes('0'), isNull);
      expect(PdfSplitter.megabytes('lots'), isNull);
    });

    test('the parts come as one ZIP in order', () {
      final PdfSplitResult r = PdfSplitter.everyN(pagesPdf(4), 'trip.pdf', 2);
      final Uint8List zip = PdfSplitter.zip(r, now: DateTime(2026, 1, 2));
      final List<ZipEntry> entries = ZipReader(zip).entries;
      expect(entries.map((ZipEntry e) => e.name), <String>['trip part 01 (p1-2).pdf', 'trip part 02 (p3-4).pdf']);
      expect(PdfSplitter.zipName('trip.pdf'), 'trip parts.zip');
    });

    test('run dispatches every mode', () {
      final Uint8List src = pagesPdf(4);
      expect(PdfSplitter.run(SplitRequest(bytes: src, name: 'a.pdf', mode: SplitMode.ranges, value: '1,2-4')).parts.length, 2);
      expect(PdfSplitter.run(SplitRequest(bytes: src, name: 'a.pdf', mode: SplitMode.everyN, value: '1')).parts.length, 4);
      expect(
          PdfSplitter.run(SplitRequest(bytes: src, name: 'a.pdf', mode: SplitMode.bySize, value: '${1024 * 1024}')).parts.length,
          1);
      expect(() => PdfSplitter.run(SplitRequest(bytes: src, name: 'a.pdf', mode: SplitMode.everyN, value: 'x')),
          throwsA(isA<SplitError>()));
    });
  });

  group('screen', () {
    Future<void> pumpScreen(WidgetTester tester, FakeFiles files, FakeSheet sheet) async {
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: SplitPdfScreen(
          files: files,
          runner: (SplitRequest r) async => PdfSplitter.run(r),
          share: ShareEngine(sheet, MemoryShareTargetStore()),
          clock: () => DateTime(2026, 1, 2),
        ),
      ));
    }

    testWidgets('splits by ranges, saves the set and a zip, shares the zip, undo removes', (WidgetTester tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      final FakeFiles files = FakeFiles(PickedPdf('report.pdf', pagesPdf(6)));
      final FakeSheet sheet = FakeSheet();
      await pumpScreen(tester, files, sheet);

      await tester.tap(find.byKey(const Key('split-pick')));
      await tester.pumpAndSettle();
      expect(find.text('6 pages'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('split-value')), '1-2, 4-6');
      await tester.tap(find.byKey(const Key('split-run')));
      await tester.pumpAndSettle();

      expect(find.text('Split 6 pages into 2 parts'), findsOneWidget);
      expect(files.written.keys.where((String k) => k.endsWith('.pdf')), hasLength(2));
      expect(files.written.keys.where((String k) => k.endsWith('report parts.zip')), hasLength(1));
      expect(tester.getSize(find.byKey(const Key('split-run'))).height, greaterThanOrEqualTo(44));

      await tester.tap(find.byKey(const Key('result-share')));
      await tester.pumpAndSettle();
      expect(sheet.requests.single.files.single.path, endsWith('report parts.zip'));

      // The list builds lazily: scroll until the button exists.
      await tester.dragUntilVisible(find.byKey(const Key('split-share-parts')), find.byType(ListView), const Offset(0, -200));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Share the parts as separate PDFs'), findsOneWidget);
      await tester.tap(find.byKey(const Key('split-share-parts')));
      await tester.pumpAndSettle();
      expect(sheet.requests.last.files, hasLength(2));

      await tester.tap(find.byKey(const Key('result-undo')));
      await tester.pumpAndSettle();
      expect(files.written, isEmpty);
      expect(find.text('Removed the parts'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('by size takes megabytes and a bad range shows the reason', (WidgetTester tester) async {
      final FakeFiles files = FakeFiles(PickedPdf('a.pdf', pagesPdf(3)));
      await pumpScreen(tester, files, FakeSheet());
      await tester.tap(find.byKey(const Key('split-pick')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('split-value')), '9');
      await tester.tap(find.byKey(const Key('split-run')));
      await tester.pumpAndSettle();
      expect(find.text('"9" goes past the last page (3).'), findsOneWidget);

      await tester.tap(find.text('By size'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('split-value')), 'big');
      await tester.tap(find.byKey(const Key('split-run')));
      await tester.pumpAndSettle();
      expect(find.text('Type a size in MB, like 5 or 2.5.'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('split-value')), '1');
      await tester.tap(find.byKey(const Key('split-run')));
      await tester.pumpAndSettle();
      expect(find.text('Split 3 pages into 1 part'), findsOneWidget);
    });
  });
}
