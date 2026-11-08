import 'package:family_utility_app/app/theme.dart';
import 'package:family_utility_app/app/tool_registry.dart';
import 'package:family_utility_app/engines/privacy/on_device_mode.dart';
import 'package:family_utility_app/tools/privacy/privacy_screen.dart';
import 'package:family_utility_app/tools/tools_home.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _OpenedMarker extends StatelessWidget {
  const _OpenedMarker(this.name);
  final String name;

  @override
  Widget build(BuildContext context) => Scaffold(body: Text('$name opened'));
}

void registerSampleTools() {
  ToolRegistry.clear();
  ToolRegistry.registerAll(<ToolEntry>[
    ToolEntry(
      id: 'local-tool',
      name: 'Merge PDF',
      section: ToolSection.pdf,
      icon: Icons.merge,
      builder: (BuildContext _) => const _OpenedMarker('Merge PDF'),
    ),
    ToolEntry(
      id: 'net-tool',
      name: 'Download video',
      section: ToolSection.links,
      icon: Icons.download,
      needsNetwork: true,
      networkReason: 'It fetches the video from the link you paste.',
      touches: const <DataTouch>{DataTouch.files, DataTouch.clipboard},
      builder: (BuildContext _) => const _OpenedMarker('Download video'),
    ),
  ]);
}

Widget app(Widget home) => MaterialApp(theme: buildAppTheme(), home: home);

void main() {
  late MemoryOnDeviceModeStore store;
  late OnDeviceMode mode;

  setUp(() {
    store = MemoryOnDeviceModeStore();
    mode = OnDeviceMode(store);
    OnDeviceMode.install(mode);
    registerSampleTools();
  });

  tearDown(ToolRegistry.clear);

  group('engine', () {
    test('default is on, even before anything was saved', () async {
      expect(mode.isOn, isTrue);
      await mode.load();
      expect(mode.isOn, isTrue);
      expect(mode.allows(needsNetwork: true), isFalse);
      expect(mode.allows(needsNetwork: false), isTrue);
    });

    test('a saved off is applied on load and set() persists', () async {
      final OnDeviceMode m = OnDeviceMode(MemoryOnDeviceModeStore(false));
      await m.load();
      expect(m.isOn, isFalse);
      expect(m.allows(needsNetwork: true), isTrue);

      await mode.set(false);
      expect(await store.read(), isFalse);
      await mode.set(true);
      expect(await store.read(), isTrue);
    });

    test('a broken store keeps the default on', () async {
      final OnDeviceMode m = OnDeviceMode(_BrokenStore());
      await m.load();
      expect(m.isOn, isTrue);
      await m.set(false);
      expect(m.isOn, isFalse, reason: 'the in-memory value still applies');
    });

    test('every tool declares what it touches', () {
      for (final ToolEntry t in ToolRegistry.all) {
        expect(t.touches, isA<Set<DataTouch>>());
        if (t.needsNetwork) {
          expect(t.networkReason, isNotNull, reason: '${t.id} needs a reason');
        }
      }
    });
  });

  group('home grid', () {
    testWidgets('network tools are greyed with a reason while on; local tools open',
        (WidgetTester tester) async {
      await tester.pumpWidget(app(const Scaffold(body: ToolsHome())));
      expect(find.text('On-device mode on'), findsOneWidget);
      expect(find.text('Off in on-device mode'), findsOneWidget);

      final Finder netTile = find.widgetWithText(ToolTile, 'Download video');
      final Opacity faded = tester.widget<Opacity>(
        find.descendant(of: netTile, matching: find.byType(Opacity)),
      );
      expect(faded.opacity, lessThan(1));

      await tester.tap(netTile);
      await tester.pumpAndSettle();
      expect(find.text('Download video opened'), findsNothing);
      expect(find.text('Download video needs the network'), findsOneWidget);
      expect(find.textContaining('fetches the video'), findsOneWidget);
      await tester.tap(find.text('Keep on-device'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ToolTile, 'Merge PDF'));
      await tester.pumpAndSettle();
      expect(find.text('Merge PDF opened'), findsOneWidget);
    });

    testWidgets('turning the switch off lets the network tool open', (WidgetTester tester) async {
      await tester.pumpWidget(app(const Scaffold(body: ToolsHome())));
      await mode.set(false);
      await tester.pump();
      expect(find.text('On-device mode off'), findsOneWidget);
      expect(find.text('Off in on-device mode'), findsNothing);

      await tester.tap(find.widgetWithText(ToolTile, 'Download video'));
      await tester.pumpAndSettle();
      expect(find.text('Download video opened'), findsOneWidget);
    });

    testWidgets('the home chip opens the privacy screen', (WidgetTester tester) async {
      await tester.pumpWidget(app(const Scaffold(body: ToolsHome())));
      await tester.tap(find.byKey(const Key('on-device-chip')));
      await tester.pumpAndSettle();
      expect(find.byType(PrivacyScreen), findsOneWidget);
    });

    testWidgets('greyed tiles are labelled for screen readers', (WidgetTester tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await tester.pumpWidget(app(const Scaffold(body: ToolsHome())));
      expect(
        find.bySemanticsLabel(RegExp('Download video, needs network, off in on-device mode')),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel(RegExp(r'^Merge PDF$')), findsWidgets);
      handle.dispose();
    });
  });

  group('privacy screen', () {
    testWidgets('lists every tool with what it touches and flips the switch',
        (WidgetTester tester) async {
      await tester.pumpWidget(app(const PrivacyScreen()));
      expect(find.text('Merge PDF'), findsOneWidget);
      expect(find.text('Download video'), findsOneWidget);
      expect(find.textContaining('fetches the video'), findsOneWidget);
      expect(find.text('Off in on-device mode'), findsOneWidget);
      // Chips: Merge PDF touches files; Download touches files, clipboard, network.
      expect(find.widgetWithText(Chip, 'Files you pick'), findsNWidgets(2));
      expect(find.widgetWithText(Chip, 'Clipboard'), findsOneWidget);
      expect(find.widgetWithText(Chip, 'Network'), findsOneWidget);

      final SwitchListTile tile = tester.widget<SwitchListTile>(find.byKey(const Key('on-device-switch')));
      expect(tile.value, isTrue);
      await tester.tap(find.byKey(const Key('on-device-switch')));
      await tester.pumpAndSettle();
      expect(mode.isOn, isFalse);
      expect(await store.read(), isFalse);
      expect(find.text('Off in on-device mode'), findsNothing);
      expect(find.textContaining('Off. Tools that need the network'), findsOneWidget);
    });

    testWidgets('switch row is at least 44 px tall', (WidgetTester tester) async {
      await tester.pumpWidget(app(const PrivacyScreen()));
      final Size size = tester.getSize(find.byKey(const Key('on-device-switch')));
      expect(size.height, greaterThanOrEqualTo(44));
    });

    testWidgets('home chip is at least 44 px tall', (WidgetTester tester) async {
      await tester.pumpWidget(app(const Scaffold(body: ToolsHome())));
      final Size chip = tester.getSize(find.byKey(const Key('on-device-chip')));
      expect(chip.height, greaterThanOrEqualTo(44));
    });
  });
}

class _BrokenStore implements OnDeviceModeStore {
  @override
  Future<bool?> read() async => throw StateError('no disk');

  @override
  Future<void> write(bool on) async => throw StateError('no disk');
}
