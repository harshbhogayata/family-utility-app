import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../engines/records/subscriptions.dart';

/// 084: renewal and trial-end reminders as local notifications.
class NotificationSubscriptionReminders implements SubscriptionReminderScheduler {
  NotificationSubscriptionReminders({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  static const String channelId = 'subscription_reminders';
  static const String channelName = 'Subscriptions';

  final FlutterLocalNotificationsPlugin _plugin;
  bool _tzReady = false;

  static const NotificationDetails _details = NotificationDetails(
    android: AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: 'Before each renewal and trial end',
      importance: Importance.high,
      priority: Priority.high,
      category: AndroidNotificationCategory.reminder,
    ),
    iOS: DarwinNotificationDetails(),
  );

  @override
  Future<void> replaceAll(List<SubscriptionReminder> reminders) async {
    if (!_tzReady) {
      tzdata.initializeTimeZones();
      _tzReady = true;
    }
    final List<PendingNotificationRequest> pending = await _plugin.pendingNotificationRequests();
    for (final PendingNotificationRequest p in pending) {
      if (p.payload != null && p.payload!.startsWith(Subscriptions.payloadPrefix)) {
        await _plugin.cancel(p.id);
      }
    }
    // Leave room in iOS's 64 pending notifications for other reminders.
    for (final SubscriptionReminder r in reminders.take(8)) {
      final tz.TZDateTime at = tz.TZDateTime.from(r.at.toUtc(), tz.UTC);
      try {
        await _schedule(r, at, AndroidScheduleMode.inexactAllowWhileIdle);
      } on PlatformException catch (e) {
        debugPrint('subscription reminder: $e');
      }
    }
  }

  Future<void> _schedule(SubscriptionReminder r, tz.TZDateTime at, AndroidScheduleMode mode) {
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
