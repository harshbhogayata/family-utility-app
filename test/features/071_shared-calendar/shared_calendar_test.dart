import 'package:family_utility_app/app/theme.dart';
import 'package:family_utility_app/engines/family/family_identity.dart';
import 'package:family_utility_app/engines/family/family_space.dart';
import 'package:family_utility_app/engines/family/family_store.dart';
import 'package:family_utility_app/engines/family/family_sync.dart';
import 'package:family_utility_app/engines/family/shared_calendar.dart';
import 'package:family_utility_app/family/calendar/shared_calendar_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

FamilySpace newSpace() => FamilySpace(
      identityStore: MemoryFamilyIdentityStore(),
      storage: MemoryFamilyStoreStorage(),
      transportsFor: (FamilyIdentity _) => <FamilySyncTransport>[],
    );

class FakeExport implements PhoneCalendarExport {
  final List<CalendarEvent> added = <CalendarEvent>[];

  @override
  Future<bool> add(CalendarEvent event) async {
    added.add(event);
    return true;
  }
}

class FakeSink implements CalendarReminderSink {
  final List<EventOccurrence> fired = <EventOccurrence>[];

  @override
  Future<void> remind(EventOccurrence occurrence) async => fired.add(occurrence);
}

CalendarEvent ev(String id, DateTime start,
        {String member = 'm1', EventRepeat repeat = EventRepeat.none, Duration? remind, DateTime? until}) =>
    CalendarEvent(
      id: id,
      title: 'Event $id',
      start: start,
      duration: const Duration(hours: 1),
      memberId: member,
      repeat: repeat,
      remindBefore: remind,
      until: until,
    );

