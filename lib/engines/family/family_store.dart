import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'vector_clock.dart';

/// Feature 068 — Family space: one shared, local-first store.
///
/// Every piece of family data is a record in a collection. Records merge
/// per record with last-writer-wins decided by vector clocks: an edit that
/// saw the other one wins outright; two edits made apart (offline) are
/// concurrent and the later wall time wins, ties broken by device id, so
/// every phone picks the same winner without talking to the others.
/// Deletes are kept as tombstones so they merge like edits.

@immutable
class FamilyRecord {
  const FamilyRecord({
    required this.collection,
    required this.id,
    required this.fields,
    required this.clock,
    required this.wallMillis,
    required this.writer,
    this.deleted = false,
  });

  final String collection;
  final String id;
  final Map<String, Object?> fields;
  final VectorClock clock;

  /// Wall time of the winning edit, only used to break concurrent ties.
  final int wallMillis;

  /// Device that made the winning edit.
  final String writer;
  final bool deleted;

  String get key => '$collection/$id';

  FamilyRecord copyWith({VectorClock? clock}) => FamilyRecord(
        collection: collection,
        id: id,
        fields: fields,
        clock: clock ?? this.clock,
        wallMillis: wallMillis,
        writer: writer,
        deleted: deleted,
      );

  /// True when this edit beats [other] in a concurrent tie.
  bool winsTieAgainst(FamilyRecord other) {
    if (wallMillis != other.wallMillis) {
      return wallMillis > other.wallMillis;
    }
    if (writer != other.writer) {
      return writer.compareTo(other.writer) > 0;
    }
    // Same writer and time cannot be concurrent in practice; keep it total.
    return jsonEncode(fields).compareTo(jsonEncode(other.fields)) > 0;
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'c': collection,
        'i': id,
        'f': fields,
        'v': clock.toJson(),
        'w': wallMillis,
        'd': writer,
        if (deleted) 'x': true,
      };

  static FamilyRecord fromJson(Map<String, Object?> json) {
    final Object? f = json['f'];
    return FamilyRecord(
      collection: json['c']! as String,
      id: json['i']! as String,
      fields: f is Map ? Map<String, Object?>.from(f) : <String, Object?>{},
      clock: VectorClock.fromJson(json['v']),
      wallMillis: (json['w'] as num?)?.toInt() ?? 0,
      writer: json['d'] as String? ?? '',
      deleted: json['x'] == true,
    );
  }

  @override
  String toString() => 'FamilyRecord($key, $fields, $clock${deleted ? ', deleted' : ''})';
}

/// Feature 079 — one change as it landed on this phone, and the path it
/// took: made here, over the home Wi-Fi, or through the own-cloud folder.
@immutable
class FamilyChange {
  const FamilyChange({required this.collection, required this.id, required this.via, required this.at, this.deleted = false});

  final String collection;
  final String id;
  final String via;
  final DateTime at;
  final bool deleted;
}

/// Names of the paths a change can take (feature 079).
abstract final class FamilyPath {
  static const String thisPhone = 'This phone';
  static const String wifi = 'Home Wi-Fi';
  static const String folder = 'Own folder';
  static const String otherPhone = 'Another phone';
}

/// Where the store keeps its records between launches.
abstract class FamilyStoreStorage {
  Future<List<FamilyRecord>> load();
  Future<void> save(List<FamilyRecord> records);
}

class MemoryFamilyStoreStorage implements FamilyStoreStorage {
  List<FamilyRecord> saved = <FamilyRecord>[];

  @override
  Future<List<FamilyRecord>> load() async => List<FamilyRecord>.of(saved);

  @override
  Future<void> save(List<FamilyRecord> records) async => saved = List<FamilyRecord>.of(records);
}

/// A JSON file in the app's private folder.
class FileFamilyStoreStorage implements FamilyStoreStorage {
  FileFamilyStoreStorage(this.folder);

  final Future<Directory> Function() folder;

  Future<File> _file() async => File('${(await folder()).path}/family_store.json');

  @override
  Future<List<FamilyRecord>> load() async {
    final File f = await _file();
    if (!f.existsSync()) {
      return <FamilyRecord>[];
    }
    final Object? json = jsonDecode(await f.readAsString());
    if (json is! List) {
      return <FamilyRecord>[];
    }
    return json.whereType<Map>().map((Map m) => FamilyRecord.fromJson(Map<String, Object?>.from(m))).toList();
  }

  @override
  Future<void> save(List<FamilyRecord> records) async {
    final File f = await _file();
    await f.parent.create(recursive: true);
    final File tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode(records.map((FamilyRecord r) => r.toJson()).toList()));
    await tmp.rename(f.path);
  }
}

/// The store. Local edits go through [put] and [delete]; records from other
/// phones go through [merge]. [changes] carries every record whose state
/// changed, local or merged, so transports can pass it on.
class FamilyStore extends ChangeNotifier {
  FamilyStore({
    required this.deviceId,
    FamilyStoreStorage? storage,
    DateTime Function()? now,
    this.saveDelay = const Duration(milliseconds: 300),
  })  : _storage = storage ?? MemoryFamilyStoreStorage(),
        _now = now ?? DateTime.now;

