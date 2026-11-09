import 'package:flutter/foundation.dart';

import '../family/family_space.dart';
import '../family/family_store.dart';
import 'medicine_reminders.dart';

/// Feature 093 — Elderly care log.
///
/// A care circle for a parent: siblings and helpers with a role each, a
/// shared medicine schedule (the medicines of feature 088, with every
/// circle member as a carer) and a log of visits, calls, doctor notes and
/// notes. Circles live in the family store, so each sibling's phone sees
/// the same log once the phones sync on Wi-Fi or through the sync folder.
/// Nothing is uploaded.

enum CareRole {
  lead('Lead', 'Runs the circle: members, medicines and the log'),
  helper('Helper', 'Adds visits and notes, logs doses'),
  viewer('Viewer', 'Reads the log and schedule');

  const CareRole(this.label, this.hint);
  final String label;
  final String hint;

  static CareRole? byName(Object? n) {
    for (final CareRole r in CareRole.values) {
      if (r.name == n) {
        return r;
      }
    }
    return null;
  }
}

enum CareEntryKind {
  visit('Visit'),
  call('Call'),
  doctor('Doctor'),
  note('Note');

  const CareEntryKind(this.label);
  final String label;

  static CareEntryKind byName(Object? n) =>
      CareEntryKind.values.firstWhere((CareEntryKind k) => k.name == n, orElse: () => CareEntryKind.note);
}

class CareCircle {
  const CareCircle({required this.id, required this.name, required this.parentKey, required this.roles, this.note = ''});

  final String id;

  /// The parent's name, e.g. "Nani".
  final String name;

  /// Member id when the parent is in the family (so their own phone sees
  /// their medicines), else `care:<id>`.
  final String parentKey;

  /// Member id to role.
  final Map<String, CareRole> roles;
  final String note;

  List<String> get memberIds => roles.keys.toList();
  int get leads => roles.values.where((CareRole r) => r == CareRole.lead).length;

  Map<String, Object?> toFields() => <String, Object?>{
        'name': name,
        'parent': parentKey,
        'roles': <String, Object?>{for (final MapEntry<String, CareRole> e in roles.entries) e.key: e.value.name},
        'note': note,
      };

  static CareCircle fromRecord(FamilyRecord r) {
    final Map<String, CareRole> roles = <String, CareRole>{};
    final Object? raw = r.fields['roles'];
    if (raw is Map) {
      raw.forEach((Object? k, Object? v) {
        final CareRole? role = CareRole.byName(v);
        if (k is String && role != null) {
          roles[k] = role;
        }
      });
    }
    return CareCircle(
      id: r.id,
      name: '${r.fields['name'] ?? 'Parent'}',
      parentKey: '${r.fields['parent'] ?? 'care:${r.id}'}',
      roles: roles,
      note: '${r.fields['note'] ?? ''}',
    );
  }

  CareCircle withRoles(Map<String, CareRole> next) => CareCircle(id: id, name: name, parentKey: parentKey, roles: next, note: note);
}

class CareEntry {
  const CareEntry({required this.id, required this.circleId, required this.at, required this.by, required this.kind, required this.text});

  final String id;
  final String circleId;
  final DateTime at;

  /// Member id of whoever wrote it.
  final String by;
  final CareEntryKind kind;
  final String text;

  static CareEntry fromRecord(FamilyRecord r) {
    final Object? at = r.fields['at'];
    return CareEntry(
      id: r.id,
      circleId: '${r.fields['circle'] ?? ''}',
      at: DateTime.fromMillisecondsSinceEpoch(at is num ? at.toInt() : 0),
      by: '${r.fields['by'] ?? ''}',
      kind: CareEntryKind.byName(r.fields['kind']),
      text: '${r.fields['text'] ?? ''}',
    );
  }
}

class ElderlyCare extends ChangeNotifier {
  ElderlyCare({FamilySpace? space, FamilyStore? soloStore, MedicineReminders? medicines, DateTime Function()? now})
      : _space = space,
        _now = now ?? DateTime.now {
    _meds = medicines ?? MedicineReminders(space: space, soloStore: soloStore, now: now);
  }

  static const String circles = 'care_circles';
  static const String entries = 'care_log';

