import 'dart:async';

import 'package:flutter/foundation.dart';

import '../family/family_space.dart';
import '../family/family_store.dart';
import 'bills.dart' show Bill;
import 'expense_tracker.dart' show formatPaise;

/// Feature 098 — Maintenance log.
///
/// Household upkeep such as AC service, water filter, pest control: each
/// item repeats every N months from the last service, keeps the service
/// history (date, cost, note) and a service contact to call. Reminders a
/// few days ahead and on the due day. Kept on the family store so the
/// household sees the same list; nothing is uploaded.

enum UpkeepKind {
  ac('AC service'),
  waterFilter('Water filter'),
  pestControl('Pest control'),
  chimney('Kitchen chimney'),
  tank('Water tank cleaning'),
  vehicle('Vehicle service'),
  other('Other');

  const UpkeepKind(this.label);
  final String label;

  static UpkeepKind byName(Object? n) => UpkeepKind.values.firstWhere((UpkeepKind k) => k.name == n, orElse: () => UpkeepKind.other);
}

class ServiceVisit {
  const ServiceVisit({required this.on, this.paise, this.note = ''});

  final DateTime on;
  final int? paise;
  final String note;

  Map<String, Object?> toJson() => <String, Object?>{
        'on': on.toIso8601String(),
        if (paise != null) 'paise': paise,
        if (note.isNotEmpty) 'note': note,
      };

  static ServiceVisit? fromJson(Object? o) {
    if (o is! Map) {
      return null;
    }
    final DateTime? on = DateTime.tryParse('${o['on'] ?? ''}');
    if (on == null) {
      return null;
    }
    final Object? p = o['paise'];
    return ServiceVisit(on: on, paise: p is num ? p.toInt() : null, note: '${o['note'] ?? ''}');
  }
}

class UpkeepItem {
  const UpkeepItem({
    required this.id,
    required this.name,
    required this.kind,
    required this.everyMonths,
    required this.nextDue,
    this.contactName = '',
    this.contactPhone = '',
    this.visits = const <ServiceVisit>[],
  });

  final String id;
  final String name;
  final UpkeepKind kind;
  final int everyMonths;
  final DateTime nextDue;
  final String contactName;
  final String contactPhone;

  /// Oldest first.
  final List<ServiceVisit> visits;

  ServiceVisit? get lastVisit => visits.isEmpty ? null : visits.last;

  String get dialable => contactPhone.replaceAll(RegExp(r'[^0-9+]'), '');

  Uri? get callUri => dialable.isEmpty ? null : Uri(scheme: 'tel', path: dialable);

  Map<String, Object?> toFields() => <String, Object?>{
        'name': name,
        'kind': kind.name,
        'every': everyMonths,
        'next': nextDue.toIso8601String(),
        if (contactName.isNotEmpty) 'contact': contactName,
        if (contactPhone.isNotEmpty) 'phone': contactPhone,
        'visits': visits.map((ServiceVisit v) => v.toJson()).toList(),
      };

  static UpkeepItem fromRecord(FamilyRecord r) {
    final Map<String, Object?> f = r.fields;
    final Object? every = f['every'];
    final Object? vs = f['visits'];
    return UpkeepItem(
      id: r.id,
      name: '${f['name'] ?? ''}',
      kind: UpkeepKind.byName(f['kind']),
      everyMonths: every is num && every > 0 ? every.toInt() : 3,
      nextDue: DateTime.tryParse('${f['next'] ?? ''}') ?? DateTime(2000),
      contactName: '${f['contact'] ?? ''}',
      contactPhone: '${f['phone'] ?? ''}',
      visits: vs is List ? vs.map(ServiceVisit.fromJson).whereType<ServiceVisit>().toList() : const <ServiceVisit>[],
    );
  }

  UpkeepItem copyWith({DateTime? nextDue, List<ServiceVisit>? visits, String? contactName, String? contactPhone}) => UpkeepItem(
        id: id,
        name: name,
        kind: kind,
        everyMonths: everyMonths,
        nextDue: nextDue ?? this.nextDue,
        contactName: contactName ?? this.contactName,
        contactPhone: contactPhone ?? this.contactPhone,
        visits: visits ?? this.visits,
      );
}

enum UpkeepState { overdue, dueSoon, later }

class UpkeepReminder {
  const UpkeepReminder({required this.id, required this.at, required this.title, required this.body, required this.payload});
  final int id;
  final DateTime at;
  final String title;
  final String body;
  final String payload;
}

