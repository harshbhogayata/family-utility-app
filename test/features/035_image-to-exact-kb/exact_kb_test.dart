import 'dart:typed_data';

import 'package:family_utility_app/app/theme.dart';
import 'package:family_utility_app/engines/image/exact_kb.dart';
import 'package:family_utility_app/tools/compress_images/compress_images_screen.dart';
import 'package:family_utility_app/tools/exact_kb/exact_kb_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// A busy photo-like picture: JPG size depends strongly on quality.
Uint8List noisy(int w, int h) {
  final img.Image im = img.Image(width: w, height: h);
  int seed = 7;
  for (final img.Pixel p in im) {
    seed = (seed * 1103515245 + 12345) & 0x7fffffff;
    p
      ..r = (p.x * 3 + (seed & 63)) & 255
      ..g = (p.y * 2 + ((seed >> 6) & 63)) & 255
      ..b = (seed >> 12) & 255;
  }
  return img.encodeJpg(im, quality: 98);
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
  final Uint8List photo = noisy(500, 400);

  test('fits under the limit by searching quality, then scale', () {
    final ExactKbResult r = ExactKb.fit(photo, 20);
    expect(r.fits, isTrue);
    expect(r.bytes.length, lessThanOrEqualTo(20 * 1024));
    expect(r.bytes.length, greaterThan(20 * 1024 * 0.8), reason: 'uses most of the allowance');
    expect(img.decodeJpg(r.bytes), isNotNull);

    final ExactKbResult big = ExactKb.fit(photo, 200);
    expect(big.fits, isTrue);
    expect((big.width, big.height), (500, 400), reason: 'no need to shrink for a generous limit');
  });

  test('a size lock in px or mm is kept; an impossible lock says so', () {
    final ExactKbResult r = ExactKb.fit(photo, 20, width: 200, height: 150);
    expect((r.width, r.height), (200, 150));
    expect(mmToPx(35), 413);
    expect(() => ExactKb.fit(noisy(1500, 1500), 1, width: 1500, height: 1500), throwsA(isA<ExactKbError>()));
  });

  testWidgets('pick, choose 50 KB, make it fit, see the tick, undo', (WidgetTester tester) async {
    final FakeFiles files = FakeFiles(<String, Uint8List>{'/a/photo.jpg': photo});
    await tester.pumpWidget(MaterialApp(theme: buildAppTheme(), home: ExactKbScreen(files: files)));
    await tester.tap(find.byKey(const Key('kb-pick')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('kb-20')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('kb-run')));
    expect(tester.getSize(find.byKey(const Key('kb-run'))).height, greaterThanOrEqualTo(44));
    await tester.tap(find.byKey(const Key('kb-run')));
    await tester.pumpAndSettle();
    expect(files.written.keys, <String>['/out/photo-20kb.jpg']);
    expect(files.written.values.single.length, lessThanOrEqualTo(20 * 1024));
    expect(find.text('Fits the limit', skipOffstage: false), findsOneWidget);

    await tester.tap(find.byKey(const Key('result-undo')));
    await tester.pumpAndSettle();
    expect(files.written, isEmpty);
  });
}
