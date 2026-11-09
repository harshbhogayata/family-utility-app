import 'package:flutter/foundation.dart';

import 'family_space.dart';
import 'family_store.dart';

/// Kind of one change in the log.
enum ChangeKind {
  added('added'),
  changed('changed'),
  removed('removed');

  const ChangeKind(this.verb);
  final String verb;
}

/// One change to one shared record (feature 078).
@immutable
class ChangeLogEntry {
  const ChangeLogEntry({
    required this.collection,
    required this.id,
    required this.state,
    required this.before,
    required this.author,
    required this.label,
  });

  final String collection;
  final String id;

  /// The record as this change left it.
  final FamilyRevision state;

  /// The record before this change; null when the change created it.
  final FamilyRevision? before;

  /// Member name of whoever made the change (or "A family phone").
  final String author;

  /// Short human name for the record ("Milk", "Dentist").
  final String label;

  DateTime get at => DateTime.fromMillisecondsSinceEpoch(state.wallMillis);

  ChangeKind get kind {
    if (state.deleted) {
      return ChangeKind.removed;
    }
    if (before == null || before!.deleted) {
      return ChangeKind.added;
    }
    return ChangeKind.changed;
  }

  String get area => ChangeLog.areaName(collection);

  String get line => '$author ${kind.verb} $label in $area';
}

/// Feature 078 — Change log: who changed what across the family's shared
/// records, newest first, with undo. Each record keeps its last
/// [FamilyRecord.keepChanges] changes, and they sync with the record, so
/// every phone sees the same log. Nothing leaves the family's phones.
class ChangeLog {
  ChangeLog(this.store);

  final FamilyStore store;

  static const Map<String, String> _areas = <String, String>{
    FamilySpace.members: 'Members',
  };

  static String areaName(String collection) {
    final String? known = _areas[collection];
    if (known != null) {
      return known;
    }
    final String words = collection.replaceAll(RegExp('[_-]+'), ' ').trim();
    if (words.isEmpty) {
      return 'Family';
    }
    return words[0].toUpperCase() + words.substring(1);
  }

  static const List<String> _labelKeys = <String>['title', 'name', 'text', 'item', 'label', 'note'];

  static String labelOf(FamilyRevision state, FamilyRevision? before, String id) {
    for (final FamilyRevision? r in <FamilyRevision?>[state, before]) {
      if (r == null) {
        continue;
      }
      for (final String k in _labelKeys) {
        final Object? v = r.fields[k];
        if (v is String && v.trim().isNotEmpty) {
          final String t = v.trim();
          return t.length > 40 ? '${t.substring(0, 39)}…' : t;
        }
      }
    }
    return 'an item';
  }

  /// Member name for a device id, from the members collection.
  String authorOf(String writer) {
    final FamilyRecord? m = store.get(FamilySpace.members, writer);
    final Object? name = m?.fields['name'];
    if (name is String && name.trim().isNotEmpty) {
      return name.trim();
    }
    return writer == store.deviceId ? 'You' : 'A family phone';
  }

  /// Changes to one record, newest first, at most [FamilyRecord.keepChanges].
  List<ChangeLogEntry> forRecord(String collection, String id) {
    final FamilyRecord? r = store.raw(collection, id);
    if (r == null) {
      return const <ChangeLogEntry>[];
    }
    return _entries(r);
  }

  List<ChangeLogEntry> _entries(FamilyRecord r) {
    final List<FamilyRevision> states = r.changes;
    final List<ChangeLogEntry> out = <ChangeLogEntry>[];
    for (int i = 0; i < states.length; i++) {
      final FamilyRevision s = states[i];
      final FamilyRevision? before = i + 1 < states.length ? states[i + 1] : null;
      // The oldest kept state of a long history replaced one we no longer have.
      final bool clipped = before == null && states.length > FamilyRecord.keepChanges;
      if (clipped) {
        continue;
      }
      out.add(ChangeLogEntry(
        collection: r.collection,
        id: r.id,
        state: s,
        before: before,
        author: authorOf(s.writer),
        label: labelOf(s, before, r.id),
      ));
    }
    return out;
  }

  /// Every change across the family, newest first.
  List<ChangeLogEntry> all({int? limit}) {
    final List<ChangeLogEntry> out = <ChangeLogEntry>[];
    for (final FamilyRecord r in store.allRecords) {
      out.addAll(_entries(r));
    }
    out.sort((ChangeLogEntry a, ChangeLogEntry b) => b.state.wallMillis.compareTo(a.state.wallMillis));
    return limit == null || out.length <= limit ? out : out.sublist(0, limit);
  }

  /// Puts the record back the way it was before [entry]. Returns false when
  /// the record has moved on in a way that makes this a no-op.
  bool undo(ChangeLogEntry entry) {
    final FamilyRecord? now = store.raw(entry.collection, entry.id);
    if (now == null) {
      return false;
    }
    final FamilyRevision? target = entry.before;
    if ((target == null || target.deleted) && now.deleted) {
      return false;
    }
    store.restore(entry.collection, entry.id, target);
    return true;
  }

  /// Plain text of the log, for Share and Save.
  String describe({int limit = 100}) {
    final StringBuffer b = StringBuffer('Family change log\n');
    for (final ChangeLogEntry e in all(limit: limit)) {
      b.writeln('${_stamp(e.at)}  ${e.line}');
    }
    return b.toString();
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  static String _stamp(DateTime t) =>
      '${t.year}-${_two(t.month)}-${_two(t.day)} ${_two(t.hour)}:${_two(t.minute)}';

  static String stamp(DateTime t) => _stamp(t);
}
