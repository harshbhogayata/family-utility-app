import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../engines/records/occasions.dart';

/// 095: birthdays and anniversaries read from the phone's own contacts
/// (read-only permission); nothing leaves the phone.
class PhoneContactDates implements ContactDatesSource {
  const PhoneContactDates();

  @override
  Future<List<ContactDate>> read() async {
    if (!await FlutterContacts.requestPermission(readonly: true)) {
      return const <ContactDate>[];
    }
    final List<Contact> contacts = await FlutterContacts.getContacts(withProperties: true);
    final List<ContactDate> out = <ContactDate>[];
    for (final Contact c in contacts) {
      for (final Event e in c.events) {
        final OccasionKind? kind = e.label == EventLabel.birthday
            ? OccasionKind.birthday
            : e.label == EventLabel.anniversary
                ? OccasionKind.anniversary
                : null;
        if (kind == null) {
          continue;
        }
        out.add(ContactDate(
          name: c.displayName,
          kind: kind,
          month: e.month,
          day: e.day,
          year: e.year,
          phone: c.phones.isEmpty ? '' : c.phones.first.number,
        ));
      }
    }
    return out;
  }
}

/// 095: the 7-day and 1-day reminders as local notifications.
class NotificationOccasionReminders implements OccasionReminderScheduler {
  NotificationOccasionReminders({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  static const String channelId = 'occasion_reminders';
  static const String channelName = 'Birthdays and anniversaries';

  final FlutterLocalNotificationsPlugin _plugin;
  bool _tzReady = false;

  static const NotificationDetails _details = NotificationDetails(
    android: AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: 'A week and a day before each date',
      importance: Importance.high,
      priority: Priority.high,
      category: AndroidNotificationCategory.reminder,
    ),
    iOS: DarwinNotificationDetails(),
  );

  @override
  Future<void> replaceAll(List<OccasionReminder> reminders) async {
    if (!_tzReady) {
      tzdata.initializeTimeZones();
      _tzReady = true;
    }
    final List<PendingNotificationRequest> pending = await _plugin.pendingNotificationRequests();
    for (final PendingNotificationRequest p in pending) {
      if (p.payload != null && p.payload!.startsWith(Occasions.payloadPrefix)) {
        await _plugin.cancel(p.id);
      }
    }
    // Leave room in iOS's 64 pending notifications for medicine alarms.
    for (final OccasionReminder r in reminders.take(20)) {
      final tz.TZDateTime at = tz.TZDateTime.from(r.at.toUtc(), tz.UTC);
      try {
        await _schedule(r, at, AndroidScheduleMode.inexactAllowWhileIdle);
      } on PlatformException catch (e) {
        debugPrint('occasion reminder: $e');
      }
    }
  }

  Future<void> _schedule(OccasionReminder r, tz.TZDateTime at, AndroidScheduleMode mode) {
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