abstract interface class UpkeepReminderScheduler {
  Future<void> replaceAll(List<UpkeepReminder> reminders);
}

class NoUpkeepReminders implements UpkeepReminderScheduler {
  const NoUpkeepReminders();
  @override
  Future<void> replaceAll(List<UpkeepReminder> reminders) async {}
}

class MaintenanceLog extends ChangeNotifier {
  MaintenanceLog({
    FamilySpace? space,
    FamilyStore? soloStore,
    UpkeepReminderScheduler reminders = const NoUpkeepReminders(),
    DateTime Function()? now,
    this.remindHour = 9,
  })  : _space = space,
        _solo = soloStore,
        _scheduler = reminders,
        _now = now ?? DateTime.now;

  static const String collection = 'maintenance';
  static const String payloadPrefix = 'upkeep:';
  static const int idBase = 9500000;
  static const int soonDays = 7;
  static const int remindDaysBefore = 3;
  static const List<int> periods = <int>[1, 2, 3, 4, 6, 12, 24];

  final FamilySpace? _space;
  final FamilyStore? _solo;
  final UpkeepReminderScheduler _scheduler;
  final DateTime Function() _now;
  final int remindHour;
  int _seq = 0;

  FamilySpace get space => _space ?? FamilySpace.instance;
  FamilyStore get store => space.inFamily ? space.store : (_solo ?? space.store);

  /// Soonest due first.
  List<UpkeepItem> get all {
    final List<UpkeepItem> l = store.list(collection).map(UpkeepItem.fromRecord).toList();
    l.sort((UpkeepItem a, UpkeepItem b) {
      final int c = a.nextDue.compareTo(b.nextDue);
      return c != 0 ? c : a.name.compareTo(b.name);
    });
    return l;
  }

  UpkeepItem? byId(String id) {
    final FamilyRecord? r = store.get(collection, id);
    return r == null ? null : UpkeepItem.fromRecord(r);
  }

  (String, Map<String, Object?>?)? _undo;

  void _remember(String id) => _undo = (id, store.get(collection, id)?.fields);

  void _changed() {
    notifyListeners();
    unawaited(reschedule());
  }

  DateTime _today() {
    final DateTime n = _now();
    return DateTime(n.year, n.month, n.day);
  }

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  static DateTime _after(DateTime from, int months) => Bill.addMonths(from, months, from.day);

  /// Adds an item. With [lastDone] the first due date is that plus the
  /// interval (and the visit is logged); otherwise [firstDue] or today.
  UpkeepItem? add({
    required String name,
    required UpkeepKind kind,
    required int everyMonths,
    DateTime? lastDone,
    DateTime? firstDue,
    String contactName = '',
    String contactPhone = '',
  }) {
    if (!periods.contains(everyMonths) || (lastDone != null && _day(lastDone).isAfter(_today()))) {
      return null;
    }
    final String n = name.trim().isEmpty ? kind.label : name.trim();
    final String id = 'm${_now().microsecondsSinceEpoch}-${_seq++}';
    final UpkeepItem item = UpkeepItem(
      id: id,
      name: n,
      kind: kind,
      everyMonths: everyMonths,
      nextDue: lastDone != null ? _after(_day(lastDone), everyMonths) : _day(firstDue ?? _today()),
      contactName: contactName.trim(),
      contactPhone: contactPhone.trim(),
      visits: lastDone == null ? const <ServiceVisit>[] : <ServiceVisit>[ServiceVisit(on: _day(lastDone))],
    );
    _remember(id);
    store.put(collection, id, item.toFields());
    _changed();
    return item;
  }

  /// Logs a service and moves the next due date to that day plus the interval.
  bool markDone(String id, {DateTime? on, int? paise, String note = ''}) {
    final UpkeepItem? item = byId(id);
    final DateTime day = _day(on ?? _today());
    if (item == null || (paise != null && paise <= 0) || day.isAfter(_today())) {
      return false;
    }
    final List<ServiceVisit> visits = <ServiceVisit>[...item.visits, ServiceVisit(on: day, paise: paise, note: note.trim())]
      ..sort((ServiceVisit a, ServiceVisit b) => a.on.compareTo(b.on));
    _remember(id);
    store.put(collection, id, item.copyWith(nextDue: _after(visits.last.on, item.everyMonths), visits: visits).toFields());
    _changed();
    return true;
  }

  bool setContact(String id, {required String name, required String phone}) {
    final UpkeepItem? item = byId(id);
    if (item == null) {
      return false;
    }
    _remember(id);
    store.put(collection, id, item.copyWith(contactName: name.trim(), contactPhone: phone.trim()).toFields());
    _changed();
    return true;
  }

