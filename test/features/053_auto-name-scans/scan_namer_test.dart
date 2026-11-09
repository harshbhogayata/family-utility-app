import 'dart:typed_data';

import 'package:family_utility_app/app/theme.dart';
import 'package:family_utility_app/engines/image/document_scanner.dart';
import 'package:family_utility_app/engines/image/scan_namer.dart';
import 'package:family_utility_app/engines/pdf/pdf_ocr.dart';
import 'package:family_utility_app/tools/document_scanner/document_scanner_screen.dart';
import 'package:family_utility_app/tools/document_scanner/scan_camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

Uint8List smallJpg() {
  final img.Image im = img.Image(width: 12, height: 16);
  img.fill(im, color: img.ColorRgb8(240, 240, 240));
  return img.encodeJpg(im, quality: 80);
}

class FakeRecognizer implements TextRecognizerEngine {
  FakeRecognizer(this.words);

  final List<OcrWord> words;
  int calls = 0;

  @override
  Future<List<OcrWord>> recognize(img.Image page, Uint8List jpeg, OcrScript script) async {
    calls++;
    return words;
  }
}

OcrWord w(String t, double left, double top) => OcrWord(t, left: left, top: top, right: left + t.length * 8, bottom: top + 12);

final List<OcrWord> invoice = <OcrWord>[
  w('Sharma', 10, 10),
  w('Electricals', 70, 10),
  w('TAX', 10, 40),
  w('INVOICE', 50, 40),
  w('Date:', 10, 70),
  w('14/03/2025', 60, 70),
  w('Total', 10, 100),
  w('1,250.00', 60, 100),
];

class FakeCamera implements ScanCamera {
  void Function(ScanFrame frame)? onFrame;

  @override
  Future<bool> start(void Function(ScanFrame frame) cb) async {
    onFrame = cb;
    return true;
  }

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

void main() {
  final DateTime now = DateTime(2026, 11, 9, 9, 5);

  group('dates', () {
    test('day-first numeric, ISO and written months', () {
      expect(findDate('Date: 14/03/2025'), DateTime(2025, 3, 14));
      expect(findDate('on 05-11-26'), DateTime(2026, 11, 5));
      expect(findDate('Issued 2024-12-31'), DateTime(2024, 12, 31));
      expect(findDate('Dated 3rd March 2025'), DateTime(2025, 3, 3));
      expect(findDate('September 9, 2024'), DateTime(2024, 9, 9));
      expect(findDate('31/02/2025 then 01/03/2025'), DateTime(2025, 3, 1));
      expect(findDate('Total 1,250.00'), isNull);
    });
  });

  group('titles', () {
    test('a capitalised line near the top beats the shop name and skips dates and numbers', () {
      expect(pickTitle('Sharma Electricals\nTAX INVOICE\nDate: 14/03/2025'), 'TAX INVOICE');
      expect(pickTitle('12345\n14/03/2025\nReport card'), 'Report card');
      expect(pickTitle('12 34\n'), isNull);
    });
  });

  group('pattern', () {
    test('fills title, date and time, and makes a safe file name', () {
      expect(fillScanName(defaultScanNamePattern, title: 'TAX INVOICE', date: DateTime(2025, 3, 14), now: now),
          '2025-03-14 TAX INVOICE');
      expect(fillScanName('{title} - {date} {time}', title: 'Fees: Term 2/3', now: now), 'Fees Term 2 3 - 2026-11-09 09.05');
      expect(fillScanName('{title}', now: now), 'Scan');
      expect(fillScanName('   ', now: now), 'Scan 2026-11-09');
    });

    test('the pattern is kept and an empty one falls back to the default', () async {
      final ScanAutoNamer n = ScanAutoNamer(recognizer: FakeRecognizer(invoice), store: MemoryScanNamePatternStore());
      expect(await n.pattern(), defaultScanNamePattern);
      await n.setPattern('{title} {date}');
      expect(await n.pattern(), '{title} {date}');
      final ScanNameSuggestion s = await n.suggest(smallJpg(), now);
      expect(s.name, 'TAX INVOICE 2025-03-14');
      expect(s.title, 'TAX INVOICE');
      await n.setPattern('  ');
      expect(await n.pattern(), defaultScanNamePattern);
    });
  });

  testWidgets('the scanner suggests the name, which can be edited before save', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2200);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    final FakeIo io = FakeIo();
    final MemoryScanNamePatternStore store = MemoryScanNamePatternStore();
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: DocumentScannerScreen(
        camera: FakeCamera(),
        io: io,
        process: (Uint8List photo) async => ScanPage(jpeg: smallJpg(), width: 12, height: 16, foundEdges: true),
        now: () => now,
        autoNamer: ScanAutoNamer(recognizer: FakeRecognizer(invoice), store: store),
      ),
    ));
    await tester.pump();
    await tester.tap(find.byKey(const Key('scan-shutter')));
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('scan-review')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('scan-make')));
    await tester.tap(find.byKey(const Key('scan-make')));
    await tester.pumpAndSettle();

    expect(find.text('Name this scan'), findsOneWidget);
    final TextField field = tester.widget<TextField>(find.byKey(const Key('scan-name-field')));
    expect(field.controller!.text, '2025-03-14 TAX INVOICE');
    expect(tester.getSize(find.byKey(const Key('scan-name-save'))).height, greaterThanOrEqualTo(44));

    // Changing the pattern refills the name; the person can still edit it.
    await tester.enterText(find.byKey(const Key('scan-name-pattern')), '{title}');
    await tester.pump();
    expect(field.controller!.text, 'TAX INVOICE');
    await tester.enterText(find.byKey(const Key('scan-name-field')), 'Sharma invoice March');
    await tester.tap(find.byKey(const Key('scan-name-save')));
    await tester.pumpAndSettle();
    expect(io.written.keys.single, '/scans/Sharma invoice March.pdf');
    expect(store.value, '{title}');
  });
}
