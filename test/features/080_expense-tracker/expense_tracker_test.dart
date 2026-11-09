import 'package:family_utility_app/engines/records/expense_tracker.dart';
import 'package:family_utility_app/records/expenses/expense_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('engine', () {
    test('amounts parse and format in paise', () {
      expect(parsePaise('1,200.5'), 120050);
      expect(parsePaise('₹99'), 9900);
      expect(parsePaise('Rs 40.25'), 4025);
      expect(parsePaise('abc'), isNull);
      expect(formatPaise(12345678), '123,456.78');
      expect(formatPaise(50000), '500');
    });

    test('quick-add from text guesses the category', () {
      final ({int paise, String category, String note})? a = ExpenseTracker.parseQuick('450 groceries milk and eggs');
      expect(a!.paise, 45000);
      expect(a.category, 'Groceries');
      expect(a.note, 'groceries milk and eggs');
      expect(ExpenseTracker.parseQuick('petrol 500')!.category, 'Fuel');
      expect(ExpenseTracker.parseQuick('₹ 1,200 school fees')!.category, 'Education');
      expect(ExpenseTracker.parseQuick('random 30')!.category, ExpenseTracker.other);
      expect(ExpenseTracker.parseQuick('no amount here'), isNull);
    });

    test('month and category totals, CSV export, undo, saved and reloaded', () async {
      DateTime now = DateTime(2026, 3, 5, 10);
      final MemoryExpenseStore store = MemoryExpenseStore();
      final ExpenseTracker t = ExpenseTracker(store: store, now: () => now);
      t.add(paise: 45000, category: 'Groceries', note: 'milk, "fresh"');
      now = DateTime(2026, 3, 5, 11);
      t.add(paise: 20000, category: 'Fuel', photo: '/data/receipts/receipt_1.jpg');
      now = DateTime(2026, 3, 5, 12);
      t.quickAdd('150 vegetables');
      expect(t.add(paise: 0, category: 'Food'), isNull);
      now = DateTime(2026, 4, 1, 9);
      t.quickAdd('99 tea');

      expect(t.monthTotal(2026, 3), 80000);
      expect(t.monthTotal(2026, 4), 9900);
      final List<MapEntry<String, int>> cats = t.categoryTotals(2026, 3);
      expect(cats.first.key, 'Groceries');
      expect(cats.first.value, 60000);
      expect(cats.last.key, 'Fuel');

      final String csv = t.toCsv(year: 2026, month: 3);
      final List<String> lines = csv.trim().split('\r\n');
      expect(lines.first, 'Date,Amount,Category,Note,Receipt');
      expect(lines.length, 4);
      expect(lines[1], '2026-03-05,450.00,Groceries,"milk, ""fresh""",');
      expect(csv, contains('200.00,Fuel,,receipt_1.jpg'));
      expect(t.toCsv().trim().split('\r\n').length, 5);

      final String id = t.all.first.id;
      expect(t.remove(id), isTrue);
      expect(t.monthTotal(2026, 4), 0);
      expect(t.undo(), isTrue);
      expect(t.monthTotal(2026, 4), 9900);
      expect(t.undo(), isFalse);

      await Future<void>.delayed(Duration.zero);
      final ExpenseTracker again = ExpenseTracker(store: store);
      await again.load();
      expect(again.all.length, 4);
      expect(again.all.firstWhere((Expense e) => e.category == 'Fuel').photo, '/data/receipts/receipt_1.jpg');
    });
  });

  testWidgets('screen: quick-add, add with photo, totals, CSV share, undo; 44 px targets', (WidgetTester tester) async {
    final SemanticsHandle sem = tester.ensureSemantics();
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    DateTime clock() => DateTime(2026, 3, 5, 10);
    final ExpenseTracker t = ExpenseTracker(now: clock);
    String? shared;
    await tester.pumpWidget(MaterialApp(
      home: ExpenseScreen(
        tracker: t,
        now: clock,
        share: (String csv) async => shared = csv,
        save: (String csv, String name) async => '/x/$name',
        pickPhoto: () async => '/kept/receipt_9.jpg',
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('March 2026'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('expense-quick')), '450 groceries');
    await tester.tap(find.byKey(const Key('expense-quick-add')));
    await tester.pumpAndSettle();
    expect(t.monthTotal(2026, 3), 45000);
    expect(find.byKey(const Key('cat-Groceries')), findsOneWidget);

    await tester.tap(find.byKey(const Key('expense-add')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('expense-amount')), '120.50');
    await tester.enterText(find.byKey(const Key('expense-note')), 'Medicines');
    await tester.tap(find.byKey(const Key('expense-photo')));
    await tester.pumpAndSettle();
    expect(find.text('Photo added'), findsOneWidget);
    await tester.tap(find.byKey(const Key('expense-save')));
    await tester.pumpAndSettle();
    expect(t.monthTotal(2026, 3), 57050);
    expect(t.all.firstWhere((Expense e) => e.paise == 12050).photo, '/kept/receipt_9.jpg');
    expect(tester.widget<Text>(find.byKey(const Key('expense-total'))).data, '₹570.50');
    expect(find.bySemanticsLabel('Total this month ₹570.50'), findsOneWidget);

    expect(tester.getSize(find.byKey(const Key('expense-quick-add'))).height, greaterThanOrEqualTo(44));
    expect(tester.getSize(find.byKey(const Key('expense-prev'))).height, greaterThanOrEqualTo(44));

    await tester.tap(find.byKey(const Key('result-share')));
    await tester.pumpAndSettle();
    expect(shared, contains('2026-03-05,120.50,Groceries,Medicines,receipt_9.jpg'));

    await tester.tap(find.byKey(const Key('result-undo')));
    await tester.pumpAndSettle();
    expect(t.monthTotal(2026, 3), 45000);

    await tester.tap(find.byKey(const Key('expense-prev')));
    await tester.pumpAndSettle();
    expect(find.text('February 2026'), findsOneWidget);
    expect(find.text('No expenses this month.'), findsOneWidget);
    await tester.pumpAndSettle(const Duration(seconds: 5));
    sem.dispose();
  });
}
