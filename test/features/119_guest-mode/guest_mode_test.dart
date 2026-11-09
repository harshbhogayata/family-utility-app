import 'package:family_utility_app/app/shell.dart';
import 'package:family_utility_app/app/theme.dart';
import 'package:family_utility_app/app/tool_registry.dart';
import 'package:family_utility_app/engines/family/member_profiles.dart';
import 'package:family_utility_app/engines/platform/guest_mode.dart';
import 'package:family_utility_app/tools/guest_mode/guest_mode_screen.dart';
import 'package:family_utility_app/tools/tools_home.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const List<String> ids = <String>['alpha', 'beta', 'gamma'];

void registerTools() {
  ToolRegistry.clear();
  for (final String id in ids) {
    ToolRegistry.register(ToolEntry(
      id: id,
      name: 'Tool $id',
      section: ToolSection.pdf,
      icon: Icons.build,
      builder: (BuildContext _) => Scaffold(appBar: AppBar(title: Text('Open $id'))),
    ));
  }
}

List<String> gridOrder(WidgetTester tester) =>
    tester.widgetList<ToolTile>(find.byType(ToolTile)).map((ToolTile t) => t.tool.id).toList();

void main() {
  group('engine', () {
    test('whitelist, start with a PIN, leave only with that PIN', () async {
      DateTime now = DateTime(2026, 1, 1, 10);
      final MemoryGuestModeStore store = MemoryGuestModeStore();
      final GuestMode g = GuestMode(store, now: () => now);
      expect(g.whyNotStart('1234'), isNotNull); // nothing ticked
      await g.toggleAllowed('beta');
      await g.toggleAllowed('alpha');
      expect(g.whyNotStart('12'), isNotNull); // PIN too short
      expect(await g.start('2468'), isTrue);
      expect(g.active, isTrue);
      expect(g.filter(ids), <String>['alpha', 'beta']);
      expect(store.value, isNot(contains('2468')));

      // The whitelist cannot change while a guest has the phone.
      await g.toggleAllowed('gamma');
      expect(g.allowed, <String>['beta', 'alpha']);

      // Survives a restart.
      final GuestMode again = GuestMode(store, now: () => now);
      await again.load();
      expect(again.active, isTrue);
      expect(again.filter(ids), <String>['alpha', 'beta']);

      // Wrong PINs, then a lockout, then the right PIN.
      for (int i = 0; i < GuestMode.maxAttempts - 1; i++) {
        expect(await again.exit('0000'), GuestExit.wrongPin);
      }
      expect(await again.exit('0000'), GuestExit.lockedOut);
      expect(await again.exit('2468'), GuestExit.lockedOut);
      now = now.add(const Duration(seconds: 31));
      expect(await again.exit('2468'), GuestExit.exited);
      expect(again.active, isFalse);
      expect(again.filter(ids), ids);
      expect(await again.exit('2468'), GuestExit.notActive);
    });

    test('a damaged or PIN-less file never starts in guest mode', () async {
      final GuestMode g = GuestMode(MemoryGuestModeStore('{"active":true,"allowed":["alpha"]}'));
      await g.load();
      expect(g.active, isFalse);
      final GuestMode h = GuestMode(MemoryGuestModeStore('not json'));
      await h.load();
      expect(h.active, isFalse);
    });
  });

  group('screens', () {
    setUp(registerTools);
    tearDown(() {
      ToolRegistry.clear();
      GuestMode.install(GuestMode(MemoryGuestModeStore()));
      MemberProfiles.install(MemberProfiles(MemoryProfileStore()));
    });

    testWidgets('owner ticks tools, starts; guest sees only those; PIN brings all back',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final GuestMode g = GuestMode(MemoryGuestModeStore());
      GuestMode.install(g);
      MemberProfiles.install(MemberProfiles(MemoryProfileStore()));
      final List<String> shared = <String>[];

      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: GuestModeScreen(
          mode: g,
          share: (String t) async {
            shared.add(t);
            return null;
          },
          save: (String t) async => '/docs/Guest mode tools.txt',
        ),
      ));
      await tester.tap(find.byKey(const Key('guest-allow-gamma')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('guest-allow-alpha')));
      await tester.pumpAndSettle();
      expect(g.allowed, <String>['gamma', 'alpha']);
      expect(tester.getSize(find.byKey(const Key('guest-allow-alpha'))).height, greaterThanOrEqualTo(44));

      // Undo the last tick, then tick again.
      await tester.tap(find.byKey(const Key('result-undo')));
      await tester.pumpAndSettle();
      expect(g.allowed, <String>['gamma']);
      await tester.tap(find.byKey(const Key('guest-allow-alpha')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('result-share')));
      await tester.pumpAndSettle();
      expect(shared.single, contains('- Tool gamma'));
      await tester.tap(find.byKey(const Key('result-save')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Saved to'), findsOneWidget);

      // A short PIN is refused with a reason.
      await tester.enterText(find.byKey(const Key('guest-pin')), '12');
      await tester.tap(find.byKey(const Key('guest-start')));
      await tester.pumpAndSettle();
      expect(g.active, isFalse);
      expect(find.textContaining('PIN of 4 to 6 digits'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('guest-pin')), '2468');
      await tester.tap(find.byKey(const Key('guest-start')));
      await tester.pumpAndSettle();
      expect(g.active, isTrue);

      // The shell now shows only the allowed tools and no other tabs.
      await tester.pumpWidget(MaterialApp(theme: buildAppTheme(), home: const AppShell()));
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsNothing);
      expect(gridOrder(tester), <String>['alpha', 'gamma']);
      expect(find.byKey(const Key('home-edit')), findsNothing);
      expect(find.bySemanticsLabel('Guest mode tools'), findsOneWidget);

      // A wrong PIN keeps guest mode on.
      await tester.tap(find.byKey(const Key('guest-exit')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('guest-exit-pin')), '1111');
      await tester.tap(find.byKey(const Key('guest-exit-confirm')));
      await tester.pumpAndSettle();
      expect(find.text('That is not the owner PIN'), findsOneWidget);
      expect(g.active, isTrue);

      // The owner's PIN brings everything back.
      await tester.enterText(find.byKey(const Key('guest-exit-pin')), '2468');
      await tester.tap(find.byKey(const Key('guest-exit-confirm')));
      await tester.pumpAndSettle();
      expect(g.active, isFalse);
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(gridOrder(tester), ids);
    });
  });
}
