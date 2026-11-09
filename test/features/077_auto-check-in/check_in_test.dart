import 'package:family_utility_app/app/theme.dart';
import 'package:family_utility_app/engines/family/check_ins.dart';
import 'package:family_utility_app/engines/family/family_identity.dart';
import 'package:family_utility_app/engines/family/family_location.dart';
import 'package:family_utility_app/engines/family/family_space.dart';
import 'package:family_utility_app/engines/family/family_store.dart';
import 'package:family_utility_app/engines/family/family_sync.dart';
import 'package:family_utility_app/family/checkin/check_in_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

FamilySpace newSpace() => FamilySpace(
      identityStore: MemoryFamilyIdentityStore(),
      storage: MemoryFamilyStoreStorage(),
      transportsFor: (FamilyIdentity _) => <FamilySyncTransport>[],
    );

const double homeLat = 19.0760;
const double homeLng = 72.8777;

void main() {
  group('engine', () {
    test('manual check-in posts to the feed with the place; undo', () async {
      final FamilySpace s = newSpace();
      await s.create(familyName: 'Shahs', memberName: 'Asha');
      final DateTime now = DateTime(2026, 11, 9, 21, 10);
      final FamilyLocation l = FamilyLocation(space: s, now: () => now);
      final CheckIns c = CheckIns(location: l, space: s, now: () => now);

      final CheckIn a = c.checkIn(note: ' Train was late ');
      expect(c.lineFor(a), 'Asha reached safely · 21:10 · Train was late');
      l.addPlace('Home', homeLat, homeLng);
      await l.report(LocationFix(homeLat, homeLng, now));
      final CheckIn b = c.checkIn();
      expect(b.place, 'Home');
      expect(c.feed.length, 2);
      expect(c.undo(), isTrue);
      expect(c.feed.single.id, a.id);
      expect(c.undo(), isFalse);
    });

    test('automatic check-in on arriving at a place, once, and only when on', () async {
      final FamilySpace s = newSpace();
      await s.create(familyName: 'F', memberName: 'Asha');
      final FamilyLocation l = FamilyLocation(space: s, now: () => DateTime(2026, 11, 9, 20));
      final CheckIns c = CheckIns(location: l, space: s, now: () => DateTime(2026, 11, 9, 20));
      l.addListener(c.onLatestFix);
      l.addPlace('School', homeLat, homeLng);

      await l.report(LocationFix(homeLat + 0.01, homeLng, DateTime(2026, 11, 9, 8)));
      expect(c.feed, isEmpty);
      await l.report(LocationFix(homeLat, homeLng, DateTime(2026, 11, 9, 8, 2)));
      expect(c.feed.single.auto, isTrue);
      expect(c.lineFor(c.feed.single), 'Asha reached School safely (automatic) · 08:02');
      await l.report(LocationFix(homeLat + 0.0001, homeLng, DateTime(2026, 11, 9, 8, 4)));
      expect(c.feed.length, 1);

      // A wobble out and back within 30 minutes does not post again.
      await l.report(LocationFix(homeLat + 0.01, homeLng, DateTime(2026, 11, 9, 8, 6)));
      await l.report(LocationFix(homeLat, homeLng, DateTime(2026, 11, 9, 8, 8)));
      expect(c.feed.length, 1);

      c.setAuto(false);
      expect(c.autoOn, isFalse);
      await l.report(LocationFix(homeLat + 0.01, homeLng, DateTime(2026, 11, 9, 15)));
      await l.report(LocationFix(homeLat, homeLng, DateTime(2026, 11, 9, 15, 30)));
      expect(c.feed.length, 1);
    });

    test('a check-in on one phone reaches the other', () {
      final FamilyStore a = FamilyStore(deviceId: 'phone-a');
      final FamilyStore b = FamilyStore(deviceId: 'phone-b');
      a.put(CheckIns.collection, 'x', <String, Object?>{'by': 'phone-a', 'at': '2026-11-09T20:00:00.000', 'auto': false});
      b.mergeAll(a.allRecords);
      expect(CheckIn.fromRecord(b.get(CheckIns.collection, 'x')!).member, 'phone-a');
    });
  });

  testWidgets('one tap reached safely, feed, toggle, share, save, undo', (WidgetTester tester) async {
    final FamilySpace s = newSpace();
    await tester.runAsync(() => s.create(familyName: 'Shahs', memberName: 'Asha'));
    final FamilyLocation l = FamilyLocation(space: s);
    final CheckIns c = CheckIns(location: l, space: s, now: () => DateTime(2026, 11, 9, 22, 5));
    String? shared;
    String? saved;
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: CheckInScreen(
        checkIns: c,
        share: (String t) async => shared = t,
        save: (String t) async {
          saved = t;
          return '/docs/Family check-ins.txt';
        },
      ),
    ));

    expect(tester.getSize(find.ancestor(of: find.text('Reached safely'), matching: find.byWidgetPredicate((Widget w) => w is FilledButton))).height, greaterThanOrEqualTo(44));
    await tester.tap(find.text('Reached safely'));
    await tester.pumpAndSettle();
    expect(find.text('Asha reached safely · 22:05'), findsOneWidget);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(c.autoOn, isFalse);

    await tester.tap(find.byKey(const Key('result-share')));
    await tester.pumpAndSettle();
    expect(shared, contains('Asha reached safely · 22:05'));
    await tester.tap(find.byKey(const Key('result-save')));
    await tester.pumpAndSettle();
    expect(saved, isNotNull);

    await tester.tap(find.byKey(const Key('result-undo')));
    await tester.pumpAndSettle();
    expect(c.feed, isEmpty);
    expect(find.text('No check-ins in the last 7 days.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });
}
