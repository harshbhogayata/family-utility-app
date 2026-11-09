import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:family_utility_app/app/theme.dart';
import 'package:family_utility_app/engines/pdf/pdf_compressor.dart';
import 'package:family_utility_app/engines/pdf/pdf_signer.dart';
import 'package:family_utility_app/engines/pdf/signature_library.dart';
import 'package:family_utility_app/engines/share/share_engine.dart';
import 'package:family_utility_app/tools/sign_pdf/sign_pdf_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

Uint8List buildPdf(List<String> bodies) {
  final BytesBuilder b = BytesBuilder();
  b.add(latin1.encode('%PDF-1.4\n'));
  for (int i = 0; i < bodies.length; i++) {
    b.add(latin1.encode('${i + 1} 0 obj\n${bodies[i]}\nendobj\n'));
  }
  b.add(latin1.encode('trailer\n<< /Size ${bodies.length + 1} /Root 1 0 R >>\n%%EOF\n'));
  return b.toBytes();
}

String stream(String data) => '<< /Length ${data.length} >>\nstream\n$data\nendstream';

/// Two pages; the size is inherited from the page tree; shared resources.
Uint8List twoPagePdf() => buildPdf(<String>[
      '<< /Type /Catalog /Pages 2 0 R >>',
      '<< /Type /Pages /Kids [3 0 R 4 0 R] /Count 2 /MediaBox [0 0 600 800] >>',
      '<< /Type /Page /Parent 2 0 R /Contents 5 0 R /Resources 6 0 R >>',
      '<< /Type /Page /Parent 2 0 R /Contents 5 0 R /Resources 6 0 R >>',
      stream('BT /F1 12 Tf (Lease) Tj ET'),
      '<< /Font << >> >>',
    ]);

Uint8List stampPng(int w, int h) {
  final img.Image im = img.Image(width: w, height: h, numChannels: 4);
  img.fillRect(im, x1: 2, y1: 2, x2: w - 3, y2: h - 3, color: img.ColorRgba8(10, 20, 80, 255));
  return img.encodePng(im);
}

class FakeFiles implements SignFiles {
  final Uint8List pdf = twoPagePdf();
  final Map<String, Uint8List> written = <String, Uint8List>{};

  @override
  Future<String?> pickPdf() async => '/docs/lease.pdf';

  @override
  Future<String?> pickImage() async => '/pics/sig.jpg';

  @override
  Future<Uint8List> read(String path) async {
    if (path.endsWith('.pdf')) {
      return pdf;
    }
    final img.Image im = img.Image(width: 80, height: 30);
    img.fill(im, color: img.ColorRgb8(255, 255, 255));
    img.drawLine(im, x1: 10, y1: 15, x2: 70, y2: 15, color: img.ColorRgb8(0, 0, 0), thickness: 3);
    return img.encodeJpg(im, quality: 95);
  }

