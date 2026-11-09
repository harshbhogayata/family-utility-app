import 'dart:typed_data';

import 'package:family_utility_app/app/theme.dart';
import 'package:family_utility_app/engines/image/image_resizer.dart';
import 'package:family_utility_app/tools/compress_images/compress_images_screen.dart';
import 'package:family_utility_app/tools/resize/resize_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

Uint8List jpg(int w, int h) => img.encodeJpg(img.Image(width: w, height: h));
Uint8List png(int w, int h) => img.encodePng(img.Image(width: w, height: h, numChannels: 4));

class FakeFiles implements ImageFiles {
  FakeFiles(this.inputs);
  final Map<String, Uint8List> inputs;
  final Map<String, Uint8List> written = <String, Uint8List>{};

  @override
  Future<List<String>> pick() async => inputs.keys.toList();

  @override
  Future<Uint8List> read(String path) async => inputs[path]!;

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
  test('target sizes: pixels with and without the lock, percent, presets', () {
    expect(ImageResizer.targetSize(4000, 3000, const ResizeSpec.pixels(width: 800)), (width: 800, height: 600));
    expect(ImageResizer.targetSize(4000, 3000, const ResizeSpec.pixels(height: 300)), (width: 400, height: 300));
    expect(ImageResizer.targetSize(4000, 3000, const ResizeSpec.pixels(width: 500, height: 500)), (width: 500, height: 375));
    expect(ImageResizer.targetSize(4000, 3000, const ResizeSpec.pixels(width: 500, height: 500, lockAspect: false)),
        (width: 500, height: 500));
    expect(ImageResizer.targetSize(4000, 3000, const ResizeSpec.percent(25)), (width: 1000, height: 750));
    final ResizePreset hd = resizePresets.firstWhere((ResizePreset p) => p.id == 'hd');
    expect(ImageResizer.targetSize(4000, 3000, ResizeSpec.preset(hd)), (width: 1440, height: 1080));
    expect(ImageResizer.targetSize(800, 600, ResizeSpec.preset(hd)), (width: 800, height: 600), reason: 'fit presets never enlarge');
  });

  test('form presets come out exactly the asked size; PNG stays PNG', () {
    final ResizePreset passport = resizePresets.first;
    final ResizeResult r = ImageResizer.resize(jpg(1200, 900), ResizeSpec.preset(passport));
    expect((r.width, r.height), (413, 531));
    final img.Image back = img.decodeJpg(r.bytes)!;
    expect((back.width, back.height), (413, 531));
    expect(r.extension, 'jpg');

    final ResizeResult p = ImageResizer.resize(png(100, 50), const ResizeSpec.percent(50));
    expect(p.extension, 'png');
    expect((p.width, p.height), (50, 25));
    expect(() => ImageResizer.resize(Uint8List.fromList(<int>[1, 2, 3]), const ResizeSpec.percent(50)),
        throwsA(isA<ResizeError>()));
  });

  testWidgets('batch: pick two pictures, resize to a preset, undo removes both', (WidgetTester tester) async {
    final FakeFiles files = FakeFiles(<String, Uint8List>{'/a/one.jpg': jpg(300, 200), '/a/two.png': png(200, 300)});
    await tester.pumpWidget(MaterialApp(theme: buildAppTheme(), home: ResizeScreen(files: files)));
    await tester.tap(find.byKey(const Key('resize-pick')));
    await tester.pumpAndSettle();
    expect(find.text('Resize 2 pictures'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('resize-preset-profile')));
    await tester.tap(find.byKey(const Key('resize-preset-profile')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('resize-run')));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byKey(const Key('resize-run'))).height, greaterThanOrEqualTo(44));
    await tester.tap(find.byKey(const Key('resize-run')));
    await tester.pumpAndSettle();
    expect(files.written.keys, <String>['/out/one 400x400.jpg', '/out/two 400x400.png']);
    expect(find.text('Resized 2 pictures'), findsOneWidget);
    expect(find.byKey(const Key('result-share')), findsOneWidget);

    await tester.tap(find.byKey(const Key('result-undo')));
    await tester.pumpAndSettle();
    expect(files.written, isEmpty);
  });
}
