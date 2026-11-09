import 'package:flutter/widgets.dart';

import '../../engines/family/document_vault.dart';
import '../../engines/family/family_location.dart';
import '../../engines/family/shared_calendar.dart';

/// Feature 071 — runs the shared calendar's reminder check while the app's
/// widget tree is alive.
class CalendarReminderHost extends StatefulWidget {
  const CalendarReminderHost({super.key, required this.child});

  final Widget child;

  @override
  State<CalendarReminderHost> createState() => _CalendarReminderHostState();
}

class _CalendarReminderHostState extends State<CalendarReminderHost> {
  @override
  void initState() {
    super.initState();
    CalendarReminderWatcher.instance?.start();
    DocumentReminderWatcher.instance?.start(); // 074
    LocationTracker.instance?.start(); // 076
  }

  @override
  void dispose() {
    CalendarReminderWatcher.instance?.stop();
    DocumentReminderWatcher.instance?.stop();
    LocationTracker.instance?.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
