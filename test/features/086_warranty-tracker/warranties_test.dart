import 'package:family_utility_app/engines/family/family_identity.dart';
import 'package:family_utility_app/engines/family/family_space.dart';
import 'package:family_utility_app/engines/family/family_store.dart';
import 'package:family_utility_app/engines/family/family_sync.dart';
import 'package:family_utility_app/engines/records/receipt_vault.dart';
import 'package:family_utility_app/engines/records/warranties.dart';
import 'package:family_utility_app/records/warranties/warranties_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

FamilySpace newSpace() => FamilySpace(
      identityStore: MemoryFamilyIdentityStore(),
      storage: MemoryFamilyStoreStorage(),
      transportsFor: (FamilyIdentity _) => <FamilySyncTransport>[],
    );

class RecordingReminders implements WarrantyReminderScheduler {
  List<WarrantyReminder> last = <WarrantyReminder>[];
  @override
  Future<void> replaceAll(List<WarrantyReminder> reminders) async => last = reminders;
}

Warranties make({WarrantyReminderScheduler? reminders}) => Warranties(
      space: newSpace(),
      soloStore: FamilyStore(deviceId: 'me'),
      reminders: reminders ?? const NoWarrantyReminders(),
      now: () => DateTime(2026, 3, 20, 10),
    );

ReceiptVault receiptsWithTv() {
  final ReceiptVault v = ReceiptVault(now: () => DateTime(2026, 3, 20));
  final Receipt tv = v.add(shop: 'Croma', paise: 5499000, date: DateTime(2026, 1, 15))!;
  v.setWarranty(tv.id, 24, product: 'Sony TV');
  v.add(shop: 'Milk', paise: 4500);
  return v;
}

void main() {
  group('engine', () {
    test('expiry, reminders 30 and 7 days ahead, linked receipt, service call, undo', () async {
      final RecordingReminders rec = RecordingReminders();
      final Warranties w = make(reminders: rec);
      expect(w.add(product: ' ', bought: DateTime(2025, 1, 1), months: 12), isNull);
      final Warranty wm = w.add(product: 'Washing machine', bought: DateTime(2025, 4, 10), months: 12, servicePhone: '1800-103 1234')!;
      final Warranty old = w.add(product: 'Old fridge', bought: DateTime(2020, 1, 1), months: 12)!;
      expect(wm.ends, DateTime(2026, 4, 10));
      expect(w.daysLeft(wm), 21);
      expect(w.state(wm), WarrantyState.endingSoon);
      expect(w.state(old), WarrantyState.expired);
      expect(wm.callUri.toString(), 'tel:18001031234');

      final ReceiptVault receipts = receiptsWithTv();
      expect(w.importFromReceipts(receipts.all), 1);
      expect(w.importFromReceipts(receipts.all), 0);
      final Warranty tv = w.all.firstWhere((Warranty x) => x.product == 'Sony TV');
      expect(tv.ends, DateTime(2028, 1, 15));
      expect(receipts.byId(tv.receiptId!)!.shop, 'Croma');
      expect(w.all.map((Warranty x) => x.product).toList(), <String>['Washing machine', 'Sony TV', 'Old fridge']);

      await Future<void>.delayed(Duration.zero);
      expect(rec.last.map((WarrantyReminder r) => (r.title, r.at)).toList(), <(String, DateTime)>[
        ('Washing machine warranty ends in 7 days', DateTime(2026, 4, 3, 10)),
        ('Sony TV warranty ends in 30 days', DateTime(2027, 12, 16, 10)),
        ('Sony TV warranty ends in 7 days', DateTime(2028, 1, 8, 10)),
      ]);

      expect(w.undo(), isTrue);
      expect(w.all.length, 2);
      expect(w.toText(), contains('- Washing machine: bought 10 Apr 2025, till 10 Apr 2026 · service 1800-103 1234'));
      expect(w.toText(), contains('- Old fridge: bought 1 Jan 2020, ended 1 Jan 2021'));
    });

    test('shared with the family', () async {
      final FamilySpace a = newSpace();
      await a.create(familyName: 'Shahs', memberName: 'Asha');
      Warranties(space: a, now: () => DateTime(2026, 3, 20)).add(product: 'AC', bought: DateTime(2026, 3, 1), months: 60);
      final FamilySpace b = newSpace();
      await b.create(familyName: 'x', memberName: 'Ravi');
      b.store.mergeAll(a.store.allRecords);
      expect(Warranties(space: b, now: () => DateTime(2026, 3, 20)).all.single.ends, DateTime(2031, 3, 1));
    });
  });

  testWidgets('screen: add, import from receipts, bill shown, call service, share, undo; 44 px', (WidgetTester tester) async {
    final SemanticsHandle sem = tester.ensureSemantics();
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final Warranties w = make();
    final ReceiptVault receipts = receiptsWithTv();
    final List<Uri> called = <Uri>[];
    final List<String> shared = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: WarrantiesScreen(
        warranties: w,
        receipts: receipts,
        call: (Uri u) async {
          called.add(u);
          return true;
        },
        share: (String t) async => shared.add(t),
        save: (String t, String n) async => '/x/$n',
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('w-add')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('w-product')), 'Washing machine');
    await tester.enterText(find.byKey(const Key('w-bought')), '10/04/2025');
    await tester.enterText(find.byKey(const Key('w-phone')), '1800 103 1234');
    await tester.tap(find.byKey(const Key('w-save')));
    await tester.pumpAndSettle();
    final Warranty wm = w.all.single;
    expect(find.text('Covered till 10 Apr 2026 · 21 days left'), findsOneWidget);

    expect(tester.getSize(find.byKey(Key('w-call-${wm.id}'))).height, greaterThanOrEqualTo(44));
    await tester.tap(find.byKey(Key('w-call-${wm.id}')));
    await tester.pumpAndSettle();
    expect(called.single.toString(), 'tel:18001031234');

    await tester.tap(find.byTooltip('Add from receipts'));
    await tester.pumpAndSettle();
    final Warranty tv = w.all.firstWhere((Warranty x) => x.product == 'Sony TV');
    expect(find.text('Bill: Croma · ₹54,990'), findsOneWidget);
    expect(find.byKey(Key('w-${tv.id}')), findsOneWidget);

    await tester.tap(find.byKey(const Key('result-share')));
    await tester.pumpAndSettle();
    expect(shared.last, contains('- Sony TV: bought 15 Jan 2026, till 15 Jan 2028'));

    await tester.tap(find.byKey(const Key('result-undo')));
    await tester.pumpAndSettle();
    expect(find.text('Bill: Croma · ₹54,990'), findsNothing);
    await tester.pumpAndSettle(const Duration(seconds: 5));
    sem.dispose();
  });
}
