import 'dart:io';
import 'dart:typed_data';

import 'package:family_utility_app/app/theme.dart';
import 'package:family_utility_app/engines/image/image_compressor.dart';
import 'package:family_utility_app/engines/share/share_engine.dart';
import 'package:family_utility_app/tools/compress_images/compress_images_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// A noisy photo-like image so JPG quality changes the size.
Uint8List photoJpg(int w, int h) {
  final img.Image im = img.Image(width: w, height: h);
  for (final img.Pixel p in im) {
    final int v = (p.x * 7 + p.y * 13 + (p.x * p.y) % 31) % 256;
    p.setRgb(v, (v * 3) % 256, (255 - v) % 256);
  }
  return img.encodeJpg(im, quality: 100);
}

/// A PNG with a transparent half.
Uint8List transparentPng(int w, int h) {
  final img.Image im = img.Image(width: w, height: h, numChannels: 4);
  for (final img.Pixel p in im) {
    p.setRgba((p.x * 5) % 256, (p.y * 9) % 256, 120, p.x < w ~/ 2 ? 0 : 255);
  }
  return img.encodePng(im, level: 0);
}

class FakeFiles implements ImageFiles {
  FakeFiles(this.images);
  final Map<String, Uint8List> images;
  final Map<String, Uint8List> written = <String, Uint8List>{};

  @override
  Future<List<String>> pick() async => images.keys.toList();

  @override
  Future<Uint8List> read(String path) async => images[path]!;

  @override
  Future<String> write(String name, Uint8List bytes) async {
    final String p = '/compressed/$name';
    written[p] = bytes;
    return p;
  }

  @override
  Future<void> remove(String path) async => written.remove(path);
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
  group('ImageCompressor', () {
    test('lower quality gives a smaller JPG', () {
      final Uint8List src = photoJpg(320, 240);
      final CompressResult high = ImageCompressor.compress(src, const CompressSettings(quality: 90));
      final CompressResult low = ImageCompressor.compress(src, const CompressSettings(quality: 30));
      expect(low.size, lessThan(high.size));
      expect(low.size, lessThan(src.length));
      expect(low.format, OutputFormat.jpg);
      expect(low.savedPercent, greaterThan(0));
      expect(img.decodeJpg(low.bytes)!.width, 320);
    });

    test('never upscales; shrinks only when bigger than the limit', () {
      final Uint8List src = photoJpg(300, 200);
      final CompressResult same = ImageCompressor.compress(src, const CompressSettings(maxSide: 2048));
      expect(same.width, 300);
      expect(same.height, 200);
      final CompressResult small = ImageCompressor.compress(src, const CompressSettings(maxSide: 150));
      expect(small.width, 150);
      expect(small.height, 100);
      final CompressResult tall = ImageCompressor.compress(photoJpg(100, 400), const CompressSettings(maxSide: 200));
      expect(tall.height, 200);
      expect(tall.width, 50);
    });

    test('PNG with transparency stays PNG and keeps its alpha', () {
      final Uint8List src = transparentPng(64, 64);
      final CompressResult r = ImageCompressor.compress(src, const CompressSettings(quality: 50));
      expect(r.format, OutputFormat.png);
      final img.Image back = img.decodePng(r.bytes)!;
      expect(back.getPixel(2, 10).a, 0);
      expect(back.getPixel(60, 10).a, 255);
      expect(r.size, lessThan(src.length));
    });

    test('an opaque PNG becomes a JPG; junk is refused', () {
      final img.Image im = img.Image(width: 50, height: 50);
      img.fill(im, color: img.ColorRgb8(10, 120, 200));
      final CompressResult r =
          ImageCompressor.compress(img.encodePng(im, level: 0), const CompressSettings(quality: 70));
      expect(r.format, OutputFormat.jpg);
      expect(() => ImageCompressor.compress(Uint8List.fromList(<int>[1, 2, 3]), const CompressSettings()),
          throwsA(isA<CompressError>()));
      expect(ImageCompressor.outputName('/a/holiday.webp', OutputFormat.jpg), 'holiday-small.jpg');
      expect(ImageCompressor.outputName('logo.png', OutputFormat.png), 'logo-small.png');
    });

    test('the engine has no network code', () {
      final String src = File('lib/engines/image/image_compressor.dart').readAsStringSync();
      expect(src.contains('HttpClient'), isFalse);
      expect(src.contains('Socket'), isFalse);
    });
  });

  group('screen', () {
    testWidgets('batch, live size as the slider moves, Save / Share / Undo', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final FakeFiles files = FakeFiles(<String, Uint8List>{
        '/pics/one.jpg': photoJpg(160, 120),
        '/pics/two.png': transparentPng(48, 48),
      });
      final FakeSheet sheet = FakeSheet();
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: CompressImagesScreen(
          files: files,
          runner: (Uint8List b, CompressSettings s) async => ImageCompressor.compress(b, s),
          share: ShareEngine(sheet, MemoryShareTargetStore()),
          debounce: const Duration(milliseconds: 10),
        ),
      ));

      await tester.tap(find.byKey(const Key('compress-pick')));
      await tester.pumpAndSettle();
      expect(find.text('one.jpg'), findsOneWidget);
      expect(find.text('two.png'), findsOneWidget);
      final String before = tester.widget<Text>(find.byKey(const Key('compress-total'))).data!;
      expect(before, contains('→'));
      expect(find.textContaining('PNG'), findsOneWidget);

      await tester.drag(find.byKey(const Key('compress-quality')), const Offset(-1000, 0));
      await tester.pump(const Duration(milliseconds: 20));
      await tester.pumpAndSettle();
      expect(find.text('Quality 10'), findsOneWidget);
      final String after = tester.widget<Text>(find.byKey(const Key('compress-total'))).data!;
      expect(after, isNot(before), reason: 'the size readout follows the slider');

      for (final String key in <String>['compress-pick', 'compress-quality', 'compress-shrink', 'result-share', 'result-save', 'result-undo']) {
        expect(tester.getSize(find.byKey(Key(key))).height, greaterThanOrEqualTo(44), reason: key);
      }

      await tester.tap(find.byKey(const Key('result-save')));
      await tester.pumpAndSettle();
      expect(files.written.keys, containsAll(<String>['/compressed/one-small.jpg', '/compressed/two-small.png']));

      await tester.tap(find.byKey(const Key('result-share')));
      await tester.pumpAndSettle();
      expect(sheet.requests.single.files, hasLength(2));

      await tester.tap(find.byKey(const Key('result-undo')));
      await tester.pumpAndSettle();
      expect(files.written, isEmpty);
    });
  });
}
