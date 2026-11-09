import 'dart:async';

import 'package:flutter/foundation.dart';

import '../family/family_roles.dart';
import '../family/family_space.dart';
import '../family/family_store.dart';

/// Feature 088 — Medicine reminders with pill stock.
///
/// Dose times per person, a taken / skipped log, tablets left and a refill
/// reminder. Medicines live in the family store, so a carer the member (or
/// an adult) has allowed sees the same schedule and log on their own phone.
/// Nothing leaves the family's phones. Alarms are handed to a
/// [MedicineAlarmScheduler]; on Android that schedules exact alarms.

/// One medicine for one member.
class Medicine {
  const Medicine({
    required this.id,
    required this.memberId,
    required this.name,
    required this.times,
    this.tabletsPerDose = 1,
    this.stock = 0,
    this.refillAt = 5,
    this.carers = const <String>[],
    this.note = '',
  });

  final String id;
  final String memberId;
  final String name;

  /// Dose times as minutes after midnight, sorted.
  final List<int> times;
  final int tabletsPerDose;

  /// Tablets left.
  final int stock;

  /// Remind to refill when [stock] is at or below this.
  final int refillAt;

  /// Members allowed to see and log this medicine besides [memberId].
  final List<String> carers;
  final String note;

  bool get needsRefill => stock <= refillAt;

  int get perDay => tabletsPerDose * times.length;

  /// Whole days the stock lasts at this schedule.
  int get daysLeft => perDay == 0 ? 0 : stock ~/ perDay;

  Map<String, Object?> toFields() => <String, Object?>{
        'member': memberId,
        'name': name,
        'times': times,
        'per': tabletsPerDose,
        'stock': stock,
        'refillAt': refillAt,
        'carers': carers,
        'note': note,
      };

  static Medicine fromRecord(FamilyRecord r) {
    final Map<String, Object?> f = r.fields;
    List<int> ints(Object? o) => o is List ? o.whereType<num>().map((num n) => n.toInt()).toList() : <int>[];
    List<String> strs(Object? o) => o is List ? o.whereType<String>().toList() : <String>[];
    int intOf(Object? o, int d) => o is num ? o.toInt() : d;
    return Medicine(
      id: r.id,
      memberId: '${f['member'] ?? ''}',
      name: '${f['name'] ?? 'Medicine'}',
      times: ints(f['times'])..sort(),
      tabletsPerDose: intOf(f['per'], 1),
      stock: intOf(f['stock'], 0),
      refillAt: intOf(f['refillAt'], 5),
      carers: strs(f['carers']),
      note: '${f['note'] ?? ''}',
    );
  }

  Medicine copyWith({int? stock, List<String>? carers}) => Medicine(
        id: id,
        memberId: memberId,
        name: name,
        times: times,
        tabletsPerDose: tabletsPerDose,
        stock: stock ?? this.stock,
        refillAt: refillAt,
        carers: carers ?? this.carers,
        note: note,
      );

  /// "08:00" for 480.
  static String clock(int minutes) =>
      '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';

  /// Parses "8:00, 20:30" into sorted minutes; null when any part is bad.
  static List<int>? parseTimes(String text) {
    final List<int> out = <int>[];
    for (final String raw in text.split(RegExp(r'[,\s]+'))) {
      final String p = raw.trim();
      if (p.isEmpty) {
        continue;
      }
      final RegExpMatch? m = RegExp(r'^(\d{1,2})[:.](\d{2})$').firstMatch(p);
      if (m == null) {
        return null;
      }
      final int h = int.parse(m.group(1)!);
      final int min = int.parse(m.group(2)!);
      if (h > 23 || min > 59) {
        return null;
      }
      final int v = h * 60 + min;
      if (!out.contains(v)) {
        out.add(v);
      }
    }
    if (out.isEmpty) {
      return null;
    }
    out.sort();
    return out;
  }
}

enum DoseStatus {
  pending('Due'),
  taken('Taken'),
  skipped('Skipped'),
  snoozed('Snoozed');

  const DoseStatus(this.label);
  final String label;

