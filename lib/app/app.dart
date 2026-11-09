import 'package:flutter/material.dart';

import '../engines/platform/accessibility.dart';
import '../family/calendar/calendar_reminder_host.dart';
import '../tools/app_lock/lock_screen.dart';
import 'shell.dart';
import 'theme.dart';

/// The app's root navigator, for screens opened from outside the widget tree
/// (another app calling the scanner, feature 047).
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

class FamilyUtilityApp extends StatelessWidget {
  const FamilyUtilityApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AccessibilitySettings>(
      valueListenable: AccessibilityPrefs.instance,
      builder: (BuildContext context, AccessibilitySettings a, Widget? _) => MaterialApp(
        navigatorKey: appNavigatorKey,
        title: 'Family Utility',
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        darkTheme: buildAppTheme(brightness: Brightness.dark),
        themeMode: themeModeFor(a.theme),
        builder: (BuildContext context, Widget? child) => AccessibleFrame(settings: a, child: child),
        home: const LockGate(child: CalendarReminderHost(child: AppShell())),
      ),
    );
  }
}

ThemeMode themeModeFor(AppThemeChoice c) => switch (c) {
      AppThemeChoice.system => ThemeMode.system,
      AppThemeChoice.light => ThemeMode.light,
      AppThemeChoice.dark => ThemeMode.dark,
    };

/// Feature 109: text scale (phone setting × boost, capped at 200%) and the
/// one-hand layout, which lowers every screen by a quarter of its height.
class AccessibleFrame extends StatelessWidget {
  const AccessibleFrame({super.key, required this.settings, required this.child});

  final AccessibilitySettings settings;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final MediaQueryData mq = MediaQuery.of(context);
    final double phone = mq.textScaler.scale(100) / 100;
    Widget c = MediaQuery(
      data: mq.copyWith(textScaler: TextScaler.linear(settings.textScaleFor(phone))),
      child: child ?? const SizedBox.shrink(),
    );
    if (settings.oneHand) {
      final double drop = mq.size.height / 4;
      c = ColoredBox(
        color: Theme.of(context).colorScheme.surface,
        child: Padding(
          padding: EdgeInsets.only(top: drop),
          child: MediaQuery.removePadding(context: context, removeTop: true, child: c),
        ),
      );
    }
    return c;
  }
}
