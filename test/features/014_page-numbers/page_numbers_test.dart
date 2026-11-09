import 'dart:convert';
import 'dart:typed_data';

import 'package:family_utility_app/app/theme.dart';
import 'package:family_utility_app/engines/convert/convert_registry.dart';
import 'package:family_utility_app/engines/convert/file_kind.dart';
import 'package:family_utility_app/engines/convert/slides.dart';
import 'package:family_utility_app/engines/pdf/page_numbers.dart';
import 'package:family_utility_app/engines/pdf/pdf_signer.dart' show PageBox;
import 'package:family_utility_app/tools/convert_anything/convert_anything_screen.dart';
import 'package:family_utility_app/tools/page_numbers/page_numbers_screen.dart';
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

/// A three-page A4 PDF.
Future<Uint8List> a4(int pages) => SlidesPdfWriter().write(SlideDeck(
      width: 595,
      height: 842,
      slides: <Slide>[
        for (int i = 0; i < pages; i++)
          Slide(<SlideShape>[
            SlideShape(x: 72, y: 72, width: 400, height: 40, paragraphs: <SlideParagraph>[
              SlideParagraph(<SlideRun>[SlideRun('Page body ${i + 1}', size: 14)]),
            ]),
          ]),
      ],
    ));

void main() {
  const List<PageBox> boxes = <PageBox>[PageBox(0, 0, 595, 842), PageBox(0, 0, 595, 842), PageBox(0, 0, 595, 842)];

  group('plan', () {
    test('six positions land at the right edges', () {
      // "1" in Helvetica 10 pt is 5.56 pt wide.
      final Map<NumberPosition, (double, double)> want = <NumberPosition, (double, double)>{
        NumberPosition.topLeft: (28, 804),
        NumberPosition.topCenter: (294.72, 804),
        NumberPosition.topRight: (561.44, 804),
        NumberPosition.bottomLeft: (28, 28),
        NumberPosition.bottomCenter: (294.72, 28),
        NumberPosition.bottomRight: (561.44, 28),
      };
      expect(NumberPosition.values, hasLength(6));
      want.forEach((NumberPosition p, (double, double) xy) {
        final PageStamp s = PageNumberer.plan(boxes, PageNumberOptions(position: p, fontSize: 10)).first;
        expect(s.x, closeTo(xy.$1, 0.01), reason: p.name);
        expect(s.y, closeTo(xy.$2, 0.01), reason: p.name);
      });
    });

    test('start number and skip-first', () {
      expect(PageNumberer.plan(boxes, const PageNumberOptions()).map((PageStamp s) => s.label), <String>['1', '2', '3']);
      final List<PageStamp> s = PageNumberer.plan(boxes, const PageNumberOptions(start: 7, skipFirst: true));
      expect(s.map((PageStamp s) => s.page), <int>[1, 2]);
      expect(s.map((PageStamp s) => s.label), <String>['7', '8']);
      expect(() => PageNumberer.plan(boxes, const PageNumberOptions(fontSize: 100)), throwsA(isA<PageNumberError>()));
    });
  });

  group('stamp', () {
    test('every page gets its number drawn into the page; the file still reads', () async {
      final Uint8List pdf = await a4(3);
      final Uint8List out = PageNumberer.stamp(pdf, const PageNumberOptions(fontSize: 12, start: 3, skipFirst: true));
      expect(sniffFileKind(out), FileKind.pdf);
      final String s = latin1.decode(out);
      expect(RegExp(r'/FuaPageNo 12\.00 Tf [\d.]+ 28\.00 Td \((\d+)\) Tj').allMatches(s).map((RegExpMatch m) => m.group(1)),
          <String>['3', '4']);
      expect(s, contains('/BaseFont /Helvetica'));
      expect(s, contains('(Page body 1) Tj'));
      expect(PageNumberer.pages(out), hasLength(3));
    });

    test('a file that is not a PDF is a clear error', () {
      expect(() => PageNumberer.stamp(Uint8List.fromList(<int>[1, 2, 3]), const PageNumberOptions()),
          throwsA(isA<PageNumberError>()));
    });
  });

  testWidgets('pick, choose top right and start 0, stamp, undo', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final Uint8List pdf = await tester.runAsync(() => a4(2)) ?? Uint8List(0);
    final FakeSink sink = FakeSink();
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: PageNumbersScreen(chooser: FakeChooser(ConvertInput(name: 'notes.pdf', bytes: pdf)), sink: sink),
    ));
    for (final String k in <String>['pn-pick', 'pn-run', 'pn-pos-topRight', 'pn-start-up', 'pn-start-down', 'pn-skip-first']) {
      expect(tester.getSize(find.byKey(Key(k))).height, greaterThanOrEqualTo(44), reason: k);
    }
    await tester.tap(find.byKey(const Key('pn-pick')));
    await tester.pumpAndSettle();
    expect(find.text('notes.pdf'), findsOneWidget);
    await tester.tap(find.byKey(const Key('pn-pos-topRight')));
    await tester.tap(find.byKey(const Key('pn-start-down')));
    await tester.pumpAndSettle();
    expect(find.text('0'), findsOneWidget);
    await tester.tap(find.byKey(const Key('pn-run')));
    await tester.pumpAndSettle();
    expect(sink.files.keys, <String>['/converted/notes-numbered.pdf']);
    final String s = latin1.decode(sink.files.values.single.bytes);
    expect(RegExp(r'/FuaPageNo 11\.00 Tf [\d.]+ 803\.00 Td \((\d+)\) Tj').allMatches(s).map((RegExpMatch m) => m.group(1)),
        <String>['0', '1']);
    expect(find.textContaining('Made notes-numbered.pdf'), findsOneWidget);

    await tester.tap(find.byKey(const Key('result-undo')));
    await tester.pumpAndSettle();
    expect(sink.files, isEmpty);
  });
}
