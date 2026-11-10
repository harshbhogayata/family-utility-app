import 'package:family_utility_app/engines/family/family_identity.dart';
import 'package:family_utility_app/engines/family/family_space.dart';
import 'package:family_utility_app/engines/family/family_store.dart';
import 'package:family_utility_app/engines/family/family_sync.dart';
import 'package:family_utility_app/engines/family/shared_calendar.dart';
import 'package:family_utility_app/engines/records/doctor_visits.dart';
import 'package:family_utility_app/records/doctor_visits/doctor_visits_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

FamilySpace newSpace() => FamilySpace(
      identityStore: MemoryFamilyIdentityStore(),
      storage: MemoryFamilyStoreStorage(),
      transportsFor: (FamilyIdentity _) => <FamilySyncTransport>[],
    );

DateTime fixedNow() => DateTime(2026, 3, 20, 10);

DoctorVisits make({FamilySpace? space}) {
  final FamilySpace s = space ?? newSpace();
  return DoctorVisits(
    space: s,
    soloStore: FamilyStore(deviceId: 'me'),
    calendar: SharedCalendar(space: s, now: fixedNow),
    now: fixedNow,
  );
}

void main() {
  group('engine', () {
    test('visit with prescription; next appointment on the calendar with a reminder', () {
      final DoctorVisits d = make();
      expect(d.add(person: ' ', doctor: ''), isNull);
      expect(d.add(person: 'Nani', doctor: 'Dr Rao', nextAt: DateTime(2026, 3, 1)), isNull);

      final DoctorVisit v = d.add(
        person: 'Nani',
        doctor: 'Dr Rao',
        date: DateTime(2026, 3, 18),
        notes: 'BP slightly high',
        nextAt: DateTime(2026, 4, 2, 11, 30),
      )!;
      final CalendarEvent ev = d.calendar.event(v.eventId)!;
      expect(ev.title, 'Doctor: Dr Rao (Nani)');
      expect(ev.start, DateTime(2026, 4, 2, 11, 30));
      expect(ev.remindBefore, const Duration(days: 1));
      expect(d.calendar.occurrences(DateTime(2026, 4, 1), DateTime(2026, 4, 3)).single.remindAt, DateTime(2026, 4, 1, 11, 30));

      expect(d.attachPrescriptions(v.id, <String>[]), isFalse);
      expect(d.attachPrescriptions(v.id, <String>['/app/scans/rx_1.pdf']), isTrue);
      expect(d.byId(v.id)!.prescriptions, <String>['/app/scans/rx_1.pdf']);
      expect(d.undo(), isTrue);
      expect(d.byId(v.id)!.prescriptions, isEmpty);

      expect(d.setNext(v.id, DateTime(2026, 4, 9, 9)), isTrue);
      expect(d.calendar.event(v.eventId)!.start, DateTime(2026, 4, 9, 9));
      expect(d.undo(), isTrue);
      expect(d.calendar.event(v.eventId)!.start, DateTime(2026, 4, 2, 11, 30));

      expect(d.setNext(v.id, null), isTrue);
      expect(d.calendar.event(v.eventId), isNull);
      expect(d.upcoming, isEmpty);
      expect(d.undo(), isTrue);
      expect(d.upcoming.single.id, v.id);

      expect(d.remove(v.id), isTrue);
      expect(d.calendar.event(v.eventId), isNull);
      expect(d.undo(), isTrue);
      expect(d.byId(v.id), isNotNull);
      expect(d.calendar.event(v.eventId), isNotNull);

      d.attachPrescriptions(v.id, <String>['/app/scans/rx_1.pdf']);
      final String text = d.toText();
      expect(text, contains('18 Mar 2026: Nani with Dr Rao'));
      expect(text, contains('Prescriptions: rx_1.pdf'));
      expect(text, contains('Next appointment: 2 Apr 2026, 11:30'));
    });

    test('visits are shared with the family', () async {
      final FamilySpace a = newSpace();
      await a.create(familyName: 'Shahs', memberName: 'Asha');
      make(space: a).add(person: 'Dad', doctor: 'Dr Iyer');
      final FamilySpace b = newSpace();
      await b.create(familyName: 'x', memberName: 'Ravi');
      b.store.mergeAll(a.store.allRecords);
      expect(make(space: b).all.single.doctor, 'Dr Iyer');
    });
  });

  testWidgets('screen: add visit, scan prescription, set appointment, share, undo; 44 px', (WidgetTester tester) async {
    final SemanticsHandle sem = tester.ensureSemantics();
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final DoctorVisits d = make();
    final List<(String, List<String>)> shared = <(String, List<String>)>[];
    await tester.pumpWidget(MaterialApp(
      home: DoctorVisitsScreen(
        visits: d,
        scan: () async => <String>['/app/scans/rx_page.pdf'],
        share: (String t, List<String> f) async => shared.add((t, f)),
        save: (String t, String n) async => '/x/$n',
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('dv-add')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('dv-person')), 'Nani');
    await tester.enterText(find.byKey(const Key('dv-doctor')), 'Dr Rao');
    await tester.enterText(find.byKey(const Key('dv-date')), '18/03/2026');
    await tester.enterText(find.byKey(const Key('dv-notes')), 'Cough');
    await tester.tap(find.byKey(const Key('dv-save')));
    await tester.pumpAndSettle();
    final DoctorVisit v = d.all.single;
    expect(find.text('Nani · Dr Rao'), findsOneWidget);

    expect(tester.getSize(find.byKey(Key('dv-scan-${v.id}'))).height, greaterThanOrEqualTo(44));
    await tester.tap(find.byKey(Key('dv-scan-${v.id}')));
    await tester.pumpAndSettle();
    expect(find.text('rx_page.pdf'), findsOneWidget);

    await tester.tap(find.byKey(Key('dv-appt-${v.id}')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('dv-next-when')), '02/04/2026 11:30');
    await tester.tap(find.byKey(const Key('dv-next-save')));
    await tester.pumpAndSettle();
    expect(find.text('Next: 2 Apr 2026, 11:30'), findsOneWidget);
    expect(d.calendar.event(v.eventId), isNotNull);

    await tester.tap(find.byKey(Key('dv-share-${v.id}')));
    await tester.pumpAndSettle();
    expect(shared.last.$1, contains('Nani with Dr Rao'));
    expect(shared.last.$2, <String>['/app/scans/rx_page.pdf']);

    await tester.tap(find.byKey(const Key('result-share')));
    await tester.pumpAndSettle();
    expect(shared.last.$1, startsWith('Doctor visits'));

    await tester.tap(find.byKey(const Key('result-undo')));
    await tester.pumpAndSettle();
    expect(find.text('Next: 2 Apr 2026, 11:30'), findsNothing);
    expect(d.calendar.event(v.eventId), isNull);
    await tester.pumpAndSettle(const Duration(seconds: 5));
    sem.dispose();
  });
}
