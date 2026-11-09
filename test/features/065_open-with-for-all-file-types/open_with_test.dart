import 'dart:io';

import 'package:family_utility_app/app/theme.dart';
import 'package:family_utility_app/app/tool_registry.dart';
import 'package:family_utility_app/engines/family/member_profiles.dart';
import 'package:family_utility_app/engines/share/open_with.dart';
import 'package:family_utility_app/tools/open_with/opened_file_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void registerTools(List<String> ids) {
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

void main() {
  group('registration', () {
    test('Android VIEW filter lists every type, 50+ across all families', () {
      final String manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
      final int view = manifest.indexOf('android.intent.action.VIEW');
      expect(view, greaterThan(0));
      final String filter = manifest.substring(view, manifest.indexOf('</intent-filter>', view));
      for (final String m in OpenWithTypes.androidMimeTypes) {
        expect(filter, contains('android:mimeType="$m"'), reason: m);
      }
      expect(filter, contains('android:scheme="content"'));
      expect(OpenWithTypes.androidMimeTypes.toSet().length, greaterThanOrEqualTo(50));
      for (final String family in <String>['application/pdf', 'image/', 'video/', 'audio/', 'application/zip', 'officedocument']) {
        expect(OpenWithTypes.androidMimeTypes.any((String m) => m.contains(family)), isTrue, reason: family);
      }
    });

    test('iOS document types are registered and copied in', () {
      final String plist = File('ios/Runner/Info.plist').readAsStringSync();
      expect(plist, contains('<key>CFBundleDocumentTypes</key>'));
      expect(plist, contains('<key>LSSupportsOpeningDocumentsInPlace</key>\n\t<false/>'));
      for (final String uti in OpenWithTypes.iosTypes) {
        expect(plist, contains('<string>$uti</string>'), reason: uti);
      }
      for (final String family in <String>['com.adobe.pdf', 'public.image', 'public.movie', 'public.audio', 'public.zip-archive', 'org.openxmlformats.wordprocessingml.document']) {
        expect(OpenWithTypes.iosTypes, contains(family));
      }
    });

    test('over fifty file extensions are known', () {
      expect(OpenWithTypes.extensions.toSet().length, OpenWithTypes.extensions.length);
      expect(OpenWithTypes.extensions.length, greaterThanOrEqualTo(50));
    });
  });

  group('inbox', () {
    test('hands each opened path over once', () async {
      final OpenWithInbox inbox = OpenWithInbox();
      final List<List<String>> got = <List<String>>[];
      inbox.onFiles = got.add;
      await inbox.handle(const MethodCall('files', <Object?>['/c/a.pdf', 3, '/c/b.jpg']));
      expect(got.single, <String>['/c/a.pdf', '/c/b.jpg']);
      expect(inbox.take(), <String>['/c/a.pdf', '/c/b.jpg']);
      expect(inbox.take(), isNull);
      inbox.receive(<String>['/c/a.pdf']);
      expect(got, hasLength(1));
      await expectLater(inbox.handle(const MethodCall('other')), throwsA(isA<MissingPluginException>()));
    });

    test('iOS inbox scan picks up new files only', () async {
      final Directory tmp = await Directory.systemTemp.createTemp('inbox');
      addTearDown(() => tmp.delete(recursive: true));
      final OpenWithInbox inbox = OpenWithInbox();
      await inbox.scanInbox('${tmp.path}/Inbox');
      expect(inbox.take(), isNull);
      final Directory box = await Directory('${tmp.path}/Inbox').create();
      await File('${box.path}/bill.pdf').writeAsString('%PDF');
      await inbox.scanInbox(box.path);
      expect(inbox.take(), <String>['${box.path}/bill.pdf']);
      await File('${box.path}/photo.jpg').writeAsString('jpg');
      await inbox.scanInbox(box.path);
      expect(inbox.take(), <String>['${box.path}/photo.jpg']);
    });
  });

  group('default-app prompt', () {
    test('Android only, after an open, never again once dismissed', () async {
      final MemoryDefaultAppPromptStore store = MemoryDefaultAppPromptStore();
      final DefaultAppPrompt p = DefaultAppPrompt(store);
      expect(p.shouldShow(isAndroid: true, openedOk: true), isFalse, reason: 'not loaded yet');
      await p.load();
      expect(p.shouldShow(isAndroid: true, openedOk: true), isTrue);
      expect(p.shouldShow(isAndroid: false, openedOk: true), isFalse);
      expect(p.shouldShow(isAndroid: true, openedOk: false), isFalse);
      await p.dismiss();
      expect(p.shouldShow(isAndroid: true, openedOk: true), isFalse);
      expect(store.dismissed, isTrue);
      final DefaultAppPrompt again = DefaultAppPrompt(store);
      await again.load();
      expect(again.shouldShow(isAndroid: true, openedOk: true), isFalse);
    });
  });

  group('opened file screen', () {
    setUp(() {
      ToolRegistry.clear();
      MemberProfiles.install(MemberProfiles(MemoryProfileStore()));
      registerTools(<String>['merge-pdf', 'sign-pdf', 'compress-pdf', 'resize', 'exif']);
    });

    testWidgets('shows the tools for the file and the one-time card on Android', (WidgetTester tester) async {
      final MemoryDefaultAppPromptStore store = MemoryDefaultAppPromptStore();
      final DefaultAppPrompt prompt = DefaultAppPrompt(store);
      await prompt.load();
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: OpenedFileScreen(paths: const <String>['/cache/opened_in/1/0/bill.pdf'], prompt: prompt, isAndroid: true),
      ));
      await tester.pumpAndSettle();

      expect(find.text('bill.pdf'), findsOneWidget);
      expect(find.text('Suggested for this PDF'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('suggest-merge-pdf')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('suggest-resize')), findsNothing);
      expect(find.text('Make this your PDF and image app?'), findsOneWidget);
      for (final String key in <String>['default-app-settings', 'default-app-dismiss', 'result-share', 'result-save', 'result-undo']) {
        expect(tester.getSize(find.byKey(ValueKey<String>(key))).height, greaterThanOrEqualTo(44), reason: key);
      }

      await tester.tap(find.byKey(const Key('default-app-dismiss')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('default-app-card')), findsNothing);
      expect(store.dismissed, isTrue);

      await tester.tap(find.byKey(const ValueKey<String>('suggest-sign-pdf')));
      await tester.pumpAndSettle();
      expect(find.text('Open sign-pdf'), findsOneWidget);
    });

    testWidgets('Open settings also retires the card; no card on iOS', (WidgetTester tester) async {
      final MemoryDefaultAppPromptStore store = MemoryDefaultAppPromptStore();
      final DefaultAppPrompt prompt = DefaultAppPrompt(store);
      await prompt.load();
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: OpenedFileScreen(paths: const <String>['/x/IMG_1.jpg'], prompt: prompt, isAndroid: true),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Suggested for this photo'), findsOneWidget);
      await tester.tap(find.byKey(const Key('default-app-settings')));
      await tester.pumpAndSettle();
      expect(store.dismissed, isTrue);
      expect(find.byKey(const Key('default-app-card')), findsNothing);

      final DefaultAppPrompt fresh = DefaultAppPrompt(MemoryDefaultAppPromptStore());
      await fresh.load();
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: OpenedFileScreen(paths: const <String>['/x/b.pdf'], prompt: fresh, isAndroid: false),
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('default-app-card')), findsNothing);
      expect(find.text('Suggested for this PDF'), findsOneWidget);
    });
  });
}
