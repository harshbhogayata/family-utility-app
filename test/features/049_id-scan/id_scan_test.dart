import 'dart:typed_data';

import 'package:family_utility_app/app/theme.dart';
import 'package:family_utility_app/engines/image/document_scanner.dart';
import 'package:family_utility_app/engines/image/id_card_page.dart';
import 'package:family_utility_app/engines/image/id_scan.dart';
import 'package:family_utility_app/tools/document_scanner/scan_camera.dart';
import 'package:family_utility_app/tools/id_card/id_card_screen.dart';
import 'package:family_utility_app/tools/id_scan/id_scan_screen.dart';
import 'package:family_utility_app/tools/images_to_pdf/images_to_pdf_screen.dart' show PickedImage;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// A card of [r, g, b] lying on a dark table.
Uint8List cardPhoto(int r, int g, int b) {
  final img.Image im = img.Image(width: 640, height: 480);
  img.fill(im, color: img.ColorRgb8(30, 30, 35));
  img.fillRect(im, x1: 120, y1: 110, x2: 519, y2: 362, color: img.ColorRgb8(r, g, b));
  return img.encodeJpg(im, quality: 95);
}

class FakeCamera implements ScanCamera {
  FakeCamera(this.shots);
  final List<Uint8List> shots;
  int taken = 0;
  bool disposed = false;

  @override
  Future<bool> start(void Function(ScanFrame frame) onFrame) async => true;

  @override
  Widget preview(BuildContext context) => const ColoredBox(color: Colors.grey);

  @override
  Future<Uint8List> takePicture() async => shots[taken++ % shots.length];

  @override
  Future<void> dispose() async => disposed = true;
}

class FakeIo implements IdCardIo {
  final Map<String, Uint8List> written = <String, Uint8List>{};

  @override
  Future<PickedImage?> pickImage() async => null;

  @override
  Future<PickedImage?> takePhoto() async => null;

  @override
  Future<String> write(String name, Uint8List bytes) async {
    final String p = '/out/$name';
    written[p] = bytes;
    return p;
  }

  @override
  Future<void> remove(String path) async => written.remove(path);
}

bool near(img.Pixel p, int r, int g, int b) => (p.r - r).abs() < 25 && (p.g - g).abs() < 25 && (p.b - b).abs() < 25;

void main() {
  final Uint8List front = cardPhoto(240, 220, 150); // pale yellow
  final Uint8List back = cardPhoto(170, 210, 240); // pale blue

  test('guided flow: front, back, review; retake keeps the other side', () {
    final IdScanFlow flow = IdScanFlow();
    expect(flow.step, IdScanStep.front);
    expect(() => flow.build(IdPaper.a4), throwsStateError);
    flow.capture(front);
    expect(flow.step, IdScanStep.back);
    flow.capture(back);
    expect(flow.step, IdScanStep.review);
    expect(() => flow.capture(front), throwsStateError);

    IdCardPage p = flow.build(IdPaper.a4);
    final (int fx, int fy, int fw, int fh) = p.frontRect;
    final (int bx, int by, int bw, int bh) = p.backRect!;
    expect(near(p.page.getPixel(fx + fw ~/ 2, fy + fh ~/ 2), 240, 220, 150), isTrue, reason: 'front on top');
    expect(near(p.page.getPixel(bx + bw ~/ 2, by + bh ~/ 2), 170, 210, 240), isTrue, reason: 'back below');
    expect(fx, bx);

    // Retake the front with the blue card: back is kept, flow returns to review.
    flow.retake(IdScanStep.front);
    expect(flow.step, IdScanStep.front);
    flow.capture(back);
    expect(flow.step, IdScanStep.review);
    p = flow.build(IdPaper.letter);
    expect((p.page.width, p.page.height), (2550, 3300));
    expect(near(p.page.getPixel(fx + fw ~/ 2, fy + fh ~/ 2), 170, 210, 240), isTrue);
  });

  testWidgets('two shots, page ready to print, save PDF and JPG, undo', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final FakeCamera camera = FakeCamera(<Uint8List>[front, back]);
    final FakeIo io = FakeIo();
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: IdScanScreen(camera: camera, io: io, builder: buildDirect),
    ));
    await tester.pumpAndSettle();
    expect(find.text(IdScanStep.front.title), findsOneWidget);
    expect(find.byKey(const Key('ids-guide')), findsOneWidget);
    final Finder shutter = find.byKey(const Key('ids-shutter'));
    expect(tester.getSize(shutter).height, greaterThanOrEqualTo(44));
    expect(find.byWidgetPredicate((Widget w) => w is Icon && w.semanticLabel == 'Photograph the front'),
        findsOneWidget);

    await tester.tap(shutter);
    await tester.pumpAndSettle();
    expect(find.text(IdScanStep.back.title), findsOneWidget);
    expect(find.text('Front captured'), findsOneWidget);

    await tester.tap(find.byKey(const Key('ids-shutter')));
    await tester.pumpAndSettle();
    expect(find.text(IdScanStep.review.title), findsOneWidget);
    expect(find.byKey(const Key('ids-preview')), findsOneWidget);
    expect(find.textContaining('Both sides aligned at actual size on A4'), findsOneWidget);
    expect(camera.taken, 2);

    await tester.tap(find.byKey(const Key('result-save')));
    await tester.pumpAndSettle();
    expect(io.written.keys, unorderedEquals(<String>['/out/id-scan-a4.pdf', '/out/id-scan-a4.jpg']));
    expect(String.fromCharCodes(io.written['/out/id-scan-a4.pdf']!.sublist(0, 5)), '%PDF-');

    await tester.tap(find.byKey(const Key('result-undo')));
    await tester.pumpAndSettle();
    expect(io.written, isEmpty);

    // Retake the back from review.
    await tester.tap(find.byKey(const Key('ids-retake-back')));
    await tester.pumpAndSettle();
    expect(find.text(IdScanStep.back.title), findsOneWidget);
  });
}
