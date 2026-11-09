import 'dart:io';

import 'package:family_utility_app/app/theme.dart';
import 'package:family_utility_app/engines/pdf/pdf_reader.dart';
import 'package:family_utility_app/engines/share/share_engine.dart';
import 'package:family_utility_app/platform/pdf_surface.dart';
import 'package:family_utility_app/tools/pdf_viewer/pdf_viewer_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Stands in for PDFium: a 200-page document of text boxes.
class FakeSurface implements PdfSurface {
  FakeSurface(this.pages);
  final int pages;
  final List<int> jumps = <int>[];

  @override
  Widget viewer(BuildContext context, String path, PdfReader reader) => _FakeViewer(this, reader);

  @override
  Widget thumbnail(BuildContext context, String path, int page) => Center(child: Text('t$page'));
}

class _FakeViewer extends StatefulWidget {
  const _FakeViewer(this.surface, this.reader);
  final FakeSurface surface;
  final PdfReader reader;

  @override
  State<_FakeViewer> createState() => _FakeViewerState();
}

class _FakeViewerState extends State<_FakeViewer> {
  @override
  void initState() {
    super.initState();
    widget.reader.jumpRequest.addListener(_jump);
    if (widget.reader.pageCount == 0) {
      widget.reader.opened(widget.surface.pages);
    }
  }

  @override
  void dispose() {
    widget.reader.jumpRequest.removeListener(_jump);
    super.dispose();
  }

  void _jump() {
    final int? n = widget.reader.jumpRequest.value;
    if (n != null) {
      widget.surface.jumps.add(n);
    }
  }

  @override
  Widget build(BuildContext context) => Center(child: Text('Showing page ${widget.reader.page}'));
}

class FakeChooser implements PdfChooser {
  @override
  Future<String?> pick() async => '/docs/manual.pdf';
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
  group('PdfReader', () {
    test('opens on the first page, then on the last-read page per file', () async {
      final MemoryLastPageStore store = MemoryLastPageStore();
      final PdfReader a = PdfReader(fileKey: '/docs/a.pdf', store: store);
      expect(await a.opened(200), 1);
      expect(a.jumpRequest.value, isNull, reason: 'no jump needed for page 1');
      expect(a.goTo(57), isTrue);
      expect(store.pages['/docs/a.pdf'], 57);

      final PdfReader again = PdfReader(fileKey: '/docs/a.pdf', store: store);
      expect(await again.opened(200), 57);
      expect(again.jumpRequest.value, 57);

      final PdfReader other = PdfReader(fileKey: '/docs/b.pdf', store: store);
      expect(await other.opened(10), 1);
      store.pages['/docs/c.pdf'] = 99;
      expect(await PdfReader(fileKey: '/docs/c.pdf', store: store).opened(12), 1,
          reason: 'a page that no longer exists starts at the top');
    });

    test('go-to-page clamps to real pages; swipes are remembered; Undo goes back', () async {
      final MemoryLastPageStore store = MemoryLastPageStore();
      final PdfReader r = PdfReader(fileKey: 'f', store: store);
      expect(r.goTo(3), isFalse, reason: 'not open yet');
      await r.opened(200);
      expect(r.goTo(0), isFalse);
      expect(r.goTo(201), isFalse);
      expect(r.goTo(150), isTrue);
      r.scrolledTo(151);
      expect(r.page, 151);
      expect(store.pages['f'], 151);
      expect(r.undoJump(), isTrue);
      expect(r.page, 1);
      expect(r.undoJump(), isTrue, reason: 'Undo again returns to where Undo started');
      expect(r.page, 151);
      expect(parsePageJump(' 12 ', 200), 12);
      expect(parsePageJump('0', 200), isNull);
      expect(parsePageJump('201', 200), isNull);
      expect(parsePageJump('abc', 200), isNull);
    });

    test('night mode turns white to black and black to white, and keeps hues', () {
      expect(NightMode.matrix, hasLength(20));
      expect(NightMode.apply(255, 255, 255), <int>[0, 0, 0]);
      expect(NightMode.apply(0, 0, 0), <int>[255, 255, 255]);
      final List<int> red = NightMode.apply(200, 30, 30);
      expect(red[0], greaterThan(red[1]), reason: 'a red photo stays red, not cyan');
      expect(red[0], greaterThan(red[2]));
      final List<int> blue = NightMode.apply(30, 30, 200);
      expect(blue[2], greaterThan(blue[0]));
    });

    test('layout switch asks the surface to keep the page', () async {
      final PdfReader r = PdfReader(fileKey: 'f', store: MemoryLastPageStore());
      await r.opened(20);
      r.goTo(9);
      r.jumpRequest.value = null;
      r.setLayout(PdfLayout.single);
      expect(r.layout, PdfLayout.single);
      expect(r.jumpRequest.value, 9);
    });

    test('the viewer code has no network calls', () {
      for (final String f in <String>['lib/engines/pdf/pdf_reader.dart', 'lib/platform/pdf_surface.dart']) {
        final String src = File(f).readAsStringSync();
        expect(src.contains('HttpClient'), isFalse, reason: f);
        expect(src.contains('http://'), isFalse, reason: f);
        expect(src.contains('https://'), isFalse, reason: f);
      }
    });
  });

