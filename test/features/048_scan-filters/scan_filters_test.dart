import 'dart:typed_data';

import 'package:family_utility_app/app/theme.dart';
import 'package:family_utility_app/engines/image/document_scanner.dart';
import 'package:family_utility_app/engines/image/scan_filters.dart';
import 'package:family_utility_app/tools/document_scanner/document_scanner_screen.dart';
import 'package:family_utility_app/tools/document_scanner/scan_camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// Paper lit from the left: bright on the left, in shadow on the right, with
/// 4 x 4 ink marks every 12 px.
img.Image shadowedPage({int w = 120, int h = 96}) {
  final img.Image im = img.Image(width: w, height: h);
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      final int paper = 230 - (x * 110) ~/ w;
      final bool ink = x % 12 >= 4 && x % 12 < 8 && y % 12 >= 4 && y % 12 < 8;
      final int v = ink ? paper ~/ 6 : paper;
      im.setPixelRgb(x, y, v, v, v);
    }
  }
  return im;
}

bool isInk(int x, int y) => x % 12 >= 4 && x % 12 < 8 && y % 12 >= 4 && y % 12 < 8;

/// Paper with some ink-free margin around each mark.
bool isClearPaper(int x, int y) => x % 12 >= 10 || x % 12 <= 1 || y % 12 >= 10 || y % 12 <= 1;

Uint8List smallJpg(int r) {
  final img.Image im = img.Image(width: 12, height: 16);
  img.fill(im, color: img.ColorRgb8(r, 120, 60));
  return img.encodeJpg(im, quality: 90);
}

ScanPage pageOf(int r) => ScanPage(jpeg: smallJpg(r), width: 12, height: 16, foundEdges: true);

class FakeCamera implements ScanCamera {
  void Function(ScanFrame frame)? onFrame;
  int shots = 0;

  @override
  Future<bool> start(void Function(ScanFrame frame) cb) async {
    onFrame = cb;
    return true;
  }

  @override
  Widget preview(BuildContext context) => const ColoredBox(color: Colors.black);

  @override
  Future<Uint8List> takePicture() async => Uint8List.fromList(<int>[++shots]);

  @override
  Future<void> dispose() async {}
}

class FakeIo implements ScanIo {
  @override
  Future<String> write(String name, String extension, Uint8List bytes) async => '/scans/$name.$extension';

  @override
  Future<void> remove(String path) async {}
}

