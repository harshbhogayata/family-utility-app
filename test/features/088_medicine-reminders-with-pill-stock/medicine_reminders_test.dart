import 'package:family_utility_app/engines/family/family_identity.dart';
import 'package:family_utility_app/engines/family/family_roles.dart';
import 'package:family_utility_app/engines/family/family_space.dart';
import 'package:family_utility_app/engines/family/family_store.dart';
import 'package:family_utility_app/engines/family/family_sync.dart';
import 'package:family_utility_app/engines/records/medicine_reminders.dart';
import 'package:family_utility_app/records/medicines/medicine_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

FamilySpace newSpace() => FamilySpace(
      identityStore: MemoryFamilyIdentityStore(),
      storage: MemoryFamilyStoreStorage(),
      transportsFor: (FamilyIdentity _) => <FamilySyncTransport>[],
    );

class RecordingAlarms implements MedicineAlarmScheduler {
  List<DoseAlarm> last = <DoseAlarm>[];
  int calls = 0;

  @override
  Future<void> replaceAll(List<DoseAlarm> alarms) async {
    calls++;
    last = alarms;
  }
}

void main() {
  final DateTime morning = DateTime(2026, 3, 10, 7, 30);

  group('engine', () {
    test('times parse; doses decrement stock once; skip, snooze and undo', () async {
      expect(Medicine.parseTimes('8:00, 20:30'), <int>[480, 1230]);
      expect(Medicine.parseTimes('21.15 08:00'), <int>[480, 1275]);
      expect(Medicine.parseTimes('25:00'), isNull);
      expect(Medicine.parseTimes(''), isNull);

      DateTime now = morning;
      final RecordingAlarms alarms = RecordingAlarms();
      final MedicineReminders r = MedicineReminders(
        space: newSpace(),
        soloStore: FamilyStore(deviceId: 'me'),
        alarms: alarms,
        now: () => now,
      );
      final Medicine m = r.add(name: 'Metformin', times: <int>[480, 1200], tabletsPerDose: 2, stock: 10, refillAt: 6)!;
      expect(r.add(name: ' ', times: <int>[480]), isNull);
      expect(r.add(name: 'X', times: <int>[]), isNull);
      await Future<void>.delayed(Duration.zero);

      // Alarms fire at the exact dose times, with Taken / Snooze payloads.
      expect(alarms.last.where((DoseAlarm a) => a.isDose).first.at, DateTime(2026, 3, 10, 8));
      expect(alarms.last.first.payload, MedicineReminders.payloadFor(m.id, DateTime(2026, 3, 10, 8)));

      final DateTime eight = DateTime(2026, 3, 10, 8);
      expect(r.today.length, 2);
      expect(r.markTaken(m.id, eight), isTrue);
      expect(r.byId(m.id)!.stock, 8);
      expect(r.markTaken(m.id, eight), isFalse, reason: 'not counted twice');
      expect(r.byId(m.id)!.stock, 8);
      expect(r.markTaken(m.id, DateTime(2026, 3, 10, 9)), isFalse, reason: 'not a dose time');

      expect(r.undo(), isTrue);
      expect(r.byId(m.id)!.stock, 10);
      expect(r.today.first.status, DoseStatus.pending);

      // Snooze rings again ten minutes later instead of at the dose time.
      now = DateTime(2026, 3, 10, 8, 2);
      final DateTime? until = r.snooze(m.id, eight);
      expect(until, DateTime(2026, 3, 10, 8, 12));
      await Future<void>.delayed(Duration.zero);
      expect(alarms.last.where((DoseAlarm a) => a.isDose).first.at, until);

      // The notification's Taken button logs it and takes the stock down.
      expect(r.handleTap(MedicineReminders.takenAction, MedicineReminders.payloadFor(m.id, eight)), isTrue);
      expect(r.today.first.status, DoseStatus.taken);
      expect(r.byId(m.id)!.stock, 8);
      expect(r.byId(m.id)!.needsRefill, isFalse);

      expect(r.skip(m.id, DateTime(2026, 3, 10, 20)), isTrue);
      expect(r.today.last.status, DoseStatus.skipped);
      expect(r.handleTap(null, MedicineReminders.payloadFor(m.id, eight)), isFalse);
      expect(r.handleTap(MedicineReminders.takenAction, 'job:1'), isFalse);
    });

    test('refill reminder when stock runs low; refill adds tablets', () async {
      final DateTime now = morning;
      final RecordingAlarms alarms = RecordingAlarms();
      final MedicineReminders r = MedicineReminders(
        space: newSpace(),
        soloStore: FamilyStore(deviceId: 'me'),
        alarms: alarms,
        now: () => now,
      );
      final Medicine m = r.add(name: 'Thyronorm', times: <int>[420 + 60], stock: 6, refillAt: 5)!;
      expect(r.byId(m.id)!.needsRefill, isFalse);
      r.markTaken(m.id, DateTime(2026, 3, 10, 8));
      expect(r.byId(m.id)!.needsRefill, isTrue);
      expect(r.byId(m.id)!.daysLeft, 5);
      await Future<void>.delayed(Duration.zero);
      final DoseAlarm refill = alarms.last.firstWhere((DoseAlarm a) => !a.isDose);
      expect(refill.title, 'Refill Thyronorm');
      expect(refill.at, DateTime(2026, 3, 10, 10));
      expect(r.refill(m.id, 30), isTrue);
      expect(r.byId(m.id)!.stock, 35);
      expect(r.refill(m.id, 0), isFalse);
      expect(r.toText(), contains('Thyronorm'));
      expect(r.toText(), contains('35 left'));
      expect(r.toText(), contains('Taken'));
    });

    test('per-member schedule is visible to allowed carers only', () async {
      final FamilySpace mum = newSpace();
      final FamilyIdentity mumId = await mum.create(familyName: 'Shahs', memberName: 'Asha');
      mum.store.put(FamilySpace.members, 'nani', <String, Object?>{'name': 'Nani', 'role': 'adult'});
      final MedicineReminders r = MedicineReminders(space: mum, roles: FamilyRoles(space: mum), now: () => morning);

      // Asha adds Nani's medicine: she becomes a carer automatically.
      final Medicine m = r.add(name: 'Amlodipine', times: <int>[540], memberId: 'nani', stock: 20)!;
      expect(m.carers, <String>[mumId.deviceId]);
      expect(r.canSee(m), isTrue);
      expect(r.alarms().first.title, 'Amlodipine for Nani');

      // Riya was not given permission, so her phone does not show it.
      final FamilySpace riyaPhone = newSpace();
      await riyaPhone.create(familyName: 'x', memberName: 'Riya');
      riyaPhone.store.mergeAll(mum.store.allRecords);
      final MedicineReminders riya = MedicineReminders(space: riyaPhone, now: () => morning);
      final String riyaId = riyaPhone.identity!.deviceId;
      riyaPhone.store.put(FamilySpace.members, riyaId, <String, Object?>{'name': 'Riya', 'role': 'child'});
      final MedicineReminders riyaWithRole =
          MedicineReminders(space: riyaPhone, roles: FamilyRoles(space: riyaPhone), now: () => morning);
      expect(riya.visible, isEmpty);
      expect(riya.markTaken(m.id, DateTime(2026, 3, 10, 9)), isFalse);

      // Allow her, sync again: she sees the schedule and can log a dose.
      expect(r.setCarer(m.id, riyaId, true), isTrue);
      expect(r.setCarer(m.id, 'nani', true), isFalse, reason: 'the member is not their own carer');
      riyaPhone.store.mergeAll(mum.store.allRecords);
      expect(riya.visible.map((Medicine x) => x.name), <String>['Amlodipine']);
      expect(riyaWithRole.canGrant(riya.visible.first), isFalse);
      expect(riya.markTaken(m.id, DateTime(2026, 3, 10, 9)), isTrue);
      mum.store.mergeAll(riyaPhone.store.allRecords);
      expect(r.byId(m.id)!.stock, 19);
      expect(r.today.first.status, DoseStatus.taken);

      expect(r.setCarer(m.id, riyaId, false), isTrue);
      riyaPhone.store.mergeAll(mum.store.allRecords);
      expect(riya.visible, isEmpty);
    });
  });

  testWidgets('screen: add, take a dose, refill, undo, share; 44 px targets and labels', (WidgetTester tester) async {
    final SemanticsHandle sem = tester.ensureSemantics();
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final DateTime now = DateTime.now();
    final MedicineReminders r = MedicineReminders(
      space: newSpace(),
      soloStore: FamilyStore(deviceId: 'me'),
      now: () => DateTime(now.year, now.month, now.day, 0, 5),
    );
    String? shared;
    await tester.pumpWidget(MaterialApp(
      home: MedicineScreen(reminders: r, share: (String t) async => shared = t, save: (String _) async => '/x'),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('med-add')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('med-name')), 'Vitamin D');
    await tester.enterText(find.byKey(const Key('med-times')), '09:00');
    await tester.enterText(find.byKey(const Key('med-stock')), '10');
    await tester.tap(find.byKey(const Key('med-save')));
    await tester.pumpAndSettle();
    expect(r.visible.single.name, 'Vitamin D');
    final Medicine m = r.visible.single;
    final String key = MedicineReminders.doseKey(m.id, DateTime(now.year, now.month, now.day, 9));

    final Finder taken = find.byKey(Key('taken-$key'));
    expect(tester.getSize(taken).height, greaterThanOrEqualTo(44));
    expect(tester.getSize(find.byKey(Key('snooze-$key'))).height, greaterThanOrEqualTo(44));
    expect(find.bySemanticsLabel(RegExp('Vitamin D at 09:00')), findsOneWidget);
    await tester.tap(taken);
    await tester.pumpAndSettle();
    expect(r.byId(m.id)!.stock, 9);
    expect(find.byKey(Key('taken-$key')), findsNothing);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(r.byId(m.id)!.stock, 10);

    await tester.tap(find.byKey(Key('refill-${m.id}')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('refill-count')), '20');
    await tester.tap(find.byKey(const Key('refill-ok')));
    await tester.pumpAndSettle();
    expect(r.byId(m.id)!.stock, 30);

    await tester.tap(find.text('Share'));
    await tester.pumpAndSettle();
    expect(shared, contains('Vitamin D'));
    await tester.pumpAndSettle(const Duration(seconds: 5));
    sem.dispose();
  });
}
