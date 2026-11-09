import 'dart:convert';
import 'dart:typed_data';

import 'package:family_utility_app/app/theme.dart';
import 'package:family_utility_app/engines/convert/convert_registry.dart';
import 'package:family_utility_app/engines/pdf/images_to_pdf.dart';
import 'package:family_utility_app/tools/images_to_pdf/images_to_pdf_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

img.Image solid(int w, int h, int r) {
  final img.Image im = img.Image(width: w, height: h);
  img.fill(im, color: img.ColorRgb8(r, 80, 40));
  return im;
}

Uint8List jpg(int w, int h, [int r = 200]) => img.encodeJpg(solid(w, h, r), quality: 80);

class FakeHeic implements HeicDecoder {
  FakeHeic(this.result);
  final Uint8List? result;
  @override
  Future<Uint8List?> toJpeg(Uint8List heic) async => result;
}

final Uint8List heicBytes = Uint8List.fromList(<int>[0, 0, 0, 24, ...ascii.encode('ftypheic'), 0, 0, 0, 0, 0, 0, 0, 0]);

String pdfText(Uint8List b) => latin1.decode(b);

int countPages(Uint8List b) => RegExp(r'/Type /Page /').allMatches(pdfText(b)).length;

int indexOfBytes(Uint8List hay, Uint8List needle) {
  outer:
  for (int i = 0; i + needle.length <= hay.length; i++) {
    for (int j = 0; j < needle.length; j++) {
      if (hay[i + j] != needle[j]) {
        continue outer;
      }
    }
    return i;
  }
  return -1;
}

class FakeIo implements ImagesToPdfIo {
  final Map<String, Uint8List> written = <String, Uint8List>{};

  @override
  Future<List<PickedImage>> pickFromGallery() async => <PickedImage>[
        PickedImage(name: 'beach.jpg', bytes: jpg(40, 30)),
        PickedImage(name: 'card.png', bytes: img.encodePng(solid(20, 20, 10))),
        PickedImage(name: 'sticker.gif', bytes: img.encodeGif(solid(10, 10, 90))),
      ];

  @override
  Future<PickedImage?> takePhoto() async => PickedImage(name: 'camera.jpg', bytes: jpg(30, 40));

  @override
  Future<String> write(String name, Uint8List bytes) async {
    written['/pdf/$name.pdf'] = bytes;
    return '/pdf/$name.pdf';
  }

  @override
  Future<void> remove(String path) async => written.remove(path);
}

