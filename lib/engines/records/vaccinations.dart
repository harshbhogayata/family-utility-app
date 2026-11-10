import 'dart:async';

import 'package:flutter/foundation.dart';

import '../family/family_space.dart';
import '../family/family_store.dart';

/// Feature 092 — Vaccination record.
///
/// Each person gets the preloaded Indian schedule that fits them (the
/// Universal Immunisation Programme schedule for a child, the common adult
/// boosters for a grown-up). Due dates come from the birth date or the last
/// dose; a reminder goes off a week before and on the day. Certificate scans
/// stay in the app's folder and are linked by path. Shared on the family
/// store; nothing is uploaded.

/// One dose in a schedule.
class VaccineDose {
  const VaccineDose(this.id, this.name, this.when, {this.afterDays = 0, this.repeatDays});

  final String id;
  final String name;

  /// When it is given, as a person reads it: "6 weeks", "Every 10 years".
  final String when;

  /// Days after birth (child) or after the previous dose of [id]'s series.
  final int afterDays;

  /// Repeats this often after it is given (adult boosters, flu).
  final int? repeatDays;
}

enum ScheduleKind { child, adult }

abstract final class IndianSchedule {
  static const int week = 7;

  /// Universal Immunisation Programme (India) for children.
  static const List<VaccineDose> child = <VaccineDose>[
    VaccineDose('bcg', 'BCG', 'At birth'),
    VaccineDose('opv0', 'OPV 0', 'At birth'),
    VaccineDose('hepb0', 'Hepatitis B birth dose', 'At birth'),
    VaccineDose('opv1', 'OPV 1', '6 weeks', afterDays: 6 * week),
    VaccineDose('penta1', 'Pentavalent 1', '6 weeks', afterDays: 6 * week),
    VaccineDose('rota1', 'Rotavirus 1', '6 weeks', afterDays: 6 * week),
    VaccineDose('fipv1', 'fIPV 1', '6 weeks', afterDays: 6 * week),
    VaccineDose('pcv1', 'PCV 1', '6 weeks', afterDays: 6 * week),
    VaccineDose('opv2', 'OPV 2', '10 weeks', afterDays: 10 * week),
    VaccineDose('penta2', 'Pentavalent 2', '10 weeks', afterDays: 10 * week),
    VaccineDose('rota2', 'Rotavirus 2', '10 weeks', afterDays: 10 * week),
    VaccineDose('opv3', 'OPV 3', '14 weeks', afterDays: 14 * week),
    VaccineDose('penta3', 'Pentavalent 3', '14 weeks', afterDays: 14 * week),
    VaccineDose('rota3', 'Rotavirus 3', '14 weeks', afterDays: 14 * week),
    VaccineDose('fipv2', 'fIPV 2', '14 weeks', afterDays: 14 * week),
    VaccineDose('pcv2', 'PCV 2', '14 weeks', afterDays: 14 * week),
    VaccineDose('mr1', 'MR 1', '9 months', afterDays: 274),
    VaccineDose('je1', 'JE 1 (where endemic)', '9 months', afterDays: 274),
    VaccineDose('pcvb', 'PCV booster', '9 months', afterDays: 274),
    VaccineDose('vita1', 'Vitamin A (1st dose)', '9 months', afterDays: 274),
    VaccineDose('mr2', 'MR 2', '16 months', afterDays: 487),
    VaccineDose('je2', 'JE 2 (where endemic)', '16 months', afterDays: 487),
    VaccineDose('dptb1', 'DPT booster 1', '16 months', afterDays: 487),
    VaccineDose('opvb', 'OPV booster', '16 months', afterDays: 487),
    VaccineDose('dptb2', 'DPT booster 2', '5 years', afterDays: 1826),
    VaccineDose('td10', 'Td', '10 years', afterDays: 3652),
    VaccineDose('td16', 'Td', '16 years', afterDays: 5844),
  ];

  /// Common adult doses; the repeating ones fall due again after each dose.
  static const List<VaccineDose> adult = <VaccineDose>[
    VaccineDose('td', 'Td booster', 'Every 10 years', repeatDays: 3652),
    VaccineDose('flu', 'Influenza', 'Every year', repeatDays: 365),
    VaccineDose('hepb1', 'Hepatitis B 1', 'If never vaccinated'),
    VaccineDose('hepb2', 'Hepatitis B 2', '1 month after dose 1', afterDays: 30),
    VaccineDose('hepb3', 'Hepatitis B 3', '6 months after dose 1', afterDays: 182),
    VaccineDose('pcv65', 'Pneumococcal', 'At 65', afterDays: 23741),
  ];

