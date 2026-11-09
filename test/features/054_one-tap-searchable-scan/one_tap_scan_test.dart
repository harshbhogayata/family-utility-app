import 'dart:convert';
import 'dart:typed_data';

import 'package:family_utility_app/app/theme.dart';
import 'package:family_utility_app/engines/image/document_scanner.dart';
import 'package:family_utility_app/engines/image/one_tap_scan.dart';
import 'package:family_utility_app/engines/image/scan_namer.dart';
import 'package:family_utility_app/engines/pdf/pdf_compressor.dart';
import 'package:family_utility_app/engines/pdf/pdf_ocr.dart';
import 'package:family_utility_app/engines/pdf/pdf_text_search.dart';
import 'package:family_utility_app/tools/document_scanner/document_scanner_screen.dart';
import 'package:family_utility_app/tools/document_scanner/scan_camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// A big noisy "photo" so compression has something to squeeze.
Uint8List photoJpg({int w = 1500, int h = 2100}) {
  final img.Image im = img.Image(width: w, height: h);
  for (final img.Pixel p in im) {
    final int v = ((p.x * 7 + p.y * 13) ^ (p.x * p.y)) & 0xFF;
    p
      ..r = v
      ..g = 255 - v
      ..b = (v * 3) & 0xFF;
  }
  return img.encodeJpg(im, quality: 95);
}

Uint8List smallJpg() {
  final img.Image im = img.Image(width: 120, height: 160);
  img.fill(im, color: img.ColorRgb8(240, 240, 240));
  return img.encodeJpg(im, quality: 80);
}

class FakeRecognizer implements TextRecognizerEngine {
  int calls = 0;
  bool fail = false;

  @override
  Future<List<OcrWord>> recognize(img.Image page, Uint8List jpeg, OcrScript script) async {
    calls++;
    if (fail) {
      throw StateError('model missing');
    }
    return const <OcrWord>[
      OcrWord('RENT', left: 10, top: 10, right: 50, bottom: 22),
      OcrWord('RECEIPT', left: 56, top: 10, right: 120, bottom: 22),
      OcrWord('01/10/2026', left: 10, top: 40, right: 90, bottom: 52),
    ];
  }
}

class FakeCamera implements ScanCamera {
  @override
  Future<bool> start(void Function(ScanFrame frame) cb) async => true;

  @override
  Widget preview(BuildContext context) => const ColoredBox(color: Colors.black);

  @override
  Future<Uint8List> takePicture() async => Uint8List.fromList(<int>[1]);

  @override
  Future<void> dispose() async {}
}

class FakeIo implements ScanIo {
  final Map<String, Uint8List> written = <String, Uint8List>{};

  @override
  Future<String> write(String name, String extension, Uint8List bytes) async {
    final String p = '/scans/$name.$extension';
    written[p] = bytes;
    return p;
  }

  @override
  Future<void> remove(String path) async => written.remove(path);
}

OneTapScan pipeline(FakeRecognizer rec) => OneTapScan(
      recognizer: rec,
      namer: ScanAutoNamer(recognizer: rec, store: MemoryScanNamePatternStore()),
    );

void main() {
  final DateTime now = DateTime(2026, 11, 9, 9, 5);

  test('reads, compresses and names in one run', () async {
    final FakeRecognizer rec = FakeRecognizer();
    final Uint8List photo = photoJpg();
    final List<String> steps = <String>[];
    final OneTapResult r = await pipeline(rec).run(
      <ScanPage>[ScanPage(jpeg: photo, width: 1500, height: 2100, foundEdges: true)],
      now,
      progress: steps.add,
    );
    expect(rec.calls, 1);
    expect(r.name, '2026-10-01 RENT RECEIPT');
    expect(r.wordCount, 3);
    expect(r.pageTexts.single, contains('RENT RECEIPT'));
    // Compressed to the Medium preset: smaller than the page as written.
    expect(r.pdf.length, lessThan(r.uncompressedBytes));
    expect(latin1.decode(r.pdf.sublist(0, 5)), '%PDF-');
    expect(steps.first, 'Reading page 1 of 1…');
    expect(steps, containsAll(<String>['Compressing…', 'Naming…']));
    expect(PdfPreset.medium.maxSide, lessThan(2100));
  });

  test('a page OCR cannot read is kept as an image with the default name', () async {
    final FakeRecognizer rec = FakeRecognizer()..fail = true;
    final OneTapResult r = await pipeline(rec).run(
      <ScanPage>[ScanPage(jpeg: smallJpg(), width: 120, height: 160, foundEdges: true)],
      now,
    );
    expect(r.wordCount, 0);
    expect(r.name, '2026-11-09 Scan');
    expect(latin1.decode(r.pdf), contains('/Subtype /Image'));
    await expectLater(pipeline(rec).run(const <ScanPage>[], now), throwsA(isA<PdfOcrError>()));
  });

  testWidgets('one button scans to a named, searchable PDF', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2200);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    final SemanticsHandle handle = tester.ensureSemantics();
    final FakeIo io = FakeIo();
    final PdfLibraryIndex index = PdfLibraryIndex(MemoryPdfIndexBackend());
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: DocumentScannerScreen(
        camera: FakeCamera(),
        io: io,
        process: (Uint8List photo) async => ScanPage(jpeg: smallJpg(), width: 120, height: 160, foundEdges: true),
        now: () => now,
        oneTap: pipeline(FakeRecognizer()),
        index: index,
      ),
    ));
    await tester.pump();
    await tester.tap(find.byKey(const Key('scan-shutter')));
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('scan-review')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('scan-one-tap')));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byKey(const Key('scan-one-tap'))).height, greaterThanOrEqualTo(44));
    expect(find.bySemanticsLabel(RegExp('One tap: searchable PDF')), findsWidgets);

    await tester.tap(find.byKey(const Key('scan-one-tap')));
    await tester.pumpAndSettle();
    expect(io.written.keys.single, '/scans/2026-10-01 RENT RECEIPT.pdf');
    expect(index.search('receipt').hits.single.path, '/scans/2026-10-01 RENT RECEIPT.pdf');
    handle.dispose();
  });
}
