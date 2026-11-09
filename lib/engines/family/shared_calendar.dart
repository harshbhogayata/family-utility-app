import 'dart:async';

import 'package:flutter/foundation.dart';

import 'family_space.dart';
import 'family_store.dart';

/// Feature 071 — Shared calendar.
///
/// Events live in the family store's `calendar` collection, so they reach
/// every family phone over Wi-Fi or the own-cloud folder, and two phones
/// that edit the same event offline merge to the same winner (vector clocks,
/// see [FamilyStore.merge]). Nothing here talks to any server.

enum EventRepeat { none, daily, weekly, monthly, yearly }

extension EventRepeatLabel on EventRepeat {
  String get label {
    switch (this) {
      case EventRepeat.none:
        return 'Does not repeat';
      case EventRepeat.daily:
        return 'Every day';
      case EventRepeat.weekly:
        return 'Every week';
      case EventRepeat.monthly:
        return 'Every month';
      case EventRepeat.yearly:
        return 'Every year';
    }
  }

  /// RFC 5545 FREQ value, or null for a one-off event.
  String? get rrule {
    switch (this) {
      case EventRepeat.none:
        return null;
      case EventRepeat.daily:
        return 'DAILY';
      case EventRepeat.weekly:
        return 'WEEKLY';
      case EventRepeat.monthly:
        return 'MONTHLY';
      case EventRepeat.yearly:
        return 'YEARLY';
    }
  }
}

@immutable
class CalendarEvent {
  const CalendarEvent({
    required this.id,
    required this.title,
    required this.start,
    required this.duration,
    required this.memberId,
    this.repeat = EventRepeat.none,
    this.until,
    this.remindBefore,
    this.note = '',
  });

  final String id;
  final String title;

  /// Local wall time of the first occurrence.
  final DateTime start;
  final Duration duration;

  /// Device id of the family member the event belongs to (sets its colour).
  final String memberId;
  final EventRepeat repeat;

  /// Last day a repeating event may occur on (inclusive), if any.
  final DateTime? until;

  /// How long before each occurrence to remind; null for no reminder.
  final Duration? remindBefore;
  final String note;

  DateTime get end => start.add(duration);

  CalendarEvent copyWith({
    String? title,
    DateTime? start,
    Duration? duration,
    String? memberId,
    EventRepeat? repeat,
    DateTime? until,
    bool clearUntil = false,
    Duration? remindBefore,
    bool clearRemind = false,
    String? note,
  }) {
    return CalendarEvent(
      id: id,
      title: title ?? this.title,
      start: start ?? this.start,
      duration: duration ?? this.duration,
      memberId: memberId ?? this.memberId,
      repeat: repeat ?? this.repeat,
      until: clearUntil ? null : (until ?? this.until),
      remindBefore: clearRemind ? null : (remindBefore ?? this.remindBefore),
      note: note ?? this.note,
    );
  }

  Map<String, Object?> toFields() => <String, Object?>{
        'title': title,
        'start': start.toIso8601String(),
        'minutes': duration.inMinutes,
        'member': memberId,
        'repeat': repeat.name,
        if (until != null) 'until': until!.toIso8601String(),
        if (remindBefore != null) 'remind': remindBefore!.inMinutes,
        if (note.isNotEmpty) 'note': note,
      };

  static CalendarEvent? fromRecord(FamilyRecord r) {
    final Map<String, Object?> f = r.fields;
    final DateTime? start = DateTime.tryParse('${f['start'] ?? ''}');
    if (start == null) {
      return null;
    }
    final Object? minutes = f['minutes'];
    final Object? remind = f['remind'];
    final String repeatName = '${f['repeat'] ?? 'none'}';
    EventRepeat repeat = EventRepeat.none;
    for (final EventRepeat each in EventRepeat.values) {
      if (each.name == repeatName) {
        repeat = each;
      }
    }
    return CalendarEvent(
      id: r.id,
      title: '${f['title'] ?? ''}',
      start: start,
      duration: Duration(minutes: minutes is num && minutes > 0 ? minutes.toInt() : 60),
      memberId: '${f['member'] ?? r.writer}',
      repeat: repeat,
      until: DateTime.tryParse('${f['until'] ?? ''}'),
      remindBefore: remind is num ? Duration(minutes: remind.toInt()) : null,
      note: '${f['note'] ?? ''}',
    );
  }

