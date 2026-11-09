import 'dart:convert';
import 'dart:typed_data';

import 'package:family_utility_app/app/theme.dart';
import 'package:family_utility_app/engines/pdf/pdf_clean_scan.dart';
import 'package:family_utility_app/engines/pdf/pdf_ocr.dart';
import 'package:family_utility_app/engines/pdf/pdf_to_images.dart';
import 'package:family_utility_app/engines/share/share_engine.dart';
import 'package:family_utility_app/tools/clean_scan/clean_scan_screen.dart';
import 'package:family_utility_app/tools/pdf_viewer/pdf_viewer_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

const int w = 200;
const int h = 280;

img.Image white() => img.Image(width: w, height: h)..clear(img.ColorRgb8(255, 255, 255));

void bar(img.Image im, int x0, int y0, int x1, int y1) {
  img.fillRect(im, x1: x0, y1: y0, x2: x1, y2: y1, color: img.ColorRgb8(0, 0, 0));
}

/// A text page: a heavy heading at the top and eleven lines of "text".
img.Image textPage() {
  final img.Image im = white();
  bar(im, 20, 20, 180, 40);
  for (int y = 60; y < 270; y += 20) {
    bar(im, 20, y, 180, y + 3);
  }
  return im;
}

/// Blank paper with a dark scanner edge inside the ignored margin.
img.Image blankPage() {
  final img.Image im = white();
  bar(im, 0, 0, 4, h - 1);
  return im;
}

/// Two short lines: about 1 % ink.
img.Image faintPage() {
  final img.Image im = white();
  bar(im, 60, 30, 120, 33);
  bar(im, 60, 50, 120, 53);
  return im;
}

/// Five pages: straight, blank, leaning 6° (rising to the right), upside
/// down, and nearly empty.
class FakeRasterizer implements PdfRasterizer {
  @override
  Future<int> pageCount(Uint8List pdf) async => 5;

  @override
  Future<img.Image> render(Uint8List pdf, int index, int dpi) async {
    switch (index) {
      case 0:
        return textPage();
      case 1:
        return blankPage();
      case 2:
        return rotateOnWhite(textPage(), -6);
      case 3:
        return img.copyRotate(textPage(), angle: 180);
      default:
        return faintPage();
    }
  }
}

int darkIn(img.Image im, int y0, int y1) {
  int n = 0;
  for (int y = y0; y < y1; y++) {
    for (int x = 0; x < im.width; x++) {
      if (im.getPixel(x, y).r < 128) {
        n++;
      }
    }
  }
  return n;
}

/// Reads well only when the heavy heading is at the top, like real text
/// that reads only the right way up.
class FakeRecognizer implements TextRecognizerEngine {
  int calls = 0;

  @override
  Future<List<OcrWord>> recognize(img.Image page, Uint8List jpeg, OcrScript script) async {
    calls++;
    final int top = darkIn(page, 0, page.height ~/ 3);
    final int bottom = darkIn(page, page.height * 2 ~/ 3, page.height);
    if (top > bottom) {
      return <OcrWord>[
        for (int i = 0; i < 6; i++) OcrWord('Word$i', left: 20.0 + i * 25, top: 20, right: 40.0 + i * 25, bottom: 40),
      ];
    }
    return const <OcrWord>[OcrWord('x', left: 0, top: 0, right: 5, bottom: 5)];
  }
}

class FakeChooser implements PdfChooser {
  @override
  Future<String?> pick() async => '/docs/bill-scan.pdf';
}

class RecordingSheet implements ShareSheet {
  final List<ShareRequest> sent = <ShareRequest>[];

  @override
  Future<ShareOutcome> share(ShareRequest request) async {
    sent.add(request);
    return const ShareOutcome.dismissed();
  }
}