void main() {
  group('engine', () {
    test('create, edit, delete and undo go through the family store', () async {
      final FamilySpace s = newSpace();
      await s.create(familyName: 'Shahs', memberName: 'Asha');
      final SharedCalendar cal = SharedCalendar(space: s);

      cal.save(ev('a', DateTime(2026, 11, 10, 9)));
      expect(cal.events.single.title, 'Event a');
      expect(s.store.get(SharedCalendar.collection, 'a'), isNotNull);

      cal.save(cal.event('a')!.copyWith(title: 'Dentist'));
      expect(cal.event('a')!.title, 'Dentist');
      expect(cal.undo(), isTrue);
      expect(cal.event('a')!.title, 'Event a');

      expect(cal.delete('a'), isTrue);
      expect(cal.events, isEmpty);
      expect(cal.undo(), isTrue);
      expect(cal.event('a'), isNotNull);
      expect(cal.undo(), isFalse);
    });

    test('repeats: weekly, monthly skips short months, until is inclusive', () {
      final List<EventOccurrence> weekly = ev('w', DateTime(2026, 11, 2, 18), repeat: EventRepeat.weekly)
          .occurrencesBetween(DateTime(2026, 11, 1), DateTime(2026, 12, 1));
      expect(weekly.map((EventOccurrence o) => o.start.day), <int>[2, 9, 16, 23, 30]);

      final List<EventOccurrence> monthly = ev('m', DateTime(2026, 1, 31, 8), repeat: EventRepeat.monthly)
          .occurrencesBetween(DateTime(2026, 1, 1), DateTime(2026, 6, 1));
      expect(monthly.map((EventOccurrence o) => o.start.month), <int>[1, 3, 5]);

      final List<EventOccurrence> daily =
          ev('d', DateTime(2026, 11, 1, 7), repeat: EventRepeat.daily, until: DateTime(2026, 11, 3))
              .occurrencesBetween(DateTime(2026, 10, 1), DateTime(2027, 1, 1));
      expect(daily.length, 3);

      expect(ev('o', DateTime(2026, 11, 5)).occurrencesBetween(DateTime(2026, 11, 1), DateTime(2026, 12, 1)).length, 1);
    });

    test('reminders fire once when due, also for repeats', () async {
      final FamilySpace s = newSpace();
      await s.create(familyName: 'F', memberName: 'A');
      final SharedCalendar cal = SharedCalendar(space: s);
      cal.save(ev('r', DateTime(2026, 11, 9, 10), repeat: EventRepeat.daily, remind: const Duration(minutes: 30)));

      DateTime now = DateTime(2026, 11, 9, 9, 0);
      final FakeSink sink = FakeSink();
      final CalendarReminderWatcher w = CalendarReminderWatcher(calendar: cal, sink: sink, now: () => now);
      expect(await w.check(), 0);
      now = DateTime(2026, 11, 9, 9, 30);
      expect(await w.check(), 1);
      now = DateTime(2026, 11, 9, 9, 31);
      expect(await w.check(), 0);
      now = DateTime(2026, 11, 10, 9, 31);
      expect(await w.check(), 1);
      expect(sink.fired.map((EventOccurrence o) => o.start.day), <int>[9, 10]);
    });

    test('edits made apart on two phones merge to the same result', () async {
      final FamilyStore a = FamilyStore(deviceId: 'phone-a', now: () => DateTime(2026, 11, 9, 10));
      final FamilyStore b = FamilyStore(deviceId: 'phone-b', now: () => DateTime(2026, 11, 9, 11));
      a.put(SharedCalendar.collection, 'e', ev('e', DateTime(2026, 11, 12, 9)).toFields());
      b.mergeAll(a.allRecords);
      a.put(SharedCalendar.collection, 'e', ev('e', DateTime(2026, 11, 12, 9)).copyWith(title: 'From A').toFields());
      b.put(SharedCalendar.collection, 'e', ev('e', DateTime(2026, 11, 12, 9)).copyWith(title: 'From B').toFields());
      a.mergeAll(b.allRecords);
      b.mergeAll(a.allRecords);
      expect(a.get(SharedCalendar.collection, 'e')!.fields['title'], 'From B');
      expect(b.get(SharedCalendar.collection, 'e')!.fields['title'], 'From B');
    });

    test('clashes for one member and an .ics export with repeat and alarm', () async {
      final FamilySpace s = newSpace();
      await s.create(familyName: 'F', memberName: 'A');
      final SharedCalendar cal = SharedCalendar(space: s, now: () => DateTime.utc(2026, 11, 9));
      cal.save(ev('x', DateTime(2026, 11, 12, 9)));
      cal.save(ev('y', DateTime(2026, 11, 12, 9, 30)));
      cal.save(ev('z', DateTime(2026, 11, 12, 9, 30), member: 'm2'));
      expect(cal.clashes(DateTime(2026, 11, 12), DateTime(2026, 11, 13)).length, 1);

      cal.save(ev('r', DateTime(2026, 11, 13, 7), repeat: EventRepeat.weekly, remind: const Duration(minutes: 10))
          .copyWith(title: 'Swim, pool; lane 2'));
      final String ics = cal.toIcs();
      expect(ics, startsWith('BEGIN:VCALENDAR\r\n'));
      expect(ics, contains('DTSTART:20261113T070000'));
      expect(ics, contains('RRULE:FREQ=WEEKLY'));
      expect(ics, contains('TRIGGER:-PT10M'));
      expect(ics, contains(r'SUMMARY:Swim\, pool\; lane 2'));
      expect('BEGIN:VEVENT'.allMatches(ics).length, 4);
    });
  });

  testWidgets('add an event, see it in the member colour, share, save and undo', (WidgetTester tester) async {
    final FamilySpace s = newSpace();
    await tester.runAsync(() => s.create(familyName: 'Shahs', memberName: 'Asha'));
    final SharedCalendar cal = SharedCalendar(space: s);
    final FakeExport export = FakeExport();
    String? shared;
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: SharedCalendarScreen(
        calendar: cal,
        export: export,
        share: (String ics) async => shared = ics,
        now: () => DateTime(2026, 11, 9, 8, 15),
      ),
    ));

    expect(find.text('Nothing in the next 6 weeks'), findsOneWidget);
    await tester.tap(find.text('Add event'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Title'), 'Swimming');
    await tester.tap(find.byKey(const Key('calendar-Repeat')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Every week').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save event'));
    await tester.pumpAndSettle();

    expect(cal.events.single.title, 'Swimming');
    expect(cal.events.single.start, DateTime(2026, 11, 9, 9));
    expect(cal.events.single.repeat, EventRepeat.weekly);
    expect(find.text('Swimming'), findsWidgets);
    expect(cal.occurrences(DateTime(2026, 11, 9), DateTime(2026, 12, 21)).length, 6);
    expect(find.text('Mon 9 Nov'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'^Swimming, Mon 9 Nov, 09:00–10:00, Asha, every week')), findsOneWidget);

    // Touch targets of the result bar and event rows are at least 44 px.
    expect(tester.getSize(find.byKey(const Key('result-save'))).height, greaterThanOrEqualTo(44));
    expect(tester.getSize(find.widgetWithText(ListTile, 'Swimming').first).height, greaterThanOrEqualTo(44));

    await tester.tap(find.byKey(const Key('result-share')));
    await tester.pumpAndSettle();
    expect(shared, contains('SUMMARY:Swimming'));

    await tester.tap(find.byKey(const Key('result-save')));
    await tester.pumpAndSettle();
    expect(export.added.single.title, 'Swimming');

    await tester.tap(find.byKey(const Key('result-undo')));
    await tester.pumpAndSettle();
    expect(cal.events, isEmpty);
    expect(find.text('Nothing in the next 6 weeks'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });
}
