import 'package:flutter/foundation.dart';

import 'family_space.dart';
import 'family_store.dart';

/// Feature 073 — Shared to-do and notice board.
///
/// Household tasks (with an owner, an optional due date and a done state)
/// live in the family store's `tasks` collection; notes live in `notes`
/// and can be pinned so they show on the Family screen. Both merge like
/// every other family record, so nothing leaves the family's phones.

@immutable
class FamilyTask {
  const FamilyTask({
    required this.id,
    required this.title,
    required this.owner,
    required this.addedBy,
    required this.addedAt,
    this.due,
    this.doneBy,
    this.doneAt,
  });

  final String id;
  final String title;

  /// Member device id of whoever should do it.
  final String owner;
  final String addedBy;
  final DateTime addedAt;

  /// Due day (date only), or null for no due date.
  final DateTime? due;
  final String? doneBy;
  final DateTime? doneAt;

  bool get done => doneBy != null;

  /// True when not done and the due day is before [today].
  bool overdueOn(DateTime today) {
    final DateTime? d = due;
    if (done || d == null) {
      return false;
    }
    return d.isBefore(DateTime(today.year, today.month, today.day));
  }

  Map<String, Object?> toFields() => <String, Object?>{
        'title': title,
        'owner': owner,
        'by': addedBy,
        'at': addedAt.toIso8601String(),
        if (due != null) 'due': FamilyBoard.dayKey(due!),
        if (doneBy != null) 'doneBy': doneBy,
        if (doneAt != null) 'doneAt': doneAt!.toIso8601String(),
      };

  static FamilyTask fromRecord(FamilyRecord r) {
    final Map<String, Object?> f = r.fields;
    final Object? db = f['doneBy'];
    return FamilyTask(
      id: r.id,
      title: '${f['title'] ?? ''}',
      owner: '${f['owner'] ?? r.writer}',
      addedBy: '${f['by'] ?? r.writer}',
      addedAt: DateTime.tryParse('${f['at'] ?? ''}') ?? DateTime.fromMillisecondsSinceEpoch(r.wallMillis),
      due: f['due'] == null ? null : DateTime.tryParse('${f['due']}'),
      doneBy: db is String ? db : null,
      doneAt: db is String ? DateTime.tryParse('${f['doneAt'] ?? ''}') : null,
    );
  }
}

@immutable
class FamilyNote {
  const FamilyNote({
    required this.id,
    required this.text,
    required this.pinned,
    required this.addedBy,
    required this.addedAt,
  });

  final String id;
  final String text;
  final bool pinned;
  final String addedBy;
  final DateTime addedAt;

  Map<String, Object?> toFields() => <String, Object?>{
        'text': text,
        'pinned': pinned,
        'by': addedBy,
        'at': addedAt.toIso8601String(),
      };

  static FamilyNote fromRecord(FamilyRecord r) {
    final Map<String, Object?> f = r.fields;
    return FamilyNote(
      id: r.id,
      text: '${f['text'] ?? ''}',
      pinned: f['pinned'] == true,
      addedBy: '${f['by'] ?? r.writer}',
      addedAt: DateTime.tryParse('${f['at'] ?? ''}') ?? DateTime.fromMillisecondsSinceEpoch(r.wallMillis),
    );
  }
}

class FamilyBoard extends ChangeNotifier {
  FamilyBoard({FamilySpace? space, DateTime Function()? now})
      : _space = space,
        _now = now ?? DateTime.now;

  static const String tasksCollection = 'tasks';
  static const String notesCollection = 'notes';

  final FamilySpace? _space;
  final DateTime Function() _now;
  int _seq = 0;

  /// What the last change replaced, for Undo: "collection/id" to old fields.
  Map<String, Map<String, Object?>?>? _undo;

  FamilySpace get space => _space ?? FamilySpace.instance;
  FamilyStore get store => space.store;
  String get me => space.identity?.deviceId ?? 'local';
  bool get canUndo => _undo != null;

