import 'dart:typed_data';

import 'package:family_utility_app/engines/platform/one_search.dart';
import 'package:family_utility_app/engines/records/expense_tracker.dart';
import 'package:family_utility_app/engines/records/receipt_vault.dart';
import 'package:family_utility_app/engines/records/reports_vault.dart';
import 'package:family_utility_app/records/receipts/receipt_vault_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeReader implements ReportTextReader {
  FakeReader(this.text);
  final String text;
  @override
  Future<String> read(Uint8List image) async => text;
}

const String croma = 'TAX INVOICE\nCroma Electronics\nAndheri West\n12/08/2026\nSamsung 43in LED TV 1 31,990.00\nSub total 31,990.00\nGrand Total Rs 32,490.00\n';

void main() {
  group('engine', () {
    test('OCR guess: shop, total, date', () {
      final ReceiptGuess g = ReceiptVault.guess(croma);
      expect(g.shop, 'Croma Electronics');
      expect(g.paise, 3249000);
      expect(g.date, DateTime(2026, 8, 12));
      expect(ReceiptVault.guess('').paise, isNull);
    });

    test('full-text search, expense link, warranty, undo, store', () async {
      final MemoryReceiptStore store = MemoryReceiptStore();
      final ExpenseTracker expenses = ExpenseTracker(now: () => DateTime(2026, 8, 20));
      final ReceiptVault v = ReceiptVault(store: store, reader: FakeReader(croma), expenses: expenses, now: () => DateTime(2026, 8, 20));
      final (String, ReceiptGuess) read = await v.read(Uint8List(0));
      final Receipt tv = v.add(shop: read.$2.shop, paise: read.$2.paise, date: read.$2.date, photo: '/app/receipts/tv.jpg', text: read.$1, tags: <String>['tv', ' TV ', 'home'])!;
      expect(tv.tags, <String>['tv', 'home']);
      final Receipt milk = v.add(shop: 'Nandini Milk', paise: 4500, date: DateTime(2026, 8, 19))!;
      expect(v.add(shop: ' '), isNull);

      expect(v.search('samsung').single.id, tv.id); // OCR text
      expect(v.search('croma').single.id, tv.id); // shop
      expect(v.search('32490').single.id, tv.id); // amount
      expect(v.search('45').single.id, milk.id);
      expect(v.search('home').single.id, tv.id); // tag
      expect(v.search('').length, 2);

      final Expense e = v.fileAsExpense(tv.id)!;
      expect(e.paise, 3249000);
      expect(e.photo, '/app/receipts/tv.jpg');
      expect(v.byId(tv.id)!.expenseId, e.id);
      expect(v.fileAsExpense(tv.id), isNull); // once only

      expect(v.setWarranty(tv.id, 24, product: 'Samsung TV'), isTrue);
      expect(v.byId(tv.id)!.warrantyEnds, DateTime(2028, 8, 12));
      expect(v.underWarranty.single.id, tv.id);
      expect(v.search('warranty'), isEmpty);
      expect(v.toText(v.all), contains('warranty (Samsung TV) till 12 Aug 2028'));
      expect(v.undo(), isTrue);
      expect(v.byId(tv.id)!.warrantyEnds, isNull);

      final List<SearchDoc> docs = await v.collect();
      expect(docs.single.ref, '/app/receipts/tv.jpg');

      await Future<void>.delayed(Duration.zero);
      final ReceiptVault again = ReceiptVault(store: store);
      await again.load();
      expect(again.all.length, 2);
      expect(again.byId(tv.id)!.text, contains('Samsung'));
    });
  });

  testWidgets('screen: add receipt with OCR guess, search, file as expense, warranty, undo; 44 px', (WidgetTester tester) async {
    final SemanticsHandle sem = tester.ensureSemantics();
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final ExpenseTracker expenses = ExpenseTracker();
    final ReceiptVault v = ReceiptVault(reader: FakeReader(croma), expenses: expenses, now: () => DateTime(2026, 8, 20));
    final List<String> shared = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: ReceiptVaultScreen(
        vault: v,
        capture: () async => (path: '/app/receipts/tv.jpg', bytes: Uint8List(0)),
        share: (String t) async => shared.add(t),
        save: (String t, String n) async => '/x/$n',
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('rc-add')));
    await tester.pumpAndSettle();
    expect(find.text('Croma Electronics'), findsOneWidget);
    expect(find.text('32490'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('rc-tags')), 'tv');
    await tester.tap(find.byKey(const Key('rc-save')));
    await tester.pumpAndSettle();
    final Receipt r = v.all.single;
    expect(find.text('12 Aug 2026 · ₹32,490'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('rc-search')), 'samsung');
    await tester.pumpAndSettle();
    expect(find.byKey(Key('rc-${r.id}')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('rc-search')), 'pizza');
    await tester.pumpAndSettle();
    expect(find.text('No receipts match.'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('rc-search')), '');
    await tester.pumpAndSettle();

    expect(tester.getSize(find.byKey(Key('rc-expense-${r.id}'))).height, greaterThanOrEqualTo(44));
    await tester.tap(find.byKey(Key('rc-expense-${r.id}')));
    await tester.pumpAndSettle();
    expect(expenses.all.single.paise, 3249000);
    expect(find.text('Filed as an expense'), findsOneWidget);

    await tester.tap(find.byKey(Key('rc-warranty-${r.id}')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('rc-product')), 'TV');
    await tester.enterText(find.byKey(const Key('rc-months')), '12');
    await tester.tap(find.byKey(const Key('rc-warranty-save')));
    await tester.pumpAndSettle();
    expect(find.text('Warranty (TV) till 12 Aug 2027'), findsOneWidget);

    await tester.tap(find.byKey(const Key('result-share')));
    await tester.pumpAndSettle();
    expect(shared.last, contains('Croma Electronics · ₹32,490 · tv'));

    await tester.tap(find.byKey(const Key('result-undo')));
    await tester.pumpAndSettle();
    expect(find.text('Warranty (TV) till 12 Aug 2027'), findsNothing);
    await tester.pumpAndSettle(const Duration(seconds: 5));
    sem.dispose();
  });
}
