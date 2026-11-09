import 'package:flutter/material.dart';

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
    return MaterialApp(
      navigatorKey: appNavigatorKey,
      title: 'Family Utility',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: const LockGate(child: CalendarReminderHost(child: AppShell())),
    );
  }
}
