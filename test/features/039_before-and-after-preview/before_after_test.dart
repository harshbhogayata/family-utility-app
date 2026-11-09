import 'dart:typed_data';

import 'package:family_utility_app/app/theme.dart';
import 'package:family_utility_app/app/widgets/before_after_view.dart';
import 'package:family_utility_app/engines/image/before_after.dart';
import 'package:family_utility_app/engines/image/image_compressor.dart';
import 'package:family_utility_app/tools/compress_images/compress_images_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

Uint8List png(int w, int h, {int level = 0}) {
  final img.Image im = img.Image(width: w, height: h);
  img.fill(im, color: img.ColorRgb8(30, 140, 90));
  return img.encodePng(im, level: level);
}

class FakeFiles implements ImageFiles {
  FakeFiles(this.inputs);
  final Map<String, Uint8List> inputs;

  @override
  Future<List<String>> pick() async => inputs.keys.toList();

  @override
  Future<Uint8List> read(String path) async => inputs[path]!;

  @override
  Future<String> write(String name, Uint8List bytes) async => '/out/$name';

  @override
  Future<void> remove(String path) async {}
}

void main() {
  test('size saved and percentage', () {
    const SizeSaving s = SizeSaving(2 * 1024 * 1024, 700 * 1024);
    expect(s.saved, 2 * 1024 * 1024 - 700 * 1024);
    expect(s.percent, 66);
    expect(s.label, 'Saved 1.3 MB (66%)');
    expect(s.sizes, '2.0 MB → 700 KB');
    expect(const SizeSaving(1000, 1000).label, 'Same size');
    expect(const SizeSaving(1000, 1500).label, startsWith('Bigger by'));
    expect(const SizeSaving(0, 0).percent, 0);
  });

  test('divider stays inside the picture', () {
    expect(CompareLimits.clampSplit(-1), 0.02);
    expect(CompareLimits.clampSplit(2), 0.98);
    expect(CompareLimits.splitAt(150, 300), 0.5);
    expect(CompareLimits.splitAt(10, 0), 0.5);
    expect(CompareLimits.maxZoom, greaterThan(CompareLimits.minZoom));
  });

  testWidgets('slider and side-by-side, zoomable, sizes shown', (WidgetTester tester) async {
    final Uint8List before = png(40, 30);
    final Uint8List after = png(40, 30, level: 9);
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: BeforeAfterScreen(title: 'leaf.png', before: before, after: after),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Compare: leaf.png'), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(find.text(SizeSaving(before.length, after.length).label), findsOneWidget);
    expect(find.textContaining('%'), findsWidgets);

    await tester.drag(find.byKey(const Key('compare-split')), const Offset(-2000, 0));
    await tester.pumpAndSettle();
    expect(tester.widget<Slider>(find.byKey(const Key('compare-split'))).value, closeTo(0.02, 0.001));
    expect(tester.getSize(find.byKey(const Key('compare-handle'))).width, greaterThanOrEqualTo(44));
    expect(tester.getSize(find.byKey(const Key('compare-reset-zoom'))).height, greaterThanOrEqualTo(44));

    await tester.tap(find.text('Side by side'));
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsNWidgets(2));
    expect(find.byKey(const Key('compare-split')), findsNothing);
    expect(find.bySemanticsLabel('Before'), findsWidgets);
    expect(find.bySemanticsLabel('After'), findsWidgets);
  });

  testWidgets('compress images opens the comparison', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final Uint8List big = png(40, 30);
    final Uint8List small = png(40, 30, level: 9);
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: CompressImagesScreen(
        files: FakeFiles(<String, Uint8List>{'/p/leaf.png': big}),
        runner: (Uint8List b, CompressSettings s) async => CompressResult(
            bytes: small, format: OutputFormat.png, width: 40, height: 30, originalBytes: b.length),
        debounce: const Duration(milliseconds: 10),
      ),
    ));
    await tester.tap(find.byKey(const Key('compress-pick')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('compress-compare-leaf.png')));
    await tester.pumpAndSettle();
    expect(find.byType(BeforeAfterView), findsOneWidget);
    expect(find.text(SizeSaving(big.length, small.length).label), findsOneWidget);
  });
}
