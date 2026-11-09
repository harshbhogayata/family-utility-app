import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../engines/family/member_profiles.dart';
import '../engines/platform/accessibility.dart';
import '../family/calendar/calendar_reminder_host.dart';
import '../tools/app_lock/lock_screen.dart';
import 'shell.dart';
import 'strings_scope.dart';
import 'theme.dart';

/// The app's root navigator, for screens opened from outside the widget tree
/// (another app calling the scanner, feature 047).
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

class FamilyUtilityApp extends StatelessWidget {
  const FamilyUtilityApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[AccessibilityPrefs.instance, MemberProfiles.instance]),
      builder: (BuildContext context, Widget? _) => _app(AccessibilityPrefs.instance.value),
    );
  }

  Widget _app(AccessibilitySettings a) {
    // 110: the active profile's language. English keeps Flutter's defaults.
    final String code = MemberProfiles.instance.active.language;
    final bool english = code == 'en';
    return MaterialApp(
      navigatorKey: appNavigatorKey,
      locale: english ? null : Locale(code),
      supportedLocales: english ? const <Locale>[Locale('en', 'US')] : <Locale>[Locale(code), const Locale('en')],
      localizationsDelegates: english ? null : GlobalMaterialLocalizations.delegates,
      title: 'Family Utility',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      darkTheme: buildAppTheme(brightness: Brightness.dark),
      themeMode: themeModeFor(a.theme),
      builder: (BuildContext context, Widget? child) => ProfileStringsScope(
        child: AccessibleFrame(settings: a, child: child),
      ),
      home: const LockGate(child: CalendarReminderHost(child: AppShell())),
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
