import 'dart:typed_data';

import 'package:family_utility_app/app/theme.dart';
import 'package:family_utility_app/engines/image/rotate_flip.dart';
import 'package:family_utility_app/engines/share/share_engine.dart';
import 'package:family_utility_app/tools/compress_images/compress_images_screen.dart' show ImageFiles;
import 'package:family_utility_app/tools/rotate_flip/rotate_flip_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// 4×2 picture with a red pixel top-left and a blue one top-right.
img.Image marked() {
  final img.Image im = img.Image(width: 4, height: 2)..clear(img.ColorRgb8(255, 255, 255));
  im.setPixelRgb(0, 0, 255, 0, 0);
  im.setPixelRgb(3, 0, 0, 0, 255);
  return im;
}

Uint8List jpeg() => Uint8List.fromList(img.encodeJpg(img.Image(width: 8, height: 4), quality: 90));

class MemoryFiles implements ImageFiles {
  MemoryFiles(this.inputs);
  final Map<String, Uint8List> inputs;
  final Map<String, Uint8List> written = <String, Uint8List>{};

  @override
  Future<List<String>> pick() async => inputs.keys.toList();

  @override
  Future<Uint8List> read(String path) async => inputs[path]!;

  @override
  Future<String> write(String name, Uint8List bytes) async {
    written['/rotated/$name'] = bytes;
    return '/rotated/$name';
  }

  @override
  Future<void> remove(String path) async => written.remove(path);
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
  group('orientation', () {
    test('all eight EXIF values round-trip', () {
      for (int v = 1; v <= 8; v++) {
        expect(PhotoOrientation.fromExif(v).exif, v);
      }
      expect(PhotoOrientation.fromExif(0).exif, 1);
    });

    test('turns and flips compose like the EXIF table', () {
      const PhotoOrientation up = PhotoOrientation.upright;
      expect(up.then(RotateOp.right).exif, 6);
      expect(up.then(RotateOp.left).exif, 8);
      expect(up.thenAll(<RotateOp>[RotateOp.right, RotateOp.right]).exif, 3);
      expect(up.then(RotateOp.flipHorizontal).exif, 2);
      expect(up.then(RotateOp.flipVertical).exif, 4);
      expect(up.thenAll(<RotateOp>[RotateOp.right, RotateOp.flipHorizontal]).exif, 5);
      expect(up.thenAll(<RotateOp>[RotateOp.left, RotateOp.flipHorizontal]).exif, 7);
      // A photo the camera saved sideways (6) turned left is upright.
      expect(PhotoOrientation.fromExif(6).then(RotateOp.left).exif, 1);
      expect(up.thenAll(<RotateOp>[RotateOp.flipHorizontal, RotateOp.flipHorizontal]), up);
      expect(up.thenAll(<RotateOp>[RotateOp.flipHorizontal, RotateOp.flipVertical]).exif, 3);
    });
  });

  group('JPG', () {
    test('a photo without EXIF gets an orientation and keeps its picture data', () {
      final Uint8List src = jpeg();
      expect(readJpegOrientation(src), 1);
      final RotateResult r = RotateFlip.apply(src, <RotateOp>[RotateOp.right]);
      expect(r.lossless, isTrue);
      expect(r.extension, 'jpg');
      expect(readJpegOrientation(r.bytes), 6);
      expect(r.bytes.length, src.length + 36);
      // Still a valid JPG; the image package honours the new orientation.
      final img.Image? back = img.decodeJpg(r.bytes);
      expect(back, isNotNull);
      final img.Image baked = img.bakeOrientation(back!);
      expect(baked.width, 4);
      expect(baked.height, 8);
    });

    test('the existing orientation is respected and rewritten in place', () {
      final Uint8List sideways = writeJpegOrientation(jpeg(), 6);
      final RotateResult r = RotateFlip.apply(sideways, <RotateOp>[RotateOp.left]);
      expect(readJpegOrientation(r.bytes), 1);
      expect(r.bytes.length, sideways.length);
      final RotateResult again = RotateFlip.apply(sideways, <RotateOp>[RotateOp.flipVertical]);
      expect(again.orientation, PhotoOrientation.fromExif(6).then(RotateOp.flipVertical).exif);
    });

    test('names the copy', () {
      expect(RotateFlip.outputName('/pics/IMG_1.jpeg', 'jpg'), 'IMG_1-rotated.jpg');
      expect(RotateFlip.outputName('scan', 'png'), 'scan-rotated.png');
    });
  });

