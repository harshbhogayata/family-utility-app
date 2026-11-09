import 'package:add_2_calendar/add_2_calendar.dart' as cal;
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../engines/family/shared_calendar.dart';

/// Feature 071 — reminders as local notifications. The plugin is set up at
/// app start by the job notification host (feature 067).
class NotificationCalendarReminders implements CalendarReminderSink {
  NotificationCalendarReminders({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  static const int idBase = 710000;

  @override
  Future<void> remind(EventOccurrence occurrence) async {
    final CalendarEvent e = occurrence.event;
    final DateTime s = occurrence.start;
    final String when = '${s.hour.toString().padLeft(2, '0')}:${s.minute.toString().padLeft(2, '0')}';
    await _plugin.show(
      idBase + (occurrence.hashCode & 0xFFFF),
      e.title.isEmpty ? 'Family event' : e.title,
      'Starts at $when',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'family_calendar',
          'Family calendar',
          channelDescription: 'Reminders for shared calendar events',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
    );
  }
}

/// One-way export: opens the phone's calendar with the event filled in.
class Add2CalendarExport implements PhoneCalendarExport {
  @override
  Future<bool> add(CalendarEvent event) async {
    try {
      return await cal.Add2Calendar.addEvent2Cal(
        cal.Event(
          title: event.title.isEmpty ? 'Family event' : event.title,
          description: event.note,
          location: '',
          startDate: event.start,
          endDate: event.end,
          allDay: event.duration.inMinutes >= 1440,
        ),
      );
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