  static List<VaccineDose> of(ScheduleKind k) => k == ScheduleKind.child ? child : adult;

  static VaccineDose? byId(ScheduleKind k, String id) {
    for (final VaccineDose d in of(k)) {
      if (d.id == id) {
        return d;
      }
    }
    return null;
  }
}

/// A dose that was given.
class GivenDose {
  const GivenDose({required this.on, this.certificates = const <String>[]});
  final DateTime on;

  /// Certificate scans in this phone's app folder.
  final List<String> certificates;

  Map<String, Object?> toJson() => <String, Object?>{
        'on': on.toIso8601String(),
        if (certificates.isNotEmpty) 'certs': certificates,
      };

  static GivenDose? fromJson(Object? j) {
    if (j is! Map) {
      return null;
    }
    final DateTime? on = DateTime.tryParse('${j['on'] ?? ''}');
    if (on == null) {
      return null;
    }
    final Object? c = j['certs'];
    return GivenDose(on: on, certificates: c is List ? c.map((Object? e) => '$e').toList() : const <String>[]);
  }
}

class VaccinePerson {
  const VaccinePerson({required this.id, required this.name, required this.born, required this.kind, this.given = const <String, GivenDose>{}});

  final String id;
  final String name;
  final DateTime born;
  final ScheduleKind kind;
  final Map<String, GivenDose> given;

  Map<String, Object?> toFields() => <String, Object?>{
        'name': name,
        'born': born.toIso8601String(),
        'kind': kind.name,
        'given': <String, Object?>{for (final MapEntry<String, GivenDose> e in given.entries) e.key: e.value.toJson()},
      };

  static VaccinePerson fromRecord(FamilyRecord r) {
    final Map<String, Object?> f = r.fields;
    final Object? g = f['given'];
    final Map<String, GivenDose> given = <String, GivenDose>{};
    if (g is Map) {
      g.forEach((Object? k, Object? v) {
        final GivenDose? d = GivenDose.fromJson(v);
        if (d != null) {
          given['$k'] = d;
        }
      });
    }
    return VaccinePerson(
      id: r.id,
      name: '${f['name'] ?? ''}',
      born: DateTime.tryParse('${f['born'] ?? ''}') ?? DateTime(2000),
      kind: f['kind'] == 'adult' ? ScheduleKind.adult : ScheduleKind.child,
      given: given,
    );
  }

  VaccinePerson withGiven(Map<String, GivenDose> g) => VaccinePerson(id: id, name: name, born: born, kind: kind, given: g);
}

enum DoseState { given, overdue, dueSoon, later }

/// A row on a person's schedule.
class DoseStatus {
  const DoseStatus({required this.dose, required this.due, required this.state, this.given});
  final VaccineDose dose;

  /// When it falls due next; null for a one-off that was given.
  final DateTime? due;
  final DoseState state;
  final GivenDose? given;
}

class VaccineReminder {
  const VaccineReminder({required this.id, required this.at, required this.title, required this.body, required this.payload});
  final int id;
  final DateTime at;
  final String title;
  final String body;
  final String payload;
}

abstract interface class VaccineReminderScheduler {
  Future<void> replaceAll(List<VaccineReminder> reminders);
}

class NoVaccineReminders implements VaccineReminderScheduler {
  const NoVaccineReminders();
  @override
  Future<void> replaceAll(List<VaccineReminder> reminders) async {}
}

class Vaccinations extends ChangeNotifier {
  Vaccinations({
    FamilySpace? space,
    FamilyStore? soloStore,
    VaccineReminderScheduler reminders = const NoVaccineReminders(),
    DateTime Function()? now,
    this.remindHour = 9,
  })  : _space = space,
        _solo = soloStore,
        _scheduler = reminders,
        _now = now ?? DateTime.now;

  static const String collection = 'vaccinations';
  static const String payloadPrefix = 'vaccine:';
  static const int idBase = 8000000;
  static const int soonDays = 14;

  final FamilySpace? _space;
  final FamilyStore? _solo;
  final VaccineReminderScheduler _scheduler;
  final DateTime Function() _now;
  final int remindHour;
  int _seq = 0;