  @override
  Future<String> write(String name, Uint8List bytes) async {
    written['/signed/$name'] = bytes;
    return '/signed/$name';
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

PdfDict pageDict(PdfDocumentModel doc, int index) {
  final PdfDict root = doc.resolve(doc.trailer['Root'])! as PdfDict;
  final PdfDict pages = doc.resolve(root['Pages'])! as PdfDict;
  final PdfArray kids = pages['Kids']! as PdfArray;
  return doc.resolve(kids.items[index])! as PdfDict;
}

String streamText(PdfDocumentModel doc, Object ref) => latin1.decode(doc.objects[(ref as PdfRef).num]!.stream!);

void main() {
  group('PdfSigner', () {
    test('reads inherited page sizes', () {
      final List<PageBox> pages = PdfSigner.pages(twoPagePdf());
      expect(pages, hasLength(2));
      expect(pages[1].width, 600);
      expect(pages[1].height, 800);
      expect(() => PdfSigner.pages(Uint8List.fromList(<int>[1, 2, 3])), throwsA(isA<SignError>()));
    });

    test('matrix puts the image where it was placed, and rotates it', () {
      const PageBox box = PageBox(0, 0, 600, 800);
      final Placement p = Placement(page: 0, png: stampPng(10, 5), left: 0.1, top: 0.25, width: 0.5, height: 0.1);
      final List<double> m = PdfSigner.matrix(p, box);
      expect(m[0], closeTo(300, 1e-9));
      expect(m[1], closeTo(0, 1e-9));
      expect(m[2], closeTo(0, 1e-9));
      expect(m[3], closeTo(80, 1e-9));
      expect(m[4], closeTo(60, 1e-9));
      expect(m[5], closeTo(800 - 200 - 80, 1e-9));
      final List<double> r = PdfSigner.matrix(p.copyWith(rotation: 90), box);
      expect(r[0], closeTo(0, 1e-9));
      expect(r[1], closeTo(-300, 1e-9), reason: 'clockwise on the page');
      // The centre stays put.
      expect(r[4] + (r[0] + r[2]) / 2, closeTo(m[4] + (m[0] + m[2]) / 2, 1e-9));
      expect(r[5] + (r[1] + r[3]) / 2, closeTo(m[5] + (m[1] + m[3]) / 2, 1e-9));
    });

    test('signs page 2 flat: image in the content, no annotations, page 1 untouched', () {
      final Uint8List out = PdfSigner.sign(twoPagePdf(), <Placement>[
        Placement(page: 1, png: stampPng(40, 12), left: 0.5, top: 0.8, width: 0.3, height: 0.09),
      ]);
      final PdfDocumentModel doc = PdfDocumentModel.parse(out);
      expect(doc.pageCount(), 2);
      final PdfDict p1 = pageDict(doc, 0);
      final PdfDict p2 = pageDict(doc, 1);
      expect(p1['Contents'], isA<PdfRef>());
      expect(p2['Annots'], isNull);
      final PdfArray contents = p2['Contents']! as PdfArray;
      expect(contents.items, hasLength(3));
      expect(streamText(doc, contents.items.first).trim(), 'q');
      final String stamp = streamText(doc, contents.items.last);
      expect(stamp, contains('cm /FuaSig1 Do'));
      final PdfDict res = p2['Resources']! as PdfDict;
      final PdfDict xo = res['XObject']! as PdfDict;
      final PdfDict image = doc.resolve(xo['FuaSig1'])! as PdfDict;
      expect(image.name('Subtype'), 'Image');
      expect(image.integer('Width'), 40);
      expect(image['SMask'], isA<PdfRef>(), reason: 'transparency kept');
      // Page 1 still uses the original shared resources without the stamp.
      final PdfDict r1 = doc.resolve(p1['Resources'])! as PdfDict;
      expect(r1['XObject'], isNull);
      expect(() => PdfSigner.sign(twoPagePdf(), const <Placement>[]), throwsA(isA<SignError>()));
    });

    test('drawn strokes become a trimmed transparent PNG; imports lose white', () {
      final Uint8List png = SignatureArt.fromStrokes(<List<StrokePoint>>[
        const <StrokePoint>[StrokePoint(0.2, 0.5), StrokePoint(0.5, 0.4), StrokePoint(0.8, 0.6)],
      ]);
      final img.Image d = img.decodePng(png)!;
      expect(d.width, lessThan(SignatureArt.padWidth));
      expect(d.getPixel(0, 0).a, 0);
      expect(() => SignatureArt.fromStrokes(<List<StrokePoint>>[]), throwsA(isA<SignError>()));

      final img.Image white = img.Image(width: 50, height: 20);
      img.fill(white, color: img.ColorRgb8(255, 255, 255));
      img.fillRect(white, x1: 10, y1: 8, x2: 40, y2: 11, color: img.ColorRgb8(0, 0, 0));
      final img.Image imported = img.decodePng(SignatureArt.fromImport(img.encodePng(white)))!;
      expect(imported.getPixel(0, 0).a, 0);
      expect(imported.width, lessThan(50));
    });

    test('library keeps signatures; no network code', () async {
      final MemorySignatureLibrary lib = MemorySignatureLibrary();
      final SavedStamp s = await lib.add(StampKind.initials, stampPng(4, 4));
      expect((await lib.list()).single.kind, StampKind.initials);
      await lib.remove(s.id);
      expect(await lib.list(), isEmpty);
      for (final String f in <String>[
        'lib/engines/pdf/pdf_signer.dart',
        'lib/engines/pdf/signature_library.dart',
        'lib/tools/sign_pdf/sign_pdf_screen.dart',
      ]) {
        final String src = File(f).readAsStringSync();
        expect(src.contains('HttpClient'), isFalse, reason: f);
        expect(src.contains('Socket'), isFalse, reason: f);
      }
    });
  });

  group('screen', () {
    testWidgets('type, draw, import, initials, date; move, resize, rotate; Save / Share / Undo',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final FakeFiles files = FakeFiles();
      final FakeSheet sheet = FakeSheet();
      final MemorySignatureLibrary lib = MemorySignatureLibrary();
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: SignPdfScreen(
          files: files,
          library: lib,
          renderText: (String text, {required bool script}) async => stampPng(text.length * 10 + 10, 20),
          runner: (Uint8List pdf, List<Placement> p) async => PdfSigner.sign(pdf, p),
          pageView: (BuildContext context, String path, int page) => Container(key: Key('page-$page')),
          share: ShareEngine(sheet, MemoryShareTargetStore()),
          today: () => DateTime(2026, 11, 9),
        ),
      ));

      await tester.tap(find.byKey(const Key('sign-pick')));
      await tester.pumpAndSettle();
      expect(find.text('Page 1 of 2'), findsOneWidget);
      expect(find.byKey(const Key('page-1')), findsOneWidget);

      // Type a signature: saved to the library and placed.
      await tester.tap(find.byKey(const Key('sign-type')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('sign-type-field')), 'Asha Shah');
      await tester.tap(find.byKey(const Key('sign-type-done')));
      await tester.pumpAndSettle();
      expect(lib.items, hasLength(1));
      expect(find.byKey(const Key('sign-stamp-0')), findsOneWidget);

      // Move it, resize it, rotate it.
      final Offset before = tester.getTopLeft(find.byKey(const Key('sign-stamp-0')));
      await tester.drag(find.byKey(const Key('sign-stamp-0')), const Offset(-40, 60));
      await tester.pumpAndSettle();
      final Offset after = tester.getTopLeft(find.byKey(const Key('sign-stamp-0')));
      expect(after.dy, greaterThan(before.dy));
      final double wBefore = tester.getSize(find.byKey(const Key('sign-stamp-0'))).width;
      await tester.drag(find.byKey(const Key('sign-resize-0')), const Offset(-50, 0));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byKey(const Key('sign-stamp-0'))).width, lessThan(wBefore));
      await tester.drag(find.byKey(const Key('sign-rotate')), const Offset(200, 0));
      await tester.pumpAndSettle();
      expect(find.textContaining('Rotate 0°'), findsNothing);

      // Draw one on the pad.
      await tester.tap(find.byKey(const Key('sign-draw')));
      await tester.pumpAndSettle();
      await tester.drag(find.byKey(const Key('sign-pad')), const Offset(120, 20));
      await tester.tap(find.byKey(const Key('sign-pad-done')));
      await tester.pumpAndSettle();
      expect(lib.items, hasLength(2));

      // Import a PNG/JPG, initials, and a date on page 2.
      await tester.tap(find.byKey(const Key('sign-import')));
      await tester.pumpAndSettle();
      expect(lib.items, hasLength(3));
      await tester.tap(find.byKey(const Key('sign-next')));
      await tester.pumpAndSettle();
      expect(find.text('Page 2 of 2'), findsOneWidget);
      await tester.tap(find.byKey(const Key('sign-initials')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('sign-type-field')), 'AS');
      await tester.tap(find.byKey(const Key('sign-type-done')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('sign-date')));
      await tester.pumpAndSettle();
      expect(lib.items, hasLength(4), reason: 'dates are not kept in the library');

      // Reuse a saved signature.
      await tester.tap(find.byKey(Key('sign-saved-${lib.items.last.id}')));
      await tester.pumpAndSettle();

      for (final String key in <String>[
        'sign-pick', 'sign-prev', 'sign-next', 'sign-draw', 'sign-type', 'sign-import', 'sign-initials',
        'sign-date', 'result-save', 'result-share', 'result-undo',
      ]) {
        expect(tester.getSize(find.byKey(Key(key))).height, greaterThanOrEqualTo(44), reason: key);
      }

      expect(files.written, isEmpty, reason: 'nothing written before Save');
      await tester.tap(find.byKey(const Key('result-save')));
      await tester.pumpAndSettle();
      final Uint8List signed = files.written['/signed/lease-signed.pdf']!;
      final PdfDocumentModel doc = PdfDocumentModel.parse(signed);
      expect(streamText(doc, (pageDict(doc, 0)['Contents']! as PdfArray).items.last), contains('Do'));
      final String p2 = streamText(doc, (pageDict(doc, 1)['Contents']! as PdfArray).items.last);
      expect('Do Q'.allMatches(p2).length, 3);

      await tester.tap(find.byKey(const Key('result-share')));
      await tester.pumpAndSettle();
      expect(sheet.requests.single.files, hasLength(1));
      await tester.tap(find.byKey(const Key('result-undo')));
      await tester.pumpAndSettle();
      expect(files.written, isEmpty);
    });
  });
}
