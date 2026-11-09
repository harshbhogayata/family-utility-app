import 'package:family_utility_app/app/theme.dart';
import 'package:family_utility_app/app/tool_registry.dart';
import 'package:family_utility_app/engines/family/member_profiles.dart';
import 'package:family_utility_app/engines/platform/tool_order.dart';
import 'package:family_utility_app/tools/profiles/profiles_screen.dart';
import 'package:family_utility_app/tools/tools_home.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

int _n = 0;
MemberProfiles fresh([MemoryProfileStore? store]) =>
    MemberProfiles(store ?? MemoryProfileStore(), newId: () => 'm${++_n}');

void registerTools() {
  for (final String id in <String>['alpha', 'beta', 'gamma', 'delta']) {
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
  group('order engine', () {
    test('pinned first, then recents newest first, then the rest', () {
      expect(
        ToolOrder.order(
          all: <String>['a', 'b', 'c', 'd', 'e'],
          pinned: <String>['d', 'gone'],
          recents: <String>['b', 'd', 'e'],
        ),
        <String>['d', 'b', 'e', 'a', 'c'],
      );
    });

    test('move clamps and ignores unknown ids', () {
      expect(ToolOrder.move(<String>['a', 'b', 'c'], 'c', 0), <String>['c', 'a', 'b']);
      expect(ToolOrder.move(<String>['a', 'b', 'c'], 'a', 99), <String>['b', 'c', 'a']);
      expect(ToolOrder.move(<String>['a', 'b'], 'z', 0), <String>['a', 'b']);
    });

    test('recents are per profile and pin order persists', () async {
      final MemoryProfileStore store = MemoryProfileStore();
      final MemberProfiles ps = fresh(store);
      await ps.recordRecent('beta');
      await ps.toggleFavourite('alpha');
      await ps.toggleFavourite('gamma');
      await ps.movePin('gamma', 0);
      final MemberProfile kid = (await ps.add('Kid'))!;
      await ps.switchTo(kid.id);
      await ps.recordRecent('delta');
      expect(ps.orderTools(<String>['alpha', 'beta', 'gamma', 'delta']), <String>['delta', 'alpha', 'beta', 'gamma']);

      final MemberProfiles again = fresh(store);
      await again.load();
      await again.switchTo('me');
      expect(again.active.favourites, <String>['gamma', 'alpha']);
      expect(again.orderTools(<String>['alpha', 'beta', 'gamma', 'delta']), <String>['gamma', 'alpha', 'beta', 'delta']);
    });
  });

  group('home', () {
    setUp(registerTools);

    testWidgets('used tools float up; long-press pins to the top', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 4000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final MemberProfiles ps = fresh();
      MemberProfiles.install(ps);
      await tester.pumpWidget(MaterialApp(theme: buildAppTheme(), home: const Scaffold(body: ToolsHome())));
      expect(gridOrder(tester), <String>['alpha', 'beta', 'gamma', 'delta']);

      await tester.tap(find.byKey(const ValueKey<String>('tile-gamma')));
      await tester.pumpAndSettle();
      expect(find.text('Open gamma'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(gridOrder(tester).first, 'gamma');

      await tester.longPress(find.byKey(const ValueKey<String>('tile-delta')));
      await tester.pumpAndSettle();
      expect(gridOrder(tester), <String>['delta', 'gamma', 'alpha', 'beta']);
      expect(find.bySemanticsLabel(RegExp('Tool delta, pinned')), findsWidgets);
      expect(tester.getSize(find.byKey(const ValueKey<String>('tile-delta'))).height, greaterThanOrEqualTo(44));

      // Another member sees their own order.
      final MemberProfile b = (await ps.add('B'))!;
      await ps.switchTo(b.id);
      await tester.pumpAndSettle();
      expect(gridOrder(tester), <String>['alpha', 'beta', 'gamma', 'delta']);
    });

    testWidgets('arrange pins: move and unpin, labelled buttons', (WidgetTester tester) async {
      final MemberProfiles ps = fresh();
      await ps.toggleFavourite('alpha');
      await ps.toggleFavourite('beta');
      await tester.pumpWidget(MaterialApp(theme: buildAppTheme(), home: PinnedToolsScreen(profiles: ps)));
      expect(find.byTooltip('Move Tool beta up'), findsOneWidget);

      await tester.tap(find.byKey(const Key('pin-down-alpha')));
      await tester.pumpAndSettle();
      expect(ps.active.favourites, <String>['beta', 'alpha']);

      await tester.tap(find.byKey(const Key('unpin-beta')));
      await tester.pumpAndSettle();
      expect(ps.active.favourites, <String>['alpha']);
      expect(tester.getSize(find.byKey(const Key('unpin-alpha'))).height, greaterThanOrEqualTo(44));
    });
  });
}