  static String dayKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Pinned notes in [store], newest first; used by the Family screen.
  static List<FamilyNote> pinnedIn(FamilyStore store) {
    final List<FamilyNote> out =
        store.list(notesCollection).map(FamilyNote.fromRecord).where((FamilyNote n) => n.pinned).toList();
    out.sort((FamilyNote a, FamilyNote b) => b.addedAt.compareTo(a.addedAt));
    return out;
  }

  String memberName(String id) {
    final FamilyRecord? r = store.get(FamilySpace.members, id);
    return r == null ? 'Someone' : '${r.fields['name'] ?? 'Someone'}';
  }

  /// Member ids and names, this phone first.
  List<MapEntry<String, String>> get memberChoices {
    final List<MapEntry<String, String>> out = <MapEntry<String, String>>[
      for (final FamilyRecord r in store.list(FamilySpace.members))
        MapEntry<String, String>(r.id, '${r.fields['name'] ?? 'Member'}'),
    ];
    out.sort((MapEntry<String, String> a, MapEntry<String, String> b) {
      if (a.key == me) {
        return -1;
      }
      if (b.key == me) {
        return 1;
      }
      return a.value.compareTo(b.value);
    });
    if (out.every((MapEntry<String, String> e) => e.key != me)) {
      out.insert(0, MapEntry<String, String>(me, 'Me'));
    }
    return out;
  }

  // ---- tasks ----

  /// Open tasks by due date (no date last), then done tasks, latest first.
  List<FamilyTask> get tasks {
    final List<FamilyTask> all = store.list(tasksCollection).map(FamilyTask.fromRecord).toList();
    all.sort((FamilyTask a, FamilyTask b) {
      if (a.done != b.done) {
        return a.done ? 1 : -1;
      }
      if (a.done) {
        return (b.doneAt ?? b.addedAt).compareTo(a.doneAt ?? a.addedAt);
      }
      if (a.due != null && b.due != null && a.due != b.due) {
        return a.due!.compareTo(b.due!);
      }
      if ((a.due == null) != (b.due == null)) {
        return a.due == null ? 1 : -1;
      }
      return a.addedAt.compareTo(b.addedAt);
    });
    return all;
  }

  FamilyTask? task(String id) {
    final FamilyRecord? r = store.get(tasksCollection, id);
    return r == null ? null : FamilyTask.fromRecord(r);
  }

  /// Adds a task; the owner defaults to this phone. Null when blank.
  FamilyTask? addTask(String title, {String? owner, DateTime? due}) {
    final String t = title.trim();
    if (t.isEmpty) {
      return null;
    }
    final DateTime now = _now();
    final FamilyTask task = FamilyTask(
      id: '$me-${now.microsecondsSinceEpoch}-${_seq++}',
      title: t,
      owner: (owner == null || owner.isEmpty) ? me : owner,
      addedBy: me,
      addedAt: now,
      due: due == null ? null : DateTime(due.year, due.month, due.day),
    );
    _write(<String, Map<String, Object?>?>{'$tasksCollection/${task.id}': task.toFields()});
    return task;
  }

  bool setDone(String id, bool done) {
    final FamilyTask? t = task(id);
    if (t == null || t.done == done) {
      return false;
    }
    final Map<String, Object?> f = Map<String, Object?>.of(t.toFields());
    if (done) {
      f['doneBy'] = me;
      f['doneAt'] = _now().toIso8601String();
    } else {
      f.remove('doneBy');
      f.remove('doneAt');
    }
    _write(<String, Map<String, Object?>?>{'$tasksCollection/$id': f});
    return true;
  }

  bool reassign(String id, String owner) {
    final FamilyTask? t = task(id);
    if (t == null || t.owner == owner) {
      return false;
    }
    _write(<String, Map<String, Object?>?>{
      '$tasksCollection/$id': Map<String, Object?>.of(t.toFields())..['owner'] = owner,
    });
    return true;
  }

