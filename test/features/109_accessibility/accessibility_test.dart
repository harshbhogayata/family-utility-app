import 'package:family_utility_app/app/app.dart';
import 'package:family_utility_app/app/theme.dart';
import 'package:family_utility_app/engines/family/family_board.dart';
import 'package:family_utility_app/engines/family/family_identity.dart';
import 'package:family_utility_app/engines/family/family_space.dart';
import 'package:family_utility_app/engines/family/family_store.dart';
import 'package:family_utility_app/engines/family/family_sync.dart';
import 'package:family_utility_app/engines/platform/accessibility.dart';
import 'package:family_utility_app/family/board/family_board_screen.dart';
import 'package:family_utility_app/tools/accessibility/accessibility_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('engine', () {
    test('every text role meets 4.5:1 in light and dark', () {
      for (final AppPalette p in <AppPalette>[AppPalette.light, AppPalette.dark]) {
        for (final Color bg in <Color>[p.ground, p.surface]) {
          for (final Color fg in <Color>[p.ink, p.muted, p.accent]) {
            expect(contrastRatio(fg, bg), greaterThanOrEqualTo(4.5), reason: '${p.brightness} $fg on $bg');
          }
        }
        expect(contrastRatio(p.onAccent, p.accent), greaterThanOrEqualTo(4.5), reason: '${p.brightness} on accent');
        final TextTheme t = buildTextTheme(p);
        for (final TextStyle? s in <TextStyle?>[t.bodyLarge, t.bodyMedium, t.bodySmall, t.titleLarge, t.labelSmall]) {
          expect(contrastRatio(s!.color!, p.ground), greaterThanOrEqualTo(4.5));
        }
      }
      expect(contrastRatio(Colors.black, Colors.white), closeTo(21, 0.01));
    });

    test('text scale follows the phone, boosted, capped at 200%', () {
      const AccessibilitySettings a = AccessibilitySettings();
      expect(a.textScaleFor(1.0), 1.0);
      expect(a.textScaleFor(1.5), 1.5);
      expect(a.textScaleFor(3.0), 2.0);
      expect(a.copyWith(textBoost: 1.5).textScaleFor(1.2), closeTo(1.8, 1e-9));
      expect(a.copyWith(textBoost: 5).textBoost, 2.0);
    });

    test('settings persist and undo', () async {
      final MemoryAccessibilityStore store = MemoryAccessibilityStore();
      final AccessibilityPrefs p = AccessibilityPrefs(store);
      await p.load();
      expect(p.value, const AccessibilitySettings());
      await p.set(p.value.copyWith(theme: AppThemeChoice.dark, oneHand: true));
      final AccessibilityPrefs again = AccessibilityPrefs(store);
      await again.load();
      expect(again.value.theme, AppThemeChoice.dark);
      expect(again.value.oneHand, isTrue);
      expect(await p.undo(), isTrue);
      expect(p.value.theme, AppThemeChoice.system);
      expect(AccessibilitySettings.decode('not json'), const AccessibilitySettings());
      expect(themeModeFor(AppThemeChoice.dark), ThemeMode.dark);
    });
  });

  testWidgets('a family screen at 200% text in dark mode, one-hand: no overflow, controls labelled',
      (WidgetTester tester) async {
    final SemanticsHandle sem = tester.ensureSemantics();
    final FamilySpace s = FamilySpace(
      identityStore: MemoryFamilyIdentityStore(),
      storage: MemoryFamilyStoreStorage(),
      transportsFor: (FamilyIdentity _) => <FamilySyncTransport>[],
    );
    await tester.runAsync(() => s.create(familyName: 'Shahs', memberName: 'Asha'));
    final FamilyBoard b = FamilyBoard(space: s)..addTask('Pay the electricity bill before Friday');
    const AccessibilitySettings a = AccessibilitySettings(theme: AppThemeChoice.dark, textBoost: 2.0, oneHand: true);
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      darkTheme: buildAppTheme(brightness: Brightness.dark),
      themeMode: themeModeFor(a.theme),
      builder: (BuildContext context, Widget? child) => AccessibleFrame(settings: a, child: child),
      home: FamilyBoardScreen(board: b),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final BuildContext ctx = tester.element(find.byType(FamilyBoardScreen));
    expect(Theme.of(ctx).brightness, Brightness.dark);
    expect(MediaQuery.of(ctx).textScaler.scale(10), 20);
    // One-hand: the screen starts a quarter of the way down.
    expect(tester.getTopLeft(find.byType(AppBar)).dy, greaterThanOrEqualTo(150));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    sem.dispose();
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('settings screen: theme, text size, one-hand, share, save, undo', (WidgetTester tester) async {
    final AccessibilityPrefs p = AccessibilityPrefs(MemoryAccessibilityStore());
    String? shared;
    String? saved;
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: AccessibilityScreen(
        prefs: p,
        share: (String t) async => shared = t,
        save: (String t) async {
          saved = t;
          return '/docs/Accessibility settings.txt';
        },
      ),
    ));
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(p.value.theme, AppThemeChoice.dark);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(p.value.oneHand, isTrue);
    expect(tester.getSize(find.byType(SwitchListTile)).height, greaterThanOrEqualTo(44));

    await tester.tap(find.byKey(const Key('result-share')));
    await tester.pumpAndSettle();
    expect(shared, contains('Theme: Dark'));
    expect(shared, contains('One-hand layout: on'));
    await tester.tap(find.byKey(const Key('result-save')));
    await tester.pumpAndSettle();
    expect(saved, isNotNull);
    await tester.tap(find.byKey(const Key('result-undo')));
    await tester.pumpAndSettle();
    expect(p.value.oneHand, isFalse);
    expect(p.value.theme, AppThemeChoice.dark);
  });
}
