import 'package:family_utility_app/engines/family/family_identity.dart';
import 'package:family_utility_app/engines/family/family_space.dart';
import 'package:family_utility_app/engines/family/family_store.dart';
import 'package:family_utility_app/engines/family/family_sync.dart';
import 'package:family_utility_app/engines/records/maintenance_log.dart';
import 'package:family_utility_app/records/maintenance/maintenance_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

FamilySpace newSpace() => FamilySpace(
      identityStore: MemoryFamilyIdentityStore(),
      storage: MemoryFamilyStoreStorage(),
      transportsFor: (FamilyIdentity _) => <FamilySyncTransport>[],
    );

class RecordingReminders implements UpkeepReminderScheduler {
  List<UpkeepReminder> last = <UpkeepReminder>[];
  @override
  Future<void> replaceAll(List<UpkeepReminder> reminders) async => last = reminders;
}

MaintenanceLog make({UpkeepReminderScheduler? reminders}) => MaintenanceLog(
      space: newSpace(),
      soloStore: FamilyStore(deviceId: 'me'),
      reminders: reminders ?? const NoUpkeepReminders(),
      now: () => DateTime(2026, 1, 20, 10),
    );

void main() {
  group('engine', () {
    test('intervals, next due, reminders, service contact, history, undo', () async {
      final RecordingReminders rec = RecordingReminders();
      final MaintenanceLog m = make(reminders: rec);
      expect(m.add(name: '', kind: UpkeepKind.ac, everyMonths: 5), isNull);
      expect(m.add(name: '', kind: UpkeepKind.ac, everyMonths: 3, lastDone: DateTime(2026, 2, 1)), isNull);

      final UpkeepItem ac = m.add(
        name: 'Bedroom AC',
        kind: UpkeepKind.ac,
        everyMonths: 3,
        lastDone: DateTime(2025, 11, 1),
        contactName: 'Raju',
        contactPhone: '+91 98450 12345',
      )!;
      final UpkeepItem filter = m.add(name: '', kind: UpkeepKind.waterFilter, everyMonths: 6, lastDone: DateTime(2025, 7, 10))!;
      final UpkeepItem pest = m.add(name: '', kind: UpkeepKind.pestControl, everyMonths: 12, firstDue: DateTime(2026, 1, 22))!;
      expect(ac.nextDue, DateTime(2026, 2, 1));
      expect(ac.visits.single.on, DateTime(2025, 11, 1));
      expect(filter.name, 'Water filter');
      expect(filter.nextDue, DateTime(2026, 1, 10));
      expect(m.state(filter), UpkeepState.overdue);
      expect(m.state(pest), UpkeepState.dueSoon);
      expect(m.state(ac), UpkeepState.later);
      expect(ac.callUri, Uri(scheme: 'tel', path: '+919845012345'));
      expect(pest.callUri, isNull);
      expect(m.all.map((UpkeepItem i) => i.name), <String>['Water filter', 'Pest control', 'Bedroom AC']);

      await Future<void>.delayed(Duration.zero);
      expect(rec.last.map((UpkeepReminder r) => (r.title, r.at)).toList(), <(String, DateTime)>[
        ('Water filter is overdue', DateTime(2026, 1, 21, 9)),
        ('Pest control is due today', DateTime(2026, 1, 22, 9)),
        ('Bedroom AC is due in 3 days', DateTime(2026, 1, 29, 9)),
        ('Bedroom AC is due today', DateTime(2026, 2, 1, 9)),
      ]);
      expect(rec.last[2].body, 'Due 1 Feb 2026 · call Raju. Tap to log the service.');
      expect(rec.last.every((UpkeepReminder r) => r.payload.startsWith(MaintenanceLog.payloadPrefix)), isTrue);

      expect(m.markDone(filter.id, paise: 0), isFalse);
      expect(m.markDone(filter.id, on: DateTime(2026, 1, 25)), isFalse); // not in the future
      expect(m.markDone(filter.id, paise: 45000, note: ' new candle '), isTrue);
      final UpkeepItem f2 = m.byId(filter.id)!;
      expect(f2.nextDue, DateTime(2026, 7, 20));
      expect(f2.visits.last.note, 'new candle');
      expect(MaintenanceLog.spent(f2), 45000);
      expect(m.state(f2), UpkeepState.later);

      // A late entry for a past service slots into the history in order.
      expect(m.markDone(ac.id, on: DateTime(2025, 12, 1), paise: 120000), isTrue);
      expect(m.byId(ac.id)!.visits.map((ServiceVisit v) => v.on), <DateTime>[DateTime(2025, 11, 1), DateTime(2025, 12, 1)]);
      expect(m.byId(ac.id)!.nextDue, DateTime(2026, 3, 1));
      expect(m.undo(), isTrue);
      expect(m.byId(ac.id)!.nextDue, DateTime(2026, 2, 1));

      expect(m.setContact(pest.id, name: 'HiCare', phone: '1800 123 456'), isTrue);
      expect(m.byId(pest.id)!.callUri, Uri(scheme: 'tel', path: '1800123456'));

      final String text = m.toText();
      expect(text, contains('- Water filter: every 6 months, next 20 Jul 2026'));
      expect(text, contains('    done 20 Jan 2026 · ₹450 · new candle'));
      expect(text, contains('- Bedroom AC: every 3 months, next 1 Feb 2026 · Raju +91 98450 12345'));

      expect(m.remove(pest.id), isTrue);
      expect(m.byId(pest.id), isNull);
      expect(m.undo(), isTrue);
      expect(m.byId(pest.id)!.contactName, 'HiCare');
    });

    test('the household sees the same list', () async {
      final FamilySpace a = newSpace();
      await a.create(familyName: 'Shahs', memberName: 'Asha');
      MaintenanceLog(space: a, now: () => DateTime(2026, 1, 20)).add(name: 'RO', kind: UpkeepKind.waterFilter, everyMonths: 4);
      final FamilySpace c = newSpace();
      await c.create(familyName: 'x', memberName: 'Ravi');
      c.store.mergeAll(a.store.allRecords);
      final UpkeepItem i = MaintenanceLog(space: c, now: () => DateTime(2026, 1, 20)).all.single;
      expect((i.name, i.everyMonths, i.nextDue), ('RO', 4, DateTime(2026, 1, 20)));
    });
  });

  testWidgets('screen: add item, call, log service, share, undo; 44 px', (WidgetTester tester) async {
    final SemanticsHandle sem = tester.ensureSemantics();
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final MaintenanceLog m = make();
    final List<String> shared = <String>[];
    final List<Uri> calls = <Uri>[];
    await tester.pumpWidget(MaterialApp(
      home: MaintenanceScreen(
        log: m,
        call: (Uri u) async {
          calls.add(u);
          return true;
        },
        share: (String t) async => shared.add(t),
        save: (String t, String n) async => '/x/$n',
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('Nothing logged yet'), findsOneWidget);

    await tester.tap(find.byKey(const Key('upkeep-add')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('upkeep-last')), '01/11/2025');
    await tester.enterText(find.byKey(const Key('upkeep-contact')), 'Raju');
    await tester.enterText(find.byKey(const Key('upkeep-phone')), '98450 12345');
    await tester.tap(find.byKey(const Key('upkeep-save')));
    await tester.pumpAndSettle();
    final UpkeepItem i = m.all.single;
    expect(find.text('AC service · Every 3 months · next 1 Feb 2026'), findsOneWidget);
    expect(find.text('Due in 12 days'), findsOneWidget);
    expect(find.text('Service: Raju · 98450 12345'), findsOneWidget);

    expect(tester.getSize(find.byKey(Key('upkeep-call-${i.id}'))).height, greaterThanOrEqualTo(44));
    await tester.tap(find.byKey(Key('upkeep-call-${i.id}')));
    await tester.pumpAndSettle();
    expect(calls.single, Uri(scheme: 'tel', path: '9845012345'));

    expect(tester.getSize(find.byKey(Key('upkeep-done-${i.id}'))).height, greaterThanOrEqualTo(44));
    await tester.tap(find.byKey(Key('upkeep-done-${i.id}')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('upkeep-cost')), '1200');
    await tester.enterText(find.byKey(const Key('upkeep-note')), 'Gas top-up');
    await tester.tap(find.byKey(const Key('upkeep-done-save')));
    await tester.pumpAndSettle();
    expect(find.text('Done 20 Jan 2026 · ₹1,200 · Gas top-up'), findsOneWidget);
    expect(find.text('AC service · Every 3 months · next 20 Apr 2026'), findsOneWidget);
    expect(find.text('Spent ₹1,200 in all'), findsOneWidget);

    await tester.tap(find.byKey(const Key('result-share')));
    await tester.pumpAndSettle();
    expect(shared.last, contains('- AC service: every 3 months, next 20 Apr 2026 · Raju 98450 12345'));

    await tester.tap(find.byKey(const Key('result-undo')));
    await tester.pumpAndSettle();
    expect(find.text('AC service · Every 3 months · next 1 Feb 2026'), findsOneWidget);
    await tester.pumpAndSettle(const Duration(seconds: 5));
    sem.dispose();
  });
}
