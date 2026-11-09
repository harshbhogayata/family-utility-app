import 'package:family_utility_app/engines/family/family_identity.dart';
import 'package:family_utility_app/engines/family/family_space.dart';
import 'package:family_utility_app/engines/family/family_store.dart';
import 'package:family_utility_app/engines/family/family_sync.dart';
import 'package:family_utility_app/engines/records/occasions.dart';
import 'package:family_utility_app/records/occasions/occasions_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

FamilySpace newSpace() => FamilySpace(
      identityStore: MemoryFamilyIdentityStore(),
      storage: MemoryFamilyStoreStorage(),
      transportsFor: (FamilyIdentity _) => <FamilySyncTransport>[],
    );

class RecordingReminders implements OccasionReminderScheduler {
  List<OccasionReminder> last = <OccasionReminder>[];
  @override
  Future<void> replaceAll(List<OccasionReminder> reminders) async => last = reminders;
}

class FakeContacts implements ContactDatesSource {
  @override
  Future<List<ContactDate>> read() async => const <ContactDate>[
        ContactDate(name: 'Meera Shah', kind: OccasionKind.birthday, month: 4, day: 2, year: 1990, phone: '+91 98000 00000'),
        ContactDate(name: 'Meera Shah', kind: OccasionKind.birthday, month: 4, day: 2),
        ContactDate(name: 'Raj and Priya', kind: OccasionKind.anniversary, month: 12, day: 9),
        ContactDate(name: 'Bad', kind: OccasionKind.birthday, month: 2, day: 30),
      ];
}

Occasions make({DateTime Function()? now, OccasionReminderScheduler? reminders}) => Occasions(
      space: newSpace(),
      soloStore: FamilyStore(deviceId: 'me'),
      reminders: reminders ?? const NoOccasionReminders(),
      contacts: FakeContacts(),
      now: now ?? () => DateTime(2026, 3, 20, 10),
    );

