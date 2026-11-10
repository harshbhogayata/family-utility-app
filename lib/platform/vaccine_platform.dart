import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../engines/records/vaccinations.dart';

/// 092: vaccine due reminders as local notifications.
class NotificationVaccineReminders implements VaccineReminderScheduler {
  NotificationVaccineReminders({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  static const String channelId = 'vaccine_reminders';
  static const String channelName = 'Vaccinations';

  final FlutterLocalNotificationsPlugin _plugin;
  bool _tzReady = false;

  static const NotificationDetails _details = NotificationDetails(
    android: AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: 'A week before and on the day a vaccine is due',
      importance: Importance.high,
      priority: Priority.high,
      category: AndroidNotificationCategory.reminder,
    ),
    iOS: DarwinNotificationDetails(),
  );

  @override
  Future<void> replaceAll(List<VaccineReminder> reminders) async {
    if (!_tzReady) {
      tzdata.initializeTimeZones();
      _tzReady = true;
    }
    final List<PendingNotificationRequest> pending = await _plugin.pendingNotificationRequests();
    for (final PendingNotificationRequest p in pending) {
      if (p.payload != null && p.payload!.startsWith(Vaccinations.payloadPrefix)) {
        await _plugin.cancel(p.id);
      }
    }
    // Leave room in iOS's 64 pending notifications for other reminders.
    for (final VaccineReminder r in reminders.take(8)) {
      final tz.TZDateTime at = tz.TZDateTime.from(r.at.toUtc(), tz.UTC);
      try {
        await _schedule(r, at, AndroidScheduleMode.inexactAllowWhileIdle);
      } on PlatformException catch (e) {
        debugPrint('vaccine reminder: $e');
      }
    }
  }

  Future<void> _schedule(VaccineReminder r, tz.TZDateTime at, AndroidScheduleMode mode) {
    return _plugin.zonedSchedule(
      r.id,
      r.title,
      r.body,
      at,
      _details,
      androidScheduleMode: mode,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      payload: r.payload,
    );
  }
}