void main() {
  group('measuring', () {
    test('ink share: blank paper and a scanner edge are blank, text is not', () {
      expect(inkShare(blankPage()), lessThan(defaultBlankInk));
      expect(inkShare(textPage()), greaterThan(0.1));
      final double faint = inkShare(faintPage());
      expect(faint, greaterThan(defaultBlankInk));
      expect(faint, lessThan(0.02));
    });

    test('skew is measured both ways and undone', () {
      expect(estimateSkew(textPage()), closeTo(0, 0.3));
      expect(estimateSkew(rotateOnWhite(textPage(), -6)), closeTo(6, 0.6));
      expect(estimateSkew(rotateOnWhite(textPage(), 12)), closeTo(-12, 0.6));
      final img.Image leaning = rotateOnWhite(textPage(), -6);
      final img.Image fixed = rotateOnWhite(leaning, estimateSkew(leaning));
      expect(estimateSkew(fixed), closeTo(0, 0.6));
    });

    test('skew stays within 15 degrees', () {
      final double s = estimateSkew(rotateOnWhite(textPage(), 14));
      expect(s.abs(), lessThanOrEqualTo(maxSkewDegrees));
      expect(s, closeTo(-14, 0.6));
    });

    test('rotation keeps the size and fills corners with white', () {
      final img.Image r = rotateOnWhite(textPage(), 10);
      expect(r.width, w);
      expect(r.height, h);
      expect(r.getPixel(0, 0).r, 255);
      expect(r.getPixel(w - 1, h - 1).g, 255);
    });

    test('a page turns only when it reads clearly better upside down', () {
      List<OcrWord> words(int n) =>
          <OcrWord>[for (int i = 0; i < n; i++) OcrWord('ab$i', left: 0, top: 0, right: 1, bottom: 1)];
      expect(readsBetterFlipped(words(1), words(6)), isTrue);
      expect(readsBetterFlipped(words(5), words(6)), isFalse);
      expect(readsBetterFlipped(words(0), words(2)), isFalse);
      expect(readsBetterFlipped(words(6), words(1)), isFalse);
    });
  });

  group('engine', () {
    test('finds the blank page, straightens the leaning one and turns the upside-down one', () async {
      final FakeRecognizer rec = FakeRecognizer();
      final List<CleanPage> pages =
          await PdfCleanScan(rasterizer: FakeRasterizer(), recognizer: rec).analyze(Uint8List(0), const CleanScanOptions());
      expect(pages, hasLength(5));
      expect(<bool>[for (final CleanPage p in pages) p.isBlank(defaultBlankInk)], <bool>[false, true, false, false, false]);
      expect(pages[0].skewDegrees, 0);
      expect(pages[2].skewDegrees, closeTo(6, 0.6));
      expect(pages[3].skewDegrees, 0);
      expect(<bool>[for (final CleanPage p in pages) p.upsideDown], <bool>[false, false, false, true, false]);
      // The corrected page reads level.
      expect(estimateSkew(img.decodeJpg(pages[2].jpeg)!), closeTo(0, 0.6));
      // Turned page now has its heading on top.
      final img.Image turned = img.decodeJpg(pages[3].jpeg)!;
      expect(darkIn(turned, 0, h ~/ 3), greaterThan(darkIn(turned, h * 2 ~/ 3, h)));
      expect(pages[3].words, hasLength(6));
      // Each inked page is read upright and flipped; the blank page is skipped.
      expect(rec.calls, 8);
      expect(pages[1].words, isEmpty);
    });

    test('options switch straightening and turning off', () async {
      final FakeRecognizer rec = FakeRecognizer();
      final List<CleanPage> pages = await PdfCleanScan(rasterizer: FakeRasterizer(), recognizer: rec)
          .analyze(Uint8List(0), const CleanScanOptions(deskew: false, autoRotate: false));
      expect(pages.every((CleanPage p) => p.skewDegrees == 0 && !p.upsideDown), isTrue);
      expect(rec.calls, 4);
    });

    test('the threshold is adjustable and the person has the last word', () async {
      final PdfCleanScan engine = PdfCleanScan(rasterizer: FakeRasterizer(), recognizer: FakeRecognizer());
      final List<CleanPage> pages = await engine.analyze(Uint8List(0), const CleanScanOptions());

      final CleanScanResult byDefault = engine.build(pages, defaultBlankInk);
      expect(byDefault.kept, 4);
      expect(byDefault.removed, 1);
      expect(byDefault.straightened, 1);
      expect(byDefault.turned, 1);
      final String s = latin1.decode(byDefault.pdf);
      expect(s, startsWith('%PDF-'));
      expect(RegExp('/Subtype /Image').allMatches(s).length, 4);
      expect(RegExp(r'BT 3 Tr').allMatches(s).length, greaterThan(0));

      // Stricter: the nearly empty page goes too.
      expect(engine.build(pages, 0.02).removed, 2);

      // Keep the blank page anyway.
      pages[1].keepOverride = true;
      expect(engine.build(pages, defaultBlankInk).kept, 5);

      for (final CleanPage p in pages) {
        p.keepOverride = false;
      }
      expect(() => engine.build(pages, defaultBlankInk), throwsA(isA<PdfOcrError>()));
    });

    test('names the copy next to the original', () {
      expect(cleanName('/docs/Bill Scan.PDF'), 'Bill Scan-clean.pdf');
      expect(cleanName('/docs/notes'), 'notes-clean.pdf');
    });
  });

  group('screen', () {
    Future<(RecordingSheet, Map<String, Uint8List>)> pump(WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 4000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final RecordingSheet sheet = RecordingSheet();
      final Map<String, Uint8List> written = <String, Uint8List>{};
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: CleanScanScreen(
          chooser: FakeChooser(),
          readBytes: (String p) async => Uint8List(0),
          rasterizer: FakeRasterizer(),
          recognizer: FakeRecognizer(),
          writer: (String name, Uint8List bytes) async {
            written['/app/$name'] = bytes;
            return '/app/$name';
          },
          share: ShareEngine(sheet, MemoryShareTargetStore()),
        ),
      ));
      await tester.pumpAndSettle();
      return (sheet, written);
    }

    testWidgets('preview, change a page, make the PDF, share and undo', (WidgetTester tester) async {
      final (RecordingSheet sheet, Map<String, Uint8List> written) = await pump(tester);
      await tester.tap(find.byKey(const Key('clean-pick')));
      await tester.pumpAndSettle();
      expect(find.text('bill-scan.pdf'), findsOneWidget);
      await tester.tap(find.byKey(const Key('clean-analyze')));
      await tester.pumpAndSettle();

      // Preview before anything is removed.
      expect(find.text('1 of 5 pages will be removed. Tap a page to change.'), findsOneWidget);
      expect(find.byKey(const Key('clean-threshold')), findsOneWidget);
      expect(written, isEmpty);

      await tester.tap(find.byKey(const Key('clean-page-1')));
      await tester.pumpAndSettle();
      expect(find.text('No pages will be removed. Tap a page to remove it.'), findsOneWidget);
      await tester.tap(find.byKey(const Key('clean-page-1')));
      await tester.pumpAndSettle();
      expect(find.text('1 of 5 pages will be removed. Tap a page to change.'), findsOneWidget);

      await tester.tap(find.byKey(const Key('clean-apply')));
      await tester.pumpAndSettle();
      expect(find.text('4 pages kept, 1 removed, 1 straightened, 1 turned'), findsOneWidget);
      expect(written.keys.single, '/app/bill-scan-clean.pdf');

      await tester.tap(find.byKey(const Key('result-share')));
      await tester.pumpAndSettle();
      expect(sheet.sent.single.files.single.path, '/app/bill-scan-clean.pdf');

      await tester.tap(find.byKey(const Key('result-undo')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('clean-summary')), findsNothing);
    });

    testWidgets('controls are labelled and at least 44 px tall', (WidgetTester tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await pump(tester);
      await tester.tap(find.byKey(const Key('clean-pick')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('clean-analyze')));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel(RegExp('Script of the text')), findsWidgets);
      expect(find.bySemanticsLabel(RegExp(r'^Page 2: kept|^Page 2: removed')), findsOneWidget);
      for (final String k in <String>[
        'clean-pick',
        'clean-analyze',
        'clean-apply',
        'clean-page-0',
        'result-share',
        'result-save',
        'result-undo',
      ]) {
        expect(tester.getSize(find.byKey(Key(k))).height, greaterThanOrEqualTo(44));
      }
      handle.dispose();
    });
  });
}
