import 'package:family_utility_app/engines/family/family_store.dart';
import 'package:family_utility_app/engines/records/lending_ledger.dart';
import 'package:family_utility_app/records/lending/lending_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class RecordingReminders implements LendReminderScheduler {
  List<LendReminder> last = <LendReminder>[];
  @override
  Future<void> replaceAll(List<LendReminder> reminders) async => last = reminders;
}

LendingLedger make({LendReminderScheduler? reminders, FamilyStore? store}) => LendingLedger(
      store: store ?? FamilyStore(deviceId: 'me'),
      reminders: reminders ?? const NoLendReminders(),
      now: () => DateTime(2026, 1, 20, 10),
    );

void main() {
  group('engine', () {
    test('who, amount, date, due date, status and reminders', () async {
      final RecordingReminders rec = RecordingReminders();
      final LendingLedger l = make(reminders: rec);
      expect(l.add(direction: LendDirection.lent, who: '  ', paise: 100), isNull);
      expect(l.add(direction: LendDirection.lent, who: 'Ravi', paise: 0), isNull);
      expect(l.add(direction: LendDirection.lent, who: 'Ravi', paise: 100, date: DateTime(2026, 1, 10), due: DateTime(2026, 1, 9)), isNull);

      final LendEntry ravi = l.add(direction: LendDirection.lent, who: ' Ravi ', paise: 500000, date: DateTime(2026, 1, 5), due: DateTime(2026, 1, 25), note: 'bike repair')!;
      final LendEntry asha = l.add(direction: LendDirection.borrowed, who: 'Asha', paise: 200000, date: DateTime(2026, 1, 1), due: DateTime(2026, 1, 15))!;
      final LendEntry ravi2 = l.add(direction: LendDirection.borrowed, who: 'ravi', paise: 100000)!;
      expect(ravi.who, 'Ravi');
      expect(ravi2.date, DateTime(2026, 1, 20));
      expect(ravi.status, LendStatus.open);
      expect(l.isOverdue(asha), isTrue);
      expect(l.daysUntil(ravi), 5);
      expect(l.daysUntil(ravi2), isNull);
      expect(l.all.map((LendEntry e) => e.who), <String>['Asha', 'Ravi', 'ravi']);

      await Future<void>.delayed(Duration.zero);
      expect(rec.last.map((LendReminder r) => (r.title, r.at)).toList(), <(String, DateTime)>[
        ('You owe Asha ₹2,000 · overdue', DateTime(2026, 1, 21, 9)),
        ('Ravi owes you ₹5,000 · due tomorrow', DateTime(2026, 1, 24, 9)),
        ('Ravi owes you ₹5,000 · due today', DateTime(2026, 1, 25, 9)),
      ]);
      expect(rec.last.every((LendReminder r) => r.payload.startsWith(LendingLedger.payloadPrefix)), isTrue);
      expect(rec.last[1].body, 'Lent on 5 Jan 2026, due 25 Jan 2026. Tap to record a repayment.');

      expect(l.totals(), (500000, 300000));
      expect(l.balances().map((PersonBalance p) => (p.who, p.netPaise)).toList(), <(String, int)>[('Ravi', 400000), ('Asha', -200000)]);

      expect(l.repay(ravi.id, 150000), isTrue);
      expect(l.byId(ravi.id)!.status, LendStatus.partlyRepaid);
      expect(l.byId(ravi.id)!.remaining, 350000);
      expect(l.repay(ravi.id, 999999), isTrue); // capped at what is left
      expect(l.byId(ravi.id)!.status, LendStatus.settled);
      expect(l.byId(ravi.id)!.repaid, 500000);
      expect(l.repay(ravi.id, 100), isFalse);
      expect(l.undo(), isTrue);
      expect(l.byId(ravi.id)!.remaining, 350000);

      expect(l.settle(asha.id), isTrue);
      expect(l.isOverdue(l.byId(asha.id)!), isFalse);
      await Future<void>.delayed(Duration.zero);
      expect(rec.last.any((LendReminder r) => r.title.contains('Asha')), isFalse);
      expect(l.all.last.who, 'Asha'); // settled entries sink to the bottom

      final String text = l.toText();
      expect(text, contains('Owed to you: ₹3,500'));
      expect(text, contains('- Lent ₹5,000 to Ravi on 5 Jan 2026, due 25 Jan 2026 · Part repaid (₹3,500 left) · bike repair'));
      expect(text, contains('- Borrowed ₹2,000 from Asha on 1 Jan 2026, due 15 Jan 2026 · Settled'));

      expect(l.remove(ravi2.id), isTrue);
      expect(l.undo(), isTrue);
      expect(l.byId(ravi2.id), isNotNull);
    });

    test('entries survive a reload of the store', () {
      final FamilyStore s = FamilyStore(deviceId: 'me');
      make(store: s).add(direction: LendDirection.lent, who: 'Meena', paise: 25050, due: DateTime(2026, 2, 1));
      final LendEntry e = make(store: s).all.single;
      expect((e.who, e.paise, e.due, e.direction), ('Meena', 25050, DateTime(2026, 2, 1), LendDirection.lent));
    });
  });

  testWidgets('screen: add, part repay, settle, share, undo; 44 px', (WidgetTester tester) async {
    final SemanticsHandle sem = tester.ensureSemantics();
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final LendingLedger l = make();
    final List<String> shared = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: LendingScreen(ledger: l, share: (String t) async => shared.add(t), save: (String t, String n) async => '/x/$n'),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('Nothing lent or borrowed yet'), findsOneWidget);

    await tester.tap(find.byKey(const Key('lend-add')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('lend-who')), 'Ravi');
    await tester.enterText(find.byKey(const Key('lend-amount')), '5000');
    await tester.enterText(find.byKey(const Key('lend-date')), '05/01/2026');
    await tester.enterText(find.byKey(const Key('lend-due')), '25/01/2026');
    await tester.tap(find.byKey(const Key('lend-save')));
    await tester.pumpAndSettle();
    final LendEntry e = l.all.single;
    expect(find.text('Ravi owes you ₹5,000'), findsWidgets);
    expect(find.text('Lent ₹5,000 on 5 Jan 2026 · due 25 Jan 2026 · Open'), findsOneWidget);
    expect(find.text('Due in 5 days'), findsOneWidget);
    expect(find.text('Owed to you ₹5,000 · You owe ₹0'), findsOneWidget);

    expect(tester.getSize(find.byKey(Key('lend-repay-${e.id}'))).height, greaterThanOrEqualTo(44));
    expect(tester.getSize(find.byKey(Key('lend-settle-${e.id}'))).height, greaterThanOrEqualTo(44));
    await tester.tap(find.byKey(Key('lend-repay-${e.id}')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('lend-repay-amount')), '1500');
    await tester.tap(find.byKey(const Key('lend-repay-save')));
    await tester.pumpAndSettle();
    expect(find.text('Paid back ₹1,500 on 20 Jan 2026'), findsOneWidget);
    expect(find.text('Lent ₹5,000 on 5 Jan 2026 · due 25 Jan 2026 · Part repaid'), findsOneWidget);

    await tester.tap(find.byKey(Key('lend-settle-${e.id}')));
    await tester.pumpAndSettle();
    expect(find.text('Ravi · settled'), findsOneWidget);
    expect(find.byKey(Key('lend-repay-${e.id}')), findsNothing);

    await tester.tap(find.byKey(const Key('result-share')));
    await tester.pumpAndSettle();
    expect(shared.last, contains('- Lent ₹5,000 to Ravi on 5 Jan 2026, due 25 Jan 2026 · Settled'));

    await tester.tap(find.byKey(const Key('result-undo')));
    await tester.pumpAndSettle();
    expect(find.text('Lent ₹5,000 on 5 Jan 2026 · due 25 Jan 2026 · Part repaid'), findsOneWidget);
    await tester.pumpAndSettle(const Duration(seconds: 5));
    sem.dispose();
  });
}
