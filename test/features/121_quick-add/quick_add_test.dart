import 'package:family_utility_app/engines/records/expense_tracker.dart';
import 'package:family_utility_app/engines/records/quick_add.dart';
import 'package:family_utility_app/records/quick_add/quick_add_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Tuesday 10 November 2026, evening.
  DateTime clock() => DateTime(2026, 11, 10, 18, 30);
  final QuickAddParser p = QuickAddParser(now: clock);

  group('parser', () {
    test('English: amount, item, person and date', () {
      final QuickEntry a = p.parse('paid 350 milk')!;
      expect(a.paise, 35000);
      expect(a.item, 'milk');
      expect(a.category, 'Groceries');
      expect(a.person, isNull);
      expect(a.date, DateTime(2026, 11, 10));

      final QuickEntry b = p.parse('gave 500 to ramesh yesterday')!;
      expect(b.paise, 50000);
      expect(b.person, 'Ramesh');
      expect(b.date, DateTime(2026, 11, 9));
      expect(b.note, 'To Ramesh');

      final QuickEntry c = p.parse('paid ₹1,200.50 for Riya school fees on 5 march')!;
      expect(c.paise, 120050);
      expect(c.person, 'Riya');
      expect(c.item, 'school fees');
      expect(c.category, 'Education');
      expect(c.date, DateTime(2026, 3, 5));

      final QuickEntry d = p.parse('2k rent on 1/11')!;
      expect(d.paise, 200000);
      expect(d.category, 'Bills');
      expect(d.date, DateTime(2026, 11, 1));

      expect(p.parse('petrol 800 monday')!.date, DateTime(2026, 11, 9));
      expect(p.parse('lunch 250 on dec 25')!.date, DateTime(2025, 12, 25), reason: 'never in the future');
      expect(p.parse('350rs auto')!.category, 'Transport');
      expect(p.parse('milk'), isNull);
    });

    test('Hinglish: kal, parso, ko, diye, Hindi item words', () {
      final QuickEntry a = p.parse('kal Ramesh ko 500 diye')!;
      expect(a.paise, 50000);
      expect(a.person, 'Ramesh');
      expect(a.date, DateTime(2026, 11, 9));
      expect(a.item, '');

      final QuickEntry b = p.parse('aaj doodh 60')!;
      expect(b.category, 'Groceries');
      expect(b.item, 'doodh');
      expect(b.date, DateTime(2026, 11, 10));

      final QuickEntry c = p.parse('parso dawai ke 450 rupaye')!;
      expect(c.category, 'Health');
      expect(c.paise, 45000);
      expect(c.date, DateTime(2026, 11, 8));

      final QuickEntry d = p.parse('kaamwali bai ko 3000 diya')!;
      expect(d.person, 'Bai');
      expect(d.paise, 300000);
    });

    test('saving puts it in the ledger on the parsed date', () {
      final ExpenseTracker ledger = ExpenseTracker(now: clock);
      final Expense? e = QuickAddParser.save(p.parse('kal sabzi 120')!, ledger, now: clock);
      expect(e!.at, DateTime(2026, 11, 9, 18, 30));
      expect(ledger.monthTotal(2026, 11), 12000);
      expect(e.category, 'Groceries');
    });
  });

  testWidgets('screen: shows what it understood, saves only on confirm, undo', (WidgetTester tester) async {
    final SemanticsHandle sem = tester.ensureSemantics();
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final ExpenseTracker ledger = ExpenseTracker(now: clock);
    String? shared;
    await tester.pumpWidget(MaterialApp(
      home: QuickAddScreen(ledger: ledger, now: clock, share: (String t) async => shared = t, save: (String _) async => '/x'),
    ));
    await tester.enterText(find.byKey(const Key('quick-text')), 'kal Ramesh ko 500 diye');
    await tester.pump();
    expect(tester.widget<Text>(find.byKey(const Key('quick-amount'))).data, '₹500');
    expect(tester.widget<Text>(find.byKey(const Key('quick-person'))).data, 'Ramesh');
    expect(tester.widget<Text>(find.byKey(const Key('quick-date'))).data, '9 Nov 2026');
    expect(find.bySemanticsLabel('Person: Ramesh'), findsOneWidget);
    expect(ledger.all, isEmpty, reason: 'nothing saved before confirming');

    final Finder confirm = find.byKey(const Key('quick-confirm'));
    expect(tester.getSize(confirm).height, greaterThanOrEqualTo(44));
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(ledger.all.single.paise, 50000);
    expect(ledger.all.single.note, 'To Ramesh');

    await tester.tap(find.byKey(const Key('result-share')));
    await tester.pumpAndSettle();
    expect(shared, contains('₹500'));

    await tester.tap(find.byKey(const Key('result-undo')));
    await tester.pumpAndSettle();
    expect(ledger.all, isEmpty);
    await tester.pumpAndSettle(const Duration(seconds: 5));
    sem.dispose();
  });
}