  String deviceId;
  final FamilyStoreStorage _storage;
  final DateTime Function() _now;
  final Duration saveDelay;

  final Map<String, FamilyRecord> _records = <String, FamilyRecord>{};
  final Map<String, String> _via = <String, String>{};
  final List<FamilyChange> _recent = <FamilyChange>[];

  /// How many recent changes [recentChanges] keeps.
  static const int keepRecent = 50;

  /// Changes as they landed here, newest first, with the path each took.
  List<FamilyChange> get recentChanges => List<FamilyChange>.unmodifiable(_recent);

  /// The path the current state of a record arrived by, if known this run.
  String? pathOf(String collection, String id) => _via['$collection/$id'];
  final StreamController<FamilyRecord> _changes = StreamController<FamilyRecord>.broadcast(sync: true);
  Timer? _saveTimer;

  Stream<FamilyRecord> get changes => _changes.stream;

  /// Every record, tombstones included (transports send these).
  List<FamilyRecord> get allRecords => _records.values.toList();

  int get liveCount => _records.values.where((FamilyRecord r) => !r.deleted).length;

  Future<void> load() async {
    try {
      for (final FamilyRecord r in await _storage.load()) {
        _records[r.key] = r;
      }
    } catch (_) {
      // A damaged file leaves an empty store; peers fill it back in.
    }
    notifyListeners();
  }

  FamilyRecord? get(String collection, String id) {
    final FamilyRecord? r = _records['$collection/$id'];
    return r == null || r.deleted ? null : r;
  }

  /// Live records in [collection], oldest edit first.
  List<FamilyRecord> list(String collection) {
    final List<FamilyRecord> out =
        _records.values.where((FamilyRecord r) => r.collection == collection && !r.deleted).toList();
    out.sort((FamilyRecord a, FamilyRecord b) => a.wallMillis.compareTo(b.wallMillis));
    return out;
  }

  FamilyRecord put(String collection, String id, Map<String, Object?> fields) =>
      _local(collection, id, Map<String, Object?>.unmodifiable(fields), deleted: false);

  FamilyRecord? delete(String collection, String id) {
    if (get(collection, id) == null) {
      return null;
    }
    return _local(collection, id, const <String, Object?>{}, deleted: true);
  }

  FamilyRecord _local(String collection, String id, Map<String, Object?> fields, {required bool deleted}) {
    final FamilyRecord? old = _records['$collection/$id'];
    int wall = _now().millisecondsSinceEpoch;
    if (old != null && wall <= old.wallMillis) {
      wall = old.wallMillis + 1; // a later edit never looks older than the one it replaced
    }
    final FamilyRecord r = FamilyRecord(
      collection: collection,
      id: id,
      fields: fields,
      clock: (old?.clock ?? const VectorClock()).increment(deviceId),
      wallMillis: wall,
      writer: deviceId,
      deleted: deleted,
    );
    _apply(r, FamilyPath.thisPhone);
    return r;
  }

  /// Merges a record from another phone. Returns true when it changed ours.
  /// [via] names the path it took (a [FamilyPath] value).
  bool merge(FamilyRecord incoming, {String via = FamilyPath.otherPhone}) {
    final FamilyRecord? local = _records[incoming.key];
    if (local == null) {
      _apply(incoming, via);
      return true;
    }
    switch (incoming.clock.compare(local.clock)) {
      case ClockOrder.after:
        _apply(incoming, via);
        return true;
      case ClockOrder.before:
      case ClockOrder.equal:
        return false;
      case ClockOrder.concurrent:
        final VectorClock joined = incoming.clock.merge(local.clock);
        final FamilyRecord winner = incoming.winsTieAgainst(local) ? incoming : local;
        _apply(winner.copyWith(clock: joined), identical(winner, incoming) ? via : (_via[local.key] ?? FamilyPath.thisPhone));
        return true;
    }
  }

  /// Merges many records; returns how many changed ours.
  int mergeAll(Iterable<FamilyRecord> records, {String via = FamilyPath.otherPhone}) {
    int n = 0;
    for (final FamilyRecord r in records) {
      if (merge(r, via: via)) {
        n++;
      }
    }
    return n;
  }

  /// Forgets everything (leaving a family). Not propagated.
  Future<void> clear() async {
    _records.clear();
    _via.clear();
    _recent.clear();
    _saveTimer?.cancel();
    await _storage.save(<FamilyRecord>[]);
    notifyListeners();
  }

  void _apply(FamilyRecord r, String via) {
    _records[r.key] = r;
    _via[r.key] = via;
    _recent.insert(0, FamilyChange(collection: r.collection, id: r.id, via: via, at: _now(), deleted: r.deleted));
    if (_recent.length > keepRecent) {
      _recent.removeRange(keepRecent, _recent.length);
    }
    _changes.add(r);
    notifyListeners();
    _saveTimer?.cancel();
    _saveTimer = Timer(saveDelay, () => unawaited(flush()));
  }

  Future<void> flush() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    try {
      await _storage.save(allRecords);
    } catch (_) {
      // Kept in memory; the next change tries again.
    }
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    unawaited(_changes.close());
    super.dispose();
  }
}