void main() {
  group('engine', () {
    test('JPEG size, components and EXIF orientation are read from the bytes', () {
      final Uint8List j = jpg(64, 48);
      final ({int width, int height, int components})? info = jpegInfo(j);
      expect(info!.width, 64);
      expect(info.height, 48);
      expect(info.components, 3);
      expect(jpegOrientation(j), 1);
    });

    test('one page per image, in order, JPEGs embedded untouched', () async {
      final Uint8List a = jpg(40, 30, 10);
      final Uint8List b = jpg(30, 40, 250);
      final Uint8List pdf = await ImagesToPdf().build(<Uint8List>[b, a], const ImagesToPdfOptions());
      expect(pdfText(pdf).startsWith('%PDF-1.4'), isTrue);
      expect(pdfText(pdf).trimRight().endsWith('%%EOF'), isTrue);
      expect(countPages(pdf), 2);
      final int ib = indexOfBytes(pdf, b);
      final int ia = indexOfBytes(pdf, a);
      expect(ib, greaterThan(0), reason: 'JPEG goes in as-is');
      expect(ia, greaterThan(ib), reason: 'pages follow the chosen order');
      expect(pdfText(pdf), contains('/Count 2'));
    });

    test('A4, Letter, fit-to-image, orientation and margins', () {
      (double, double) page(int w, int h, ImagesToPdfOptions o) => ImagesToPdf.pageFor(w, h, o);
      expect(page(300, 400, const ImagesToPdfOptions()), (595.28, 841.89));
      expect(page(400, 300, const ImagesToPdfOptions()), (841.89, 595.28), reason: 'auto turns wide photos');
      expect(page(400, 300, const ImagesToPdfOptions(orientation: PdfOrientation.portrait)), (595.28, 841.89));
      expect(page(300, 400, const ImagesToPdfOptions(pageSize: PdfPageSize.letter, orientation: PdfOrientation.landscape)),
          (792.0, 612.0));
      expect(page(400, 300, const ImagesToPdfOptions(pageSize: PdfPageSize.fit, marginPt: 10)), (320.0, 245.0));
    });

    test('the media box and image placement respect the margin', () async {
      final Uint8List pdf = await ImagesToPdf().build(
        <Uint8List>[jpg(100, 100)],
        const ImagesToPdfOptions(pageSize: PdfPageSize.letter, orientation: PdfOrientation.portrait, marginPt: 36),
      );
      final String t = pdfText(pdf);
      expect(t, contains('/MediaBox [0 0 612.00 792.00]'));
      // Square image in a 540 x 720 box: 540 wide, centred vertically.
      expect(t, contains('q 540.00 0 0 540.00 36.00 126.00 cm /Im0 Do Q'));
    });

    test('PNG, GIF and WebP-style decodable images are converted, alpha flattened', () async {
      final img.Image clear = img.Image(width: 8, height: 8, numChannels: 4);
      final Uint8List pdf = await ImagesToPdf().build(
        <Uint8List>[img.encodePng(clear), img.encodeGif(solid(6, 6, 30)), img.encodeBmp(solid(5, 7, 60))],
        const ImagesToPdfOptions(),
      );
      expect(countPages(pdf), 3);
      expect(pdfText(pdf), contains('/Filter /DCTDecode'));
    });

    test('HEIC goes through the phone decoder with no extra step', () async {
      final Uint8List decoded = jpg(12, 9);
      final Uint8List pdf = await ImagesToPdf(heic: FakeHeic(decoded)).build(<Uint8List>[heicBytes], const ImagesToPdfOptions());
      expect(countPages(pdf), 1);
      expect(indexOfBytes(pdf, decoded), greaterThan(0));
      await expectLater(
        ImagesToPdf(heic: FakeHeic(null)).build(<Uint8List>[heicBytes], const ImagesToPdfOptions()),
        throwsA(isA<ConvertException>()),
      );
    });

    test('20 photos in under 2 seconds', () async {
      final List<Uint8List> photos = <Uint8List>[for (int i = 0; i < 20; i++) jpg(1200, 900, i * 10)];
      final Stopwatch sw = Stopwatch()..start();
      final Uint8List pdf = await ImagesToPdf().build(photos, const ImagesToPdfOptions());
      sw.stop();
      expect(countPages(pdf), 20);
      expect(sw.elapsedMilliseconds, lessThan(2000));
    });

    test('not an image is refused plainly', () async {
      await expectLater(
        ImagesToPdf().build(<Uint8List>[Uint8List.fromList(utf8.encode('%PDF-1.4'))], const ImagesToPdfOptions()),
        throwsA(isA<ConvertException>()),
      );
    });
  });

  testWidgets('gallery and camera, remove one, make the PDF, undo', (WidgetTester tester) async {
    final FakeIo io = FakeIo();
    await tester.pumpWidget(MaterialApp(theme: buildAppTheme(), home: ImagesToPdfScreen(io: io)));
    await tester.tap(find.byKey(const Key('i2p-gallery')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('i2p-camera')));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byKey(const Key('i2p-camera'))).height, greaterThanOrEqualTo(44));
    await tester.scrollUntilVisible(find.byKey(const Key('i2p-make')), 200, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    expect(find.text('Make 4-page PDF'), findsOneWidget);

    await tester.ensureVisible(find.byTooltip('Remove sticker.gif'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Remove sticker.gif'));
    await tester.pumpAndSettle();
    expect(find.text('sticker.gif'), findsNothing);

    await tester.drag(find.byType(ListView).first, const Offset(0, 2000));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Letter'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.byKey(const Key('i2p-make')), 200, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('i2p-make')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(io.written.length, 1);
    final Uint8List pdf = io.written.values.single;
    expect(countPages(pdf), 3);
    expect(pdfText(pdf), contains('612.00'));

    await tester.drag(find.byType(ListView).first, const Offset(0, 2000));
    await tester.pumpAndSettle();
    expect(find.textContaining('3-page PDF in Files'), findsOneWidget);
    expect(find.byKey(const Key('result-share')), findsOneWidget);
    await tester.tap(find.byKey(const Key('result-undo')));
    await tester.pumpAndSettle();
    expect(io.written, isEmpty);
  });
}
