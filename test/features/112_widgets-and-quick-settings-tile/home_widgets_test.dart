import 'dart:io';

import 'package:family_utility_app/engines/platform/batch_everywhere.dart';
import 'package:family_utility_app/engines/platform/home_widgets.dart';
import 'package:family_utility_app/tools/home_widget/home_widget_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final DateTime now = DateTime(2026, 11, 9, 7, 30);

  group('engine', () {
    test('launch links and bare action names parse; others are ignored', () {
      for (final WidgetAction a in WidgetAction.values) {
        expect(WidgetLaunch.parse(WidgetLaunch.linkFor(a)), a);
        expect(WidgetLaunch.parse(a.id), a);
      }
      expect(WidgetLaunch.linkFor(WidgetAction.scan), 'familyapp://widget/scan');
      expect(WidgetLaunch.parse('https://example.com/scan'), isNull);
      expect(WidgetLaunch.parse('familyapp://widget/nope'), isNull);
      expect(WidgetLaunch.parse('familyapp://widget'), isNull);
      expect(WidgetLaunch.parse(''), isNull);
      expect(WidgetLaunch.parse(null), isNull);
      expect(WidgetAction.scan.toolId, 'document-scanner');
    });

    test('next medicine is the first dose not yet past', () {
      final WidgetSnapshot s = WidgetSnapshot.build(now: now, doses: <MedicineDose>[
        MedicineDose(name: 'Old', at: now.subtract(const Duration(minutes: 1))),
        MedicineDose(name: 'Later', at: DateTime(2026, 11, 10, 21, 0)),
        MedicineDose(name: 'Metformin 500', at: DateTime(2026, 11, 9, 8, 5), member: 'Dad'),
        MedicineDose(name: 'Far', at: DateTime(2026, 11, 14, 12, 0)),
      ]);
      expect(s.medicineTitle, 'Metformin 500');
      expect(s.medicineDetail, '8:05 am · Dad');
      expect(WidgetSnapshot.whenText(DateTime(2026, 11, 10, 21, 0), now), 'Tomorrow 9:00 pm');
      expect(WidgetSnapshot.whenText(DateTime(2026, 11, 14, 0, 15), now), '14 Nov 12:15 am');

      final WidgetSnapshot none = WidgetSnapshot.build(now: now);
      expect(none.medicineTitle, 'No medicine due');
      expect(none.medicineDetail, '');
    });

    test('snapshot flattens to the keys the native widget reads', () {
      final WidgetSnapshot s = WidgetSnapshot.build(now: now, speedDial: const <SpeedDialEntry>[
        SpeedDialEntry(label: 'Doctor', number: '+91 98765-43210'),
        SpeedDialEntry(label: 'Bad', number: '12'),
        SpeedDialEntry(label: 'Mum', number: '(022) 2345 6789'),
        SpeedDialEntry(label: 'Dad', number: '9999988888'),
        SpeedDialEntry(label: 'Extra', number: '1234567'),
      ]);
      expect(s.speedDial.map((SpeedDialEntry e) => e.label), <String>['Doctor', 'Mum', 'Dad']);
      final Map<String, String> m = s.toMap();
      expect(m['dial_count'], '3');
      expect(m['dial_0_number'], '+919876543210');
      expect(m['dial_1_number'], '02223456789');
      expect(m['dial_2_label'], 'Dad');
      expect(m['medicine_title'], 'No medicine due');
      expect(m.keys, containsAll(<String>['medicine_detail', 'updated_at']));
      expect(s.describe(), contains('Speed dial: Doctor +919876543210'));
    });

    test('controller publishes, keeps the dial list, routes taps', () async {
      final MemoryWidgetBridge bridge = MemoryWidgetBridge(initial: 'familyapp://widget/paste');
      final MemorySpeedDialStore store = MemorySpeedDialStore();
      final HomeWidgets w = HomeWidgets(
        bridge: bridge,
        store: store,
        clock: () => now,
        doses: () async => <MedicineDose>[MedicineDose(name: 'Vitamin D', at: DateTime(2026, 11, 9, 9, 0))],
      );
      final List<WidgetAction> seen = <WidgetAction>[];
      w.onAction = seen.add;
      await w.load();
      expect(bridge.published.last['medicine_title'], 'Vitamin D');
      expect(w.published, isTrue);

      expect(await w.addSpeedDial(const SpeedDialEntry(label: 'Doctor', number: '98765 43210')), isTrue);
      expect(await w.addSpeedDial(const SpeedDialEntry(label: 'Again', number: '9876543210')), isFalse);
      expect(await w.addSpeedDial(const SpeedDialEntry(label: '', number: '9876543210')), isFalse);
      expect(store.saved.single.label, 'Doctor');
      expect(bridge.published.last['dial_0_number'], '9876543210');

      await w.attach();
      expect(seen, <WidgetAction>[WidgetAction.paste]);
      bridge.tap(WidgetAction.scan);
      bridge.handler!('not-a-link');
      expect(seen, <WidgetAction>[WidgetAction.paste, WidgetAction.scan]);

      final HomeWidgets again = HomeWidgets(bridge: MemoryWidgetBridge(), store: store, clock: () => now);
      await again.load();
      expect(again.speedDial.single.number, '98765 43210');
      expect(await again.removeSpeedDial(0), isTrue);
      expect(store.saved, isEmpty);
    });

    test('the Widgets screen opens no files, so batch does not apply', () {
      expect(BatchPolicy.byFeature[112]!.kind, BatchKind.noPicker);
    });

    test('native widget, tile and iOS extension are declared', () {
      final String manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
      expect(manifest, contains('.FamilyWidgetProvider'));
      expect(manifest, contains('android.appwidget.action.APPWIDGET_UPDATE'));
      expect(manifest, contains('.ScanTileService'));
      expect(manifest, contains('android.permission.BIND_QUICK_SETTINGS_TILE'));
      expect(File('android/app/src/main/res/xml/family_widget_info.xml').existsSync(), isTrue);
      expect(File('android/app/src/main/res/layout/family_widget.xml').existsSync(), isTrue);
      final String swift = File('ios/FamilyWidget/FamilyWidget.swift').readAsStringSync();
      expect(swift, contains('accessoryRectangular'));
      expect(swift, contains('systemSmall'));
      expect(swift, contains('familyapp://widget/scan'));
      final String plist = File('ios/Runner/Info.plist').readAsStringSync();
      expect(plist, contains('<string>familyapp</string>'));
      expect(File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync(), contains('FamilyWidget.appex'));
    });
  });

  testWidgets('screen: preview, add and remove a number, Undo, Share', (WidgetTester tester) async {
    final SemanticsHandle sem = tester.ensureSemantics();
    final MemoryWidgetBridge bridge = MemoryWidgetBridge();
    final HomeWidgets w = HomeWidgets(bridge: bridge, store: MemorySpeedDialStore(), clock: () => now);
    await w.load();
    String? shared;
    await tester.pumpWidget(MaterialApp(
      home: HomeWidgetScreen(widgets: w, share: (String t) async => shared = t),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('widget-preview')), findsOneWidget);
    expect(find.text('No medicine due'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Widget preview')), findsOneWidget);
    expect(find.text('Share'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('dial-label')), 'Doctor');
    await tester.enterText(find.byKey(const Key('dial-number')), '+91 98765 43210');
    await tester.ensureVisible(find.byKey(const Key('dial-add')));
    await tester.tap(find.byKey(const Key('dial-add')));
    await tester.pumpAndSettle();
    expect(w.speedDial.single.label, 'Doctor');
    expect(find.byKey(const Key('dial-0')), findsOneWidget);
    expect(tester.getSize(find.byKey(const Key('dial-remove-0'))).height, greaterThanOrEqualTo(44));
    expect(tester.getSize(find.byKey(const Key('dial-add'))).height, greaterThanOrEqualTo(44));
    expect(find.byTooltip('Remove Doctor'), findsOneWidget);

    await tester.tap(find.byKey(const Key('result-undo')));
    await tester.pumpAndSettle();
    expect(w.speedDial, isEmpty);

    await tester.tap(find.byKey(const Key('result-undo')));
    await tester.pumpAndSettle();
    expect(find.text('Nothing to undo'), findsOneWidget);

    await tester.tap(find.byKey(const Key('result-share')));
    await tester.pumpAndSettle();
    expect(shared, contains('Next medicine: No medicine due'));
    expect(shared, contains('Buttons: Scan, Paste'));
    sem.dispose();
  });
}
