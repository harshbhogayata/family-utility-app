import 'dart:convert';
import 'dart:typed_data';

import 'package:family_utility_app/app/theme.dart';
import 'package:family_utility_app/engines/image/webp_convert.dart';
import 'package:family_utility_app/tools/compress_images/compress_images_screen.dart';
import 'package:family_utility_app/tools/webp/webp_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// 4 × 4 lossless WebP: left half fully see-through, right half opaque red.
final Uint8List webp = base64Decode('UklGRh4AAABXRUJQVlA4TBEAAAAvA8AAEA8Q8x/zH4wyRPQ/AAA=');

/// Records the PNG it was given and returns a marker "WebP".
class FakeWebp implements WebpEncoder {
  Uint8List? lastPng;

  @override
  Future<Uint8List> encode(Uint8List png, {int quality = 90}) async {
    lastPng = png;
    return Uint8List.fromList(<int>[...ascii.encode('RIFF'), 0, 0, 0, 0, ...ascii.encode('WEBP')]);
  }
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
  final FakeWebp enc = FakeWebp();
  final WebpConverter c = WebpConverter(enc);

  test('WebP to PNG keeps transparency', () async {
    final WebpConverted r = await c.convert(webp, 'logo.webp', ImageTarget.png);
    expect(r.name, 'logo.png');
    expect(r.hadAlpha, isTrue);
    expect(r.keptAlpha, isTrue);
    final img.Image png = img.decodePng(r.bytes)!;
    expect(png.numChannels, 4);
    expect(png.getPixel(0, 0).a, 0);
    final img.Pixel red = png.getPixel(3, 0);
    expect((red.r, red.g, red.b, red.a), (255, 0, 0, 255));
  });

  test('WebP to JPG fills see-through parts with white', () async {
    final WebpConverted r = await c.convert(webp, 'logo.webp', ImageTarget.jpg);
    expect(r.name, 'logo.jpg');
    expect(r.keptAlpha, isFalse);
    final img.Image jpg = img.decodeJpg(r.bytes)!;
    expect(jpg.getPixel(0, 0).r, greaterThan(200));
    expect(jpg.getPixel(0, 0).b, greaterThan(200));
  });

  test('PNG back to WebP hands the encoder a PNG with alpha', () async {
    final Uint8List png = (await c.convert(webp, 'logo.webp', ImageTarget.png)).bytes;
    final WebpConverted r = await c.convert(png, 'logo.png', ImageTarget.webp);
    expect(r.name, 'logo.webp');
    expect(ascii.decode(r.bytes.sublist(8, 12)), 'WEBP');
    final img.Image given = img.decodePng(enc.lastPng!)!;
    expect(given.getPixel(0, 0).a, 0);
    expect(r.keptAlpha, isTrue);
    expect(WebpConverter.defaultTarget('a.WEBP'), ImageTarget.png);
    expect(WebpConverter.defaultTarget('a.jpg'), ImageTarget.webp);
  });

  testWidgets('pick a WebP, convert to PNG by default, undo', (WidgetTester tester) async {
    final FakeFiles files = FakeFiles(<String, Uint8List>{'/a/site.webp': webp});
    await tester.pumpWidget(MaterialApp(theme: buildAppTheme(), home: WebpScreen(files: files, encoder: FakeWebp())));
    await tester.tap(find.byKey(const Key('webp-pick')));
    await tester.pumpAndSettle();
    final ChoiceChip png = tester.widget<ChoiceChip>(find.byKey(const Key('webp-to-png')));
    expect(png.selected, isTrue);
    expect(tester.getSize(find.byKey(const Key('webp-run'))).height, greaterThanOrEqualTo(44));
    await tester.tap(find.byKey(const Key('webp-run')));
    await tester.pumpAndSettle();
    expect(files.written.keys, <String>['/out/site.png']);
    expect(find.text('1 picture saved as PNG'), findsOneWidget);

    await tester.tap(find.byKey(const Key('webp-to-jpg')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('webp-run')));
    await tester.pumpAndSettle();
    expect(find.textContaining('filled with white'), findsOneWidget);

    await tester.tap(find.byKey(const Key('result-undo')));
    await tester.pumpAndSettle();
    expect(files.written.keys, <String>['/out/site.png']);
  });
}