  final FamilySpace? _space;
  final DateTime Function() _now;
  late final MedicineReminders _meds;
  int _seq = 0;

  FamilySpace get space => _space ?? FamilySpace.instance;
  MedicineReminders get medicines => _meds;

  /// The family store when in a family, else this phone's own store; the
  /// same store the medicines use.
  FamilyStore get store => _meds.store;

  String get me => _meds.me;

  Map<String, String> get members => _meds.members;
  String nameOf(String memberId) => _meds.nameOf(memberId);

  List<CareCircle> get all => store.list(circles).map(CareCircle.fromRecord).toList();

  /// Circles this phone's member belongs to (all of them when not in a
  /// family).
  List<CareCircle> get visible =>
      all.where((CareCircle c) => !space.inFamily || c.roles.containsKey(me)).toList()
        ..sort((CareCircle a, CareCircle b) => a.name.compareTo(b.name));

  CareCircle? byId(String id) {
    final FamilyRecord? r = store.get(circles, id);
    return r == null ? null : CareCircle.fromRecord(r);
  }

  CareRole? myRole(CareCircle c) => space.inFamily ? c.roles[me] : CareRole.lead;

  bool canManage(CareCircle c) => myRole(c) == CareRole.lead;
  bool canWrite(CareCircle c) {
    final CareRole? r = myRole(c);
    return r == CareRole.lead || r == CareRole.helper;
  }

  // Undo: the fields each touched record had before the last change.
  final List<(String, String, Map<String, Object?>?)> _undo = <(String, String, Map<String, Object?>?)>[];

  void _remember(List<(String, String)> keys) {
    _undo
      ..clear()
      ..addAll(keys.map(((String, String) k) => (k.$1, k.$2, store.get(k.$1, k.$2)?.fields)));
  }

  String _id(String p) => '$p${_now().microsecondsSinceEpoch}-${_seq++}';

  /// Starts a circle for [name]; this phone's member is its lead. Pass
  /// [parentMemberId] when the parent is in the family.
  CareCircle? create({required String name, String? parentMemberId, Map<String, CareRole> others = const <String, CareRole>{}, String note = ''}) {
    if (name.trim().isEmpty) {
      return null;
    }
    final String id = _id('c');
    final Map<String, CareRole> roles = <String, CareRole>{...others, me: CareRole.lead};
    final CareCircle c = CareCircle(id: id, name: name.trim(), parentKey: parentMemberId ?? 'care:$id', roles: roles, note: note.trim());
    _remember(<(String, String)>[(circles, id)]);
    store.put(circles, id, c.toFields());
    notifyListeners();
    return c;
  }

  /// Gives [memberId] a role in the circle, or removes them with null. Only
  /// a lead can, and the last lead cannot leave or step down. Medicines in
  /// the circle follow: every member is a carer.
  bool setRole(String circleId, String memberId, CareRole? role) {
    final CareCircle? c = byId(circleId);
    if (c == null || !canManage(c) || c.roles[memberId] == role) {
      return false;
    }
    final Map<String, CareRole> next = Map<String, CareRole>.of(c.roles);
    if (role == null) {
      next.remove(memberId);
    } else {
      next[memberId] = role;
    }
    if (!next.values.contains(CareRole.lead)) {
      return false;
    }
    final List<Medicine> meds = medicinesFor(c);
    _remember(<(String, String)>[(circles, circleId), for (final Medicine m in meds) (MedicineReminders.medicines, m.id)]);
    store.put(circles, circleId, c.withRoles(next).toFields());
    for (final Medicine m in meds) {
      store.put(MedicineReminders.medicines, m.id, m.copyWith(carers: _carers(next, c.parentKey)).toFields());
    }
    notifyListeners();
    return true;
  }

  static List<String> _carers(Map<String, CareRole> roles, String parentKey) =>
      roles.keys.where((String k) => k != parentKey).toList()..sort();

  /// The circle's medicines: those whose member is the parent.
  List<Medicine> medicinesFor(CareCircle c) =>
      _meds.all.where((Medicine m) => m.memberId == c.parentKey).toList()..sort((Medicine a, Medicine b) => a.name.compareTo(b.name));

