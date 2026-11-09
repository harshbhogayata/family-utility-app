import 'package:family_utility_app/app/theme.dart';
import 'package:family_utility_app/app/tool_registry.dart';
import 'package:family_utility_app/engines/family/member_profiles.dart';
import 'package:family_utility_app/tools/profiles/profiles_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

int _n = 0;
MemberProfiles fresh([MemoryProfileStore? store]) =>
    MemberProfiles(store ?? MemoryProfileStore(), newId: () => 'm${++_n}');

Widget host(MemberProfiles ps, {void Function(ToolEntry t)? onOpen}) => MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: Column(
          children: <Widget>[
            ProfileChip(profiles: ps),
            ProfileShortcuts(profiles: ps, onOpen: onOpen ?? (ToolEntry _) {}),
          ],
        ),
      ),
    );

void main() {
  group('engine', () {
    test('starts with one profile and keeps the last one', () async {
      final MemberProfiles ps = fresh();
      expect(ps.profiles.single.name, 'Me');
      expect(await ps.remove('me'), isFalse);
      expect(await ps.add('   '), isNull);
    });

    test('each member has their own recents, favourites and language', () async {
      final MemberProfiles ps = fresh();
      final MemberProfile asha = (await ps.add('Asha', language: 'hi'))!;
      await ps.recordRecent('merge-pdf');
      await ps.recordRecent('compress-pdf');
      await ps.recordRecent('merge-pdf');
      await ps.toggleFavourite('qr-generator');
      expect(ps.active.recents, <String>['merge-pdf', 'compress-pdf']);

      expect(await ps.switchTo(asha.id), SwitchOutcome.switched);
      expect(ps.active.language, 'hi');
      expect(ps.active.recents, isEmpty);
      expect(ps.isFavourite('qr-generator'), isFalse);
      await ps.recordRecent('resize');
      expect(ps.active.recents, <String>['resize']);

      await ps.setLanguage(asha.id, 'xx');
      expect(ps.active.language, 'hi');
      await ps.setLanguage(asha.id, 'gu');
      expect(ps.active.language, 'gu');
    });

    test('recents are capped and newest first', () async {
      final MemberProfiles ps = fresh();
      for (int i = 0; i < 12; i++) {
        await ps.recordRecent('t$i');
      }
      expect(ps.active.recents.length, MemberProfiles.maxRecents);
      expect(ps.active.recents.first, 't11');
    });

    test('a PIN guards switching in, never switching out', () async {
      final MemberProfiles ps = fresh();
      final MemberProfile ravi = (await ps.add('Ravi'))!;
      expect(await ps.setPin(ravi.id, '12'), isFalse);
      expect(await ps.setPin(ravi.id, '2468'), isTrue);
      expect(ps.byId(ravi.id)!.pinHash, isNot(contains('2468')));

      expect(await ps.switchTo(ravi.id), SwitchOutcome.needsPin);
      expect(await ps.switchTo(ravi.id, pin: '1111'), SwitchOutcome.wrongPin);
      expect(ps.active.id, 'me');
      expect(await ps.switchTo(ravi.id, pin: '2468'), SwitchOutcome.switched);
      expect(await ps.switchTo('me'), SwitchOutcome.switched);

      await ps.clearPin(ravi.id);
      expect(await ps.switchTo(ravi.id), SwitchOutcome.switched);
    });

    test('survives a restart through the store, and a broken file', () async {
      final MemoryProfileStore store = MemoryProfileStore();
      final MemberProfiles a = fresh(store);
      final MemberProfile k = (await a.add('Kiran', language: 'ta'))!;
      await a.switchTo(k.id);
      await a.recordRecent('scan');

      final MemberProfiles b = fresh(store);
      await b.load();
      expect(b.profiles.length, 2);
      expect(b.active.name, 'Kiran');
      expect(b.active.language, 'ta');
      expect(b.active.recents, <String>['scan']);

      final MemberProfiles c = fresh(MemoryProfileStore('{not json'));
      await c.load();
      expect(c.active.name, 'Me');
    });

    test('removing the active member falls back to another', () async {
      final MemberProfiles ps = fresh();
      final MemberProfile x = (await ps.add('X'))!;
      await ps.switchTo(x.id);
      expect(await ps.remove(x.id), isTrue);
      expect(ps.active.id, 'me');
    });
  });

  group('screens', () {
    testWidgets('switch profile from the home chip, with a PIN', (WidgetTester tester) async {
      final MemberProfiles ps = fresh();
      final MemberProfile neha = (await ps.add('Neha'))!;
      await ps.setPin(neha.id, '1357');
      await tester.pumpWidget(host(ps));

      expect(find.bySemanticsLabel('Profile: Me. Switch profile'), findsOneWidget);
      expect(tester.getSize(find.byKey(const Key('profile-chip'))).height, greaterThanOrEqualTo(44));

      await tester.tap(find.byKey(const Key('profile-chip')));
      await tester.pumpAndSettle();
      expect(find.text('Who is using the phone?'), findsOneWidget);
      await tester.tap(find.byKey(Key('switch-${neha.id}')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('profile-pin-field')), '1357');
      await tester.tap(find.byKey(const Key('profile-pin-ok')));
      await tester.pumpAndSettle();

      expect(ps.active.id, neha.id);
      expect(find.bySemanticsLabel('Profile: Neha. Switch profile'), findsOneWidget);
    });

    testWidgets('home shows the active member favourites and recents', (WidgetTester tester) async {
      for (final String id in <String>['t069-a', 't069-b']) {
        ToolRegistry.register(ToolEntry(
          id: id,
          name: 'Tool $id',
          section: ToolSection.pdf,
          icon: Icons.build,
          builder: (BuildContext _) => const SizedBox(),
        ));
      }
      final List<ToolEntry> all = <ToolEntry>[ToolRegistry.byId('t069-a')!, ToolRegistry.byId('t069-b')!];
      final MemberProfiles ps = fresh();
      await ps.recordRecent(all[0].id);
      await ps.toggleFavourite(all[1].id);
      ToolEntry? opened;
      await tester.pumpWidget(host(ps, onOpen: (ToolEntry t) => opened = t));
      expect(find.byKey(Key('recent-${all[0].id}')), findsOneWidget);
      expect(find.byKey(Key('recent-${all[1].id}')), findsOneWidget);
      await tester.tap(find.byKey(Key('recent-${all[0].id}')));
      expect(opened?.id, all[0].id);

      final MemberProfile b = (await ps.add('B'))!;
      await ps.switchTo(b.id);
      await tester.pump();
      expect(find.byKey(Key('recent-${all[0].id}')), findsNothing);
    });

    testWidgets('manage: add a member, pick a language, set a PIN', (WidgetTester tester) async {
      final MemberProfiles ps = fresh();
      await tester.pumpWidget(MaterialApp(theme: buildAppTheme(), home: ProfilesScreen(profiles: ps)));

      await tester.tap(find.byKey(const Key('add-profile')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('profile-name-field')), 'Dadi');
      await tester.tap(find.byKey(const Key('profile-name-ok')));
      await tester.pumpAndSettle();
      final MemberProfile dadi = ps.profiles.last;
      expect(dadi.name, 'Dadi');

      await tester.ensureVisible(find.byKey(Key('language-${dadi.id}')));
      await tester.tap(find.byKey(Key('language-${dadi.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('lang-mr')));
      await tester.pumpAndSettle();
      expect(ps.byId(dadi.id)!.language, 'mr');

      await tester.ensureVisible(find.byKey(Key('pin-${dadi.id}')));
      await tester.tap(find.byKey(Key('pin-${dadi.id}')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('profile-pin-field')), '9876');
      await tester.tap(find.byKey(const Key('profile-pin-ok')));
      await tester.pumpAndSettle();
      expect(ps.byId(dadi.id)!.hasPin, isTrue);
    });
  });
}
