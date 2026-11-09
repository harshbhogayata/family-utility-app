import 'dart:convert';
import 'dart:typed_data';

import 'package:family_utility_app/app/theme.dart';
import 'package:family_utility_app/engines/pdf/page_rotate.dart';
import 'package:family_utility_app/engines/pdf/pdf_compressor.dart';
import 'package:family_utility_app/engines/pdf/pdf_splitter.dart';
import 'package:family_utility_app/engines/pdf/pdf_to_images.dart';
import 'package:family_utility_app/engines/share/share_engine.dart';
import 'package:family_utility_app/tools/rotate_pages/rotate_pages_screen.dart';
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

List<PdfDict> pageDicts(Uint8List pdf) {
  final PdfDocumentModel d = PdfDocumentModel.parse(pdf);
  final PdfDict root = d.resolve(d.trailer['Root'])! as PdfDict;
  final PdfDict pages = d.resolve(root['Pages'])! as PdfDict;
  return <PdfDict>[for (final Object k in (pages['Kids']! as PdfArray).items) d.resolve(k)! as PdfDict];
}

/// Source page numbers in output order; 0 for a blank page. Page k of
/// [pagesPdf] draws through content object 6 + 2(k - 1).
/// The /Rotate each output page is shown at; null when it has none.
List<int?> rotations(Uint8List pdf) {
  final PdfDocumentModel d = PdfDocumentModel.parse(pdf);
  final List<int?> out = <int?>[];
  for (final PdfDict p in pageDicts(pdf)) {
    final Object? r = d.resolve(p['Rotate']);
    out.add(r is PdfNum ? r.value.toInt() : null);
  }
  return out;
}

/// Page k of [pagesPdf] draws through content object 6 + 2(k - 1).
List<int> pageOrder(Uint8List pdf) => <int>[
      for (final PdfDict p in pageDicts(pdf)) ((p['Contents']! as PdfRef).num - 6) ~/ 2 + 1,
    ];

class FakeFiles implements RotateFiles {
  FakeFiles(this.picked);
  final RotateSource? picked;
  final Map<String, Uint8List> written = <String, Uint8List>{};

  @override
  Future<RotateSource?> pick() async => picked;

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
  Future<int> pageCount(Uint8List pdf) async => 3;

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

Future<RotateResult> direct(RotateRequest r) async => PageRotator.run(r);

Future<FakeFiles> pumpScreen(WidgetTester tester, {ShareEngine? share}) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final FakeFiles files = FakeFiles(RotateSource('report.pdf', pagesPdf(3)));
  await tester.pumpWidget(MaterialApp(
    theme: buildAppTheme(),
    home: RotatePagesScreen(files: files, rasterizer: FakeRasterizer(), runner: direct, share: share),
  ));
  await tester.tap(find.byKey(const Key('rotate-pick')));
  await tester.pumpAndSettle();
  return files;
}

