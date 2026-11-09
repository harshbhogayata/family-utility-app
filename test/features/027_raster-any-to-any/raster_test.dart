import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:family_utility_app/app/theme.dart';
import 'package:family_utility_app/engines/image/raster_convert.dart';
import 'package:family_utility_app/tools/compress_images/compress_images_screen.dart';
import 'package:family_utility_app/tools/raster/raster_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// Two-page uncompressed TIFF, 4 × 4 each: page 1 red, page 2 blue.
final Uint8List twoPageTiff = base64Decode(
    'SUkqAAgAAAAKAAABBAABAAAABAAAAAEBBAABAAAABAAAAAIBAwADAAAAhgAAAAMBAwABAAAAAQAAAAYBAwABAAAAAgAAABEBBAABAAAAjAAAABUBAwABAAAAAwAAABYBBAABAAAABAAAABcBBAABAAAAMAAAABwBAwABAAAAAQAAAMgAAAAIAAgACAD/AAD/AAD/AAD/AAD/AAD/AAD/AAD/AAD/AAD/AAD/AAD/AAD/AAD/AAD/AAD/AAAAAAAASUkqAAgAAAAKAAABBAABAAAABAAAAAEBBAABAAAABAAAAAIBAwADAAAARgEAAAMBAwABAAAAAQAAAAYBAwABAAAAAgAAABEBBAABAAAATAEAABUBAwABAAAAAwAAABYBBAABAAAABAAAABcBBAABAAAAMAAAABwBAwABAAAAAQAAAAAAAAAIAAgACAAAAP8AAP8AAP8AAP8AAP8AAP8AAP8AAP8AAP8AAP8AAP8AAP8AAP8AAP8AAP8AAAAA');

Uint8List solidPng(int r, int g, int b) {
  final img.Image im = img.Image(width: 8, height: 8);
  img.fill(im, color: img.ColorRgb8(r, g, b));
  return img.encodePng(im);
}

Uint8List noisyPng() {
  final Random rnd = Random(7);
  final img.Image im = img.Image(width: 64, height: 64);
  for (final img.Pixel p in im) {
    p.setRgb(rnd.nextInt(256), rnd.nextInt(256), rnd.nextInt(256));
  }
  return img.encodePng(im);
}

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
  const RasterConverter c = RasterConverter();

  test('a multi-page TIFF becomes one picture per page', () {
    final RasterResult r = c.convert(twoPageTiff, 'scan.tiff', RasterFormat.png);
    expect(r.pages.map((RasterPage p) => p.name), <String>['scan_p1.png', 'scan_p2.png']);
    final img.Pixel first = img.decodePng(r.pages[0].bytes)!.getPixel(1, 1);
    final img.Pixel second = img.decodePng(r.pages[1].bytes)!.getPixel(1, 1);
    expect((first.r, first.g, first.b), (255, 0, 0));
    expect((second.r, second.g, second.b), (0, 0, 255));
  });

  test('every target writes a file that reads back with the same colour', () {
    final Uint8List green = solidPng(0, 200, 0);
    for (final RasterFormat t in RasterFormat.values) {
      final RasterResult r = c.convert(green, 'leaf.png', t, quality: 95);
      expect(r.pages.single.name, 'leaf.${t.extension}');
      final img.Image back = img.decodeImage(r.pages.single.bytes)!;
      final img.Pixel p = back.getPixel(4, 4);
      expect(p.g, closeTo(200, 12), reason: t.label);
      expect(p.r, lessThan(20), reason: t.label);
    }
  });

  test('the quality slider changes JPG size; transparency kept only where possible', () {
    final Uint8List noisy = noisyPng();
    final int low = c.convert(noisy, 'n.png', RasterFormat.jpg, quality: 20).pages.single.bytes.length;
    final int high = c.convert(noisy, 'n.png', RasterFormat.jpg, quality: 95).pages.single.bytes.length;
    expect(low, lessThan(high));

    final img.Image clear = img.Image(width: 4, height: 4, numChannels: 4);
    final Uint8List see = img.encodePng(clear);
    final RasterResult png = c.convert(see, 'c.png', RasterFormat.png);
    expect(png.hadAlpha, isTrue);
    expect(png.keptAlpha, isTrue);
    final RasterResult bmp = c.convert(see, 'c.png', RasterFormat.bmp);
    expect(bmp.keptAlpha, isFalse);
    expect(img.decodeImage(bmp.pages.single.bytes)!.getPixel(0, 0).r, greaterThan(240));

    expect(RasterFormat.fromName('a.JPEG'), RasterFormat.jpg);
    expect(RasterFormat.fromName('a.tif'), RasterFormat.tiff);
    expect(RasterConverter.defaultTarget('a.jpg'), RasterFormat.png);
    expect(RasterConverter.defaultTarget('a.bmp'), RasterFormat.jpg);
    expect(() => c.convert(Uint8List.fromList(utf8.encode('nope')), 'x.png', RasterFormat.png),
        throwsA(isA<RasterConvertError>()));
  });

  testWidgets('pick a TIFF, convert to JPG with the slider, undo', (WidgetTester tester) async {
    final FakeFiles files = FakeFiles(<String, Uint8List>{'/a/scan.tif': twoPageTiff});
    await tester.pumpWidget(MaterialApp(theme: buildAppTheme(), home: RasterScreen(files: files)));
    await tester.tap(find.byKey(const Key('raster-pick')));
    await tester.pumpAndSettle();
    expect(tester.widget<ChoiceChip>(find.byKey(const Key('raster-to-jpg'))).selected, isTrue);
    expect(find.byKey(const Key('raster-quality')), findsOneWidget);
    expect(tester.getSize(find.byKey(const Key('raster-run'))).height, greaterThanOrEqualTo(44));

    await tester.tap(find.byKey(const Key('raster-run')));
    await tester.pumpAndSettle();
    expect(files.written.keys, <String>['/out/scan_p1.jpg', '/out/scan_p2.jpg']);
    expect(find.text('2 pictures saved as JPG'), findsOneWidget);

    await tester.tap(find.byKey(const Key('raster-to-png')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('raster-quality')), findsNothing);

    await tester.tap(find.byKey(const Key('result-undo')));
    await tester.pumpAndSettle();
    expect(files.written, isEmpty);
  });
}
