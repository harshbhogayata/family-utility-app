import 'package:family_utility_app/engines/records/shared_expenses.dart';
import 'package:family_utility_app/records/shared_expenses/shared_expenses_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('splits', () {
    test('equal split hands odd paise to the first people', () {
      expect(Splits.equal(10000, <String>['Me', 'Ramesh', 'Priya']), <String, int>{'Me': 3334, 'Ramesh': 3333, 'Priya': 3333});
      expect(() => Splits.equal(100, <String>[]), throwsA(isA<SplitError>()));
    });

    test('custom split must add up', () {
      expect(Splits.custom(50000, <String, int>{'Me': 20000, 'Ramesh': 30000, 'Priya': 0}), <String, int>{'Me': 20000, 'Ramesh': 30000});
      expect(
        () => Splits.custom(50000, <String, int>{'Me': 20000}),
        throwsA(isA<SplitError>().having((SplitError e) => e.message, 'message', 'Shares are ₹300 short of ₹500')),
      );
    });

    test('balances add to zero and settle in the fewest payments', () {
      final DateTime t = DateTime(2026, 11, 1);
      final List<SharedExpense> list = <SharedExpense>[
        SharedExpense(id: '1', groupId: 'g', description: 'Dinner', paise: 90000, paidBy: 'Me', shares: Splits.equal(90000, <String>['Me', 'Ramesh', 'Priya']), at: t),
        SharedExpense(id: '2', groupId: 'g', description: 'Cab', paise: 30000, paidBy: 'Ramesh', shares: Splits.equal(30000, <String>['Me', 'Ramesh', 'Priya']), at: t),
      ];
      final Map<String, int> b = Splits.balances(list, <String>['Me', 'Ramesh', 'Priya']);
      expect(b, <String, int>{'Me': 50000, 'Ramesh': -10000, 'Priya': -40000});
      expect(b.values.fold<int>(0, (int a, int c) => a + c), 0);
      expect(Splits.settle(b), <Transfer>[const Transfer('Priya', 'Me', 40000), const Transfer('Ramesh', 'Me', 10000)]);
    });

    test('drafted reminder names the person, group and amount', () {
      expect(Splits.reminder(const Transfer('Ramesh', 'Me', 125000), 'Goa trip'),
          'Hi Ramesh, a gentle reminder from our "Goa trip" expenses: you owe me ₹1,250. Pay whenever it suits you. Thanks!');
      expect(Splits.reminder(const Transfer('Me', 'Priya', 5050), 'Home'), contains('I owe you ₹50.50'));
    });
  });

  group('store', () {
    test('saves, reloads, settles and undoes', () async {
      final MemorySharedExpenseStore store = MemorySharedExpenseStore();
      final SharedExpenses s = SharedExpenses(store: store, now: () => DateTime(2026, 11, 9));
      final SplitGroup g = await s.addGroup('Home', <String>['Ramesh', ' ', 'ramesh', 'Priya']);
      expect(g.people, <String>['Me', 'Ramesh', 'Priya']);
      await s.addExpense(groupId: g.id, description: 'Rent', paise: 3000000, paidBy: 'Me', shares: Splits.equal(3000000, g.people));
      expect(s.balancesOf(g.id)['Me'], 2000000);

      final SharedExpenses again = SharedExpenses(store: store);
      await again.load();
      expect(again.groups.single.name, 'Home');
      expect(again.balancesOf(g.id)['Priya'], -1000000);

      final Transfer t = again.settleUp(g.id).first;
      await again.settle(g.id, t);
      expect(again.balancesOf(g.id)[t.from], 0);
      expect(await again.undo(), isTrue);
      expect(again.balancesOf(g.id)[t.from], -1000000);
      await expectLater(again.addGroup('Solo', <String>[]), throwsA(isA<SplitError>()));
    });
  });

  testWidgets('add a custom split, see balances, send a reminder, Share/Save/Undo', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final SharedExpenses s = SharedExpenses(now: () => DateTime(2026, 11, 9));
    final List<String> shared = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: SharedExpensesScreen(
        store: s,
        familyNames: const <String>['Ramesh'],
        share: (String t) async => shared.add(t),
        save: (String name, String t) async => '/x/$name',
      ),
    ));
    await tester.tap(find.byKey(const Key('new-group')));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'Ramesh'), findsOneWidget, reason: 'family members are offered');
    await tester.enterText(find.byKey(const Key('group-name')), 'Goa trip');
    await tester.enterText(find.byKey(const Key('group-people')), 'Ramesh, Priya');
    await tester.tap(find.byKey(const Key('group-ok')));
    await tester.pumpAndSettle();
    expect(find.text('Goa trip'), findsOneWidget);

    await tester.tap(find.byKey(const Key('add-expense')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('expense-desc')), 'Hotel');
    await tester.enterText(find.byKey(const Key('expense-amount')), '600');
    await tester.tap(find.text('Custom'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('share-Me')), '100');
    await tester.enterText(find.byKey(const Key('share-Ramesh')), '200');
    await tester.enterText(find.byKey(const Key('share-Priya')), '200');
    await tester.tap(find.byKey(const Key('expense-ok')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('expense-error')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('share-Priya')), '300');
    await tester.tap(find.byKey(const Key('expense-ok')));
    await tester.pumpAndSettle();

    expect(find.text('gets back ₹500'), findsOneWidget);
    expect(find.text('owes ₹300'), findsOneWidget);
    expect(find.text('Priya pays Me ₹300'), findsOneWidget);

    await tester.tap(find.byKey(const Key('remind-0')));
    await tester.pump();
    expect(shared.single, contains('Hi Priya'));
    expect(tester.getSize(find.byKey(const Key('remind-0'))).height, greaterThanOrEqualTo(44));

    await tester.tap(find.byKey(const Key('paid-0')));
    await tester.pumpAndSettle();
    expect(find.text('Priya pays Me ₹300'), findsNothing);
    await tester.tap(find.byKey(const Key('result-undo')));
    await tester.pumpAndSettle();
    expect(find.text('Priya pays Me ₹300'), findsOneWidget);

    await tester.tap(find.byKey(const Key('result-share')));
    await tester.pump();
    expect(shared.last, contains('To settle up:'));
    await tester.tap(find.byKey(const Key('result-save')));
    await tester.pumpAndSettle();
    expect(find.text('Saved to /x/Goa trip.txt'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });
}
