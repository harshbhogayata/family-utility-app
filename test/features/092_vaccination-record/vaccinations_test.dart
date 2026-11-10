import 'package:family_utility_app/engines/family/family_identity.dart';
import 'package:family_utility_app/engines/family/family_space.dart';
import 'package:family_utility_app/engines/family/family_store.dart';
import 'package:family_utility_app/engines/family/family_sync.dart';
import 'package:family_utility_app/engines/records/vaccinations.dart';
import 'package:family_utility_app/records/vaccinations/vaccinations_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

FamilySpace newSpace() => FamilySpace(
      identityStore: MemoryFamilyIdentityStore(),
      storage: MemoryFamilyStoreStorage(),
      transportsFor: (FamilyIdentity _) => <FamilySyncTransport>[],
    );

class RecordingReminders implements VaccineReminderScheduler {
  List<VaccineReminder> last = <VaccineReminder>[];
  @override
  Future<void> replaceAll(List<VaccineReminder> reminders) async => last = reminders;
}

Vaccinations make({VaccineReminderScheduler? reminders}) => Vaccinations(
      space: newSpace(),
      soloStore: FamilyStore(deviceId: 'me'),
      reminders: reminders ?? const NoVaccineReminders(),
      now: () => DateTime(2026, 3, 20, 10),
    );

DoseState stateOf(Vaccinations v, VaccinePerson p, String id) => v.schedule(p).firstWhere((DoseStatus s) => s.dose.id == id).state;

