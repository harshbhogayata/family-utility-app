import 'dart:convert';
import 'dart:typed_data';

import 'package:family_utility_app/app/theme.dart';
import 'package:family_utility_app/engines/pdf/page_remover.dart';
import 'package:family_utility_app/engines/pdf/pdf_compressor.dart';
import 'package:family_utility_app/engines/pdf/pdf_splitter.dart';
import 'package:family_utility_app/engines/pdf/pdf_to_images.dart';
import 'package:family_utility_app/engines/share/share_engine.dart';
import 'package:family_utility_app/tools/remove_pages/remove_pages_screen.dart';
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

class FakeFiles implements RemoveFiles {
  FakeFiles(this.picked) {
    final String? p = picked?.path;
    if (p != null) {
      disk[p] = picked!.bytes;
    }
  }
  final RemoveSource? picked;
  final Map<String, Uint8List> disk = <String, Uint8List>{};
  final List<String> versions = <String>[];

  @override
  Future<RemoveSource?> pick() async => picked;

  @override
  Future<String> writeCopy(String name, Uint8List bytes) async {
    disk['/edited/$name'] = bytes;
    return '/edited/$name';
  }

  @override
  Future<void> overwrite(String path, Uint8List bytes) async => disk[path] = bytes;

  @override
  Future<void> remove(String path) async => disk.remove(path);

  @override
  Future<void> keepVersion(String path) async => versions.add(path);
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

Future<RemoveResult> direct(RemoveRequest r) async => PageRemover.run(r);

Future<void> pumpScreen(WidgetTester tester, FakeFiles files, {ShareEngine? share}) async {
  tester.view.physicalSize = const Size(800, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: buildAppTheme(),
    home: RemovePagesScreen(files: files, rasterizer: FakeRasterizer(), runner: direct, share: share),
  ));
  await tester.tap(find.byKey(const Key('remove-pick')));
  await tester.pumpAndSettle();
}

Future<void> tapKey(WidgetTester tester, String key) async {
  await tester.ensureVisible(find.byKey(Key(key)));
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

void main() {
  group('engine', () {
    test('marked pages are left out; the rest keep their order', () {
      final RemoveResult r = PageRemover.remove(pagesPdf(6), 'report.pdf', <int>[5, 2, 2]);
      expect(pageOrder(r.bytes), <int>[1, 3, 4, 6]);
      expect(r.removed, <int>[2, 5]);
      expect(r.kept, <int>[1, 3, 4, 6]);
      expect(r.name, 'report (pages removed).pdf');
      expect(latin1.decode(r.bytes), isNot(contains('(Page 2)')));
    });

    test('nothing marked, every page marked, or a bad page is refused', () {
      expect(() => PageRemover.remove(pagesPdf(3), 'a.pdf', <int>[]), throwsA(isA<SplitError>()));
      expect(() => PageRemover.remove(pagesPdf(3), 'a.pdf', <int>[1, 2, 3]), throwsA(isA<SplitError>()));
      expect(() => PageRemover.remove(pagesPdf(3), 'a.pdf', <int>[7]), throwsA(isA<SplitError>()));
      expect(() => PageRemover.remove(Uint8List.fromList(<int>[1, 2]), 'a.pdf', <int>[1]), throwsA(isA<SplitError>()));
    });
  });

  group('screen', () {
    testWidgets('keeps the original by default; undo removes the copy', (WidgetTester tester) async {
      final Uint8List original = pagesPdf(5);
      final FakeFiles files = FakeFiles(RemoveSource('report.pdf', original, path: '/docs/report.pdf'));
      final FakeSheet sheet = FakeSheet();
      await pumpScreen(tester, files, share: ShareEngine(sheet, MemoryShareTargetStore()));
      await tapKey(tester, 'remove-page-2');
      await tapKey(tester, 'remove-page-4');
      expect(find.text('2 of 5 marked'), findsOneWidget);
      expect(find.bySemanticsLabel('Page 2, marked for removal'), findsOneWidget);
      expect(tester.getSize(find.byKey(const Key('remove-page-1'))).height, greaterThanOrEqualTo(44));

      await tapKey(tester, 'remove-run');
      expect(files.disk['/docs/report.pdf'], same(original));
      expect(pageOrder(files.disk['/edited/report (pages removed).pdf']!), <int>[1, 3, 5]);
      expect(files.versions, isEmpty);

      await tapKey(tester, 'result-share');
      expect(sheet.requests.single.files.single.path, '/edited/report (pages removed).pdf');

      await tapKey(tester, 'result-undo');
      expect(files.disk.keys.toList(), <String>['/docs/report.pdf']);
      expect(find.text('2 of 5 marked'), findsOneWidget);
    });

    testWidgets('overwrite keeps a version and undo puts the original back', (WidgetTester tester) async {
      final Uint8List original = pagesPdf(5);
      final FakeFiles files = FakeFiles(RemoveSource('report.pdf', original, path: '/docs/report.pdf'));
      await pumpScreen(tester, files);
      await tapKey(tester, 'remove-page-1');
      await tapKey(tester, 'remove-overwrite');
      await tapKey(tester, 'remove-run');
      expect(files.versions, <String>['/docs/report.pdf']);
      expect(pageOrder(files.disk['/docs/report.pdf']!), <int>[2, 3, 4, 5]);
      expect(files.disk.length, 1);

      await tapKey(tester, 'result-undo');
      expect(files.disk['/docs/report.pdf'], same(original));
    });

    testWidgets('a file without a path can only be saved as a copy', (WidgetTester tester) async {
      final FakeFiles files = FakeFiles(RemoveSource('report.pdf', pagesPdf(3)));
      await pumpScreen(tester, files);
      expect(tester.widget<SwitchListTile>(find.byKey(const Key('remove-overwrite'))).onChanged, isNull);
    });
  });
}
