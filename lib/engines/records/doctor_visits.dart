import 'package:flutter/foundation.dart';

import '../family/family_space.dart';
import '../family/family_store.dart';
import '../family/shared_calendar.dart';

/// Feature 090 — Doctor visits and prescriptions.
///
/// A visit keeps who went, which doctor, the date, notes and the scanned
/// prescription pages (paths in the app's own folder, from the document
/// scanner of 047). The next appointment is put on the shared calendar
/// (071) with a reminder the day before. Nothing is uploaded.

class DoctorVisit {
  const DoctorVisit({
    required this.id,
    required this.person,
    required this.doctor,
    required this.date,
    this.notes = '',
    this.prescriptions = const <String>[],
    this.nextAt,
  });

  final String id;
  final String person;
  final String doctor;
  final DateTime date;
  final String notes;

  /// Scanned prescription files kept on this phone.
  final List<String> prescriptions;

  /// The next appointment, if one was booked.
  final DateTime? nextAt;

  /// Id of the shared calendar event for [nextAt].
  String get eventId => 'visit-$id';

  Map<String, Object?> toFields() => <String, Object?>{
        'person': person,
        'doctor': doctor,
        'date': date.toIso8601String(),
        if (notes.isNotEmpty) 'notes': notes,
        'rx': prescriptions,
        if (nextAt != null) 'next': nextAt!.toIso8601String(),
      };

  static DoctorVisit fromRecord(FamilyRecord r) {
    final Map<String, Object?> f = r.fields;
    final Object? rx = f['rx'];
    return DoctorVisit(
      id: r.id,
      person: '${f['person'] ?? ''}',
      doctor: '${f['doctor'] ?? ''}',
      date: DateTime.tryParse('${f['date'] ?? ''}') ?? DateTime(2000),
      notes: '${f['notes'] ?? ''}',
      prescriptions: rx is List ? rx.whereType<String>().toList() : const <String>[],
      nextAt: DateTime.tryParse('${f['next'] ?? ''}'),
    );
  }

  DoctorVisit copyWith({List<String>? prescriptions, DateTime? nextAt, bool clearNext = false}) => DoctorVisit(
        id: id,
        person: person,
        doctor: doctor,
        date: date,
        notes: notes,
        prescriptions: prescriptions ?? this.prescriptions,
        nextAt: clearNext ? null : (nextAt ?? this.nextAt),
      );
}

class DoctorVisits extends ChangeNotifier {
  DoctorVisits({
    FamilySpace? space,
    FamilyStore? soloStore,
    SharedCalendar? calendar,
    DateTime Function()? now,
  })  : _space = space,
        _solo = soloStore,
        _calendar = calendar,
        _now = now ?? DateTime.now;

  static const String collection = 'doctor_visits';
  static const Duration appointmentLength = Duration(minutes: 30);
  static const Duration remindBefore = Duration(days: 1);

  final FamilySpace? _space;
  final FamilyStore? _solo;
  final SharedCalendar? _calendar;
  final DateTime Function() _now;
  int _seq = 0;

  FamilySpace get space => _space ?? FamilySpace.instance;
  FamilyStore get store => space.inFamily ? space.store : (_solo ?? space.store);
  SharedCalendar get calendar => _calendar ?? SharedCalendar.instance;

  /// Every visit, newest first.
  List<DoctorVisit> get all {
    final List<DoctorVisit> list = store.list(collection).map(DoctorVisit.fromRecord).toList();
    list.sort((DoctorVisit a, DoctorVisit b) => b.date.compareTo(a.date));
    return list;
  }

  DoctorVisit? byId(String id) {
    final FamilyRecord? r = store.get(collection, id);
    return r == null ? null : DoctorVisit.fromRecord(r);
  }

  /// Visits that still have an appointment ahead, soonest first.
  List<DoctorVisit> get upcoming {
    final DateTime now = _now();
    final List<DoctorVisit> list = all.where((DoctorVisit v) => v.nextAt != null && v.nextAt!.isAfter(now)).toList();
    list.sort((DoctorVisit a, DoctorVisit b) => a.nextAt!.compareTo(b.nextAt!));
    return list;
  }

  /// Names of everyone with a visit, for quick picking.
  List<String> get people {
    final Set<String> s = <String>{for (final DoctorVisit v in all) if (v.person.isNotEmpty) v.person};
    return s.toList()..sort();
  }

  // Undo keeps the visit and its calendar event as they were.
  String? _undoId;
  Map<String, Object?>? _undoFields;
  CalendarEvent? _undoEvent;
  bool _hasUndo = false;

  bool get canUndo => _hasUndo;

  void _remember(String id) {
    _undoId = id;
    final FamilyRecord? r = store.get(collection, id);
    _undoFields = r == null ? null : Map<String, Object?>.of(r.fields);
    _undoEvent = calendar.event('visit-$id');
    _hasUndo = true;
  }

  String _member() => space.identity?.deviceId ?? 'local';

