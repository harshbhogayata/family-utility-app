import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../engines/records/medicine_reminders.dart';

/// 088: dose and refill alarms through the phone's own scheduler. Android
/// uses exact alarms that fire while the phone dozes (USE_EXACT_ALARM /
/// SCHEDULE_EXACT_ALARM in the manifest) and survive a reboot; if exact
/// alarms are refused it falls back to inexact ones. iOS uses local
/// notifications with the `medicine_due` category's Taken and Snooze.
///
/// The plugin itself is initialised by NotificationJobHost, which routes
/// taps with a `med:` payload to [MedicineReminders.handleTap].
class NotificationMedicineAlarms implements MedicineAlarmScheduler {
  NotificationMedicineAlarms({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  static const String channelId = 'medicine_reminders';
  static const String channelName = 'Medicine reminders';
  static const String iosCategory = 'medicine_due';

  final FlutterLocalNotificationsPlugin _plugin;
  bool _tzReady = false;
  bool _asked = false;

  NotificationDetails _details(DoseAlarm a) {
    return NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        channelName,
        channelDescription: 'Dose times and refill reminders',
        importance: Importance.max,
        priority: Priority.high,
        category: AndroidNotificationCategory.reminder,
        actions: a.isDose
            ? const <AndroidNotificationAction>[
                AndroidNotificationAction(MedicineReminders.takenAction, 'Taken', showsUserInterface: true),
                AndroidNotificationAction(MedicineReminders.snoozeAction, 'Snooze 10 min', showsUserInterface: true),
              ]
            : null,
      ),
      iOS: DarwinNotificationDetails(categoryIdentifier: a.isDose ? iosCategory : null),
    );
  }

  Future<void> _ask() async {
    if (_asked) {
      return;
    }
    _asked = true;
    try {
      await _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      await _plugin
          .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: false, sound: true);
    } catch (e) {
      debugPrint('medicine alarm permission: $e');
    }
  }

  @override
  Future<void> replaceAll(List<DoseAlarm> alarms) async {
    if (!_tzReady) {
      tzdata.initializeTimeZones();
      _tzReady = true;
    }
    if (alarms.isNotEmpty) {
      await _ask();
    }
    final List<PendingNotificationRequest> pending = await _plugin.pendingNotificationRequests();
    for (final PendingNotificationRequest p in pending) {
      if (MedicineReminders.ownsPayload(p.payload)) {
        await _plugin.cancel(p.id);
      }
    }
    // iOS keeps at most 64 pending notifications; the soonest go first.
    for (final DoseAlarm a in alarms.take(60)) {
      // The absolute instant is what matters, so UTC needs no zone lookup.
      final tz.TZDateTime at = tz.TZDateTime.from(a.at.toUtc(), tz.UTC);
      try {
        await _schedule(a, at, AndroidScheduleMode.exactAllowWhileIdle);
      } on PlatformException catch (e) {
        debugPrint('exact alarm refused, using inexact: $e');
        await _schedule(a, at, AndroidScheduleMode.inexactAllowWhileIdle);
      }
    }
  }

  Future<void> _schedule(DoseAlarm a, tz.TZDateTime at, AndroidScheduleMode mode) {
    return _plugin.zonedSchedule(
      a.id,
      a.title,
      a.body,
      at,
      _details(a),
      androidScheduleMode: mode,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      payload: a.payload,
    );
  }
}
