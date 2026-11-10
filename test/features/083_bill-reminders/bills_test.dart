import 'package:family_utility_app/engines/family/family_identity.dart';
import 'package:family_utility_app/engines/family/family_space.dart';
import 'package:family_utility_app/engines/family/family_store.dart';
import 'package:family_utility_app/engines/family/family_sync.dart';
import 'package:family_utility_app/engines/records/bills.dart';
import 'package:family_utility_app/engines/records/receipt_vault.dart';
import 'package:family_utility_app/records/bills/bills_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

FamilySpace newSpace() => FamilySpace(
      identityStore: MemoryFamilyIdentityStore(),
      storage: MemoryFamilyStoreStorage(),
      transportsFor: (FamilyIdentity _) => <FamilySyncTransport>[],
    );

class RecordingReminders implements BillReminderScheduler {
  List<BillReminder> last = <BillReminder>[];
  @override
  Future<void> replaceAll(List<BillReminder> reminders) async => last = reminders;
}

Bills make({BillReminderScheduler? reminders}) => Bills(
      space: newSpace(),
      soloStore: FamilyStore(deviceId: 'me'),
      reminders: reminders ?? const NoBillReminders(),
      now: () => DateTime(2026, 1, 20, 10),
    );

void main() {
  group('engine', () {
    test('month arithmetic keeps the due day', () {
      expect(Bill.addMonths(DateTime(2026, 1, 31), 1, 31), DateTime(2026, 2, 28));
      expect(Bill.addMonths(DateTime(2026, 2, 28), 1, 31), DateTime(2026, 3, 31));
      expect(Bill.addMonths(DateTime(2026, 11, 15), 3, 15), DateTime(2027, 2, 15));
    });

    test('reminders, mark paid with history, receipt, undo', () async {
      final RecordingReminders rec = RecordingReminders();
      final Bills b = make(reminders: rec);
      expect(b.add(name: 'x', kind: BillKind.rent, due: DateTime(2026, 2, 1), everyMonths: 5), isNull);
      final Bill power = b.add(name: 'BESCOM', kind: BillKind.electricity, due: DateTime(2026, 1, 31), paise: 180000)!;
      final Bill net = b.add(name: '', kind: BillKind.internet, due: DateTime(2026, 1, 18), everyMonths: 3)!;
      expect(net.name, 'Internet');
      expect(b.state(net), BillState.overdue);
      expect(b.state(power), BillState.later);
      await Future<void>.delayed(Duration.zero);
      expect(rec.last.map((BillReminder r) => (r.title, r.at)).toList(), <(String, DateTime)>[
        ('Internet is overdue', DateTime(2026, 1, 21, 9)),
        ('BESCOM is due in 3 days', DateTime(2026, 1, 28, 9)),
        ('BESCOM is due today', DateTime(2026, 1, 31, 9)),
      ]);
      expect(rec.last[1].body, 'Due 31 Jan 2026 · ₹1,800. Tap to mark paid.');

      expect(b.markPaid(net.id), isFalse); // no usual amount, none typed
      expect(b.attachReceipt(power.id, 'r1'), isFalse); // nothing paid yet
      expect(b.markPaid(power.id), isTrue);
      expect(b.byId(power.id)!.nextDue, DateTime(2026, 2, 28));
      expect(b.markPaid(power.id, paise: 210000, on: DateTime(2026, 1, 20)), isTrue);
      expect(b.byId(power.id)!.nextDue, DateTime(2026, 3, 31));
      expect(b.byId(power.id)!.payments.map((BillPayment p) => p.paise), <int>[180000, 210000]);
      expect(b.byId(power.id)!.payments.last.dueFor, DateTime(2026, 2, 28));
      expect(Bills.average(b.byId(power.id)!), 195000);

      expect(b.attachReceipt(power.id, 'r1'), isTrue);
      expect(b.byId(power.id)!.payments.last.receiptId, 'r1');
      expect(b.toText(), contains('paid ₹2,100 on 20 Jan 2026 (receipt)'));
      expect(b.undo(), isTrue);
      expect(b.byId(power.id)!.payments.last.receiptId, isNull);

      expect(b.markPaid(net.id, paise: 99900), isTrue);
      expect(b.byId(net.id)!.nextDue, DateTime(2026, 4, 18));
    });

    test('bills are shared with the family', () async {
      final FamilySpace a = newSpace();
      await a.create(familyName: 'Shahs', memberName: 'Asha');
      Bills(space: a, now: () => DateTime(2026, 1, 20)).add(name: 'Society', kind: BillKind.society, due: DateTime(2026, 2, 5));
      final FamilySpace c = newSpace();
      await c.create(familyName: 'x', memberName: 'Ravi');
      c.store.mergeAll(a.store.allRecords);
      expect(Bills(space: c, now: () => DateTime(2026, 1, 20)).all.single.kind, BillKind.society);
    });
  });

  testWidgets('screen: add bill, mark paid, attach receipt, share, undo; 44 px', (WidgetTester tester) async {
    final SemanticsHandle sem = tester.ensureSemantics();
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final Bills b = make();
    final ReceiptVault receipts = ReceiptVault(now: () => DateTime(2026, 1, 20));
    final Receipt r = receipts.add(shop: 'BESCOM counter', paise: 175000, date: DateTime(2026, 1, 20))!;
    final List<String> shared = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: BillsScreen(bills: b, receipts: receipts, share: (String t) async => shared.add(t), save: (String t, String n) async => '/x/$n'),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('bill-add')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('bill-name')), 'BESCOM');
    await tester.enterText(find.byKey(const Key('bill-due')), '25/01/2026');
    await tester.enterText(find.byKey(const Key('bill-amount')), '1800');
    await tester.tap(find.byKey(const Key('bill-save')));
    await tester.pumpAndSettle();
    final Bill bill = b.all.single;
    expect(find.text('Electricity · Monthly · 25 Jan 2026 · ₹1,800'), findsOneWidget);
    expect(find.text('Due in 5 days'), findsOneWidget);

    expect(tester.getSize(find.byKey(Key('bill-pay-${bill.id}'))).height, greaterThanOrEqualTo(44));
    await tester.tap(find.byKey(Key('bill-pay-${bill.id}')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('bill-paid-amount')), '1750');
    await tester.tap(find.byKey(const Key('bill-paid-save')));
    await tester.pumpAndSettle();
    expect(find.text('Paid ₹1,750 on 20 Jan 2026'), findsOneWidget);
    expect(find.text('Due in 36 days'), findsOneWidget);

    await tester.tap(find.byKey(Key('bill-attach-${bill.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('bill-receipt-${r.id}')));
    await tester.pumpAndSettle();
    expect(find.text('Paid ₹1,750 on 20 Jan 2026 · receipt attached'), findsOneWidget);

    await tester.tap(find.byKey(const Key('result-share')));
    await tester.pumpAndSettle();
    expect(shared.last, contains('- BESCOM: due 25 Feb 2026 · ₹1,800'));

    await tester.tap(find.byKey(const Key('result-undo')));
    await tester.pumpAndSettle();
    expect(find.text('Paid ₹1,750 on 20 Jan 2026'), findsOneWidget);
    await tester.pumpAndSettle(const Duration(seconds: 5));
    sem.dispose();
  });
}
