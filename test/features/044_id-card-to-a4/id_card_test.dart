import 'dart:convert';
import 'dart:typed_data';

import 'package:family_utility_app/app/theme.dart';
import 'package:family_utility_app/engines/image/id_card_page.dart';
import 'package:family_utility_app/tools/id_card/id_card_screen.dart';
import 'package:family_utility_app/tools/images_to_pdf/images_to_pdf_screen.dart' show PickedImage;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// A pale yellow card lying on a dark table.
Uint8List cardPhoto(int w, int h, int cx, int cy, int cw, int ch) {
  final img.Image im = img.Image(width: w, height: h);
  img.fill(im, color: img.ColorRgb8(30, 30, 35));
  img.fillRect(im, x1: cx, y1: cy, x2: cx + cw - 1, y2: cy + ch - 1, color: img.ColorRgb8(240, 220, 150));
  return img.encodeJpg(im, quality: 95);
}

bool yellow(img.Pixel p) => p.r > 200 && p.g > 180 && p.b < 200;

class FakeIo implements IdCardIo {
  FakeIo(this.front, this.back);
  final PickedImage front;
  final PickedImage back;
  int picks = 0;
  final Map<String, Uint8List> written = <String, Uint8List>{};

  @override
  Future<PickedImage?> pickImage() async => picks++ == 0 ? front : back;

  @override
  Future<PickedImage?> takePhoto() async => back;

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
  final Uint8List front = cardPhoto(800, 600, 150, 140, 500, 316);
  // The back photographed upright: a portrait card.
  final Uint8List back = cardPhoto(600, 800, 140, 150, 316, 500);
  const IdCardEngine engine = IdCardEngine();

  test('card size is ID-1 at 300 dpi; A4 and Letter pages', () {
    expect((engine.cardWidthPx, engine.cardHeightPx), (1011, 638));
    expect((IdPaper.a4.widthPx, IdPaper.a4.heightPx), (2480, 3508));
    expect((IdPaper.letter.widthPx, IdPaper.letter.heightPx), (2550, 3300));
  });

  test('each side is found, flattened and turned landscape', () {
    final IdCardSide f = engine.side(front);
    expect(f.foundEdges, isTrue);
    expect(f.turned, isFalse);
    expect((f.image.width, f.image.height), (1011, 638));
    final IdCardSide b = engine.side(back);
    expect(b.foundEdges, isTrue);
    expect(b.turned, isTrue);
    expect((b.image.width, b.image.height), (1011, 638));
    // The dark table is cut away: the corners of the result are card.
    for (final img.Image im in <img.Image>[f.image, b.image]) {
      for (final (int x, int y) in <(int, int)>[(25, 25), (985, 25), (25, 612), (985, 612)]) {
        expect(yellow(im.getPixel(x, y)), isTrue, reason: 'card at ($x, $y)');
      }
    }
  });

  test('front above back at actual size on A4, as JPG and PDF', () {
    final IdCardPage p = engine.build(front, back, IdPaper.a4);
    expect((p.page.width, p.page.height), (2480, 3508));
    final (int fx, int fy, int fw, int fh) = p.frontRect;
    final (int bx, int by, int bw, int bh) = p.backRect!;
    expect((fw, fh), (1011, 638));
    expect((bw, bh), (1011, 638));
    expect(fx, bx, reason: 'aligned one above the other');
    expect(by, greaterThan(fy + fh));
    expect(fx, (2480 - 1011) ~/ 2, reason: 'centred');
    for (final (int x, int y, int w, int h) in <(int, int, int, int)>[p.frontRect, p.backRect!]) {
      expect(yellow(p.page.getPixel(x + w ~/ 2, y + h ~/ 2)), isTrue);
      expect(yellow(p.page.getPixel(x + 25, y + 25)), isTrue);
      expect(yellow(p.page.getPixel(x + w - 26, y + h - 26)), isTrue);
    }
    final img.Pixel corner = p.page.getPixel(50, 50);
    expect((corner.r, corner.g, corner.b), (255, 255, 255));

    final img.Image? jpg = img.decodeJpg(p.jpg);
    expect((jpg!.width, jpg.height), (2480, 3508));
    final String pdf = latin1.decode(p.pdf);
    expect(pdf.startsWith('%PDF-'), isTrue);
    // Page box is A4 in points and the image fills it edge to edge: actual size.
    expect(pdf, contains('/MediaBox [0 0 595.28 841.89]'));
    expect(pdf, contains('/Width 2480 /Height 3508'));
    expect(pdf.trimRight().endsWith('%%EOF'), isTrue);
  });

  test('Letter, and front only', () {
    final IdCardPage p = engine.build(front, null, IdPaper.letter);
    expect((p.page.width, p.page.height), (2550, 3300));
    expect(p.backRect, isNull);
    expect(latin1.decode(p.pdf), contains('/MediaBox [0 0 612.00 792.00]'));
  });

  testWidgets('add front and back, make the page, undo', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final FakeIo io = FakeIo(
      PickedImage(name: 'front.jpg', bytes: front),
      PickedImage(name: 'back.jpg', bytes: back),
    );
    await tester.pumpWidget(MaterialApp(theme: buildAppTheme(), home: IdCardScreen(io: io)));
    expect(tester.getSize(find.byKey(const Key('id-front-pick'))).height, greaterThanOrEqualTo(44));
    expect(find.byWidgetPredicate((Widget w) => w is Icon && w.semanticLabel == 'Front of the card not added'),
        findsOneWidget);
    await tester.tap(find.byKey(const Key('id-front-pick')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('id-back-pick')));
    await tester.pumpAndSettle();
    expect(find.text('Front of the card: front.jpg'), findsOneWidget);
    expect(find.text('Back of the card (optional): back.jpg'), findsOneWidget);

    await tester.tap(find.byKey(const Key('id-make')));
    await tester.pumpAndSettle();
    expect(io.written.keys, unorderedEquals(<String>['/out/id-card-a4.pdf', '/out/id-card-a4.jpg']));
    expect(find.byKey(const Key('id-preview')), findsOneWidget);
    expect(find.textContaining('Saved as PDF and JPG at actual size on A4'), findsOneWidget);

    await tester.tap(find.byKey(const Key('result-undo')));
    await tester.pumpAndSettle();
    expect(io.written, isEmpty);
  });
}