  /// The [n]th occurrence's start (n = 0 is [start]). Monthly and yearly
  /// repeats skip months without that day (31st, 29 Feb) instead of rolling
  /// into the next month, like phone calendars do.
  DateTime? occurrenceStart(int n) {
    if (n == 0) {
      return start;
    }
    switch (repeat) {
      case EventRepeat.none:
        return null;
      case EventRepeat.daily:
        return DateTime(start.year, start.month, start.day + n, start.hour, start.minute);
      case EventRepeat.weekly:
        return DateTime(start.year, start.month, start.day + 7 * n, start.hour, start.minute);
      case EventRepeat.monthly:
        final DateTime d = DateTime(start.year, start.month + n, start.day, start.hour, start.minute);
        return d.day == start.day ? d : null;
      case EventRepeat.yearly:
        final DateTime d = DateTime(start.year + n, start.month, start.day, start.hour, start.minute);
        return d.day == start.day ? d : null;
    }
  }

  /// Occurrences that overlap [from, to).
  List<EventOccurrence> occurrencesBetween(DateTime from, DateTime to) {
    final List<EventOccurrence> out = <EventOccurrence>[];
    final DateTime? last = until == null ? null : DateTime(until!.year, until!.month, until!.day, 23, 59, 59);
    for (int n = 0; n < 100000; n++) {
      final DateTime? s = occurrenceStart(n);
      if (repeat == EventRepeat.none && n > 0) {
        break;
      }
      if (s == null) {
        continue; // a skipped month or year
      }
      if (!s.isBefore(to) || (last != null && s.isAfter(last))) {
        break;
      }
      if (s.add(duration).isAfter(from)) {
        out.add(EventOccurrence(this, s));
      }
    }
    return out;
  }
}

@immutable
class EventOccurrence {
  const EventOccurrence(this.event, this.start);

  final CalendarEvent event;
  final DateTime start;

  DateTime get end => start.add(event.duration);

  DateTime? get remindAt => event.remindBefore == null ? null : start.subtract(event.remindBefore!);

  bool overlaps(EventOccurrence other) => start.isBefore(other.end) && other.start.isBefore(end);

  @override
  bool operator ==(Object other) => other is EventOccurrence && other.event.id == event.id && other.start == start;

  @override
  int get hashCode => Object.hash(event.id, start);
}

/// Shows a reminder (a local notification on the phone).
abstract class CalendarReminderSink {
  Future<void> remind(EventOccurrence occurrence);
}

/// Adds an event to the phone's own calendar (one-way; never read back).
abstract class PhoneCalendarExport {
  Future<bool> add(CalendarEvent event);
}

class SharedCalendar extends ChangeNotifier {
  SharedCalendar({FamilySpace? space, DateTime Function()? now})
      : _space = space,
        _now = now ?? DateTime.now;

  static const String collection = 'calendar';

  final FamilySpace? _space;
  final DateTime Function() _now;
  int _seq = 0;

  /// The record as it was before the last change, for Undo. A null value
  /// means the event did not exist before.
  ({String id, Map<String, Object?>? fields})? _undo;

  FamilySpace get space => _space ?? FamilySpace.instance;
  FamilyStore get store => space.store;
  bool get canUndo => _undo != null;

  List<CalendarEvent> get events => store
      .list(collection)
      .map(CalendarEvent.fromRecord)
      .whereType<CalendarEvent>()
      .toList();

  CalendarEvent? event(String id) {
    final FamilyRecord? r = store.get(collection, id);
    return r == null ? null : CalendarEvent.fromRecord(r);
  }

  /// A new id, unique across phones (device id + time + counter).
  String newId() => '${space.identity?.deviceId ?? 'local'}-${_now().microsecondsSinceEpoch}-${_seq++}';

  CalendarEvent save(CalendarEvent e) {
    _remember(e.id);
    store.put(collection, e.id, e.toFields());
    notifyListeners();
    return e;
  }

  bool delete(String id) {
    if (store.get(collection, id) == null) {
      return false;
    }
    _remember(id);
    store.delete(collection, id);
    notifyListeners();
    return true;
  }

  /// Puts back the event the last save or delete changed.
  bool undo() {
    final ({String id, Map<String, Object?>? fields})? u = _undo;
    if (u == null) {
      return false;
    }
    _undo = null;
    if (u.fields == null) {
      store.delete(collection, u.id);
    } else {
      store.put(collection, u.id, u.fields!);
    }
    notifyListeners();
    return true;
  }

  void _remember(String id) {
    final FamilyRecord? old = store.get(collection, id);
    _undo = (id: id, fields: old == null ? null : Map<String, Object?>.of(old.fields));
  }

  /// Every occurrence in [from, to), soonest first.
  List<EventOccurrence> occurrences(DateTime from, DateTime to) {
    final List<EventOccurrence> out = <EventOccurrence>[
      for (final CalendarEvent e in events) ...e.occurrencesBetween(from, to),
    ];
    out.sort((EventOccurrence a, EventOccurrence b) {
      final int c = a.start.compareTo(b.start);
      return c != 0 ? c : a.event.title.compareTo(b.event.title);
    });
    return out;
  }

