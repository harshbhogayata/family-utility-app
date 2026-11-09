import 'dart:convert';
import 'dart:typed_data';

import 'package:family_utility_app/app/theme.dart';
import 'package:family_utility_app/engines/pdf/page_extractor.dart';
import 'package:family_utility_app/engines/pdf/pdf_compressor.dart';
import 'package:family_utility_app/engines/pdf/pdf_splitter.dart';
import 'package:family_utility_app/engines/pdf/pdf_to_images.dart';
import 'package:family_utility_app/engines/share/share_engine.dart';
import 'package:family_utility_app/tools/extract_pages/extract_pages_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

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

/// Which source pages the output holds, in page-tree order. Page k of
/// [pagesPdf] is object 5 + 2(k - 1) and keeps its number in the output.
List<int> pageOrder(Uint8List pdf) {
  final PdfDocumentModel d = PdfDocumentModel.parse(pdf);
  final PdfDict root = d.resolve(d.trailer['Root'])! as PdfDict;
  final PdfDict pages = d.resolve(root['Pages'])! as PdfDict;
  return <int>[
    for (final Object k in (pages['Kids']! as PdfArray).items) ((k as PdfRef).num - 5) ~/ 2 + 1,
  ];
}

class FakeFiles implements ExtractFiles {
  FakeFiles(this.picked);
  final ExtractSource? picked;
  final Map<String, Uint8List> written = <String, Uint8List>{};

  @override
  Future<ExtractSource?> pick() async => picked;

  @override
  Future<String> write(String name, Uint8List bytes) async {
    written['/extracted/$name'] = bytes;
    return '/extracted/$name';
  }

  @override
  Future<void> remove(String path) async => written.remove(path);
}

class FakeRasterizer implements PdfRasterizer {
  @override
  Future<int> pageCount(Uint8List pdf) async => 5;

  @override
  Future<img.Image> render(Uint8List pdf, int index, int dpi) async => img.Image(width: 8, height: 11);
}

class FakeSheet implements ShareSheet {
  final List<ShareRequest> requests = <ShareRequest>[];

  @override
  Future<ShareOutcome> share(ShareRequest request) async {
    requests.add(request);
    return const ShareOutcome(completed: true);
  }
}

Future<ExtractResult> direct(ExtractRequest r) async => PageExtractor.run(r);

void main() {
  group('engine', () {
    test('pages come out in the order they were chosen', () {
      final ExtractResult r = PageExtractor.extract(pagesPdf(6), 'report.pdf', <int>[5, 2, 6]);
      expect(pageOrder(r.bytes), <int>[5, 2, 6]);
      expect(r.sourcePages, 6);
      expect(r.name, 'report pages 5, 2, 6.pdf');
      expect(latin1.decode(r.bytes), isNot(contains('(Page 1)')));
      // Inherited landscape size and fonts travel with each page.
      final PdfDocumentModel d = PdfDocumentModel.parse(r.bytes);
      final PdfDict root = d.resolve(d.trailer['Root'])! as PdfDict;
      final PdfDict pages = d.resolve(root['Pages'])! as PdfDict;
      final PdfDict first = d.resolve((pages['Kids']! as PdfArray).items.first)! as PdfDict;
      expect(first['MediaBox'], isNotNull);
      expect(first['Resources'], isNotNull);
    });

    test('repeats are dropped; empty and missing pages are refused', () {
      expect(PageExtractor.extract(pagesPdf(3), 'a.pdf', <int>[2, 2, 1]).pages, <int>[2, 1]);
      expect(() => PageExtractor.extract(pagesPdf(3), 'a.pdf', <int>[]), throwsA(isA<SplitError>()));
      expect(() => PageExtractor.extract(pagesPdf(3), 'a.pdf', <int>[4]), throwsA(isA<SplitError>()));
      expect(() => PageExtractor.extract(Uint8List.fromList(<int>[1, 2, 3]), 'a.pdf', <int>[1]), throwsA(isA<SplitError>()));
    });

    test('long picks get a short name', () {
      expect(PageExtractor.outputName('x.pdf', <int>[1]), 'x page 1.pdf');
      expect(PageExtractor.outputName('x.pdf', <int>[1, 2, 3, 4, 5, 6, 7, 8]), 'x pages 1, 2, 3, 4, 5 and 3 more.pdf');
    });

    test('selection keeps tap order and renumbers when one is dropped', () {
      final PageSelection s = PageSelection()
        ..toggle(3)
        ..toggle(1)
        ..toggle(5);
      expect(s.order, <int>[3, 1, 5]);
      expect(s.placeOf(5), 3);
      s.toggle(1);
      expect(s.order, <int>[3, 5]);
      expect(s.placeOf(5), 2);
      s.selectAll(4);
      expect(s.order, <int>[3, 5, 1, 2, 4]);
    });
  });

  group('screen', () {
    testWidgets('tap pages, extract in that order, share and undo', (WidgetTester tester) async {
      final FakeFiles files = FakeFiles(ExtractSource('report.pdf', pagesPdf(5)));
      final FakeSheet sheet = FakeSheet();
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: ExtractPagesScreen(
          files: files,
          rasterizer: FakeRasterizer(),
          runner: direct,
          share: ShareEngine(sheet, MemoryShareTargetStore()),
        ),
      ));
      await tester.tap(find.byKey(const Key('extract-pick')));
      await tester.pumpAndSettle();
      expect(find.text('0 of 5 chosen'), findsOneWidget);

      for (final int p in <int>[3, 1, 5]) {
        await tester.ensureVisible(find.byKey(Key('extract-page-$p')));
        await tester.tap(find.byKey(Key('extract-page-$p')));
        await tester.pump();
      }
      expect(find.text('3 of 5 chosen'), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('extract-place-5'))).data, '3');
      expect(find.bySemanticsLabel('Page 1, chosen 2nd'), findsOneWidget);
      expect(tester.getSize(find.byKey(const Key('extract-page-1'))).height, greaterThanOrEqualTo(44));

      await tester.ensureVisible(find.byKey(const Key('extract-run')));
      await tester.tap(find.byKey(const Key('extract-run')));
      await tester.pumpAndSettle();
      expect(files.written.keys.single, '/extracted/report pages 3, 1, 5.pdf');
      expect(pageOrder(files.written.values.single), <int>[3, 1, 5]);

      await tester.tap(find.byKey(const Key('result-share')));
      await tester.pumpAndSettle();
      expect(sheet.requests.single.files.single.path, '/extracted/report pages 3, 1, 5.pdf');

      await tester.tap(find.byKey(const Key('result-undo')));
      await tester.pumpAndSettle();
      expect(files.written, isEmpty);
      expect(find.text('3 of 5 chosen'), findsOneWidget);

      await tester.tap(find.byKey(const Key('result-undo')));
      await tester.pumpAndSettle();
      expect(find.text('0 of 5 chosen'), findsOneWidget);
      await tester.tap(find.byKey(const Key('result-undo')));
      await tester.pumpAndSettle();
      expect(find.text('3 of 5 chosen'), findsOneWidget);
    });
  });
}
