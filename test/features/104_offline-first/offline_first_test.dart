import 'dart:io';

import 'package:family_utility_app/app/bootstrap.dart';
import 'package:family_utility_app/app/theme.dart';
import 'package:family_utility_app/app/tool_registry.dart';
import 'package:family_utility_app/engines/privacy/offline_policy.dart';
import 'package:family_utility_app/engines/privacy/on_device_mode.dart';
import 'package:family_utility_app/tools/tools_home.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ToolEntry tool({
  required String id,
  required int feature,
  bool needsNetwork = false,
  String? reason,
  Set<DataTouch> touches = const <DataTouch>{DataTouch.files},
}) {
  return ToolEntry(
    id: id,
    name: id,
    section: ToolSection.platform,
    icon: Icons.build_outlined,
    featureNumber: feature,
    needsNetwork: needsNetwork,
    networkReason: reason,
    touches: touches,
    builder: (BuildContext _) => const SizedBox(),
  );
}

void main() {
  group('OfflinePolicy', () {
    test('the real registry only lets downloads and cloud use the network', () {
      ToolRegistry.clear();
      bootstrap();
      expect(OfflinePolicy.violations(ToolRegistry.all), isEmpty);
      for (final ToolEntry t in ToolRegistry.all) {
        expect(t.needsNetwork, OfflinePolicy.mayUseNetwork(t) && t.needsNetwork,
            reason: '${t.id} may not claim the network');
      }
      ToolRegistry.clear();
    });

    test('a tool outside the allow-list cannot claim the network', () {
      final List<String> problems = OfflinePolicy.violations(<ToolEntry>[
        tool(id: 'merge', feature: 2),
        tool(id: 'sneaky', feature: 2, needsNetwork: true, reason: 'because'),
        tool(
          id: 'download',
          feature: 123,
          needsNetwork: true,
          touches: const <DataTouch>{DataTouch.files, DataTouch.network},
        ),
        tool(
          id: 'cloud',
          feature: 63,
          needsNetwork: true,
          reason: 'Reads and writes your own Drive or iCloud folder.',
          touches: const <DataTouch>{DataTouch.files, DataTouch.network},
        ),
      ]);
      expect(problems, hasLength(3));
      expect(problems.where((String p) => p.startsWith('sneaky')), hasLength(2));
      expect(problems.where((String p) => p.startsWith('download')), hasLength(1));
      expect(problems.where((String p) => p.startsWith('cloud')), isEmpty);
    });

    test('LAN tools are not internet tools', () {
      expect(OfflinePolicy.lanFeatures.intersection(OfflinePolicy.networkFeatures), isEmpty);
    });
  });

  group('NetworkGuard', () {
    final ToolEntry download = tool(
      id: 'download',
      feature: 123,
      needsNetwork: true,
      reason: 'Fetches the link you paste.',
      touches: const <DataTouch>{DataTouch.files, DataTouch.network},
    );
    final ToolEntry merge = tool(id: 'merge', feature: 2);

    test('on-device mode on blocks every network job before it starts', () async {
      final OnDeviceMode mode = OnDeviceMode(MemoryOnDeviceModeStore());
      bool ran = false;
      expect(
        () => NetworkGuard.run<void>(download, () async => ran = true, mode: mode),
        throwsA(isA<OfflineBlocked>()),
      );
      expect(ran, isFalse);
      expect(NetworkGuard.blockedReason(download, mode: mode), contains('On-device mode is on'));
    });

    test('with the switch off, an allowed tool runs; an on-device tool never does', () async {
      final OnDeviceMode mode = OnDeviceMode(MemoryOnDeviceModeStore());
      await mode.set(false);
      expect(await NetworkGuard.run<int>(download, () async => 7, mode: mode), 7);
      expect(NetworkGuard.blockedReason(download, mode: mode), isNull);
      expect(
        () => NetworkGuard.run<int>(merge, () async => 7, mode: mode),
        throwsA(isA<OfflineBlocked>()),
      );
      expect(NetworkGuard.blockedReason(merge, mode: mode), contains('never uses the network'));
    });
  });

  group('airplane-mode source scan', () {
    test('no network code outside the folders the network features own', () {
      final Directory lib = Directory('lib');
      expect(lib.existsSync(), isTrue);
      final List<String> offenders = <String>[];
      for (final FileSystemEntity f in lib.listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) {
          continue;
        }
        final String rel = f.path.replaceAll(r'\', '/');
        if (OfflinePolicy.networkSourceFolders.any(rel.startsWith)) {
          continue;
        }
        final String src = f.readAsStringSync();
        for (final String marker in OfflinePolicy.networkMarkers) {
          if (src.contains(marker)) {
            offenders.add('$rel uses $marker');
          }
        }
      }
      expect(offenders, isEmpty);
    });

    test('pubspec pulls in no HTTP client package', () {
      final String pubspec = File('pubspec.yaml').readAsStringSync();
      for (final String pkg in <String>['\n  http:', '\n  dio:', '\n  firebase', '\n  sentry', '\n  amplitude']) {
        expect(pubspec.contains(pkg), isFalse, reason: 'pubspec declares $pkg');
      }
    });
  });

  group('badge', () {
    setUp(() {
      OnDeviceMode.install(OnDeviceMode(MemoryOnDeviceModeStore()));
      ToolRegistry.clear();
      ToolRegistry.registerAll(<ToolEntry>[
        tool(id: 'Merge PDF', feature: 2),
        tool(
          id: 'Download video',
          feature: 123,
          needsNetwork: true,
          reason: 'Fetches the link you paste.',
          touches: const <DataTouch>{DataTouch.files, DataTouch.network},
        ),
      ]);
    });

    tearDown(ToolRegistry.clear);

    testWidgets('only network tools carry the badge, whether the switch is on or off',
        (WidgetTester tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await tester.pumpWidget(MaterialApp(theme: buildAppTheme(), home: const Scaffold(body: ToolsHome())));
      final Finder badge = find.byTooltip('Needs network');
      expect(badge, findsOneWidget);
      expect(find.descendant(of: find.widgetWithText(ToolTile, 'Download video'), matching: badge),
          findsOneWidget);
      expect(find.descendant(of: find.widgetWithText(ToolTile, 'Merge PDF'), matching: badge),
          findsNothing);

      await OnDeviceMode.instance.set(false);
      await tester.pump();
      expect(badge, findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'^Download video, needs network$')), findsOneWidget);
      handle.dispose();
    });
  });
}
