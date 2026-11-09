import 'dart:convert';
import 'dart:typed_data';

import 'package:family_utility_app/app/theme.dart';
import 'package:family_utility_app/engines/image/document_scanner.dart';
import 'package:family_utility_app/engines/image/scan_entry.dart';
import 'package:family_utility_app/tools/document_scanner/document_scanner_screen.dart';
import 'package:family_utility_app/tools/document_scanner/scan_camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// True when (x, y) is inside the convex polygon (clockwise corners).
bool inside(List<ScanPoint> poly, double x, double y) {
  bool? sign;
  for (int i = 0; i < poly.length; i++) {
    final ScanPoint a = poly[i];
    final ScanPoint b = poly[(i + 1) % poly.length];
    final double cross = (b.x - a.x) * (y - a.y) - (b.y - a.y) * (x - a.x);
    final bool s = cross >= 0;
    sign ??= s;
    if (s != sign) {
      return false;
    }
  }
  return true;
}

const ScanQuad tilted = ScanQuad(
  ScanPoint(60, 40),
  ScanPoint(250, 70),
  ScanPoint(230, 300),
  ScanPoint(40, 280),
);

/// A dark desk with a bright page on it.
ScanFrame frameWith(ScanQuad? q, {int w = 320, int h = 360, int dx = 0}) {
  final Uint8List luma = Uint8List(w * h);
  final List<ScanPoint>? poly = q?.corners.map((ScanPoint p) => ScanPoint(p.x + dx, p.y)).toList();
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      final bool on = poly != null && inside(poly, x + 0.5, y + 0.5);
      // A little texture so the desk is not a flat colour.
      luma[y * w + x] = on ? 225 : 45 + ((x * 7 + y * 3) % 11);
    }
  }
  return ScanFrame(luma: luma, width: w, height: h);
}

img.Image photoWith(ScanQuad q, {int w = 320, int h = 360}) {
  final img.Image im = img.Image(width: w, height: h);
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      final bool on = inside(q.corners, x + 0.5, y + 0.5);
      if (on) {
        im.setPixelRgb(x, y, 240, 240, 235);
      } else {
        im.setPixelRgb(x, y, 50, 40, 35);
      }
    }
  }
  return im;
}

void expectNear(ScanPoint a, ScanPoint b, double tol) {
  expect(a.distanceTo(b), lessThan(tol), reason: 'got $a, wanted $b');
}

Uint8List smallJpg(int r) {
  final img.Image im = img.Image(width: 12, height: 16);
  img.fill(im, color: img.ColorRgb8(r, 200, 200));
  return img.encodeJpg(im, quality: 80);
}

ScanPage pageOf(int r) => ScanPage(jpeg: smallJpg(r), width: 12, height: 16, foundEdges: true);

class FakeCamera implements ScanCamera {
  FakeCamera({this.available = true});
  final bool available;
  void Function(ScanFrame frame)? onFrame;
  int shots = 0;
  bool disposed = false;

  @override
  Future<bool> start(void Function(ScanFrame frame) cb) async {
    onFrame = cb;
    return available;
  }

  @override
  Widget preview(BuildContext context) => const ColoredBox(key: Key('fake-preview'), color: Colors.black);

  @override
  Future<Uint8List> takePicture() async {
    shots++;
    return Uint8List.fromList(<int>[shots]);
  }

  @override
  Future<void> dispose() async => disposed = true;
}

class FakeIo implements ScanIo {
  final Map<String, Uint8List> written = <String, Uint8List>{};

  @override
  Future<String> write(String name, String extension, Uint8List bytes) async {
    final String p = '/scans/$name.$extension';
    written[p] = bytes;
    return p;
  }

  @override
  Future<void> remove(String path) async => written.remove(path);
}