  static DoseStatus byName(Object? n) =>
      DoseStatus.values.firstWhere((DoseStatus s) => s.name == n, orElse: () => DoseStatus.pending);
}

/// One scheduled dose and what happened to it.
class Dose {
  const Dose({required this.medicine, required this.due, this.status = DoseStatus.pending, this.at, this.until, this.by});

  final Medicine medicine;
  final DateTime due;
  final DoseStatus status;

  /// When it was taken, skipped or snoozed.
  final DateTime? at;

  /// When a snoozed dose rings again.
  final DateTime? until;

  /// Member id of whoever logged it.
  final String? by;

  String get key => MedicineReminders.doseKey(medicine.id, due);

  bool get open => status == DoseStatus.pending || status == DoseStatus.snoozed;
}

/// An alarm the platform should ring.
class DoseAlarm {
  const DoseAlarm({required this.id, required this.at, required this.title, required this.body, required this.payload});

  final int id;
  final DateTime at;
  final String title;
  final String body;
  final String payload;

  /// True for dose alarms (Taken and Snooze buttons); false for refills.
  bool get isDose => payload.startsWith(MedicineReminders.payloadPrefix) && payload.contains('@');
}

/// Rings dose and refill alarms. The app replaces the whole set each time.
abstract interface class MedicineAlarmScheduler {
  Future<void> replaceAll(List<DoseAlarm> alarms);
}

class NoMedicineAlarms implements MedicineAlarmScheduler {
  const NoMedicineAlarms();
  @override
  Future<void> replaceAll(List<DoseAlarm> alarms) async {}
}

class MedicineReminders extends ChangeNotifier {
  MedicineReminders({
    FamilySpace? space,
    FamilyRoles? roles,
    FamilyStore? soloStore,
    MedicineAlarmScheduler alarms = const NoMedicineAlarms(),
    DateTime Function()? now,
    this.snoozeFor = const Duration(minutes: 10),
    this.horizon = const Duration(hours: 48),
    this.refillHour = 10,
  })  : _space = space,
        _roles = roles,
        _solo = soloStore,
        _alarms = alarms,
        _now = now ?? DateTime.now;

  static const String medicines = 'medicines';
  static const String doses = 'doses';
  static const String payloadPrefix = 'med:';
  static const String takenAction = 'med_taken';
  static const String snoozeAction = 'med_snooze';
  static const int alarmIdBase = 880000;

  /// Id used for this phone's member when not in a family.
  static const String soloMember = 'me';

  final FamilySpace? _space;
  final FamilyRoles? _roles;
  final FamilyStore? _solo;
  final MedicineAlarmScheduler _alarms;
  final DateTime Function() _now;
  final Duration snoozeFor;
  final Duration horizon;
  final int refillHour;

  FamilySpace get space => _space ?? FamilySpace.instance;
  FamilyRoles get roles => _roles ?? FamilyRoles(space: space);

  /// The family store when in a family, else this phone's own store.
  FamilyStore get store => space.inFamily ? space.store : (_solo ?? space.store);

  String get me => space.identity?.deviceId ?? soloMember;

  static String doseKey(String medicineId, DateTime due) => '$medicineId@${due.millisecondsSinceEpoch}';

  /// Member ids and names this phone can pick from.
  Map<String, String> get members {
    final Map<String, String> out = <String, String>{};
    if (!space.inFamily) {
      out[soloMember] = 'Me';
      return out;
    }
    for (final FamilyRecord m in space.memberRecords) {
      out[m.id] = '${m.fields['name'] ?? 'Member'}';
    }
    out.putIfAbsent(me, () => 'Me');
    return out;
  }

  String nameOf(String memberId) => members[memberId] ?? 'Member';

  /// Every medicine in the store, whoever it is for.
  List<Medicine> get all => store.list(medicines).map(Medicine.fromRecord).toList();

  /// The member themself and the carers they allowed see a schedule.
  bool canSee(Medicine m) => !space.inFamily || m.memberId == me || m.carers.contains(me);

  /// Only the member, or an adult, chooses who cares for a medicine.
  bool canGrant(Medicine m) => !space.inFamily || m.memberId == me || (roles.iManage && m.carers.contains(me));