  FamilySpace get space => _space ?? FamilySpace.instance;
  FamilyStore get store => space.inFamily ? space.store : (_solo ?? space.store);

  List<VaccinePerson> get people {
    final List<VaccinePerson> l = store.list(collection).map(VaccinePerson.fromRecord).toList();
    l.sort((VaccinePerson a, VaccinePerson b) {
      final int c = b.born.compareTo(a.born); // youngest first
      return c != 0 ? c : a.name.compareTo(b.name);
    });
    return l;
  }

  VaccinePerson? byId(String id) {
    final FamilyRecord? r = store.get(collection, id);
    return r == null ? null : VaccinePerson.fromRecord(r);
  }

  DateTime _today() {
    final DateTime n = _now();
    return DateTime(n.year, n.month, n.day);
  }

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  static DateTime _plus(DateTime d, int days) => DateTime(d.year, d.month, d.day + days);

  /// Every dose on the person's schedule with its state, in schedule order.
  List<DoseStatus> schedule(VaccinePerson p) {
    final DateTime today = _today();
    final List<DoseStatus> out = <DoseStatus>[];
    for (final VaccineDose d in IndianSchedule.of(p.kind)) {
      final GivenDose? g = p.given[d.id];
      DateTime? due;
      if (g != null) {
        due = d.repeatDays == null ? null : _plus(g.on, d.repeatDays!);
      } else if (p.kind == ScheduleKind.child) {
        due = _plus(p.born, d.afterDays);
      } else {
        // Adult series hang off the first dose; Hep B 2 and 3 after dose 1.
        final GivenDose? first = d.id == 'hepb2' || d.id == 'hepb3' ? p.given['hepb1'] : null;
        if (d.id == 'hepb2' || d.id == 'hepb3') {
          due = first == null ? null : _plus(first.on, d.afterDays);
        } else if (d.id == 'pcv65') {
          due = _plus(p.born, d.afterDays);
        } else {
          due = today; // never given: due now
        }
      }
      final DoseState st;
      if (due == null) {
        st = g != null ? DoseState.given : DoseState.later;
      } else if (g != null && due.isAfter(_plus(today, soonDays))) {
        st = DoseState.given;
      } else if (due.isBefore(today)) {
        st = DoseState.overdue;
      } else if (!due.isAfter(_plus(today, soonDays))) {
        st = DoseState.dueSoon;
      } else {
        st = DoseState.later;
      }
      out.add(DoseStatus(dose: d, due: due, state: st, given: g));
    }
    return out;
  }

  /// Doses overdue or due within two weeks, soonest first, across everyone.
  List<(VaccinePerson, DoseStatus)> dueNow() {
    final List<(VaccinePerson, DoseStatus)> out = <(VaccinePerson, DoseStatus)>[
      for (final VaccinePerson p in people)
        for (final DoseStatus s in schedule(p))
          if (s.state == DoseState.overdue || s.state == DoseState.dueSoon) (p, s),
    ];
    out.sort(((VaccinePerson, DoseStatus) a, (VaccinePerson, DoseStatus) b) => a.$2.due!.compareTo(b.$2.due!));
    return out;
  }

  final List<(String, Map<String, Object?>?)> _undo = <(String, Map<String, Object?>?)>[];

  void _remember(String id) {
    _undo
      ..clear()
      ..add((id, store.get(collection, id)?.fields));
  }

  void _changed() {
    notifyListeners();
    unawaited(reschedule());
  }

  VaccinePerson? addPerson({required String name, required DateTime born, ScheduleKind? kind}) {
    if (name.trim().isEmpty || born.isAfter(_now())) {
      return null;
    }
    final DateTime b = _day(born);
    final ScheduleKind k = kind ?? (_plus(b, 18 * 365).isAfter(_today()) ? ScheduleKind.child : ScheduleKind.adult);
    final String id = 'vx${_now().microsecondsSinceEpoch}-${_seq++}';
    final VaccinePerson p = VaccinePerson(id: id, name: name.trim(), born: b, kind: k);
    _remember(id);
    store.put(collection, id, p.toFields());
    _changed();
    return p;
  }