  /// Adds a medicine to the shared schedule; every circle member can see
  /// it and log doses on their own phone.
  Medicine? addMedicine(String circleId, {required String name, required List<int> times, int tabletsPerDose = 1, int stock = 0, String note = ''}) {
    final CareCircle? c = byId(circleId);
    if (c == null || !canWrite(c)) {
      return null;
    }
    final Medicine? m = _meds.add(
      name: name,
      times: times,
      memberId: c.parentKey,
      tabletsPerDose: tabletsPerDose,
      stock: stock,
      carers: _carers(c.roles, c.parentKey),
      note: note,
    );
    if (m != null) {
      _undo
        ..clear()
        ..add((MedicineReminders.medicines, m.id, null));
      notifyListeners();
    }
    return m;
  }

  /// Writes a visit, call, doctor note or note to the circle's log.
  CareEntry? addEntry(String circleId, CareEntryKind kind, String text, {DateTime? at}) {
    final CareCircle? c = byId(circleId);
    if (c == null || !canWrite(c) || text.trim().isEmpty) {
      return null;
    }
    final String id = _id('v');
    final DateTime when = at ?? _now();
    _remember(<(String, String)>[(entries, id)]);
    store.put(entries, id, <String, Object?>{
      'circle': circleId,
      'at': when.millisecondsSinceEpoch,
      'by': me,
      'kind': kind.name,
      'text': text.trim(),
    });
    notifyListeners();
    return CareEntry(id: id, circleId: circleId, at: when, by: me, kind: kind, text: text.trim());
  }

  bool removeEntry(String entryId) {
    final FamilyRecord? r = store.get(entries, entryId);
    if (r == null) {
      return false;
    }
    final CareEntry e = CareEntry.fromRecord(r);
    final CareCircle? c = byId(e.circleId);
    if (c == null || !(canManage(c) || (canWrite(c) && e.by == me))) {
      return false;
    }
    _remember(<(String, String)>[(entries, entryId)]);
    store.delete(entries, entryId);
    notifyListeners();
    return true;
  }

  /// The circle's log, newest first. Only members see it.
  List<CareEntry> logFor(String circleId) {
    final CareCircle? c = byId(circleId);
    if (c == null || myRole(c) == null) {
      return <CareEntry>[];
    }
    return store.list(entries).map(CareEntry.fromRecord).where((CareEntry e) => e.circleId == circleId).toList()
      ..sort((CareEntry a, CareEntry b) => b.at.compareTo(a.at));
  }

  bool undo() {
    if (_undo.isEmpty) {
      return false;
    }
    for (final (String, String, Map<String, Object?>?) u in _undo) {
      if (u.$3 == null) {
        store.delete(u.$1, u.$2);
      } else {
        store.put(u.$1, u.$2, u.$3!);
      }
    }
    _undo.clear();
    notifyListeners();
    return true;
  }

  static String _two(int v) => v.toString().padLeft(2, '0');
  static String stamp(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)} ${_two(d.hour)}:${_two(d.minute)}';

  /// A plain-text summary to share with a sibling or a doctor.
  String toText(String circleId, {int lastEntries = 20}) {
    final CareCircle? c = byId(circleId);
    if (c == null) {
      return '';
    }
    final StringBuffer b = StringBuffer('Care log: ${c.name}\n');
    b.write('Circle: ${c.roles.entries.map((MapEntry<String, CareRole> e) => '${nameOf(e.key)} (${e.value.label})').join(', ')}\n');
    b.write('\nMedicines\n');
    final List<Medicine> meds = medicinesFor(c);
    if (meds.isEmpty) {
      b.write('- none\n');
    }
    for (final Medicine m in meds) {
      b.write('- ${m.name}: ${m.times.map(Medicine.clock).join(', ')} · ${m.stock} left\n');
    }
    b.write('\nLog\n');
    final List<CareEntry> log = logFor(circleId).take(lastEntries).toList();
    if (log.isEmpty) {
      b.write('- nothing yet\n');
    }
    for (final CareEntry e in log) {
      b.write('- ${stamp(e.at)} ${e.kind.label} by ${nameOf(e.by)}: ${e.text}\n');
    }
    return b.toString();
  }

  static ElderlyCare instance = ElderlyCare();
  static void install(ElderlyCare c) => instance = c;
}