  /// Medicines visible on this phone.
  List<Medicine> get visible => all.where(canSee).toList();

  Medicine? byId(String id) {
    final FamilyRecord? r = store.get(medicines, id);
    return r == null ? null : Medicine.fromRecord(r);
  }

  final List<_Undo> _undo = <_Undo>[];

  void _remember(List<String> keys) {
    _undo
      ..clear()
      ..addAll(keys.map((String k) {
        final List<String> p = k.split('|');
        return _Undo(p[0], p[1], store.get(p[0], p[1])?.fields);
      }));
  }

  /// Adds a medicine. Whoever adds it for someone else becomes a carer.
  Medicine? add({
    required String name,
    required List<int> times,
    String? memberId,
    int tabletsPerDose = 1,
    int stock = 0,
    int refillAt = 5,
    List<String> carers = const <String>[],
    String note = '',
  }) {
    final String who = memberId ?? me;
    if (name.trim().isEmpty || times.isEmpty || tabletsPerDose < 1 || stock < 0 || refillAt < 0) {
      return null;
    }
    final Set<String> care = <String>{...carers.where((String c) => c != who)};
    if (who != me) {
      care.add(me);
    }
    final String id = 'm${_now().microsecondsSinceEpoch}';
    final Medicine m = Medicine(
      id: id,
      memberId: who,
      name: name.trim(),
      times: List<int>.of(times)..sort(),
      tabletsPerDose: tabletsPerDose,
      stock: stock,
      refillAt: refillAt,
      carers: care.toList(),
      note: note,
    );
    _remember(<String>['$medicines|$id']);
    store.put(medicines, id, m.toFields());
    _changed();
    return m;
  }

  bool remove(String id) {
    final Medicine? m = byId(id);
    if (m == null || !canSee(m)) {
      return false;
    }
    _remember(<String>['$medicines|$id']);
    store.delete(medicines, id);
    _changed();
    return true;
  }

  /// Lets [memberId] see and log [medicineId], or takes that away.
  bool setCarer(String medicineId, String memberId, bool allowed) {
    final Medicine? m = byId(medicineId);
    if (m == null || !canGrant(m) || memberId == m.memberId) {
      return false;
    }
    final List<String> c = List<String>.of(m.carers)..remove(memberId);
    if (allowed) {
      c.add(memberId);
    }
    if (c.length == m.carers.length && m.carers.contains(memberId) == allowed) {
      return false;
    }
    _remember(<String>['$medicines|$medicineId']);
    store.put(medicines, medicineId, m.copyWith(carers: c).toFields());
    _changed();
    return true;
  }

  /// Adds a new strip or bottle to the stock.
  bool refill(String medicineId, int tablets) {
    final Medicine? m = byId(medicineId);
    if (m == null || tablets <= 0 || !canSee(m)) {
      return false;
    }
    _remember(<String>['$medicines|$medicineId']);
    store.put(medicines, medicineId, m.copyWith(stock: m.stock + tablets).toFields());
    _changed();
    return true;
  }

  Dose _dose(Medicine m, DateTime due) {
    final FamilyRecord? r = store.get(doses, doseKey(m.id, due));
    if (r == null) {
      return Dose(medicine: m, due: due);
    }
    DateTime? t(Object? o) => o is num ? DateTime.fromMillisecondsSinceEpoch(o.toInt()) : null;
    return Dose(
      medicine: m,
      due: due,
      status: DoseStatus.byName(r.fields['status']),
      at: t(r.fields['at']),
      until: t(r.fields['until']),
      by: r.fields['by'] as String?,
    );
  }

  /// Doses on [day] for visible medicines (or one member), by time.
  List<Dose> dosesOn(DateTime day, {String? memberId}) {
    final List<Dose> out = <Dose>[];
    for (final Medicine m in visible) {
      if (memberId != null && m.memberId != memberId) {
        continue;
      }
      for (final int t in m.times) {
        out.add(_dose(m, DateTime(day.year, day.month, day.day, t ~/ 60, t % 60)));
      }
    }
    out.sort((Dose a, Dose b) {
      final int c = a.due.compareTo(b.due);
      return c != 0 ? c : a.medicine.name.compareTo(b.medicine.name);
    });
    return out;
  }