  /// Marks [doseId] given on [on]; [certificates] are scan paths.
  bool markGiven(String personId, String doseId, {required DateTime on, List<String> certificates = const <String>[]}) {
    final VaccinePerson? p = byId(personId);
    if (p == null || IndianSchedule.byId(p.kind, doseId) == null || on.isAfter(_now()) || on.isBefore(p.born)) {
      return false;
    }
    final Map<String, GivenDose> g = Map<String, GivenDose>.of(p.given);
    final List<String> keep = <String>[...?g[doseId]?.certificates, ...certificates];
    g[doseId] = GivenDose(on: _day(on), certificates: keep);
    _remember(personId);
    store.put(collection, personId, p.withGiven(g).toFields());
    _changed();
    return true;
  }

  /// Links a certificate scan to a dose already given.
  bool attachCertificate(String personId, String doseId, String path) {
    final VaccinePerson? p = byId(personId);
    final GivenDose? g = p?.given[doseId];
    if (p == null || g == null || path.isEmpty) {
      return false;
    }
    return markGiven(personId, doseId, on: g.on, certificates: <String>[path]);
  }

  bool unmark(String personId, String doseId) {
    final VaccinePerson? p = byId(personId);
    if (p == null || !p.given.containsKey(doseId)) {
      return false;
    }
    final Map<String, GivenDose> g = Map<String, GivenDose>.of(p.given)..remove(doseId);
    _remember(personId);
    store.put(collection, personId, p.withGiven(g).toFields());
    _changed();
    return true;
  }

  bool removePerson(String id) {
    if (byId(id) == null) {
      return false;
    }
    _remember(id);
    store.delete(collection, id);
    _changed();
    return true;
  }

  bool undo() {
    if (_undo.isEmpty) {
      return false;
    }
    for (final (String, Map<String, Object?>?) u in _undo) {
      if (u.$2 == null) {
        store.delete(collection, u.$1);
      } else {
        store.put(collection, u.$1, u.$2!);
      }
    }
    _undo.clear();
    _changed();
    return true;
  }

  static int _id(String key) {
    int h = 0;
    for (final int c in key.codeUnits) {
      h = (h * 31 + c) & 0x3FFFF;
    }
    return idBase + h;
  }

  /// A week before and on the day for every dose not yet given (or a
  /// repeating dose's next one), from now on.
  List<VaccineReminder> reminders() {
    final DateTime now = _now();
    final List<VaccineReminder> out = <VaccineReminder>[];
    for (final VaccinePerson p in people) {
      for (final DoseStatus s in schedule(p)) {
        if (s.due == null || s.state == DoseState.given) {
          continue;
        }
        for (final int ahead in const <int>[7, 0]) {
          final DateTime at = DateTime(s.due!.year, s.due!.month, s.due!.day - ahead, remindHour);
          if (!at.isAfter(now)) {
            continue;
          }
          out.add(VaccineReminder(
            id: _id('${p.id}/${s.dose.id}@$ahead'),
            at: at,
            title: ahead == 0 ? '${p.name}: ${s.dose.name} is due today' : '${p.name}: ${s.dose.name} due in a week',
            body: 'Due ${dayLabel(s.due!)} (${s.dose.when}).',
            payload: '$payloadPrefix${p.id}',
          ));
        }
      }
    }
    out.sort((VaccineReminder a, VaccineReminder b) => a.at.compareTo(b.at));
    return out;
  }

  Future<void> reschedule() async {
    try {
      await _scheduler.replaceAll(reminders());
    } catch (e) {
      debugPrint('vaccine reminders: $e');
    }
  }

  static const List<String> months = <String>['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  static String dayLabel(DateTime d) => '${d.day} ${months[d.month - 1]} ${d.year}';

  String toText([VaccinePerson? only]) {
    final StringBuffer b = StringBuffer('Vaccination record\n');
    for (final VaccinePerson p in only == null ? people : <VaccinePerson>[only]) {
      b.write('\n${p.name} (born ${dayLabel(p.born)})\n');
      for (final DoseStatus s in schedule(p)) {
        final String state = switch (s.state) {
          DoseState.given => 'given ${dayLabel(s.given!.on)}',
          DoseState.overdue => 'overdue since ${dayLabel(s.due!)}',
          DoseState.dueSoon => 'due ${dayLabel(s.due!)}',
          DoseState.later => s.due == null ? 'not yet' : 'due ${dayLabel(s.due!)}',
        };
        b.write('- ${s.dose.name} (${s.dose.when}): $state\n');
      }
    }
    return b.toString();
  }

  static Vaccinations instance = Vaccinations();
  static void install(Vaccinations v) => instance = v;
}