void main() {
  group('engine', () {
    test('next dates, days left, 29 February, ordinals', () {
      const Occasion leap = Occasion(id: 'x', name: 'L', kind: OccasionKind.birthday, month: 2, day: 29);
      expect(leap.nextFrom(DateTime(2026, 1, 1)), DateTime(2026, 2, 28));
      expect(leap.nextFrom(DateTime(2027, 3, 1)), DateTime(2028, 2, 29));
      const Occasion d = Occasion(id: 'y', name: 'D', kind: OccasionKind.birthday, month: 3, day: 20);
      expect(d.nextFrom(DateTime(2026, 3, 20, 23)), DateTime(2026, 3, 20));
      expect(d.nextFrom(DateTime(2026, 3, 21)), DateTime(2027, 3, 20));
      expect(Occasions.ordinal(1), '1st');
      expect(Occasions.ordinal(12), '12th');
      expect(Occasions.ordinal(22), '22nd');
      expect(Occasions.ordinal(63), '63rd');
      expect(Occasions.validDate(2, 29), isTrue);
      expect(Occasions.validDate(4, 31), isFalse);
    });

    test('reminders 7 days and 1 day ahead; gift ideas; wish; undo', () async {
      final RecordingReminders rec = RecordingReminders();
      final Occasions o = make(reminders: rec);
      expect(o.add(name: ' ', kind: OccasionKind.birthday, month: 1, day: 1), isNull);
      expect(o.add(name: 'X', kind: OccasionKind.birthday, month: 2, day: 30), isNull);
      final Occasion nani = o.add(name: 'Nani Devi', kind: OccasionKind.birthday, month: 4, day: 1, year: 1956)!;
      await Future<void>.delayed(Duration.zero);
      expect(rec.last.map((OccasionReminder r) => r.at).toList(), <DateTime>[DateTime(2026, 3, 25, 9), DateTime(2026, 3, 31, 9)]);
      expect(rec.last.first.title, "Nani Devi's birthday in 7 days");
      expect(rec.last.last.title, "Nani Devi's birthday tomorrow");
      expect(o.daysUntil(nani), 12);

      expect(o.addGift(nani.id, 'Shawl'), isTrue);
      expect(o.addGift(nani.id, ' '), isFalse);
      await Future<void>.delayed(Duration.zero);
      expect(rec.last.first.body, 'Gift ideas: Shawl');
      expect(o.draftWish(o.byId(nani.id)!), startsWith('Happy 70th birthday, Nani!'));
      expect(o.undo(), isTrue);
      expect(o.byId(nani.id)!.gifts, isEmpty);

      final Occasion ann = o.add(name: 'Mum and Dad', kind: OccasionKind.anniversary, month: 3, day: 22)!;
      expect(o.draftWish(ann), startsWith('Happy anniversary, Mum!'));
      await Future<void>.delayed(Duration.zero);
      // Only the 1-day reminder is still ahead.
      expect(rec.last.where((OccasionReminder r) => r.title.startsWith('Mum')).map((OccasionReminder r) => r.at),
          <DateTime>[DateTime(2026, 3, 21, 9)]);
      expect(o.upcoming.first.name, 'Mum and Dad');
      expect(o.toText(), contains('- 22 Mar: Mum and Dad (Anniversary)'));
    });

    test('import from contacts skips duplicates and bad dates; one undo', () async {
      final Occasions o = make();
      o.add(name: 'Raj and Priya', kind: OccasionKind.anniversary, month: 12, day: 9);
      expect(await o.importFromContacts(), 1);
      expect(o.all.where((Occasion x) => x.name == 'Meera Shah').single.year, 1990);
      expect(await o.importFromContacts(), 0);
      expect(o.undo(), isTrue);
      expect(o.all.length, 1);
    });

    test('dates are shared with the family', () async {
      final FamilySpace a = newSpace();
      await a.create(familyName: 'Shahs', memberName: 'Asha');
      final Occasions oa = Occasions(space: a, now: () => DateTime(2026, 3, 20));
      oa.add(name: 'Ravi', kind: OccasionKind.birthday, month: 6, day: 5);
      final FamilySpace b = newSpace();
      await b.create(familyName: 'x', memberName: 'Ravi');
      b.store.mergeAll(a.store.allRecords);
      expect(Occasions(space: b, now: () => DateTime(2026, 3, 20)).all.single.name, 'Ravi');
    });
  });

  testWidgets('screen: add a date, gift idea, send wish, share list, undo; 44 px', (WidgetTester tester) async {
    final SemanticsHandle sem = tester.ensureSemantics();
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final Occasions o = make();
    final List<String> shared = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: OccasionsScreen(occasions: o, share: (String t) async => shared.add(t), save: (String t, String n) async => '/x/$n'),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('occ-add')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('occ-name')), 'Nani');
    await tester.enterText(find.byKey(const Key('occ-date')), '27/03/1956');
    await tester.tap(find.byKey(const Key('occ-save')));
    await tester.pumpAndSettle();
    final Occasion n = o.all.single;
    expect(find.text('Birthday · 27 Mar 1956 · In 7 days'), findsOneWidget);

    await tester.tap(find.byKey(Key('occ-gift-${n.id}')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('occ-gift')), 'Reading glasses');
    await tester.tap(find.byKey(const Key('occ-gift-save')));
    await tester.pumpAndSettle();
    expect(find.text('Reading glasses'), findsOneWidget);

    expect(tester.getSize(find.byKey(Key('occ-send-${n.id}'))).height, greaterThanOrEqualTo(44));
    await tester.tap(find.byKey(Key('occ-send-${n.id}')));
    await tester.pumpAndSettle();
    expect(shared.last, startsWith('Happy 70th birthday, Nani!'));

    await tester.tap(find.byKey(const Key('result-share')));
    await tester.pumpAndSettle();
    expect(shared.last, contains('27 Mar 1956: Nani (Birthday) · gifts: Reading glasses'));

    await tester.tap(find.byKey(const Key('result-undo')));
    await tester.pumpAndSettle();
    expect(find.text('Reading glasses'), findsNothing);
    expect(find.byTooltip('Add from contacts'), findsOneWidget);
    await tester.pumpAndSettle(const Duration(seconds: 5));
    sem.dispose();
  });
}
