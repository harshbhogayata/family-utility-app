import 'package:family_utility_app/app/theme.dart';
import 'package:family_utility_app/engines/family/family_identity.dart';
import 'package:family_utility_app/engines/family/family_location.dart';
import 'package:family_utility_app/engines/family/family_space.dart';
import 'package:family_utility_app/engines/family/family_store.dart';
import 'package:family_utility_app/engines/family/family_sync.dart';
import 'package:family_utility_app/family/location/family_location_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

FamilySpace newSpace() => FamilySpace(
      identityStore: MemoryFamilyIdentityStore(),
      storage: MemoryFamilyStoreStorage(),
      transportsFor: (FamilyIdentity _) => <FamilySyncTransport>[],
    );

class FixedSource implements PositionSource {
  FixedSource(this.fix);
  LocationFix? fix;

  @override
  Future<LocationFix?> current() async => fix;
}

class ListSink implements PlaceEventSink {
  final List<String> out = <String>[];

  @override
  Future<void> notify(String text) async => out.add(text);
}

const double homeLat = 19.0760;
const double homeLng = 72.8777;

void main() {
  group('engine', () {
    test('sharing toggle; only shared when on; 2 min moving, 15 min still', () async {
      final FamilySpace s = newSpace();
      await s.create(familyName: 'Shahs', memberName: 'Asha');
      final FamilyLocation l = FamilyLocation(space: s, now: () => DateTime(2026, 11, 9, 12));
      final DateTime t = DateTime(2026, 11, 9, 11);

      await l.report(LocationFix(homeLat, homeLng, t));
      expect(s.store.get(FamilyLocation.locations, s.identity!.deviceId), isNull);
      expect(l.trail.length, 1);

      l.setSharing(true);
      expect(l.sharing, isTrue);
      expect(await l.report(LocationFix(homeLat + 0.001, homeLng, t)), FamilyLocation.movingEvery); // ~110 m
      expect(await l.report(LocationFix(homeLat + 0.0011, homeLng, t)), FamilyLocation.stillEvery); // ~11 m
      expect(l.members.single.fix!.lat, closeTo(homeLat + 0.0011, 1e-9));

      l.setSharing(false);
      final FamilyRecord r = s.store.get(FamilyLocation.locations, s.identity!.deviceId)!;
      expect(r.fields.containsKey('lat'), isFalse);
      expect(l.members.single.fix, isNull);
      expect(l.lineFor(l.members.single), 'Not sharing');
      expect(l.undo(), isTrue);
      expect(l.sharing, isTrue);
    });

    test('history kept 7 days, on this phone only', () async {
      final MemoryLocationHistoryStore h = MemoryLocationHistoryStore()
        ..fixes = <LocationFix>[
          LocationFix(1, 1, DateTime(2026, 11, 1)),
          LocationFix(1, 1, DateTime(2026, 11, 5)),
        ];
      final FamilySpace s = newSpace();
      await s.create(familyName: 'F', memberName: 'A');
      final FamilyLocation l = FamilyLocation(space: s, history: h, now: () => DateTime(2026, 11, 9, 12));
      await l.load();
      expect(l.trail.length, 1);
      await l.report(LocationFix(1, 1, DateTime(2026, 11, 9, 12)));
      expect(h.fixes.length, 2);
      // The trail is not in the shared store.
      expect(s.store.allRecords.where((FamilyRecord r) => r.fields.containsKey('trail')), isEmpty);
    });

    test('places: arrive and leave events from shared positions', () async {
      final FamilySpace s = newSpace();
      await s.create(familyName: 'F', memberName: 'Asha');
      final FamilyLocation l = FamilyLocation(space: s);
      s.store.put(FamilySpace.members, 'ravi', <String, Object?>{'name': 'Ravi'});
      final FamilyPlace home = l.addPlace('Home', homeLat, homeLng)!;
      expect(l.addPlace(' ', 0, 0), isNull);

      void ravi(double lat) => s.store.put(FamilyLocation.locations, 'ravi', <String, Object?>{
            'sharing': true,
            ...LocationFix(lat, homeLng, DateTime(2026, 11, 9, 18)).toJson(),
          });

      ravi(homeLat + 0.01); // ~1.1 km away
      expect(l.placeEvents(), isEmpty);
      ravi(homeLat + 0.0005); // ~55 m: inside 150 m
      final List<PlaceEvent> arrive = l.placeEvents();
      expect(arrive.single.arrived, isTrue);
      expect(l.eventText(arrive.single), 'Ravi arrived at Home');
      expect(l.lineFor(l.members.firstWhere((MemberLocation m) => m.member == 'ravi')), 'At Home · 18:00');
      ravi(homeLat + 0.01);
      expect(l.eventText(l.placeEvents().single), 'Ravi left Home');
      expect(l.toText(), contains('Ravi: '));

      expect(l.removePlace(home.id), isTrue);
      expect(l.placeList, isEmpty);
      expect(l.undo(), isTrue);
      expect(l.placeList.single.name, 'Home');
    });

    test('tracker notifies for others and reports at the asked pace', () async {
      final FamilySpace s = newSpace();
      await s.create(familyName: 'F', memberName: 'Asha');
      final FamilyLocation l = FamilyLocation(space: s);
      l.setSharing(true);
      final ListSink sink = ListSink();
      final LocationTracker tr =
          LocationTracker(location: l, source: FixedSource(LocationFix(homeLat, homeLng, DateTime(2026, 11, 9))), sink: sink);
      l.addPlace('School', homeLat, homeLng);
      s.store.put(FamilySpace.members, 'kid', <String, Object?>{'name': 'Kid'});
      tr.start();
      s.store.put(FamilyLocation.locations, 'kid', <String, Object?>{'sharing': true, 'lat': 0, 'lng': 0, 'at': '2026-11-09T08:00:00'});
      s.store.put(FamilyLocation.locations, 'kid', <String, Object?>{'sharing': true, 'lat': homeLat, 'lng': homeLng, 'at': '2026-11-09T08:30:00'});
      await tr.tick();
      tr.stop();
      expect(sink.out, <String>['Kid arrived at School']);
      expect(l.trail, isNotEmpty);
    });
  });

  testWidgets('toggle sharing, see yourself, save a place, share, save, undo', (WidgetTester tester) async {
    final FamilySpace s = newSpace();
    await tester.runAsync(() => s.create(familyName: 'Shahs', memberName: 'Asha'));
    final FamilyLocation l = FamilyLocation(space: s);
    String? shared;
    String? saved;
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: FamilyLocationScreen(
        location: l,
        source: FixedSource(LocationFix(homeLat, homeLng, DateTime(2026, 11, 9, 9, 15))),
        share: (String t) async => shared = t,
        save: (String t) async {
          saved = t;
          return '/docs/Family locations.txt';
        },
      ),
    ));
    expect(find.text('Not sharing'), findsOneWidget);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(l.sharing, isTrue);
    expect(find.text('19.0760, 72.8777 · 09:15'), findsOneWidget);

    await tester.ensureVisible(find.byTooltip('Add place'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Save where I am as'), 'Home');
    await tester.tap(find.byTooltip('Add place'));
    await tester.pumpAndSettle();
    expect(find.text('At Home · 09:15', skipOffstage: false), findsOneWidget);
    expect(tester.getSize(find.byTooltip('Add place')).height, greaterThanOrEqualTo(44));
    expect(tester.getSize(find.byType(SwitchListTile)).height, greaterThanOrEqualTo(44));

    await tester.tap(find.byKey(const Key('result-share')));
    await tester.pumpAndSettle();
    expect(shared, contains('Asha: At Home · 09:15'));
    await tester.tap(find.byKey(const Key('result-save')));
    await tester.pumpAndSettle();
    expect(saved, isNotNull);

    await tester.tap(find.byKey(const Key('result-undo')));
    await tester.pumpAndSettle();
    expect(l.placeList, isEmpty);
    await tester.pump(const Duration(seconds: 5));
  });
}