  List<Dose> get today => dosesOn(_now());

  /// Doses from [days] days ago up to now, newest first.
  List<Dose> log({int days = 7}) {
    final DateTime now = _now();
    final List<Dose> out = <Dose>[];
    for (int i = 0; i <= days; i++) {
      final DateTime d = DateTime(now.year, now.month, now.day - i);
      out.addAll(dosesOn(d).where((Dose x) => !x.due.isAfter(now) || x.status != DoseStatus.pending));
    }
    out.sort((Dose a, Dose b) => b.due.compareTo(a.due));
    return out;
  }

  Dose? _find(String medicineId, DateTime due) {
    final Medicine? m = byId(medicineId);
    if (m == null || !canSee(m) || !m.times.contains(due.hour * 60 + due.minute)) {
      return null;
    }
    return _dose(m, due);
  }

  void _logDose(Medicine m, DateTime due, DoseStatus s, {DateTime? until}) {
    store.put(doses, doseKey(m.id, due), <String, Object?>{
      'med': m.id,
      'member': m.memberId,
      'due': due.millisecondsSinceEpoch,
      'status': s.name,
      'at': _now().millisecondsSinceEpoch,
      if (until != null) 'until': until.millisecondsSinceEpoch,
      'by': me,
    });
  }

  /// Marks a dose taken and takes its tablets off the stock. A dose already
  /// taken is not counted twice.
  bool markTaken(String medicineId, DateTime due) {
    final Dose? d = _find(medicineId, due);
    if (d == null || d.status == DoseStatus.taken) {
      return false;
    }
    final Medicine m = d.medicine;
    _remember(<String>['$medicines|${m.id}', '$doses|${d.key}']);
    final int left = m.stock - m.tabletsPerDose;
    store.put(medicines, m.id, m.copyWith(stock: left < 0 ? 0 : left).toFields());
    _logDose(m, due, DoseStatus.taken);
    _changed();
    return true;
  }

  bool skip(String medicineId, DateTime due) {
    final Dose? d = _find(medicineId, due);
    if (d == null || d.status == DoseStatus.skipped || d.status == DoseStatus.taken) {
      return false;
    }
    _remember(<String>['$doses|${d.key}']);
    _logDose(d.medicine, due, DoseStatus.skipped);
    _changed();
    return true;
  }

  /// Rings again after [snoozeFor].
  DateTime? snooze(String medicineId, DateTime due) {
    final Dose? d = _find(medicineId, due);
    if (d == null || !d.open) {
      return null;
    }
    final DateTime until = _now().add(snoozeFor);
    _remember(<String>['$doses|${d.key}']);
    _logDose(d.medicine, due, DoseStatus.snoozed, until: until);
    _changed();
    return until;
  }

  bool undo() {
    if (_undo.isEmpty) {
      return false;
    }
    for (final _Undo u in _undo) {
      final Map<String, Object?>? f = u.fields;
      if (f == null) {
        store.delete(u.collection, u.id);
      } else {
        store.put(u.collection, u.id, f);
      }
    }
    _undo.clear();
    _changed();
    return true;
  }

  /// Payload for a dose alarm.
  static String payloadFor(String medicineId, DateTime due) => '$payloadPrefix${doseKey(medicineId, due)}';

  static bool ownsPayload(String? payload) => payload != null && payload.startsWith(payloadPrefix);

  /// Handles a tap on an alarm's Taken or Snooze button. Returns true when
  /// it changed something; a plain tap only opens the app.
  bool handleTap(String? actionId, String? payload) {
    if (!ownsPayload(payload)) {
      return false;
    }
    final String key = payload!.substring(payloadPrefix.length);
    final int at = key.lastIndexOf('@');
    if (at < 0) {
      return false;
    }
    final int? millis = int.tryParse(key.substring(at + 1));
    if (millis == null) {
      return false;
    }
    final String id = key.substring(0, at);
    final DateTime due = DateTime.fromMillisecondsSinceEpoch(millis);
    if (actionId == takenAction) {
      return markTaken(id, due);
    }
    if (actionId == snoozeAction) {
      return snooze(id, due) != null;
    }
    return false;
  }

