import 'package:family_utility_app/engines/family/family_identity.dart';
import 'package:family_utility_app/engines/family/family_space.dart';
import 'package:family_utility_app/engines/family/family_store.dart';
import 'package:family_utility_app/engines/family/family_sync.dart';
import 'package:family_utility_app/engines/records/elderly_care.dart';
import 'package:family_utility_app/engines/records/medicine_reminders.dart';
import 'package:family_utility_app/records/elderly_care/elderly_care_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

FamilySpace newSpace() => FamilySpace(
      identityStore: MemoryFamilyIdentityStore(),
      storage: MemoryFamilyStoreStorage(),
      transportsFor: (FamilyIdentity _) => <FamilySyncTransport>[],
    );

void main() {
  final DateTime morning = DateTime(2026, 3, 10, 7, 30);

  group('engine', () {
    test('a circle shared with siblings: roles, medicines and the log sync', () async {
      final FamilySpace asha = newSpace();
      final FamilyIdentity ashaId = await asha.create(familyName: 'Shahs', memberName: 'Asha');
      final ElderlyCare a = ElderlyCare(space: asha, now: () => morning);

      final FamilySpace ravi = newSpace();
      await ravi.create(familyName: 'x', memberName: 'Ravi');
      final String raviId = ravi.identity!.deviceId;
      asha.store.put(FamilySpace.members, raviId, <String, Object?>{'name': 'Ravi', 'role': 'adult'});
      asha.store.put(FamilySpace.members, 'kiran', <String, Object?>{'name': 'Kiran', 'role': 'adult'});
      final ElderlyCare r = ElderlyCare(space: ravi, now: () => morning);

      expect(a.create(name: '  '), isNull);
      final CareCircle c = a.create(name: 'Nani')!;
      expect(c.roles, <String, CareRole>{ashaId.deviceId: CareRole.lead});
      expect(c.parentKey, 'care:${c.id}');

      final Medicine m = a.addMedicine(c.id, name: 'Amlodipine', times: <int>[540], stock: 20)!;
      expect(a.medicinesFor(c).single.name, 'Amlodipine');
      expect(a.addEntry(c.id, CareEntryKind.visit, 'Took her to the park')!.by, ashaId.deviceId);
      expect(a.addEntry(c.id, CareEntryKind.note, ' '), isNull);

      // Ravi is not in the circle yet: after sync he sees nothing.
      ravi.store.mergeAll(asha.store.allRecords);
      expect(r.visible, isEmpty);
      expect(r.logFor(c.id), isEmpty);
      expect(r.addEntry(c.id, CareEntryKind.call, 'Called'), isNull);

      // Asha adds Ravi as a helper; he becomes a carer of the medicine too.
      expect(a.setRole(c.id, raviId, CareRole.helper), isTrue);
      expect(a.medicines.byId(m.id)!.carers, contains(raviId));
      ravi.store.mergeAll(asha.store.allRecords);
      expect(r.visible.single.name, 'Nani');
      expect(r.myRole(r.visible.single), CareRole.helper);
      expect(r.medicines.visible.map((Medicine x) => x.name), <String>['Amlodipine']);
      expect(r.medicines.markTaken(m.id, DateTime(2026, 3, 10, 9)), isTrue);
      expect(r.addEntry(c.id, CareEntryKind.doctor, 'Dr Mehta: keep the same dose', at: DateTime(2026, 3, 10, 11)), isNotNull);
      expect(r.setRole(c.id, 'kiran', CareRole.viewer), isFalse, reason: 'only a lead manages the circle');

      asha.store.mergeAll(ravi.store.allRecords);
      final List<CareEntry> log = a.logFor(c.id);
      expect(log.first.kind, CareEntryKind.doctor);
      expect(a.nameOf(log.first.by), 'Ravi');
      expect(a.medicines.byId(m.id)!.stock, 19);

      // The last lead cannot step down; a viewer can read but not write.
      expect(a.setRole(c.id, ashaId.deviceId, CareRole.helper), isFalse);
      expect(a.setRole(c.id, raviId, CareRole.viewer), isTrue);
      ravi.store.mergeAll(asha.store.allRecords);
      expect(r.canWrite(r.byId(c.id)!), isFalse);
      expect(r.logFor(c.id).length, 2);
      expect(r.addEntry(c.id, CareEntryKind.note, 'x'), isNull);

      // Removing him takes away the medicine too; undo puts both back.
      expect(a.setRole(c.id, raviId, null), isTrue);
      expect(a.medicines.byId(m.id)!.carers, isNot(contains(raviId)));
      expect(a.undo(), isTrue);
      expect(a.byId(c.id)!.roles[raviId], CareRole.viewer);
      expect(a.medicines.byId(m.id)!.carers, contains(raviId));

      final String text = a.toText(c.id);
      expect(text, contains('Care log: Nani'));
      expect(text, contains('Ravi (Viewer)'));
      expect(text, contains('Amlodipine: 09:00 · 19 left'));
      expect(text, contains('Doctor by Ravi: Dr Mehta: keep the same dose'));
    });

    test('alone on this phone: the circle works without a family', () {
      final ElderlyCare a = ElderlyCare(space: newSpace(), soloStore: FamilyStore(deviceId: 'me'), now: () => morning);
      final CareCircle c = a.create(name: 'Papa')!;
      expect(a.visible.single.id, c.id);
      expect(a.canManage(c), isTrue);
      final CareEntry e = a.addEntry(c.id, CareEntryKind.visit, 'Lunch together')!;
      expect(a.logFor(c.id).single.text, 'Lunch together');
      expect(a.undo(), isTrue);
      expect(a.logFor(c.id), isEmpty);
      expect(a.removeEntry(e.id), isFalse);
      expect(a.addMedicine(c.id, name: 'Ecosprin', times: <int>[1260])!.memberId, c.parentKey);
      expect(a.undo(), isTrue);
      expect(a.medicinesFor(c), isEmpty);
    });
  });

  testWidgets('screen: start a circle, add a medicine and a visit, share, undo; 44 px', (WidgetTester tester) async {
    final SemanticsHandle sem = tester.ensureSemantics();
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final ElderlyCare care = ElderlyCare(space: newSpace(), soloStore: FamilyStore(deviceId: 'me'), now: () => DateTime(2026, 3, 10, 8));
    String? shared;
    await tester.pumpWidget(MaterialApp(
      home: ElderlyCareScreen(care: care, share: (String t) async => shared = t, save: (String t, String n) async => '/x/$n'),
    ));
    await tester.pumpAndSettle();

    expect(tester.getSize(find.byKey(const Key('care-start'))).height, greaterThanOrEqualTo(44));
    await tester.tap(find.byKey(const Key('care-start')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('care-circle-name')), 'Nani');
    await tester.tap(find.byKey(const Key('care-dialog-ok')));
    await tester.pumpAndSettle();
    expect(find.text('Caring for Nani'), findsOneWidget);

    await tester.tap(find.byKey(const Key('care-med-add')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('care-med-name')), 'Thyronorm');
    await tester.enterText(find.byKey(const Key('care-med-times')), '07:00');
    await tester.tap(find.byKey(const Key('care-med-save')));
    await tester.pumpAndSettle();
    expect(find.text('Thyronorm'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('care-entry')), 'Walk in the evening');
    await tester.tap(find.byKey(const Key('care-log')));
    await tester.pumpAndSettle();
    expect(find.text('Walk in the evening'), findsOneWidget);
    expect(tester.getSize(find.byKey(const Key('care-log'))).height, greaterThanOrEqualTo(44));
    expect(tester.getSize(find.byKey(const Key('care-new'))).height, greaterThanOrEqualTo(44));
    expect(find.byTooltip('New care circle'), findsOneWidget);

    await tester.tap(find.byKey(const Key('result-share')));
    await tester.pumpAndSettle();
    expect(shared, contains('Thyronorm: 07:00'));
    expect(shared, contains('Visit by Me: Walk in the evening'));

    await tester.tap(find.byKey(const Key('result-undo')));
    await tester.pumpAndSettle();
    expect(find.text('Walk in the evening'), findsNothing);
    await tester.pumpAndSettle(const Duration(seconds: 5));
    sem.dispose();
  });
}