  group('screen', () {
    testWidgets('open, thumbnails, go to page, night mode, layout, Share / Save / Undo', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final FakeSurface surface = FakeSurface(200);
      final MemoryLastPageStore store = MemoryLastPageStore();
      final FakeSheet sheet = FakeSheet();
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: PdfViewerScreen(
          surface: surface,
          chooser: FakeChooser(),
          store: store,
          share: ShareEngine(sheet, MemoryShareTargetStore()),
        ),
      ));

      await tester.tap(find.byKey(const Key('pdf-open')));
      await tester.pumpAndSettle();
      expect(find.text('manual.pdf'), findsOneWidget);
      expect(find.text('Page 1 of 200'), findsOneWidget);
      expect(find.text('t1'), findsOneWidget);
      expect(find.byWidgetPredicate((Widget w) => w is Semantics && w.properties.label == 'Page 2'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey<String>('pdf-thumb-3')));
      await tester.pumpAndSettle();
      expect(find.text('Page 3 of 200'), findsOneWidget);
      expect(surface.jumps.last, 3);

      await tester.tap(find.byKey(const Key('pdf-jump')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('pdf-jump-field')), '120');
      await tester.tap(find.byKey(const Key('pdf-jump-go')));
      await tester.pumpAndSettle();
      expect(find.text('Page 120 of 200'), findsOneWidget);
      expect(store.pages['/docs/manual.pdf'], 120);

      await tester.tap(find.byKey(const Key('pdf-jump')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('pdf-jump-field')), '999');
      await tester.tap(find.byKey(const Key('pdf-jump-go')));
      await tester.pumpAndSettle();
      expect(find.text('Type a page from 1 to 200'), findsOneWidget);
      expect(find.text('Page 120 of 200'), findsOneWidget);

      expect(find.byType(ColorFiltered), findsOneWidget);
      await tester.tap(find.byKey(const Key('pdf-night')));
      await tester.pumpAndSettle();
      final ColorFiltered cf = tester.widget<ColorFiltered>(find.byType(ColorFiltered));
      expect(cf.colorFilter, const ColorFilter.matrix(NightMode.matrix));

      await tester.tap(find.byKey(const Key('pdf-layout')));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Continuous scroll'), findsOneWidget);

      for (final String key in <String>['pdf-jump', 'pdf-night', 'pdf-layout', 'pdf-thumbs', 'result-share', 'result-save', 'result-undo']) {
        expect(tester.getSize(find.byKey(Key(key))).height, greaterThanOrEqualTo(44), reason: key);
      }

      await tester.tap(find.byKey(const Key('result-undo')));
      await tester.pumpAndSettle();
      expect(find.text('Page 3 of 200'), findsOneWidget);

      await tester.tap(find.byKey(const Key('result-save')));
      await tester.pumpAndSettle();
      expect(store.pages['/docs/manual.pdf'], 3);
      expect(find.text('Saved your place: page 3'), findsOneWidget);

      await tester.tap(find.byKey(const Key('result-share')));
      await tester.pumpAndSettle();
      expect(sheet.requests.single.files.single.mimeType, 'application/pdf');

      await tester.tap(find.byKey(const Key('pdf-thumbs')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('pdf-thumb-strip')), findsNothing);
    });
  });
}
