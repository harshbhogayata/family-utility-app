import 'dart:typed_data';

import 'package:family_utility_app/engines/records/expense_tracker.dart';
import 'package:family_utility_app/engines/records/receipt_vault.dart';
import 'package:family_utility_app/engines/records/reports_vault.dart';
import 'package:family_utility_app/records/receipts/receipt_vault_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeReader implements ReportTextReader {
  FakeReader(this.text);
  final String text;
  int calls = 0;
  @override
  Future<String> read(Uint8List image) async {
    calls++;
    return text;
  }
}

const String bill = 'More Supermarket\nBill No 4471\nDate: 03-11-26\nToor dal 1kg 165.00\nTotal 1,248.50\n';

void main() {
  test('a scanned photo is read by OCR; a searchable PDF gives its own text', () async {
    final FakeReader reader = FakeReader(bill);
    final ReceiptVault v = ReceiptVault(
      reader: reader,
      expenses: ExpenseTracker(),
      loadFile: (String path) async => Uint8List.fromList(<int>[1, 2, 3]),
      pdfText: (String path) => path == '/scans/bill.pdf' ? 'DMart\nGrand Total 640.00\n02/11/2026' : '',
    );
    final (String, ReceiptGuess) photo = await v.readScan('/scans/bill.jpg');
    expect(reader.calls, 1);
    expect(photo.$2.shop, 'More Supermarket');
    expect(photo.$2.paise, 124850);
    expect(photo.$2.date, DateTime(2026, 11, 3));

    final (String, ReceiptGuess) pdf = await v.readScan('/scans/bill.pdf');
    expect(reader.calls, 1);
    expect(pdf.$2.shop, 'DMart');
    expect(pdf.$2.paise, 64000);
    expect(pdf.$2.date, DateTime(2026, 11, 2));

    final (String, ReceiptGuess) missing = await ReceiptVault(loadFile: (String p) async => throw StateError('gone')).readScan('/x.jpg');
    expect(missing.$2.paise, isNull);
  });

  testWidgets('scan a receipt, amount and date suggested, tagged to a shop, saved; 44 px', (WidgetTester tester) async {
    final SemanticsHandle sem = tester.ensureSemantics();
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final ReceiptVault v = ReceiptVault(
      reader: FakeReader(bill),
      expenses: ExpenseTracker(),
      loadFile: (String path) async => Uint8List(0),
      now: () => DateTime(2026, 11, 10),
    );
    await tester.pumpWidget(MaterialApp(
      home: ReceiptVaultScreen(vault: v, scan: () async => <String>['/scans/bill.jpg']),
    ));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Scan receipt'), findsOneWidget);
    expect(tester.getSize(find.byKey(const Key('rc-scan'))).height, greaterThanOrEqualTo(44));
    await tester.tap(find.byKey(const Key('rc-scan')));
    await tester.pumpAndSettle();
    expect(find.text('More Supermarket'), findsOneWidget);
    expect(find.text('1248.50'), findsOneWidget);
    expect(find.text('03/11/2026'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('rc-tags')), 'groceries');
    await tester.tap(find.byKey(const Key('rc-save')));
    await tester.pumpAndSettle();

    final Receipt r = v.all.single;
    expect(r.shop, 'More Supermarket');
    expect(r.paise, 124850);
    expect(r.date, DateTime(2026, 11, 3));
    expect(r.photo, '/scans/bill.jpg');
    expect(r.tags, <String>['groceries']);
    expect(v.search('dal').single.id, r.id);
    expect(find.text('3 Nov 2026 · ₹1,248.50'), findsOneWidget);
    await tester.pumpAndSettle(const Duration(seconds: 5));
    sem.dispose();
  });
}