  bool remove(String id) {
    if (byId(id) == null) {
      return false;
    }
    _remember(id);
    store.delete(collection, id);
    _changed();
    return true;
  }

  bool undo() {
    final (String, Map<String, Object?>?)? u = _undo;
    if (u == null) {
      return false;
    }
    _undo = null;
    if (u.$2 == null) {
      store.delete(collection, u.$1);
    } else {
      store.put(collection, u.$1, u.$2!);
    }
    _changed();
    return true;
  }

  int daysUntil(UpkeepItem i) {
    final DateTime t = _today();
    return DateTime.utc(i.nextDue.year, i.nextDue.month, i.nextDue.day).difference(DateTime.utc(t.year, t.month, t.day)).inDays;
  }

  UpkeepState state(UpkeepItem i) {
    final int d = daysUntil(i);
    return d < 0 ? UpkeepState.overdue : (d <= soonDays ? UpkeepState.dueSoon : UpkeepState.later);
  }

  /// Total spent on an item across its logged visits.
  static int spent(UpkeepItem i) => i.visits.fold<int>(0, (int s, ServiceVisit v) => s + (v.paise ?? 0));

  static int _id(String key) {
    int h = 0;
    for (final int c in key.codeUnits) {
      h = (h * 31 + c) & 0x3FFFF;
    }
    return idBase + h;
  }

  static String amountLabel(int paise) => '₹${formatPaise(paise)}';

  static String periodLabel(int months) => switch (months) {
        1 => 'Every month',
        12 => 'Every year',
        24 => 'Every 2 years',
        _ => 'Every $months months',
      };

  /// [remindDaysBefore] days ahead and on the due day; tomorrow morning
  /// while overdue.
  List<UpkeepReminder> reminders() {
    final DateTime now = _now();
    final DateTime today = _today();
    final List<UpkeepReminder> out = <UpkeepReminder>[];
    for (final UpkeepItem i in all) {
      final List<(DateTime, String)> times = state(i) == UpkeepState.overdue
          ? <(DateTime, String)>[(DateTime(today.year, today.month, today.day + 1, remindHour), 'is overdue')]
          : <(DateTime, String)>[
              (DateTime(i.nextDue.year, i.nextDue.month, i.nextDue.day - remindDaysBefore, remindHour), 'is due in $remindDaysBefore days'),
              (DateTime(i.nextDue.year, i.nextDue.month, i.nextDue.day, remindHour), 'is due today'),
            ];
      final String who = i.contactName.isNotEmpty ? i.contactName : i.contactPhone;
      for (final (DateTime, String) t in times) {
        if (!t.$1.isAfter(now)) {
          continue;
        }
        out.add(UpkeepReminder(
          id: _id('${i.id}@${t.$2}'),
          at: t.$1,
          title: '${i.name} ${t.$2}',
          body: 'Due ${dayLabel(i.nextDue)}${who.isEmpty ? '' : ' · call $who'}. Tap to log the service.',
          payload: '$payloadPrefix${i.id}',
        ));
      }
    }
    out.sort((UpkeepReminder a, UpkeepReminder b) => a.at.compareTo(b.at));
    return out;
  }

  Future<void> reschedule() async {
    try {
      await _scheduler.replaceAll(reminders());
    } catch (e) {
      debugPrint('maintenance reminders: $e');
    }
  }

  static const List<String> months = <String>['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  static String dayLabel(DateTime d) => '${d.day} ${months[d.month - 1]} ${d.year}';

  String toText() {
    final StringBuffer b = StringBuffer('Maintenance log\n');
    for (final UpkeepItem i in all) {
      b.write('- ${i.name}: ${periodLabel(i.everyMonths).toLowerCase()}, next ${dayLabel(i.nextDue)}');
      if (i.contactName.isNotEmpty || i.contactPhone.isNotEmpty) {
        b.write(' · ${<String>[i.contactName, i.contactPhone].where((String s) => s.isNotEmpty).join(' ')}');
      }
      b.write('\n');
      for (final ServiceVisit v in i.visits.reversed.take(6)) {
        b.write('    done ${dayLabel(v.on)}${v.paise == null ? '' : ' · ${amountLabel(v.paise!)}'}${v.note.isEmpty ? '' : ' · ${v.note}'}\n');
      }
    }
    return b.toString();
  }

  static MaintenanceLog instance = MaintenanceLog();
  static void install(MaintenanceLog m) => instance = m;
}
