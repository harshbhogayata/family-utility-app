import 'dart:convert';
import 'dart:typed_data';

import 'package:family_utility_app/app/theme.dart';
import 'package:family_utility_app/engines/pdf/page_reorder.dart';
import 'package:family_utility_app/engines/pdf/pdf_compressor.dart';
import 'package:family_utility_app/engines/pdf/pdf_splitter.dart';
import 'package:family_utility_app/engines/pdf/pdf_to_images.dart';
import 'package:family_utility_app/engines/share/share_engine.dart';
import 'package:family_utility_app/tools/reorder_pages/reorder_pages_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
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

List<PdfDict> pageDicts(Uint8List pdf) {
  final PdfDocumentModel d = PdfDocumentModel.parse(pdf);
  final PdfDict root = d.resolve(d.trailer['Root'])! as PdfDict;
  final PdfDict pages = d.resolve(root['Pages'])! as PdfDict;
  return <PdfDict>[for (final Object k in (pages['Kids']! as PdfArray).items) d.resolve(k)! as PdfDict];
}

/// Source page numbers in output order; 0 for a blank page. Page k of
/// [pagesPdf] draws through content object 6 + 2(k - 1).
List<int> pageOrder(Uint8List pdf) => <int>[
      for (final PdfDict p in pageDicts(pdf))
        p['Contents'] == null ? 0 : ((p['Contents']! as PdfRef).num - 6) ~/ 2 + 1,
    ];

List<String> boxOf(PdfDict p) => <String>[for (final Object n in (p['MediaBox']! as PdfArray).items) (n as PdfNum).raw];

class FakeFiles implements ReorderFiles {
  FakeFiles(this.picked);
  final ReorderSource? picked;
  final Map<String, Uint8List> written = <String, Uint8List>{};

  @override
  Future<ReorderSource?> pick() async => picked;

  @override
  Future<String> write(String name, Uint8List bytes) async {
    written['/edited/$name'] = bytes;
    return '/edited/$name';
  }

  @override
  Future<void> remove(String path) async => written.remove(path);
}

class FakeRasterizer implements PdfRasterizer {
  @override
  Future<int> pageCount(Uint8List pdf) async => 4;

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

Future<ReorderResult> direct(ReorderRequest r) async => PageReorderer.run(r);

Future<FakeFiles> pumpScreen(WidgetTester tester, {ShareEngine? share}) async {
  tester.view.physicalSize = const Size(800, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final FakeFiles files = FakeFiles(ReorderSource('report.pdf', pagesPdf(4)));
  await tester.pumpWidget(MaterialApp(
    theme: buildAppTheme(),
    home: ReorderPagesScreen(files: files, rasterizer: FakeRasterizer(), runner: direct, share: share),
  ));
  await tester.tap(find.byKey(const Key('reorder-pick')));
  await tester.pumpAndSettle();
  return files;
}

Future<void> menu(WidgetTester tester, int i, String item) async {
  await tester.tap(find.byKey(Key('reorder-menu-$i')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(item).last);
  await tester.pumpAndSettle();
}

void main() {
  group('engine', () {
    test('layout moves pages and adds or drops blanks', () {
      final PageLayout l = PageLayout(4);
      expect(l.isOriginal, isTrue);
      l.move(0, 3);
      expect(l.slots, <int>[2, 3, 4, 1]);
      l.insertBlank(1);
      expect(l.slots, <int>[2, 0, 3, 4, 1]);
      expect(l.blanks, 1);
      expect(l.removeBlank(0), isFalse);
      expect(l.removeBlank(1), isTrue);
      l.insertBlank(99);
      expect(l.slots, <int>[2, 3, 4, 1, 0]);
      expect(l.isOriginal, isFalse);
    });

    test('the PDF follows the layout; a blank takes the size before it', () {
      final ReorderResult r = PageReorderer.apply(pagesPdf(3), 'report.pdf', <int>[3, 0, 1, 2]);
      expect(pageOrder(r.bytes), <int>[3, 0, 1, 2]);
      expect(r.name, 'report (reordered).pdf');
      final List<PdfDict> pages = pageDicts(r.bytes);
      expect(boxOf(pages[1]), <String>['0', '0', '842', '595']);
      expect(pages[0]['Resources'], isNotNull);
      expect(pageOrder(PageReorderer.apply(pagesPdf(2), 'a.pdf', <int>[0, 2, 1]).bytes), <int>[0, 2, 1]);
    });

    test('repeats and missing pages are refused', () {
      expect(() => PageReorderer.apply(pagesPdf(3), 'a.pdf', <int>[1, 1, 2]), throwsA(isA<SplitError>()));
      expect(() => PageReorderer.apply(pagesPdf(3), 'a.pdf', <int>[5]), throwsA(isA<SplitError>()));
      expect(() => PageReorderer.apply(pagesPdf(3), 'a.pdf', <int>[]), throwsA(isA<SplitError>()));
    });
  });

  group('screen', () {
    testWidgets('move with the menu, add a blank, save, share and undo', (WidgetTester tester) async {
      final FakeSheet sheet = FakeSheet();
      final FakeFiles files = await pumpScreen(tester, share: ShareEngine(sheet, MemoryShareTargetStore()));
      expect(find.text('4 pages'), findsOneWidget);
      expect(tester.getSize(find.byKey(const Key('reorder-menu-0'))).height, greaterThanOrEqualTo(44));

      await menu(tester, 0, 'Move later');
      await menu(tester, 3, 'Add blank page before');
      expect(find.text('5 pages · 1 blank'), findsOneWidget);

      await tester.tap(find.byKey(const Key('result-save')));
      await tester.pumpAndSettle();
      expect(pageOrder(files.written['/edited/report (reordered).pdf']!), <int>[2, 1, 3, 0, 4]);

      await tester.tap(find.byKey(const Key('result-share')));
      await tester.pumpAndSettle();
      expect(sheet.requests.single.files.single.path, '/edited/report (reordered).pdf');

      await tester.tap(find.byKey(const Key('result-undo')));
      await tester.pumpAndSettle();
      expect(files.written, isEmpty);
      await tester.tap(find.byKey(const Key('result-undo')));
      await tester.pumpAndSettle();
      expect(find.text('4 pages'), findsOneWidget);
    });

    testWidgets('drag a thumbnail onto another place', (WidgetTester tester) async {
      final FakeFiles files = await pumpScreen(tester);
      final Offset from = tester.getCenter(find.byKey(const Key('reorder-tile-0')));
      final Offset to = tester.getCenter(find.byKey(const Key('reorder-tile-2')));
      final TestGesture g = await tester.startGesture(from);
      await tester.pump(const Duration(milliseconds: 700));
      await g.moveTo(to);
      await tester.pump();
      await g.up();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('result-save')));
      await tester.pumpAndSettle();
      expect(pageOrder(files.written.values.single), <int>[2, 3, 1, 4]);
    });

    testWidgets('screen readers get move and blank actions', (WidgetTester tester) async {
      final SemanticsHandle h = tester.ensureSemantics();
      await pumpScreen(tester);
      final SemanticsNode node = tester.getSemantics(find.bySemanticsLabel(RegExp(r'^Page 1, place 1 of 4')));
      final Set<String> labels = <String>{
        for (final int id in node.getSemanticsData().customSemanticsActionIds ?? <int>[])
          CustomSemanticsAction.getAction(id)!.label,
      };
      expect(labels, containsAll(<String>['Move later', 'Add blank page before', 'Add blank page after']));
      expect(labels, isNot(contains('Move earlier')));
      h.dispose();
    });
  });
}
