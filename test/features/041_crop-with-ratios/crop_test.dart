import 'dart:io';
import 'dart:typed_data';

import 'package:family_utility_app/app/theme.dart';
import 'package:family_utility_app/engines/image/crop_engine.dart';
import 'package:family_utility_app/engines/share/share_engine.dart';
import 'package:family_utility_app/tools/crop/crop_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// A w×h JPG with a red block in the top-left corner.
Uint8List markedJpg(int w, int h) {
  final img.Image im = img.Image(width: w, height: h);
  img.fill(im, color: img.ColorRgb8(20, 20, 200));
  img.fillRect(im, x1: 0, y1: 0, x2: w ~/ 5, y2: h ~/ 5, color: img.ColorRgb8(250, 0, 0));
  return img.encodeJpg(im, quality: 95);
}

Uint8List plainPng(int w, int h) {
  final img.Image im = img.Image(width: w, height: h);
  img.fill(im, color: img.ColorRgb8(0, 160, 0));
  return img.encodePng(im);
}

class FakeFiles implements CropFiles {
  FakeFiles(this.path, this.bytes);
  final String path;
  final Uint8List bytes;
  final Map<String, Uint8List> written = <String, Uint8List>{};

  @override
  Future<String?> pick() async => path;

  @override
  Future<Uint8List> read(String p) async => bytes;

  @override
  Future<String> write(String name, Uint8List b) async {
    final String p = '/cropped/$name';
    written[p] = b;
    return p;
  }

  @override
  Future<void> remove(String p) async => written.remove(p);
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
  group('CropEngine maths', () {
    test('fitRatio gives the largest centred box of each ratio', () {
      const PixelSize land = PixelSize(400, 300);
      expect(CropEngine.fitRatio(CropRatio.free, land), NormRect.full);
      final NormRect sq = CropEngine.fitRatio(CropRatio.square, land);
      expect(sq.height, 1);
      expect(sq.width, closeTo(0.75, 1e-9));
      expect(sq.left, closeTo(0.125, 1e-9));
      final NormRect wide = CropEngine.fitRatio(CropRatio.r16x9, land);
      expect(wide.width, 1);
      expect(wide.height * 300 / (wide.width * 400), closeTo(9 / 16, 1e-9));
      for (final CropRatio r in CropRatio.values) {
        final NormRect n = CropEngine.fitRatio(r, land);
        expect(n.left, greaterThanOrEqualTo(0));
        expect(n.top, greaterThanOrEqualTo(0));
        expect(n.right, lessThanOrEqualTo(1 + 1e-9));
        expect(n.bottom, lessThanOrEqualTo(1 + 1e-9));
        if (r.value != null) {
          expect(n.width * 400 / (n.height * 300), closeTo(r.value!, 1e-9), reason: r.label);
        }
      }
    });

    test('dragging a corner keeps the ratio and stays inside', () {
      const PixelSize f = PixelSize(400, 300);
      final NormRect start = CropEngine.fitRatio(CropRatio.r4x3, f);
      final NormRect dragged = CropEngine.dragCorner(start, CropCorner.bottomRight, -0.3, -0.05, CropRatio.r4x3, f);
      expect(dragged.left, start.left);
      expect(dragged.top, start.top);
      expect(dragged.width, closeTo(0.7, 1e-9));
      expect(dragged.width * 400 / (dragged.height * 300), closeTo(4 / 3, 1e-9));

      final NormRect free = CropEngine.dragCorner(NormRect.full, CropCorner.topLeft, 0.2, 0.4, CropRatio.free, f);
      expect(free.left, closeTo(0.2, 1e-9));
      expect(free.top, closeTo(0.4, 1e-9));
      expect(free.right, closeTo(1, 1e-9));

      final NormRect tooFar = CropEngine.dragCorner(NormRect.full, CropCorner.topLeft, 5, 5, CropRatio.free, f);
      expect(tooFar.width, closeTo(CropEngine.minSide, 1e-9));
      final NormRect outward = CropEngine.dragCorner(free, CropCorner.topLeft, -5, -5, CropRatio.free, f);
      expect(outward, NormRect.full);

      final NormRect moved = CropEngine.move(const NormRect(0.1, 0.1, 0.5, 0.5), 0.9, -0.9);
      expect(moved.left, closeTo(0.5, 1e-9));
      expect(moved.top, 0);
    });

    test('straighten scale is 1 at 0° and shrinks with the angle', () {
      expect(CropEngine.straightenScale(400, 300, 0), 1);
      final double s5 = CropEngine.straightenScale(400, 300, 5);
      final double s20 = CropEngine.straightenScale(400, 300, -20);
      expect(s5, lessThan(1));
      expect(s20, lessThan(s5));
      expect(CropEngine.frame(const PixelSize(400, 300), 1).width, 300);
    });
  });