  static int _alarmId(String key) {
    int h = 0;
    for (final int c in key.codeUnits) {
      h = (h * 31 + c) & 0x3FFFFF;
    }
    return alarmIdBase + h;
  }

  /// Alarms this phone should ring: its member's doses and those it cares
  /// for, still open, within [horizon]; plus a daily refill reminder.
  List<DoseAlarm> alarms() {
    final DateTime now = _now();
    final DateTime end = now.add(horizon);
    final List<DoseAlarm> out = <DoseAlarm>[];
    final int days = horizon.inDays + 1;
    for (int i = 0; i <= days; i++) {
      final DateTime day = DateTime(now.year, now.month, now.day + i);
      for (final Dose d in dosesOn(day)) {
        if (!d.open) {
          continue;
        }
        final DateTime ring = d.status == DoseStatus.snoozed && d.until != null ? d.until! : d.due;
        if (!ring.isAfter(now) || ring.isAfter(end)) {
          continue;
        }
        final Medicine m = d.medicine;
        final String who = m.memberId == me ? '' : ' for ${nameOf(m.memberId)}';
        final String tabs = m.tabletsPerDose == 1 ? '1 tablet' : '${m.tabletsPerDose} tablets';
        out.add(DoseAlarm(
          id: _alarmId(d.key),
          at: ring,
          title: '${m.name}$who',
          body: '$tabs at ${Medicine.clock(d.due.hour * 60 + d.due.minute)} · ${m.stock} left',
          payload: payloadFor(m.id, d.due),
        ));
      }
    }
    for (final Medicine m in visible.where((Medicine m) => m.needsRefill)) {
      DateTime ring = DateTime(now.year, now.month, now.day, refillHour);
      if (!ring.isAfter(now)) {
        ring = DateTime(now.year, now.month, now.day + 1, refillHour);
      }
      out.add(DoseAlarm(
        id: _alarmId('refill:${m.id}'),
        at: ring,
        title: 'Refill ${m.name}',
        body: '${m.stock} tablets left for ${nameOf(m.memberId)}',
        payload: '${payloadPrefix}refill:${m.id}',
      ));
    }
    out.sort((DoseAlarm a, DoseAlarm b) => a.at.compareTo(b.at));
    return out;
  }

  /// Hands the current alarms to the platform.
  Future<void> reschedule() async {
    try {
      await _alarms.replaceAll(alarms());
    } catch (e) {
      debugPrint('medicine alarms: $e');
    }
  }

  void _changed() {
    notifyListeners();
    unawaited(reschedule());
  }

  /// Schedule, stock and the last week's log, for Share and Save.
  String toText() {
    final StringBuffer b = StringBuffer('Medicines\n');
    final List<Medicine> list = visible;
    if (list.isEmpty) {
      b.writeln('None yet.');
    }
    for (final Medicine m in list) {
      b.writeln();
      b.writeln('${m.name} — ${nameOf(m.memberId)}');
      b.writeln('  ${m.tabletsPerDose} at ${m.times.map(Medicine.clock).join(', ')}');
      b.writeln('  ${m.stock} left (about ${m.daysLeft} days)${m.needsRefill ? ' — refill now' : ''}');
      if (m.carers.isNotEmpty) {
        b.writeln('  Carers: ${m.carers.map(nameOf).join(', ')}');
      }
    }
    final List<Dose> logged = log().where((Dose d) => d.status != DoseStatus.pending).toList();
    if (logged.isNotEmpty) {
      b.writeln();
      b.writeln('Last 7 days');
      for (final Dose d in logged) {
        final DateTime t = d.due;
        b.writeln('  ${t.day}/${t.month} ${Medicine.clock(t.hour * 60 + t.minute)} ${d.medicine.name}: ${d.status.label}');
      }
    }
    return b.toString();
  }

  static MedicineReminders instance = MedicineReminders();
  static void install(MedicineReminders m) => instance = m;
}

class _Undo {
  _Undo(this.collection, this.id, this.fields);
  final String collection;
  final String id;
  final Map<String, Object?>? fields;
}