void main() {
  group('filters', () {
    test('grayscale makes every pixel grey; contrast stretches around mid-grey', () {
      final img.Image im = img.Image(width: 2, height: 1);
      im.setPixelRgb(0, 0, 200, 60, 40);
      im.setPixelRgb(1, 0, 100, 100, 100);
      final img.Image g = applyScanFilter(im, const ScanFilterSettings(filter: ScanFilter.grayscale));
      final img.Pixel p = g.getPixel(0, 0);
      expect(p.r, p.g);
      expect(p.g, p.b);

      final img.Image hi = applyScanFilter(im, const ScanFilterSettings(contrast: 2));
      final img.Image lo = applyScanFilter(im, const ScanFilterSettings(contrast: 0.5));
      expect(hi.getPixel(1, 0).r, 72); // (100 - 128) * 2 + 128
      expect(lo.getPixel(1, 0).r, 114); // (100 - 128) * 0.5 + 128
      expect(hi.getPixel(0, 0).r, 255);
    });

    test('colour boost widens the gap between channels', () {
      final img.Image im = img.Image(width: 1, height: 1);
      im.setPixelRgb(0, 0, 160, 120, 100);
      final img.Pixel p = applyScanFilter(im, const ScanFilterSettings(filter: ScanFilter.colorBoost)).getPixel(0, 0);
      expect(p.r - p.b, greaterThan(60));
    });

    test('shadow removal evens out the paper and keeps the ink dark', () {
      final img.Image page = shadowedPage();
      final img.Image out = applyScanFilter(page, const ScanFilterSettings(filter: ScanFilter.removeShadows));
      int minPaper = 255, maxInk = 0;
      for (int y = 0; y < page.height; y++) {
        for (int x = 0; x < page.width; x++) {
          final int v = out.getPixel(x, y).r.toInt();
          if (isClearPaper(x, y)) {
            minPaper = v < minPaper ? v : minPaper;
          } else if (isInk(x, y)) {
            maxInk = v > maxInk ? v : maxInk;
          }
        }
      }
      // Before: paper ran from 230 down to 120.
      expect(minPaper, greaterThan(205));
      expect(maxInk, lessThan(80));
    });

    test('black and white: clean white paper and black ink, even in shadow', () {
      final img.Image page = shadowedPage();
      final img.Image out = applyScanFilter(page, const ScanFilterSettings(filter: ScanFilter.blackWhite));
      int paper = 0, white = 0, ink = 0, black = 0;
      for (int y = 0; y < page.height; y++) {
        for (int x = 0; x < page.width; x++) {
          final int v = out.getPixel(x, y).r.toInt();
          expect(v == 0 || v == 255, isTrue);
          if (isClearPaper(x, y)) {
            paper++;
            if (v == 255) {
              white++;
            }
          } else if (isInk(x, y)) {
            ink++;
            if (v == 0) {
              black++;
            }
          }
        }
      }
      expect(white / paper, greaterThan(0.97));
      expect(black / ink, greaterThan(0.97));
    });

    test('glare removal fills the blown-out spot with the paper colour', () {
      final img.Image im = img.Image(width: 60, height: 60);
      for (int y = 0; y < 60; y++) {
        for (int x = 0; x < 60; x++) {
          final bool spot = (x - 30) * (x - 30) + (y - 30) * (y - 30) <= 36;
          if (spot) {
            im.setPixelRgb(x, y, 255, 255, 255);
          } else {
            im.setPixelRgb(x, y, 200, 190, 170);
          }
        }
      }
      final img.Image out = applyScanFilter(im, const ScanFilterSettings(filter: ScanFilter.removeGlare));
      final img.Pixel centre = out.getPixel(30, 30);
      expect((centre.r - 200).abs(), lessThan(4));
      expect((centre.g - 190).abs(), lessThan(4));
      expect((centre.b - 170).abs(), lessThan(4));
      final img.Pixel corner = out.getPixel(2, 2);
      expect(corner.r, 200);
    });

    test('the engine passes the original through untouched and refuses garbage', () {
      final Uint8List j = smallJpg(10);
      expect(identical(const ScanFilterEngine().apply(j, ScanFilterSettings.none), j), isTrue);
      final Uint8List g = const ScanFilterEngine().apply(j, const ScanFilterSettings(filter: ScanFilter.grayscale));
      expect(img.decodeJpg(g), isNotNull);
      expect(() => const ScanFilterEngine().apply(Uint8List(4), const ScanFilterSettings(contrast: 1.5)), throwsA(anything));
    });
  });

  group('per page or whole document', () {
    test('filters start from the capture every time and undo in one step', () {
      final ScanSession s = ScanSession()
        ..add(pageOf(200))
        ..add(pageOf(40))
        ..add(pageOf(120));
      final List<Uint8List> originals = <Uint8List>[for (final ScanPage p in s.pages) p.original];

      s.applyFilter(const ScanFilterSettings(filter: ScanFilter.grayscale), page: 1);
      expect(s.pages[1].filter.filter, ScanFilter.grayscale);
      expect(s.pages[0].filter, ScanFilterSettings.none);
      final img.Pixel grey = img.decodeJpg(s.pages[1].jpeg)!.getPixel(5, 5);
      expect((grey.r - grey.b).abs(), lessThan(4));

      s.applyFilter(const ScanFilterSettings(filter: ScanFilter.colorBoost, contrast: 1.4));
      for (int i = 0; i < 3; i++) {
        expect(s.pages[i].filter, const ScanFilterSettings(filter: ScanFilter.colorBoost, contrast: 1.4));
        expect(identical(s.pages[i].original, originals[i]), isTrue, reason: 'never stacks on a filtered page');
      }

      // Back to the original: exactly the captured bytes.
      s.applyFilter(ScanFilterSettings.none);
      for (int i = 0; i < 3; i++) {
        expect(identical(s.pages[i].jpeg, originals[i]), isTrue);
      }

      expect(s.undo(), isTrue);
      expect(s.pages[2].filter.filter, ScanFilter.colorBoost);
      expect(s.undo(), isTrue);
      expect(s.pages[0].filter, ScanFilterSettings.none);
      expect(s.pages[1].filter.filter, ScanFilter.grayscale);
    });
  });

  testWidgets('choose a filter and contrast, apply to all pages or one, undo', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    final FakeCamera cam = FakeCamera();
    final List<ScanFilterSettings> calls = <ScanFilterSettings>[];
    Future<ScanPage> process(Uint8List photo) async => pageOf(photo.first * 50);
    Future<Uint8List> filter(Uint8List jpeg, ScanFilterSettings s) async {
      calls.add(s);
      return smallJpg(5);
    }

    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: DocumentScannerScreen(camera: cam, io: FakeIo(), process: process, filter: filter),
    ));
    await tester.pump();
    for (int i = 0; i < 2; i++) {
      await tester.tap(find.byKey(const Key('scan-shutter')));
      await tester.pump();
      await tester.pump();
    }
    await tester.tap(find.byKey(const Key('scan-review')));
    await tester.pumpAndSettle();

    // Whole document, grayscale, contrast up.
    await tester.ensureVisible(find.byKey(const Key('scan-filter-grayscale')));
    await tester.pumpAndSettle();
    final Size chip = tester.getSize(find.byKey(const Key('scan-filter-grayscale')));
    expect(chip.height, greaterThanOrEqualTo(44));
    await tester.tap(find.byKey(const Key('scan-filter-grayscale')));
    await tester.pumpAndSettle();
    final Slider slider = tester.widget<Slider>(find.byKey(const Key('scan-contrast')));
    slider.onChanged!(1.5);
    await tester.pumpAndSettle();
    expect(find.text('Contrast: 150%'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('scan-filter-apply')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('scan-filter-apply')));
    await tester.pumpAndSettle();
    expect(calls, hasLength(2));
    expect(calls.first, const ScanFilterSettings(filter: ScanFilter.grayscale, contrast: 1.5));
    await tester.drag(find.byType(ListView).first, const Offset(0, 3000));
    await tester.pumpAndSettle();
    expect(find.text('Applied Grayscale to all 2 pages'), findsOneWidget);
    expect(find.text('Grayscale'), findsNWidgets(3), reason: 'two page subtitles and the chip');

    // Just page 2, black and white.
    await tester.tap(find.text('Page 2'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('This page'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('This page'));
    await tester.tap(find.byKey(const Key('scan-filter-blackWhite')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('scan-filter-apply')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('scan-filter-apply')));
    await tester.pumpAndSettle();
    expect(calls, hasLength(3));
    expect(calls.last.filter, ScanFilter.blackWhite);
    await tester.drag(find.byType(ListView).first, const Offset(0, 3000));
    await tester.pumpAndSettle();
    expect(find.text('Applied Black and white to page 2'), findsOneWidget);

    // Undo puts page 2 back to grayscale.
    await tester.tap(find.byKey(const Key('result-undo')));
    await tester.pumpAndSettle();
    expect(find.text('Black and white'), findsOneWidget, reason: 'only the chip');
  });
}