void main() {
  group('edge detection', () {
    test('finds the four corners of a tilted page', () {
      final ScanQuad? q = const EdgeDetector().detect(frameWith(tilted));
      expect(q, isNotNull);
      // The grid is 2 px per cell on a 320 px frame.
      expectNear(q!.topLeft, tilted.topLeft, 8);
      expectNear(q.topRight, tilted.topRight, 8);
      expectNear(q.bottomRight, tilted.bottomRight, 8);
      expectNear(q.bottomLeft, tilted.bottomLeft, 8);
    });

    test('no page, or a page too small, finds nothing', () {
      expect(const EdgeDetector().detect(frameWith(null)), isNull);
      const ScanQuad tiny = ScanQuad(ScanPoint(10, 10), ScanPoint(40, 10), ScanPoint(40, 40), ScanPoint(10, 40));
      expect(const EdgeDetector().detect(frameWith(tiny)), isNull);
    });

    test('keeps up with a 30 fps preview', () {
      final ScanFrame f = frameWith(tilted, w: 240, h: 320);
      const EdgeDetector d = EdgeDetector();
      d.detect(f); // warm up
      final Stopwatch sw = Stopwatch()..start();
      for (int i = 0; i < 30; i++) {
        d.detect(f);
      }
      sw.stop();
      expect(sw.elapsedMilliseconds / 30, lessThan(33), reason: 'one frame must fit in 33 ms');
    });

    test('sensor frames are turned upright and reduced', () {
      // 4 x 2 landscape plane, row stride 5 (one pad byte per row).
      final Uint8List plane = Uint8List.fromList(<int>[1, 2, 3, 4, 0, 5, 6, 7, 8, 0]);
      final ScanFrame up = reduceLuma(plane, 4, 2, 5, 0, 240);
      expect(up.width, 4);
      expect(up.luma, <int>[1, 2, 3, 4, 5, 6, 7, 8]);
      final ScanFrame turned = reduceLuma(plane, 4, 2, 5, 1, 240);
      expect(turned.width, 2);
      expect(turned.height, 4);
      expect(turned.luma, <int>[5, 1, 6, 2, 7, 3, 8, 4]);
      final ScanFrame half = reduceLuma(Uint8List(1920 * 1080), 1920, 1080, 1920, 1, 240);
      expect(half.height, 240);
      expect(half.width, 135);
    });
  });

  group('auto-capture', () {
    test('fires once after a steady hold, again only after the page moves', () {
      final SteadyDetector s = SteadyDetector(steadyFrames: 5);
      int fires = 0;
      for (int i = 0; i < 12; i++) {
        if (s.feed(tilted, 320, 360)) {
          fires++;
        }
      }
      expect(fires, 1);
      expect(s.progress, 1);
      // Slight hand shake stays within tolerance.
      expect(s.feed(tilted.scale(1.005, 1.005), 320, 360), isFalse);
      // Moved: the hold starts over.
      const ScanQuad moved = ScanQuad(ScanPoint(100, 40), ScanPoint(290, 70), ScanPoint(270, 300), ScanPoint(80, 280));
      expect(s.feed(moved, 320, 360), isFalse);
      expect(s.progress, lessThan(1));
      for (int i = 0; i < 4; i++) {
        if (s.feed(moved, 320, 360)) {
          fires++;
        }
      }
      expect(fires, 2);
      // Losing the page resets.
      s.feed(null, 320, 360);
      expect(s.progress, 0);
    });
  });

  group('perspective fix', () {
    test('homography maps the rectangle onto the quad', () {
      final Homography h = Homography.rectToQuad(200, 250, tilted);
      expectNear(h.map(0, 0), tilted.topLeft, 1e-6);
      expectNear(h.map(200, 0), tilted.topRight, 1e-6);
      expectNear(h.map(200, 250), tilted.bottomRight, 1e-6);
      expectNear(h.map(0, 250), tilted.bottomLeft, 1e-6);
    });

    test('a photographed page comes out flat and filled', () {
      final img.Image photo = photoWith(tilted);
      final img.Image page = perspectiveFix(photo, tilted);
      expect(page.width, closeTo(191, 3));
      expect(page.height, closeTo(236, 3));
      // Inside the page everything is paper-white.
      for (final List<int> p in <List<int>>[
        <int>[5, 5],
        <int>[page.width - 6, 5],
        <int>[page.width ~/ 2, page.height ~/ 2],
        <int>[5, page.height - 6],
      ]) {
        expect(page.getPixel(p[0], p[1]).r, greaterThan(200), reason: 'pixel $p');
      }
    });

    test('process: detect, flatten and encode from a camera JPEG', () {
      final Uint8List jpeg = img.encodeJpg(photoWith(tilted), quality: 92);
      final ScanPage p = const DocumentScanner().process(jpeg);
      expect(p.foundEdges, isTrue);
      expect(p.width, closeTo(192, 10));
      expect(p.height, closeTo(236, 10));
      final img.Image out = img.decodeJpg(p.jpeg)!;
      expect(out.getPixel(out.width ~/ 2, out.height ~/ 2).r, greaterThan(200));
    });

    test('no page found keeps the whole photo; garbage is refused', () {
      final img.Image plain = img.Image(width: 40, height: 30);
      img.fill(plain, color: img.ColorRgb8(90, 90, 90));
      final ScanPage p = const DocumentScanner().process(img.encodeJpg(plain));
      expect(p.foundEdges, isFalse);
      expect(p.width, 40);
      expect(() => const DocumentScanner().process(Uint8List.fromList(utf8.encode('hello'))), throwsA(anything));
    });
  });

  group('session', () {
    test('add, retake, reorder, remove and undo', () {
      final ScanSession s = ScanSession();
      final ScanPage a = pageOf(10), b = pageOf(20), c = pageOf(30), b2 = pageOf(40);
      s
        ..add(a)
        ..add(b)
        ..add(c);
      s.retake(1, b2);
      expect(s.pages, <ScanPage>[a, b2, c]);
      s.move(0, 3);
      expect(s.pages, <ScanPage>[b2, c, a]);
      s.remove(1);
      expect(s.pages, <ScanPage>[b2, a]);
      expect(s.undo(), isTrue);
      expect(s.pages, <ScanPage>[b2, c, a]);
      expect(s.undo(), isTrue);
      expect(s.undo(), isTrue);
      expect(s.pages, <ScanPage>[a, b, c]);
    });

    test('saves as one PDF or a JPG per page', () async {
      final ScanSession s = ScanSession()
        ..add(pageOf(10))
        ..add(pageOf(90));
      final Uint8List pdf = await s.toPdf();
      final String t = latin1.decode(pdf);
      expect(t.startsWith('%PDF'), isTrue);
      expect(t, contains('/Count 2'));
      final List<Uint8List> jpgs = s.toJpgs();
      expect(jpgs, hasLength(2));
      expect(jpgs.first[0], 0xFF);
      expect(jpgs.first[1], 0xD8);
    });
  });

  group('share-sheet entry', () {
    test('another app asks for a scan and gets the saved paths back', () async {
      int opened = 0;
      final ScanEntry e = ScanEntry(() async {
        opened++;
        return <String>['/scans/Scan.pdf'];
      });
      expect(await e.handle(const MethodCall('scan')), <String>['/scans/Scan.pdf']);
      expect(opened, 1);
      await expectLater(e.handle(const MethodCall('other')), throwsA(isA<MissingPluginException>()));
      expect(ScanEntry.channelName, 'app.family/scan');
    });
  });

  testWidgets('auto-capture, manual capture, retake, reorder, save as JPG and PDF, undo', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2200);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    final FakeCamera cam = FakeCamera();
    final FakeIo io = FakeIo();
    int processed = 0;
    Future<ScanPage> process(Uint8List photo) async {
      processed++;
      return pageOf(processed * 30);
    }

    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: DocumentScannerScreen(
        camera: cam,
        io: io,
        process: process,
        now: () => DateTime(2026, 11, 9, 9, 5),
      ),
    ));
    await tester.pump();
    expect(find.byKey(const Key('fake-preview')), findsOneWidget);
    final Size shutter = tester.getSize(find.byKey(const Key('scan-shutter')));
    expect(shutter.height, greaterThanOrEqualTo(44));
    expect(shutter.width, greaterThanOrEqualTo(44));
    expect(find.bySemanticsLabel('Capture page'), findsOneWidget);

    // Hold steady over a page: auto-capture fires once.
    final ScanFrame f = frameWith(tilted);
    for (int i = 0; i < 20; i++) {
      cam.onFrame!(f);
      await tester.pump();
    }
    await tester.pump();
    expect(cam.shots, 1);
    expect(find.text('Page 1 captured'), findsOneWidget);

    // Manual shutter for page 2.
    await tester.tap(find.byKey(const Key('scan-shutter')));
    await tester.pump();
    await tester.pump();
    expect(cam.shots, 2);

    await tester.tap(find.byKey(const Key('scan-review')));
    await tester.pumpAndSettle();
    expect(find.text('Page 1'), findsOneWidget);
    expect(find.text('Page 2'), findsOneWidget);

    // Retake page 1.
    await tester.tap(find.byTooltip('Retake page 1'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Retake page 1'), findsOneWidget);
    await tester.tap(find.byKey(const Key('scan-shutter')));
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();
    expect(cam.shots, 3);
    expect(find.text('Retook page 1'), findsOneWidget);

    Future<void> scrollTop() async {
      await tester.drag(find.byType(ListView).first, const Offset(0, 3000));
      await tester.pumpAndSettle();
    }

    // Save as JPG: one file per page.
    await tester.ensureVisible(find.text('JPG'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('JPG'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('scan-make')));
    await tester.tap(find.byKey(const Key('scan-make')));
    await tester.pumpAndSettle();
    expect(io.written.keys, <String>['/scans/Scan 2026-11-09 09.05 p1.jpg', '/scans/Scan 2026-11-09 09.05 p2.jpg']);
    await scrollTop();
    expect(find.text('Saved 2 JPGs in Files › scans'), findsOneWidget);

    // Undo removes what was saved.
    await tester.tap(find.byKey(const Key('result-undo')));
    await tester.pumpAndSettle();
    expect(io.written, isEmpty);

    // Save as PDF through the result bar.
    await tester.ensureVisible(find.text('PDF'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('PDF'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('result-save')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(io.written.keys.single, '/scans/Scan 2026-11-09 09.05.pdf');
    expect(latin1.decode(io.written.values.single), contains('/Count 2'));
    expect(find.byKey(const Key('result-share')), findsOneWidget);

    // Undo the save, then undo the retake, then remove a page.
    await tester.tap(find.byKey(const Key('result-undo')));
    await tester.pumpAndSettle();
    expect(io.written, isEmpty);
    await scrollTop();
    await tester.tap(find.byTooltip('Remove page 2'));
    await tester.pumpAndSettle();
    expect(find.text('Page 2'), findsNothing);
    await tester.tap(find.byKey(const Key('result-undo')));
    await tester.pumpAndSettle();
    expect(find.text('Page 2'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    expect(cam.disposed, isTrue);
  });

  testWidgets('no camera: says so plainly and the shutter is off', (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: DocumentScannerScreen(camera: FakeCamera(available: false), io: FakeIo()),
    ));
    await tester.pump();
    expect(find.textContaining('No camera available'), findsOneWidget);
    final FilledButton b = tester.widget<FilledButton>(find.byKey(const Key('scan-shutter')));
    expect(b.onPressed, isNull);
  });
}
