import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../engines/records/bills.dart';

/// 083: bill due reminders as local notifications.
class NotificationBillReminders implements BillReminderScheduler {
  NotificationBillReminders({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  static const String channelId = 'bill_reminders';
  static const String channelName = 'Bills';

  final FlutterLocalNotificationsPlugin _plugin;
  bool _tzReady = false;

  static const NotificationDetails _details = NotificationDetails(
    android: AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: 'Three days before and on the due date',
      importance: Importance.high,
      priority: Priority.high,
      category: AndroidNotificationCategory.reminder,
    ),
    iOS: DarwinNotificationDetails(),
  );

  @override
  Future<void> replaceAll(List<BillReminder> reminders) async {
    if (!_tzReady) {
      tzdata.initializeTimeZones();
      _tzReady = true;
    }
    final List<PendingNotificationRequest> pending = await _plugin.pendingNotificationRequests();
    for (final PendingNotificationRequest p in pending) {
      if (p.payload != null && p.payload!.startsWith(Bills.payloadPrefix)) {
        await _plugin.cancel(p.id);
      }
    }
    // Leave room in iOS's 64 pending notifications for other reminders.
    for (final BillReminder r in reminders.take(12)) {
      final tz.TZDateTime at = tz.TZDateTime.from(r.at.toUtc(), tz.UTC);
      try {
        await _schedule(r, at, AndroidScheduleMode.inexactAllowWhileIdle);
      } on PlatformException catch (e) {
        debugPrint('bill reminder: $e');
      }
    }
  }

  Future<void> _schedule(BillReminder r, tz.TZDateTime at, AndroidScheduleMode mode) {
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