  group('CropEngine.apply', () {
    test('identity keeps the size; the original bytes are untouched', () {
      final Uint8List src = markedJpg(200, 100);
      final Uint8List copy = Uint8List.fromList(src);
      final CropResult r = CropEngine.apply(src, const CropSpec());
      expect(r.width, 200);
      expect(r.height, 100);
      expect(r.isPng, isFalse);
      expect(src, copy);
      expect(CropEngine.measure(src).width, 200);
    });

    test('crops to the ratio box in pixels', () {
      final Uint8List src = markedJpg(200, 100);
      final NormRect box = CropEngine.fitRatio(CropRatio.square, const PixelSize(200, 100));
      final CropResult r = CropEngine.apply(src, CropSpec(ratio: CropRatio.square, rect: box));
      expect(r.width, 100);
      expect(r.height, 100);
      final img.Image out = img.decodeJpg(r.bytes)!;
      expect(out.width, 100);
    });

    test('a quarter turn right moves the top-left corner to the top-right', () {
      final CropResult r = CropEngine.apply(markedJpg(200, 100), const CropSpec(quarterTurns: 1));
      expect(r.width, 100);
      expect(r.height, 200);
      final img.Image out = img.decodeJpg(r.bytes)!;
      final img.Pixel topRight = out.getPixel(95, 5);
      final img.Pixel topLeft = out.getPixel(5, 5);
      expect(topRight.r, greaterThan(180), reason: 'red block ends top-right');
      expect(topLeft.r, lessThan(80));
    });

    test('straightening trims empty corners away', () {
      final CropResult r = CropEngine.apply(markedJpg(200, 100), const CropSpec(angle: 10));
      final double s = CropEngine.straightenScale(200, 100, 10);
      expect(r.width, (200 * s).floor());
      expect(r.height, (100 * s).floor());
      final img.Image out = img.decodeJpg(r.bytes)!;
      // No black fill at the corners: every corner pixel is part of the photo.
      for (final List<int> xy in <List<int>>[
        <int>[2, 2],
        <int>[out.width - 3, 2],
        <int>[2, out.height - 3],
        <int>[out.width - 3, out.height - 3],
      ]) {
        final img.Pixel p = out.getPixel(xy[0], xy[1]);
        expect(p.r + p.g + p.b, greaterThan(120), reason: 'corner $xy');
      }
    });

    test('circle is a transparent-cornered PNG', () {
      final NormRect box = CropEngine.fitRatio(CropRatio.circle, const PixelSize(120, 80));
      final CropResult r = CropEngine.apply(markedJpg(120, 80), CropSpec(ratio: CropRatio.circle, rect: box));
      expect(r.isPng, isTrue);
      expect(r.width, r.height);
      final img.Image out = img.decodePng(r.bytes)!;
      expect(out.getPixel(0, 0).a, 0);
      expect(out.getPixel(r.width ~/ 2, r.height ~/ 2).a, 255);
      expect(CropEngine.outputName('/a/me.jpg', r), 'me-crop.png');
    });

    test('PNG stays PNG; junk is refused; no network code', () {
      final CropResult r = CropEngine.apply(plainPng(60, 40), const CropSpec());
      expect(r.isPng, isTrue);
      expect(() => CropEngine.apply(Uint8List.fromList(<int>[1, 2, 3]), const CropSpec()),
          throwsA(isA<CropError>()));
      final String src = File('lib/engines/image/crop_engine.dart').readAsStringSync();
      expect(src.contains('HttpClient'), isFalse);
      expect(src.contains('Socket'), isFalse);
    });
  });