  void _syncCalendar(DoctorVisit v) {
    final DateTime? at = v.nextAt;
    if (at == null) {
      calendar.delete(v.eventId);
      return;
    }
    final String who = v.person.isEmpty ? '' : ' (${v.person})';
    calendar.save(CalendarEvent(
      id: v.eventId,
      title: 'Doctor: ${v.doctor.isEmpty ? 'appointment' : v.doctor}$who',
      start: at,
      duration: appointmentLength,
      memberId: _member(),
      remindBefore: remindBefore,
      note: v.notes,
    ));
  }

  /// Adds a visit. Needs a person or a doctor; a next appointment must be
  /// in the future. Returns null when the input does not fit.
  DoctorVisit? add({
    required String person,
    required String doctor,
    DateTime? date,
    String notes = '',
    List<String> prescriptions = const <String>[],
    DateTime? nextAt,
  }) {
    if (person.trim().isEmpty && doctor.trim().isEmpty) {
      return null;
    }
    final DateTime now = _now();
    if (nextAt != null && !nextAt.isAfter(now)) {
      return null;
    }
    final String id = 'v${now.microsecondsSinceEpoch}-${_seq++}';
    final DoctorVisit v = DoctorVisit(
      id: id,
      person: person.trim(),
      doctor: doctor.trim(),
      date: date ?? DateTime(now.year, now.month, now.day),
      notes: notes.trim(),
      prescriptions: List<String>.of(prescriptions),
      nextAt: nextAt,
    );
    _remember(id);
    store.put(collection, id, v.toFields());
    _syncCalendar(v);
    notifyListeners();
    return v;
  }

  /// Adds scanned prescription pages to a visit.
  bool attachPrescriptions(String id, List<String> paths) {
    final DoctorVisit? v = byId(id);
    final List<String> clean = paths.where((String p) => p.trim().isNotEmpty).toList();
    if (v == null || clean.isEmpty) {
      return false;
    }
    _remember(id);
    store.put(collection, id, v.copyWith(prescriptions: <String>[...v.prescriptions, ...clean]).toFields());
    notifyListeners();
    return true;
  }

  bool removePrescription(String id, int index) {
    final DoctorVisit? v = byId(id);
    if (v == null || index < 0 || index >= v.prescriptions.length) {
      return false;
    }
    _remember(id);
    store.put(collection, id, v.copyWith(prescriptions: List<String>.of(v.prescriptions)..removeAt(index)).toFields());
    notifyListeners();
    return true;
  }

  /// Sets or clears (null) the next appointment and keeps the calendar
  /// event in step.
  bool setNext(String id, DateTime? at) {
    final DoctorVisit? v = byId(id);
    if (v == null || (at != null && !at.isAfter(_now()))) {
      return false;
    }
    _remember(id);
    final DoctorVisit next = at == null ? v.copyWith(clearNext: true) : v.copyWith(nextAt: at);
    store.put(collection, id, next.toFields());
    _syncCalendar(next);
    notifyListeners();
    return true;
  }

  bool remove(String id) {
    final DoctorVisit? v = byId(id);
    if (v == null) {
      return false;
    }
    _remember(id);
    store.delete(collection, id);
    calendar.delete(v.eventId);
    notifyListeners();
    return true;
  }

  bool undo() {
    final String? id = _undoId;
    if (!_hasUndo || id == null) {
      return false;
    }
    _hasUndo = false;
    if (_undoFields == null) {
      store.delete(collection, id);
    } else {
      store.put(collection, id, _undoFields!);
    }
    final CalendarEvent? ev = _undoEvent;
    if (ev == null) {
      calendar.delete('visit-$id');
    } else {
      calendar.save(ev);
    }
    _undoId = null;
    _undoFields = null;
    _undoEvent = null;
    notifyListeners();
    return true;
  }

  static const List<String> months = <String>['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  static String _two(int n) => n.toString().padLeft(2, '0');

  static String dayLabel(DateTime d) => '${d.day} ${months[d.month - 1]} ${d.year}';

  static String timeLabel(DateTime d) => '${dayLabel(d)}, ${_two(d.hour)}:${_two(d.minute)}';

  static String fileName(String path) => path.split(RegExp(r'[/\\]')).last;

  /// One visit as text, to share.
  static String visitText(DoctorVisit v) {
    final StringBuffer b = StringBuffer();
    b.write('${dayLabel(v.date)}: ${v.person.isEmpty ? 'Visit' : v.person}');
    if (v.doctor.isNotEmpty) {
      b.write(' with ${v.doctor}');
    }
    b.write('\n');
    if (v.notes.isNotEmpty) {
      b.write('  Notes: ${v.notes}\n');
    }
    if (v.prescriptions.isNotEmpty) {
      b.write('  Prescriptions: ${v.prescriptions.map(fileName).join(', ')}\n');
    }
    if (v.nextAt != null) {
      b.write('  Next appointment: ${timeLabel(v.nextAt!)}\n');
    }
    return b.toString();
  }

  /// Every visit as text, newest first, to share or save.
  String toText() {
    final StringBuffer b = StringBuffer('Doctor visits\n');
    for (final DoctorVisit v in all) {
      b.write(visitText(v));
    }
    return b.toString();
  }

  static DoctorVisits instance = DoctorVisits();
  static void install(DoctorVisits v) => instance = v;
}
