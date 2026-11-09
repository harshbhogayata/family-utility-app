import 'dart:typed_data';

import 'package:family_utility_app/app/theme.dart';
import 'package:family_utility_app/engines/pdf/pdf_to_images.dart';
import 'package:family_utility_app/tools/pdf_to_images/pdf_to_images_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// A4 pages (595 × 842 pt), each a different grey, drawn at the asked dpi.
class FakeRasterizer implements PdfRasterizer {
  FakeRasterizer(this.pages);
  final int pages;
  final List<(int, int)> drawn = <(int, int)>[];

  @override
  Future<int> pageCount(Uint8List pdf) async => pages;

  @override
  Future<img.Image> render(Uint8List pdf, int index, int dpi) async {
    drawn.add((index, dpi));
    final img.Image im = img.Image(width: (595 * dpi / 72).round(), height: (842 * dpi / 72).round());
    img.fill(im, color: img.ColorRgb8(40 * index, 40 * index, 40 * index));
    return im;
  }
}

class FakeIo implements PdfImagesIo {
  final Map<String, Uint8List> written = <String, Uint8List>{};

  @override
  Future<String?> pick() async => '/docs/Report.pdf';

  @override
  Future<Uint8List> read(String path) async => Uint8List.fromList('%PDF-1.4'.codeUnits);

  @override
  Future<String> write(String name, Uint8List bytes) async {
    final String p = '/out/$name';
    written[p] = bytes;
    return p;
  }

  @override
  Future<void> remove(String path) async => written.remove(path);
}

void main() {
  final Uint8List pdf = Uint8List.fromList('%PDF-1.4'.codeUnits);

  test('page ranges', () {
    expect(PageRange.parse('', 4), <int>[0, 1, 2, 3]);
    expect(PageRange.parse('1-2, 4', 5), <int>[0, 1, 3]);
    expect(PageRange.parse('3-', 5), <int>[2, 3, 4]);
    expect(PageRange.parse('2,2,1', 5), <int>[1, 0]);
    expect(() => PageRange.parse('6', 5), throwsA(isA<PdfToImagesError>()));
    expect(() => PageRange.parse('3-1', 5), throwsA(isA<PdfToImagesError>()));
    expect(() => PageRange.parse('a', 5), throwsA(isA<PdfToImagesError>()));
  });

  test('one image per page in JPG or PNG at the chosen dpi', () async {
    final FakeRasterizer r = FakeRasterizer(3);
    final PdfToImages e = PdfToImages(r);
    final List<PdfImageOut> jpgs = await e.perPage(pdf, 'doc', range: '1,3', dpi: 72);
    expect(jpgs.map((PdfImageOut o) => o.name), <String>['doc-p1.jpg', 'doc-p3.jpg']);
    expect((jpgs.first.width, jpgs.first.height), (595, 842));
    expect(img.decodeJpg(jpgs.first.bytes), isNotNull);
    final List<PdfImageOut> pngs = await e.perPage(pdf, 'doc', dpi: 150, format: PdfImageFormat.png);
    expect(pngs, hasLength(3));
    final img.Image? png = img.decodePng(pngs[1].bytes);
    expect((png!.width, png.height), (1240, 1754));
    expect(r.drawn.last, (2, 150));
  });

  test('long image stacks pages and stays under the chat-friendly height', () async {
    final PdfToImages e = PdfToImages(FakeRasterizer(3));
    final PdfImageOut long = await e.longImage(pdf, 'doc', dpi: 72, format: PdfImageFormat.png);
    expect(long.name, 'doc-long.png');
    expect(long.width, 595);
    expect(long.height, 842 * 3 + 4 * 2);
    final img.Image im = img.decodePng(long.bytes)!;
    expect(im.getPixel(10, 10).r, 0);
    expect(im.getPixel(10, 842 + 4 + 10).r, 40);
    expect(im.getPixel(10, 2 * (842 + 4) + 10).r, 80);

    final PdfToImages many = PdfToImages(FakeRasterizer(8));
    final PdfImageOut tall = await many.longImage(pdf, 'doc', dpi: 150);
    expect(tall.height, lessThanOrEqualTo(longImageMaxHeight));
  });

  testWidgets('pick, choose PNG and a range, make images, undo', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final FakeIo io = FakeIo();
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: PdfToImagesScreen(io: io, rasterizer: FakeRasterizer(4)),
    ));
    await tester.tap(find.byKey(const Key('p2i-pick')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('p2i-png')));
    await tester.tap(find.byKey(const Key('p2i-dpi-72')));
    await tester.enterText(find.byKey(const Key('p2i-range')), '2-3');
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byKey(const Key('p2i-run'))).height, greaterThanOrEqualTo(44));
    await tester.tap(find.byKey(const Key('p2i-run')));
    await tester.pumpAndSettle();
    expect(io.written.keys, <String>['/out/Report-p2.png', '/out/Report-p3.png']);
    expect(find.text('2 PNG images at 72 dpi'), findsOneWidget);

    await tester.tap(find.byKey(const Key('p2i-long')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('p2i-run')));
    await tester.pumpAndSettle();
    expect(io.written.keys, containsAll(<String>['/out/Report-long.png']));
    expect(find.textContaining('One long PNG'), findsOneWidget);

    await tester.tap(find.byKey(const Key('result-undo')));
    await tester.pumpAndSettle();
    expect(io.written.keys, <String>['/out/Report-p2.png', '/out/Report-p3.png']);
  });
}