  bool removeTask(String id) {
    if (task(id) == null) {
      return false;
    }
    _write(<String, Map<String, Object?>?>{'$tasksCollection/$id': null});
    return true;
  }

  /// Removes every done task; returns how many.
  int clearDone() {
    final List<FamilyTask> done = tasks.where((FamilyTask t) => t.done).toList();
    if (done.isEmpty) {
      return 0;
    }
    _write(<String, Map<String, Object?>?>{for (final FamilyTask t in done) '$tasksCollection/${t.id}': null});
    return done.length;
  }

  // ---- notes ----

  /// Pinned first, then newest first.
  List<FamilyNote> get notes {
    final List<FamilyNote> all = store.list(notesCollection).map(FamilyNote.fromRecord).toList();
    all.sort((FamilyNote a, FamilyNote b) {
      if (a.pinned != b.pinned) {
        return a.pinned ? -1 : 1;
      }
      return b.addedAt.compareTo(a.addedAt);
    });
    return all;
  }

  FamilyNote? note(String id) {
    final FamilyRecord? r = store.get(notesCollection, id);
    return r == null ? null : FamilyNote.fromRecord(r);
  }

  FamilyNote? addNote(String text, {bool pinned = true}) {
    final String t = text.trim();
    if (t.isEmpty) {
      return null;
    }
    final DateTime now = _now();
    final FamilyNote n = FamilyNote(
      id: '$me-${now.microsecondsSinceEpoch}-${_seq++}',
      text: t,
      pinned: pinned,
      addedBy: me,
      addedAt: now,
    );
    _write(<String, Map<String, Object?>?>{'$notesCollection/${n.id}': n.toFields()});
    return n;
  }

  bool setPinned(String id, bool pinned) {
    final FamilyNote? n = note(id);
    if (n == null || n.pinned == pinned) {
      return false;
    }
    _write(<String, Map<String, Object?>?>{
      '$notesCollection/$id': Map<String, Object?>.of(n.toFields())..['pinned'] = pinned,
    });
    return true;
  }

  bool removeNote(String id) {
    if (note(id) == null) {
      return false;
    }
    _write(<String, Map<String, Object?>?>{'$notesCollection/$id': null});
    return true;
  }

  // ---- undo and text ----

  bool undo() {
    final Map<String, Map<String, Object?>?>? u = _undo;
    if (u == null) {
      return false;
    }
    _undo = null;
    u.forEach(_set);
    notifyListeners();
    return true;
  }

  void _write(Map<String, Map<String, Object?>?> changes) {
    _undo = <String, Map<String, Object?>?>{
      for (final String key in changes.keys) key: _get(key),
    };
    changes.forEach(_set);
    notifyListeners();
  }

  Map<String, Object?>? _get(String key) {
    final int i = key.indexOf('/');
    return store.get(key.substring(0, i), key.substring(i + 1))?.fields;
  }

  void _set(String key, Map<String, Object?>? fields) {
    final int i = key.indexOf('/');
    final String c = key.substring(0, i);
    final String id = key.substring(i + 1);
    if (fields == null) {
      store.delete(c, id);
    } else {
      store.put(c, id, fields);
    }
  }

  /// The board as plain text, to share in a chat.
  String toText() {
    final StringBuffer b = StringBuffer('Family board\n');
    final List<FamilyNote> ns = notes;
    if (ns.isNotEmpty) {
      b.write('\nNotes\n');
      for (final FamilyNote n in ns) {
        b.write('${n.pinned ? '* ' : '- '}${n.text}\n');
      }
    }
    final List<FamilyTask> ts = tasks;
    if (ts.isNotEmpty) {
      b.write('\nTo do\n');
      for (final FamilyTask t in ts) {
        b.write('${t.done ? '[x]' : '[ ]'} ${t.title} · ${memberName(t.owner)}'
            '${t.due == null ? '' : ' · due ${dayKey(t.due!)}'}\n');
      }
    }
    return b.toString();
  }

  static FamilyBoard instance = FamilyBoard();

  static void install(FamilyBoard board) => instance = board;
}