  group('PNG', () {
    test('turning right swaps the sides and moves the corners', () {
      final RotateResult r =
          RotateFlip.apply(Uint8List.fromList(img.encodePng(marked())), <RotateOp>[RotateOp.right]);
      expect(r.extension, 'png');
      expect(r.lossless, isFalse);
      final img.Image out = img.decodePng(r.bytes)!;
      expect(out.width, 2);
      expect(out.height, 4);
    });

    test('a flip mirrors, and two flips give the picture back', () {
      final Uint8List png = Uint8List.fromList(img.encodePng(marked()));
      final img.Image once = img.decodePng(RotateFlip.apply(png, <RotateOp>[RotateOp.flipHorizontal]).bytes)!;
      expect(once.getPixel(3, 0).r, 255);
      expect(once.getPixel(0, 0).b, 255);
      final img.Image twice = img.decodePng(
          RotateFlip.apply(png, <RotateOp>[RotateOp.flipHorizontal, RotateOp.flipHorizontal]).bytes)!;
      expect(twice.getPixel(0, 0).r, 255);
      final img.Image round = img.decodePng(RotateFlip.apply(
          png, <RotateOp>[RotateOp.right, RotateOp.right, RotateOp.right, RotateOp.right]).bytes)!;
      expect(round.width, 4);
      expect(round.getPixel(3, 0).b, 255);
    });

    test('not a picture is a clear error', () {
      expect(() => RotateFlip.apply(Uint8List.fromList(<int>[1, 2, 3]), <RotateOp>[RotateOp.left]),
          throwsA(isA<RotateError>()));
    });
  });

  testWidgets('many pictures at once: turn, save, share, undo', (WidgetTester tester) async {
    final MemoryFiles files = MemoryFiles(<String, Uint8List>{
      '/pics/a.jpg': jpeg(),
      '/pics/b.png': Uint8List.fromList(img.encodePng(marked())),
    });
    final RecordingSheet sheet = RecordingSheet();
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: RotateFlipScreen(files: files, share: ShareEngine(sheet, MemoryShareTargetStore())),
    ));
    await tester.tap(find.byKey(const Key('rotate-pick')));
    await tester.pumpAndSettle();
    expect(find.text('2 pictures chosen'), findsOneWidget);
    await tester.tap(find.byKey(const Key('rotate-right')));
    await tester.pumpAndSettle();
    expect(find.text('turned right'), findsOneWidget);
    await tester.tap(find.byKey(const Key('rotate-apply')));
    await tester.pumpAndSettle();
    expect(files.written.keys, unorderedEquals(<String>['/rotated/a-rotated.jpg', '/rotated/b-rotated.png']));
    expect(readJpegOrientation(files.written['/rotated/a-rotated.jpg']!), 6);
    expect(find.text('Saved 2 pictures in Files › rotated'), findsOneWidget);

    await tester.tap(find.byKey(const Key('result-share')));
    await tester.pumpAndSettle();
    expect(sheet.sent.single.files, hasLength(2));

    await tester.tap(find.byKey(const Key('result-undo')));
    await tester.pumpAndSettle();
    expect(files.written, isEmpty);
  });

  testWidgets('buttons are labelled and at least 44 px', (WidgetTester tester) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    await tester.pumpWidget(MaterialApp(theme: buildAppTheme(), home: RotateFlipScreen(files: MemoryFiles(<String, Uint8List>{}))));
    for (final String label in <String>['Rotate left', 'Rotate right', 'Flip horizontal', 'Flip vertical']) {
      expect(find.bySemanticsLabel(label), findsWidgets);
    }
    for (final String k in <String>['rotate-pick', 'rotate-left', 'rotate-right', 'flip-h', 'flip-v', 'rotate-apply']) {
      final Size s = tester.getSize(find.byKey(Key(k)));
      expect(s.height, greaterThanOrEqualTo(44));
      expect(s.width, greaterThanOrEqualTo(44));
    }
    handle.dispose();
  });
}