  /// Occurrences whose reminder time falls in (since, until].
  List<EventOccurrence> dueReminders(DateTime since, DateTime until) {
    final Duration longest = events.fold<Duration>(
      Duration.zero,
      (Duration m, CalendarEvent e) => e.remindBefore != null && e.remindBefore! > m ? e.remindBefore! : m,
    );
    return occurrences(since, until.add(longest + const Duration(days: 1))).where((EventOccurrence o) {
      final DateTime? at = o.remindAt;
      return at != null && at.isAfter(since) && !at.isAfter(until);
    }).toList();
  }

  /// Pairs of occurrences for the same member that overlap in [from, to).
  List<(EventOccurrence, EventOccurrence)> clashes(DateTime from, DateTime to) {
    final List<EventOccurrence> all = occurrences(from, to);
    final List<(EventOccurrence, EventOccurrence)> out = <(EventOccurrence, EventOccurrence)>[];
    for (int i = 0; i < all.length; i++) {
      for (int j = i + 1; j < all.length && all[j].start.isBefore(all[i].end); j++) {
        if (all[i].event.memberId == all[j].event.memberId && all[i].overlaps(all[j])) {
          out.add((all[i], all[j]));
        }
      }
    }
    return out;
  }

  /// The whole calendar as an iCalendar (.ics) file, for Share or for
  /// importing into any calendar app.
  String toIcs({DateTime? stamp}) {
    final StringBuffer b = StringBuffer()
      ..write('BEGIN:VCALENDAR\r\n')
      ..write('VERSION:2.0\r\n')
      ..write('PRODID:-//Family Utility App//Shared calendar//EN\r\n');
    final String dtstamp = _icsUtc(stamp ?? _now());
    for (final CalendarEvent e in events) {
      b
        ..write('BEGIN:VEVENT\r\n')
        ..write('UID:${e.id}@family.app\r\n')
        ..write('DTSTAMP:$dtstamp\r\n')
        ..write('DTSTART:${_icsLocal(e.start)}\r\n')
        ..write('DTEND:${_icsLocal(e.end)}\r\n')
        ..write('SUMMARY:${_icsText(e.title.isEmpty ? 'Event' : e.title)}\r\n');
      if (e.note.isNotEmpty) {
        b.write('DESCRIPTION:${_icsText(e.note)}\r\n');
      }
      final String? freq = e.repeat.rrule;
      if (freq != null) {
        final DateTime? u = e.until;
        b.write('RRULE:FREQ=$freq${u == null ? '' : ';UNTIL=${_icsLocal(DateTime(u.year, u.month, u.day, 23, 59, 59))}'}\r\n');
      }
      if (e.remindBefore != null) {
        b
          ..write('BEGIN:VALARM\r\n')
          ..write('ACTION:DISPLAY\r\n')
          ..write('DESCRIPTION:${_icsText(e.title)}\r\n')
          ..write('TRIGGER:-PT${e.remindBefore!.inMinutes}M\r\n')
          ..write('END:VALARM\r\n');
      }
      b.write('END:VEVENT\r\n');
    }
    b.write('END:VCALENDAR\r\n');
    return b.toString();
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  static String _icsLocal(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}${_two(d.month)}${_two(d.day)}T${_two(d.hour)}${_two(d.minute)}${_two(d.second)}';

  static String _icsUtc(DateTime d) => '${_icsLocal(d.toUtc())}Z';

  static String _icsText(String s) => s
      .replaceAll(r'\', r'\\')
      .replaceAll(';', r'\;')
      .replaceAll(',', r'\,')
      .replaceAll('\r\n', r'\n')
      .replaceAll('\n', r'\n');

  /// The app's one shared calendar. Bootstrap may install another.
  static SharedCalendar instance = SharedCalendar();

  static void install(SharedCalendar calendar) => instance = calendar;
}

/// Checks for due reminders once a minute while the app runs, and once
/// right away, so a reminder made on another phone still fires here.
class CalendarReminderWatcher {
  CalendarReminderWatcher({
    required this.calendar,
    required this.sink,
    DateTime Function()? now,
    this.every = const Duration(minutes: 1),
  }) : _now = now ?? DateTime.now;

  final SharedCalendar calendar;
  final CalendarReminderSink sink;
  final DateTime Function() _now;
  final Duration every;
  Timer? _timer;
  DateTime? _last;

  void start() {
    _last = _now();
    _timer?.cancel();
    _timer = Timer.periodic(every, (_) => unawaited(check()));
  }

  /// Fires every reminder that came due since the last check.
  Future<int> check() async {
    final DateTime now = _now();
    final DateTime since = _last ?? now.subtract(every);
    _last = now;
    final List<EventOccurrence> due = calendar.dueReminders(since, now);
    for (final EventOccurrence o in due) {
      try {
        await sink.remind(o);
      } catch (_) {
        // Notifications off: the event is still on the calendar screen.
      }
    }
    return due.length;
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }
}