  group('screen', () {
    testWidgets('ratios, handles, rotate, non-destructive Save / Share / Undo', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 2800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final Uint8List src = markedJpg(200, 100);
      final FakeFiles files = FakeFiles('/pics/beach.jpg', src);
      final FakeSheet sheet = FakeSheet();
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: CropScreen(
          files: files,
          runner: (Uint8List b, CropSpec s) async => CropEngine.apply(b, s),
          measure: (Uint8List b) async => CropEngine.measure(b),
          share: ShareEngine(sheet, MemoryShareTargetStore()),
        ),
      ));

      await tester.tap(find.byKey(const Key('crop-pick')));
      await tester.pumpAndSettle();
      for (final CropRatio r in CropRatio.values) {
        expect(find.byKey(Key('crop-ratio-${r.name}')), findsOneWidget);
      }
      expect(find.textContaining('200×100'), findsOneWidget);

      await tester.tap(find.byKey(const Key('crop-ratio-square')));
      await tester.pumpAndSettle();
      expect(find.textContaining('1:1 · 100×100'), findsOneWidget);

      // Shrink with the bottom-right handle; the ratio holds.
      await tester.drag(find.byKey(const Key('crop-handle-bottomRight')), const Offset(-60, -10));
      await tester.pumpAndSettle();
      final String afterDrag = tester.widget<Text>(find.byKey(const Key('crop-summary'))).data!;
      final RegExpMatch m = RegExp(r'(\d+)×(\d+)').firstMatch(afterDrag)!;
      expect(m.group(1), m.group(2));
      expect(int.parse(m.group(1)!), lessThan(100));

      // Handles and controls are big enough to hit and labelled.
      for (final String key in <String>[
        'crop-handle-topLeft',
        'crop-handle-bottomRight',
        'crop-rotate-left',
        'crop-angle-plus',
        'crop-pick',
        'result-share',
        'result-save',
        'result-undo',
      ]) {
        final Size s = tester.getSize(find.byKey(Key(key)));
        expect(s.height, greaterThanOrEqualTo(44), reason: key);
        expect(s.width, greaterThanOrEqualTo(44), reason: key);
      }
      expect(
          find.byWidgetPredicate(
              (Widget w) => w is Semantics && w.properties.label == 'Top left crop handle'),
          findsOneWidget);

      // Undo steps back through edits before anything is saved.
      await tester.tap(find.byKey(const Key('result-undo')));
      await tester.pumpAndSettle();
      expect(find.textContaining('1:1 · 100×100'), findsOneWidget);

      await tester.tap(find.byKey(const Key('crop-angle-plus')));
      await tester.pumpAndSettle();
      expect(find.text('Straighten 1°'), findsOneWidget);
      await tester.tap(find.byKey(const Key('crop-rotate-right')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('crop-grid')));
      await tester.pumpAndSettle();
      expect(files.written, isEmpty, reason: 'nothing is written until Save');

      await tester.tap(find.byKey(const Key('result-save')));
      await tester.pumpAndSettle();
      expect(files.written.keys, <String>['/cropped/beach-crop.jpg']);
      final img.Image saved = img.decodeJpg(files.written.values.single)!;
      expect(saved.width, saved.height);

      await tester.tap(find.byKey(const Key('result-share')));
      await tester.pumpAndSettle();
      expect(sheet.requests.single.files, hasLength(1));

      await tester.tap(find.byKey(const Key('result-undo')));
      await tester.pumpAndSettle();
      expect(files.written, isEmpty);
    });
  });
}
