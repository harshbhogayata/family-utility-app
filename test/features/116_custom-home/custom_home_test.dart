import 'package:family_utility_app/app/theme.dart';
import 'package:family_utility_app/app/tool_registry.dart';
import 'package:family_utility_app/engines/family/member_profiles.dart';
import 'package:family_utility_app/engines/platform/home_layout.dart';
import 'package:family_utility_app/tools/custom_home/custom_home_screen.dart';
import 'package:family_utility_app/tools/tools_home.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

int _n = 0;
MemberProfiles fresh([MemoryProfileStore? store]) =>
    MemberProfiles(store ?? MemoryProfileStore(), newId: () => 'h${++_n}');

const List<String> ids = <String>['alpha', 'beta', 'gamma', 'delta'];

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

void bigView(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  group('layout engine', () {
    test('default is pinned, then recents, then registry order', () {
      const HomeLayout l = HomeLayout(pinned: <String>['delta']);
      expect(l.visible(all: ids, recents: <String>['gamma']), <String>['delta', 'gamma', 'alpha', 'beta']);
    });

    test('drag reorder keeps the dragged order and pins on top', () {
      const HomeLayout l = HomeLayout();
      // Drag alpha (0) to after gamma (slot 3 before removal).
      final HomeLayout a = l.reorder(ids, 0, 3);
      expect(a.visible(all: ids), <String>['beta', 'gamma', 'alpha', 'delta']);
      // Recents no longer reshuffle an arranged home.
      expect(a.visible(all: ids, recents: <String>['delta']), <String>['beta', 'gamma', 'alpha', 'delta']);

      // A pinned tool dragged below the rest snaps back to the pin group.
      final HomeLayout p = a.togglePinned('gamma');
      final List<String> order = p.fullOrder(all: ids);
      expect(order.first, 'gamma');
      final HomeLayout q = p.reorder(order, 0, 4);
      expect(q.visible(all: ids).first, 'gamma');
      expect(q.pinned, <String>['gamma']);
    });

    test('step moves one place and stops at the ends', () {
      const HomeLayout l = HomeLayout();
      expect(l.step(ids, 'beta', -1).visible(all: ids), <String>['beta', 'alpha', 'gamma', 'delta']);
      expect(l.step(ids, 'beta', 1).visible(all: ids), <String>['alpha', 'gamma', 'beta', 'delta']);
      expect(l.step(ids, 'alpha', -1), l);
      expect(l.step(ids, 'delta', 1), l);
    });

    test('hide removes from the grid and unpins; pin shows again; reset clears', () {
      final HomeLayout l = const HomeLayout(pinned: <String>['beta']).toggleHidden('beta');
      expect(l.visible(all: ids), <String>['alpha', 'gamma', 'delta']);
      expect(l.fullOrder(all: ids), contains('beta'));
      expect(l.pinned, isEmpty);
      final HomeLayout back = l.togglePinned('beta');
      expect(back.hidden, isEmpty);
      expect(back.visible(all: ids).first, 'beta');
      expect(back.reset().isDefault, isTrue);
      expect(back.reset().visible(all: ids), ids);
    });

    test('unknown ids are ignored; describe lists order and hidden', () {
      const HomeLayout l = HomeLayout(arranged: <String>['gone', 'delta'], hidden: <String>['beta', 'gone']);
      expect(l.visible(all: ids), <String>['delta', 'alpha', 'gamma']);
      final String text = l.describe(memberName: 'Me', all: ids, nameOf: (String id) => 'Tool $id');
      expect(text, contains('1. Tool delta'));
      expect(text, contains('Hidden: Tool beta'));
      expect(text, isNot(contains('gone')));
    });

    test('layout is per member and persists', () async {
      final MemoryProfileStore store = MemoryProfileStore();
      final MemberProfiles ps = fresh(store);
      await ps.setLayout(const HomeLayout(arranged: <String>['gamma'], hidden: <String>['alpha']));
      final MemberProfile kid = (await ps.add('Kid'))!;
      await ps.switchTo(kid.id);
      expect(ps.orderTools(ids), ids);

      final MemberProfiles again = fresh(store);
      await again.load();
      await again.switchTo('me');
      expect(again.layout.hidden, <String>['alpha']);
      expect(again.orderTools(ids), <String>['gamma', 'beta', 'delta']);
    });
  });

  group('screens', () {
    setUp(registerTools);
    tearDown(ToolRegistry.clear);

    testWidgets('hide, drag, pin, undo and reset; home follows', (WidgetTester tester) async {
      bigView(tester);
      final MemberProfiles ps = fresh();
      final List<String> shared = <String>[];
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: CustomHomeScreen(
          profiles: ps,
          share: (String t) async {
            shared.add(t);
            return null;
          },
          save: (String t) async => '/docs/Home layout.txt',
        ),
      ));
      expect(find.byKey(const ValueKey<String>('arrange-alpha')), findsOneWidget);

      // Hide beta.
      await tester.tap(find.byKey(const Key('hide-toggle-beta')));
      await tester.pumpAndSettle();
      expect(ps.layout.hidden, <String>['beta']);
      expect(find.text('Hidden from home'), findsOneWidget);
      expect(find.byTooltip('Show Tool beta on home'), findsOneWidget);

      // Drag: alpha to after delta, through the list's own reorder callback.
      final ReorderableListView list = tester.widget<ReorderableListView>(find.byType(ReorderableListView));
      list.onReorder(0, 4);
      await tester.pumpAndSettle();
      expect(ps.orderTools(ids), <String>['gamma', 'delta', 'alpha']);

      // A real drag on the handle also reorders: gamma down past delta.
      final List<String> beforeDrag = ps.fullToolOrder(ids);
      final TestGesture g = await tester.startGesture(tester.getCenter(find.byKey(const Key('drag-gamma'))));
      await tester.pump(kPressTimeout);
      for (int i = 0; i < 10; i++) {
        await g.moveBy(const Offset(0, 20));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await g.up();
      await tester.pumpAndSettle();
      expect(ps.fullToolOrder(ids), isNot(beforeDrag));
      expect(ps.fullToolOrder(ids).indexOf('gamma'), greaterThan(beforeDrag.indexOf('gamma')));

      // Pin delta: it goes to the top.
      await tester.tap(find.byKey(const Key('pin-toggle-delta')));
      await tester.pumpAndSettle();
      expect(ps.orderTools(ids).first, 'delta');

      // Undo takes back the pin.
      await tester.tap(find.byKey(const Key('result-undo')));
      await tester.pumpAndSettle();
      expect(ps.layout.pinned, isEmpty);

      // Share and save describe the layout.
      await tester.tap(find.byKey(const Key('result-share')));
      await tester.pumpAndSettle();
      expect(shared.single, contains('Hidden: Tool beta'));
      await tester.tap(find.byKey(const Key('result-save')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Saved to'), findsOneWidget);

      // Reset to default, then undo the reset.
      await tester.tap(find.byKey(const Key('home-reset')));
      await tester.pumpAndSettle();
      expect(ps.layout.isDefault, isTrue);
      expect(ps.orderTools(ids), ids);
      await tester.tap(find.byKey(const Key('result-undo')));
      await tester.pumpAndSettle();
      expect(ps.layout.hidden, <String>['beta']);

      // Touch targets.
      expect(tester.getSize(find.byKey(const Key('hide-toggle-alpha'))).height, greaterThanOrEqualTo(44));
      expect(tester.getSize(find.byKey(const Key('pin-toggle-alpha'))).height, greaterThanOrEqualTo(44));
      expect(tester.getSize(find.byKey(const Key('drag-alpha'))).height, greaterThanOrEqualTo(44));
    });

    testWidgets('rows are labelled and offer move actions to screen readers', (WidgetTester tester) async {
      bigView(tester);
      final SemanticsHandle sem = tester.ensureSemantics();
      final MemberProfiles ps = fresh();
      await tester.pumpWidget(MaterialApp(theme: buildAppTheme(), home: CustomHomeScreen(profiles: ps)));
      expect(find.bySemanticsLabel(RegExp('Tool beta, position 2 of 4, shown')), findsOneWidget);
      final SemanticsNode node = tester.getSemantics(find.byKey(const ValueKey<String>('arrange-beta')));
      final SemanticsOwner owner = tester.binding.pipelineOwner.semanticsOwner!;
      final int up = CustomSemanticsAction.getIdentifier(const CustomSemanticsAction(label: 'Move Tool beta up'));
      owner.performAction(node.id, SemanticsAction.customAction, up);
      await tester.pumpAndSettle();
      expect(ps.orderTools(ids), <String>['beta', 'alpha', 'gamma', 'delta']);
      sem.dispose();
    });

    testWidgets('home leaves hidden tools out and links to the editor', (WidgetTester tester) async {
      bigView(tester);
      final MemberProfiles ps = fresh();
      MemberProfiles.install(ps);
      await ps.setLayout(const HomeLayout(arranged: <String>['delta', 'gamma'], hidden: <String>['alpha']));
      await tester.pumpWidget(MaterialApp(theme: buildAppTheme(), home: const Scaffold(body: ToolsHome())));
      await tester.pumpAndSettle();
      expect(gridOrder(tester), <String>['delta', 'gamma', 'beta']);
      expect(find.text('1 tool hidden. Arrange home'), findsOneWidget);

      await tester.tap(find.byKey(const Key('home-edit')));
      await tester.pumpAndSettle();
      expect(find.byType(CustomHomeScreen), findsOneWidget);
      await tester.tap(find.byKey(const Key('home-reset')));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(gridOrder(tester), ids);
      expect(find.byKey(const Key('home-hidden-count')), findsNothing);
      MemberProfiles.install(MemberProfiles(MemoryProfileStore()));
    });
  });
}