void main() {
  group('engine', () {
    test('the preloaded schedules', () {
      expect(IndianSchedule.child.length, greaterThanOrEqualTo(25));
      expect(IndianSchedule.child.map((VaccineDose d) => d.name), containsAll(<String>['BCG', 'Pentavalent 1', 'MR 1', 'DPT booster 2']));
      expect(IndianSchedule.adult.map((VaccineDose d) => d.id), containsAll(<String>['td', 'flu', 'hepb1']));
    });

    test('child: due dates from birth, overdue and due soon, reminders, certificates, undo', () async {
      final RecordingReminders rec = RecordingReminders();
      final Vaccinations v = make(reminders: rec);
      expect(v.addPerson(name: ' ', born: DateTime(2026, 1, 15)), isNull);
      expect(v.addPerson(name: 'X', born: DateTime(2027, 1, 1)), isNull);
      final VaccinePerson baby = v.addPerson(name: 'Aarav', born: DateTime(2026, 1, 15))!;
      expect(baby.kind, ScheduleKind.child);
      final DoseStatus penta1 = v.schedule(baby).firstWhere((DoseStatus s) => s.dose.id == 'penta1');
      expect(penta1.due, DateTime(2026, 2, 26));
      expect(penta1.state, DoseState.overdue);
      expect(stateOf(v, baby, 'penta2'), DoseState.dueSoon);
      expect(stateOf(v, baby, 'penta3'), DoseState.later);

      expect(v.markGiven(baby.id, 'bcg', on: DateTime(2026, 4, 1)), isFalse); // future
      expect(v.markGiven(baby.id, 'bcg', on: DateTime(2025, 1, 1)), isFalse); // before birth
      expect(v.markGiven(baby.id, 'nope', on: DateTime(2026, 1, 15)), isFalse);
      for (final String id in <String>['bcg', 'opv0', 'hepb0']) {
        expect(v.markGiven(baby.id, id, on: DateTime(2026, 1, 15)), isTrue);
      }
      expect(v.attachCertificate(baby.id, 'bcg', '/scans/bcg.pdf'), isTrue);
      expect(v.attachCertificate(baby.id, 'penta1', '/scans/x.pdf'), isFalse);
      final VaccinePerson b2 = v.byId(baby.id)!;
      expect(b2.given['bcg']!.certificates, <String>['/scans/bcg.pdf']);
      expect(stateOf(v, b2, 'bcg'), DoseState.given);

      final List<(VaccinePerson, DoseStatus)> due = v.dueNow();
      expect(due.first.$2.due, DateTime(2026, 2, 26));
      expect(due.where(((VaccinePerson, DoseStatus) d) => d.$2.state == DoseState.overdue).length, 5);
      expect(due.where(((VaccinePerson, DoseStatus) d) => d.$2.state == DoseState.dueSoon).length, 3);

      await Future<void>.delayed(Duration.zero);
      final VaccineReminder first = rec.last.first;
      expect(first.at, DateTime(2026, 3, 26, 9));
      expect(first.title, contains('Aarav: '));
      expect(first.title, contains('is due today'));
      expect(rec.last.any((VaccineReminder r) => r.at == DateTime(2026, 4, 16, 9) && r.title == 'Aarav: Pentavalent 3 due in a week'), isTrue);
      expect(rec.last.every((VaccineReminder r) => r.at.isAfter(DateTime(2026, 3, 20, 10))), isTrue);

      expect(v.undo(), isTrue);
      expect(v.byId(baby.id)!.given['bcg']!.certificates, isEmpty);
      expect(v.toText(), contains('- BCG (At birth): given 15 Jan 2026'));
      expect(v.toText(), contains('- Pentavalent 1 (6 weeks): overdue since 26 Feb 2026'));
    });

    test('adult: boosters fall due again after each dose; Hep B series follows dose 1', () {
      final Vaccinations v = make();
      final VaccinePerson mum = v.addPerson(name: 'Asha', born: DateTime(1990, 5, 1))!;
      expect(mum.kind, ScheduleKind.adult);
      expect(stateOf(v, mum, 'td'), DoseState.dueSoon);
      expect(stateOf(v, mum, 'hepb2'), DoseState.later);
      expect(v.markGiven(mum.id, 'flu', on: DateTime(2025, 12, 1)), isTrue);
      final DoseStatus flu = v.schedule(v.byId(mum.id)!).firstWhere((DoseStatus s) => s.dose.id == 'flu');
      expect(flu.state, DoseState.given);
      expect(flu.due, DateTime(2026, 12, 1));
      expect(v.markGiven(mum.id, 'hepb1', on: DateTime(2026, 3, 1)), isTrue);
      final DoseStatus hepb2 = v.schedule(v.byId(mum.id)!).firstWhere((DoseStatus s) => s.dose.id == 'hepb2');
      expect(hepb2.due, DateTime(2026, 3, 31));
      expect(hepb2.state, DoseState.dueSoon);
      expect(v.unmark(mum.id, 'flu'), isTrue);
      expect(stateOf(v, v.byId(mum.id)!, 'flu'), DoseState.dueSoon);
      expect(v.removePerson(mum.id), isTrue);
      expect(v.people, isEmpty);
      expect(v.undo(), isTrue);
      expect(v.people.single.name, 'Asha');
    });

    test('shared with the family', () async {
      final FamilySpace a = newSpace();
      await a.create(familyName: 'Shahs', memberName: 'Asha');
      Vaccinations(space: a, now: () => DateTime(2026, 3, 20)).addPerson(name: 'Aarav', born: DateTime(2026, 1, 15));
      final FamilySpace b = newSpace();
      await b.create(familyName: 'x', memberName: 'Ravi');
      b.store.mergeAll(a.store.allRecords);
      expect(Vaccinations(space: b, now: () => DateTime(2026, 3, 20)).people.single.name, 'Aarav');
    });
  });

  testWidgets('screen: add a child, due now, mark given, scan certificate, share, undo; 44 px', (WidgetTester tester) async {
    final SemanticsHandle sem = tester.ensureSemantics();
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final Vaccinations v = make();
    final List<String> shared = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: VaccinationsScreen(
        vaccinations: v,
        scan: (BuildContext _) async => <String>['/scans/bcg.pdf'],
        share: (String t) async => shared.add(t),
        save: (String t, String n) async => '/x/$n',
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('vx-add')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('vx-name')), 'Aarav');
    await tester.enterText(find.byKey(const Key('vx-born')), '15/01/2026');
    await tester.tap(find.byKey(const Key('vx-save')));
    await tester.pumpAndSettle();
    final VaccinePerson baby = v.people.single;
    expect(find.text('Due now'), findsOneWidget);
    expect(find.byKey(Key('vx-due-${baby.id}-bcg')), findsOneWidget);

    await tester.tap(find.byKey(Key('vx-${baby.id}')));
    await tester.pumpAndSettle();
    final Finder give = find.byKey(const Key('vx-give-bcg'));
    expect(tester.getSize(give).height, greaterThanOrEqualTo(44));
    await tester.tap(give);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byKey(const Key('vx-given-on'))).controller!.text, '15/01/2026');
    await tester.tap(find.byKey(const Key('vx-given-save')));
    await tester.pumpAndSettle();
    expect(find.text('Given 15 Jan 2026'), findsOneWidget);

    await tester.tap(find.byKey(const Key('vx-cert-bcg')));
    await tester.pumpAndSettle();
    expect(find.text('1 certificate scan attached'), findsOneWidget);

    await tester.tap(find.byKey(const Key('result-share')));
    await tester.pumpAndSettle();
    expect(shared.single, contains('Aarav (born 15 Jan 2026)'));
    expect(shared.single, contains('- BCG (At birth): given 15 Jan 2026'));

    await tester.tap(find.byKey(const Key('result-undo')));
    await tester.pumpAndSettle();
    expect(find.text('1 certificate scan attached'), findsNothing);
    await tester.pumpAndSettle(const Duration(seconds: 5));
    sem.dispose();
  });
}
