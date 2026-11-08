import 'dart:io';

import 'package:family_utility_app/app/app.dart';
import 'package:family_utility_app/app/bootstrap.dart';
import 'package:family_utility_app/app/theme.dart';
import 'package:family_utility_app/app/tool_registry.dart';
import 'package:family_utility_app/engines/platform/first_run.dart';
import 'package:family_utility_app/engines/security/app_lock.dart';
import 'package:family_utility_app/tools/app_lock/app_lock_settings_screen.dart';
import 'package:family_utility_app/tools/tools_home.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AccountPolicy', () {
    test('no account screen copy anywhere in lib/', () {
      final List<String> problems = <String>[];
      for (final FileSystemEntity f in Directory('lib').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) {
          continue;
        }
        final String rel = f.path.replaceAll(r'\', '/');
        if (rel == 'lib/engines/platform/first_run.dart') {
          continue; // the rule itself
        }
        problems.addAll(AccountPolicy.violationsInSource(rel, f.readAsStringSync()));
      }
      expect(problems, isEmpty);
    });

    test('no account, analytics or ads packages in pubspec', () {
      expect(AccountPolicy.violationsInPubspec(File('pubspec.yaml').readAsStringSync()), isEmpty);
      expect(
        AccountPolicy.violationsInPubspec('dependencies:\n  firebase_auth: ^5.0.0\n'),
        <String>['pubspec declares firebase_auth'],
      );
    });

    test('the rule flags account copy but allows talking about the rule', () {
      expect(AccountPolicy.violationsInSource('x.dart', "Text('Sign in to continue')"), hasLength(1));
      expect(AccountPolicy.violationsInSource('x.dart', "Text('No sign-up, no account')"), isEmpty);
      expect(AccountPolicy.violationsInSource('x.dart', "Text('Nothing to sign up for')"), isEmpty);
    });
  });

  group('first run', () {
    late MemoryFirstRunStore store;
    late FirstRun firstRun;

    setUp(() {
      store = MemoryFirstRunStore();
      firstRun = FirstRun(store);
      FirstRun.install(firstRun);
      AppLock.install(AppLock(store: MemoryLockStore()));
      ToolRegistry.clear();
    });

    tearDown(ToolRegistry.clear);

    test('welcome shows once; a broken store never shows it', () async {
      await firstRun.load();
      expect(firstRun.showWelcome, isTrue);
      await firstRun.dismiss();
      expect(firstRun.showWelcome, isFalse);
      final FirstRun again = FirstRun(store);
      await again.load();
      expect(again.showWelcome, isFalse);
      final FirstRun broken = FirstRun(_BrokenStore());
      await broken.load();
      expect(broken.showWelcome, isFalse);
    });

    testWidgets('first run to first tool: no account screen, tool opens straight away',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      bootstrap();
      FirstRun.install(firstRun);
      AppLock.install(AppLock(store: MemoryLockStore()));
      await firstRun.load();
      final Stopwatch sw = Stopwatch()..start();
      await tester.pumpWidget(const FamilyUtilityApp());
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('welcome-card')), findsOneWidget);
      expect(find.textContaining('Sign in'), findsNothing);
      expect(find.textContaining('Log in'), findsNothing);
      expect(find.textContaining('Create account'), findsNothing);

      // The card does not block the grid: a tool opens with one tap.
      await tester.tap(find.widgetWithText(ToolTile, 'Secure notes'));
      await tester.pumpAndSettle();
      sw.stop();
      expect(find.text('Secure notes'), findsWidgets);
      expect(find.text('No notes yet'), findsOneWidget);
      expect(sw.elapsed, lessThan(const Duration(seconds: 10)));
    });

    testWidgets('Got it dismisses the card for good; Set a PIN opens App lock', (WidgetTester tester) async {
      await firstRun.load();
      await tester.pumpWidget(MaterialApp(theme: buildAppTheme(), home: const Scaffold(body: ToolsHome())));
      expect(find.byKey(const Key('welcome-card')), findsOneWidget);
      await tester.tap(find.byKey(const Key('welcome-set-pin')));
      await tester.pumpAndSettle();
      expect(find.byType(AppLockSettingsScreen), findsOneWidget);
      expect(firstRun.showWelcome, isFalse);
      expect(await store.readWelcomeDone(), isTrue);

      final FirstRun second = FirstRun(MemoryFirstRunStore());
      FirstRun.install(second);
      await second.load();
      await tester.pumpWidget(MaterialApp(theme: buildAppTheme(), home: const Scaffold(body: ToolsHome())));
      expect(find.byKey(const Key('welcome-card')), findsOneWidget);
      final Size gotIt = tester.getSize(find.byKey(const Key('welcome-dismiss')));
      expect(gotIt.height, greaterThanOrEqualTo(44));
      await tester.tap(find.byKey(const Key('welcome-dismiss')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('welcome-card')), findsNothing);
    });
  });
}

class _BrokenStore implements FirstRunStore {
  @override
  Future<bool> readWelcomeDone() async => throw StateError('no disk');

  @override
  Future<void> writeWelcomeDone() async => throw StateError('no disk');
}