void main() {
  group('engine', () {
    test('turns step a quarter and wrap around', () {
      final PageTurns t = PageTurns(3);
      expect(t.isOriginal, isTrue);
      t.rotate(1);
      t.rotate(2, clockwise: false);
      expect(t.turns, <int>[1, 3, 0]);
      t.rotateAll();
      expect(t.turns, <int>[2, 0, 1]);
      expect(t.turned, 2);
      expect(t.degreesOf(1), 180);
      t.rotate(9);
      expect(PageTurns.of(<int>[4, -1, 5]).turns, <int>[0, 3, 1]);
    });

    test('the turn is written into the file and adds to an existing one', () {
      // Page 2 is not turned, so it keeps no /Rotate of its own.
      final RotateResult r = PageRotator.apply(pagesPdf(3), 'report.pdf', <int>[1, 0, 2]);
      expect(r.name, 'report (rotated).pdf');
      expect(r.turned, 2);
      expect(rotations(r.bytes), <int?>[90, null, 180]);
      expect(pageOrder(r.bytes), <int>[1, 2, 3]);
      expect(pageDicts(r.bytes).first['Resources'], isNotNull);

      final RotateResult again = PageRotator.apply(r.bytes, r.name, <int>[3, 3, 3]);
      expect(rotations(again.bytes), <int?>[0, 270, 90]);
      final PdfSplitSource src = PdfSplitSource.parse(again.bytes);
      expect(<int>[src.rotationOf(1), src.rotationOf(2), src.rotationOf(3)], <int>[0, 270, 90]);
    });

    test('an inherited rotation is read before adding the turn', () {
      final Uint8List tilted = classicPdf(<String>[
        '<< /Type /Catalog /Pages 2 0 R >>',
        '<< /Type /Pages /Kids [3 0 R] /Count 1 /MediaBox [0 0 595 842] /Rotate -90 >>',
        '<< /Type /Page /Parent 2 0 R /Contents 4 0 R >>',
        '<< /Length 0 >>\nstream\n\nendstream',
      ]);
      expect(PdfSplitSource.parse(tilted).rotationOf(1), 270);
      expect(rotations(PageRotator.apply(tilted, 'a.pdf', <int>[1]).bytes), <int?>[0]);
    });

    test('no turns, a wrong page count and a broken file are refused', () {
      expect(() => PageRotator.apply(pagesPdf(2), 'a.pdf', <int>[0, 4]), throwsA(isA<SplitError>()));
      expect(() => PageRotator.apply(pagesPdf(2), 'a.pdf', <int>[1]), throwsA(isA<SplitError>()));
      expect(() => PageRotator.apply(Uint8List.fromList(<int>[1, 2, 3]), 'a.pdf', <int>[1]), throwsA(isA<SplitError>()));
    });
  });

  group('screen', () {
    testWidgets('turn one page, then all, save, share and undo', (WidgetTester tester) async {
      final FakeSheet sheet = FakeSheet();
      final FakeFiles files = await pumpScreen(tester, share: ShareEngine(sheet, MemoryShareTargetStore()));
      expect(find.text('3 pages · 0 turned'), findsOneWidget);
      expect(tester.getSize(find.byKey(const Key('rotate-right-1'))).height, greaterThanOrEqualTo(44));
      expect(tester.getSize(find.byKey(const Key('rotate-all-right'))).height, greaterThanOrEqualTo(44));

      await tester.tap(find.byKey(const Key('rotate-right-2')));
      await tester.pumpAndSettle();
      expect(find.text('3 pages · 1 turned'), findsOneWidget);
      await tester.tap(find.byKey(const Key('rotate-all-left')));
      await tester.pumpAndSettle();
      expect(find.text('3 pages · 2 turned'), findsOneWidget);

      await tester.tap(find.byKey(const Key('result-save')));
      await tester.pumpAndSettle();
      expect(rotations(files.written['/edited/report (rotated).pdf']!), <int?>[270, null, 270]);

      await tester.tap(find.byKey(const Key('result-share')));
      await tester.pumpAndSettle();
      expect(sheet.requests.single.files.single.path, '/edited/report (rotated).pdf');

      await tester.tap(find.byKey(const Key('result-undo')));
      await tester.pumpAndSettle();
      expect(files.written, isEmpty);
      await tester.tap(find.byKey(const Key('result-undo')));
      await tester.pumpAndSettle();
      expect(find.text('3 pages · 1 turned'), findsOneWidget);
    });

    testWidgets('saving with nothing turned does not write a file', (WidgetTester tester) async {
      final FakeFiles files = await pumpScreen(tester);
      await tester.tap(find.byKey(const Key('result-save')));
      await tester.pumpAndSettle();
      expect(files.written, isEmpty);
      expect(find.text('Turn a page first'), findsOneWidget);
    });

    testWidgets('screen readers hear each page and its turn', (WidgetTester tester) async {
      final SemanticsHandle h = tester.ensureSemantics();
      await pumpScreen(tester);
      expect(find.bySemanticsLabel(RegExp(r'^Page 1, upright as in the file')), findsOneWidget);
      expect(find.byTooltip('Turn page 1 right'), findsOneWidget);
      await tester.tap(find.byKey(const Key('rotate-right-1')));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel(RegExp(r'^Page 1, turned 90° clockwise')), findsOneWidget);
      h.dispose();
    });
  });
}
