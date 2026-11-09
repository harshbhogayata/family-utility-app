import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Feature 118 — Action history and trash.
///
/// Every tool run is recorded with the files it read and wrote, so it can be
/// undone (its outputs go to the trash) or re-run on a new file. Anything the
/// app deletes goes to a trash first and can be restored for 30 days. All of
/// it lives in the app's own folder; nothing leaves the phone.

/// One tool run.
@immutable
class HistoryEntry {
  const HistoryEntry({
    required this.id,
    required this.toolId,
    required this.toolName,
    required this.inputs,
    required this.outputs,
    required this.at,
    this.undone = false,
  });

  factory HistoryEntry.fromJson(Map<String, Object?> j) {
    return HistoryEntry(
      id: j['id']! as String,
      toolId: j['toolId']! as String,
      toolName: j['toolName']! as String,
      inputs: (j['inputs']! as List<Object?>).cast<String>(),
      outputs: (j['outputs']! as List<Object?>).cast<String>(),
      at: DateTime.fromMillisecondsSinceEpoch(j['at']! as int),
      undone: j['undone'] == true,
    );
  }

  final String id;
  final String toolId;
  final String toolName;
  final List<String> inputs;
  final List<String> outputs;
  final DateTime at;
  final bool undone;

  HistoryEntry markUndone() => HistoryEntry(
        id: id,
        toolId: toolId,
        toolName: toolName,
        inputs: inputs,
        outputs: outputs,
        at: at,
        undone: true,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'toolId': toolId,
        'toolName': toolName,
        'inputs': inputs,
        'outputs': outputs,
        'at': at.millisecondsSinceEpoch,
        'undone': undone,
      };
}

/// One deleted file waiting in the trash.
@immutable
class TrashItem {
  const TrashItem({
    required this.id,
    required this.originalPath,
    required this.trashedPath,
    required this.deletedAt,
  });

  factory TrashItem.fromJson(Map<String, Object?> j) {
    return TrashItem(
      id: j['id']! as String,
      originalPath: j['originalPath']! as String,
      trashedPath: j['trashedPath']! as String,
      deletedAt: DateTime.fromMillisecondsSinceEpoch(j['deletedAt']! as int),
    );
  }

  final String id;
  final String originalPath;
  final String trashedPath;
  final DateTime deletedAt;

  String get name => baseName(originalPath);

  DateTime get expiresAt => deletedAt.add(ActionHistory.retention);

  /// Whole days left before it is removed for good, never below zero.
  int daysLeft(DateTime now) {
    final Duration left = expiresAt.difference(now);
    if (left.isNegative) {
      return 0;
    }
    return (left.inHours / 24).ceil();
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'originalPath': originalPath,
        'trashedPath': trashedPath,
        'deletedAt': deletedAt.millisecondsSinceEpoch,
      };
}

String baseName(String path) => path.split('/').last.split(r'\').last;

/// What a re-run asks the tool to do.
@immutable
class RerunRequest {
  const RerunRequest({required this.toolId, required this.inputs, required this.from});

  final String toolId;
  final List<String> inputs;

  /// The entry it repeats.
  final String from;
}

/// Where the history and trash index are kept (one JSON document).
abstract class HistoryStore {
  Future<String?> read();

  Future<void> write(String json);
}

class MemoryHistoryStore implements HistoryStore {
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String json) async => value = json;
}

class FileHistoryStore implements HistoryStore {
  FileHistoryStore(this.folder);

  final Future<Directory> Function() folder;

  Future<File> _file() async => File('${(await folder()).path}/history.json');

  @override
  Future<String?> read() async {
    final File f = await _file();
    return f.existsSync() ? f.readAsString() : null;
  }

  @override
  Future<void> write(String json) async {
    final File f = await _file();
    await f.parent.create(recursive: true);
    await f.writeAsString(json, flush: true);
  }
}

/// Moves files in and out of the trash folder.
abstract class TrashBin {
  /// Moves [path] into the trash and returns where it went.
  Future<String> moveIn(String path, String id);

  /// Moves a trashed file back. Returns the path it was restored to, which is
  /// the original path unless something new now sits there.
  Future<String> moveOut(String trashedPath, String originalPath);

  Future<void> purge(String trashedPath);
}

class DirectoryTrashBin implements TrashBin {
  DirectoryTrashBin(this.folder);

  final Future<Directory> Function() folder;

  @override
  Future<String> moveIn(String path, String id) async {
    final Directory dir = await folder();
    await dir.create(recursive: true);
    final String target = '${dir.path}/$id-${baseName(path)}';
    await _move(File(path), target);
    return target;
  }

  @override
  Future<String> moveOut(String trashedPath, String originalPath) async {
    final String target = freePath(originalPath, (String p) => File(p).existsSync());
    await File(target).parent.create(recursive: true);
    await _move(File(trashedPath), target);
    return target;
  }

  @override
  Future<void> purge(String trashedPath) async {
    final File f = File(trashedPath);
    if (f.existsSync()) {
      await f.delete();
    }
  }

  static Future<void> _move(File f, String target) async {
    try {
      await f.rename(target);
    } on FileSystemException {
      // Across volumes rename fails: copy then delete.
      await f.copy(target);
      await f.delete();
    }
  }
}

/// [path] if free, else `name (2).ext`, `name (3).ext`, …
String freePath(String path, bool Function(String) exists) {
  if (!exists(path)) {
    return path;
  }
  final int slash = path.lastIndexOf('/');
  final String dir = slash >= 0 ? path.substring(0, slash + 1) : '';
  final String name = path.substring(slash + 1);
  final int dot = name.lastIndexOf('.');
  final String stem = dot > 0 ? name.substring(0, dot) : name;
  final String ext = dot > 0 ? name.substring(dot) : '';
  int i = 2;
  while (exists('$dir$stem ($i)$ext')) {
    i++;
  }
  return '$dir$stem ($i)$ext';
}

/// The history and the trash.
class ActionHistory extends ChangeNotifier {
  ActionHistory({required HistoryStore store, required TrashBin bin, DateTime Function()? clock})
      : _store = store,
        _bin = bin,
        _clock = clock ?? DateTime.now;

  static const Duration retention = Duration(days: 30);
  static const int keepEntries = 500;

  final HistoryStore _store;
  final TrashBin _bin;
  final DateTime Function() _clock;

  List<HistoryEntry> _entries = <HistoryEntry>[];
  List<TrashItem> _trash = <TrashItem>[];
  int _seq = 0;

  /// Feature 108: called after each recorded run, so Versions can keep the
  /// originals. Errors are swallowed; history never fails because of it.
  Future<void> Function(HistoryEntry entry)? onRecorded;

  /// Feature 108: called after the trash is emptied, when kept originals go too.
  Future<void> Function()? onTrashEmptied;

  /// Newest first.
  List<HistoryEntry> get entries => List<HistoryEntry>.unmodifiable(_entries);

  /// Most recently deleted first.
  List<TrashItem> get trash => List<TrashItem>.unmodifiable(_trash);

  DateTime get now => _clock();

  String _id() => '${_clock().millisecondsSinceEpoch.toRadixString(36)}${(_seq++).toRadixString(36)}';

  Future<void> load() async {
    try {
      final String? raw = await _store.read();
      if (raw != null && raw.isNotEmpty) {
        final Map<String, Object?> j = jsonDecode(raw) as Map<String, Object?>;
        _entries = (j['entries'] as List<Object?>? ?? <Object?>[])
            .map((Object? e) => HistoryEntry.fromJson(e! as Map<String, Object?>))
            .toList();
        _trash = (j['trash'] as List<Object?>? ?? <Object?>[])
            .map((Object? e) => TrashItem.fromJson(e! as Map<String, Object?>))
            .toList();
      }
    } catch (_) {
      // A damaged index starts empty rather than blocking the app.
      _entries = <HistoryEntry>[];
      _trash = <TrashItem>[];
    }
    await purgeExpired();
    notifyListeners();
  }

  Future<void> _save() async {
    try {
      await _store.write(jsonEncode(<String, Object?>{
        'entries': _entries.map((HistoryEntry e) => e.toJson()).toList(),
        'trash': _trash.map((TrashItem t) => t.toJson()).toList(),
      }));
    } catch (_) {
      // Memory still holds it for this launch.
    }
  }

  /// Called by a tool when it finishes.
  Future<HistoryEntry> record({
    required String toolId,
    required String toolName,
    required List<String> inputs,
    required List<String> outputs,
  }) async {
    final HistoryEntry e = HistoryEntry(
      id: _id(),
      toolId: toolId,
      toolName: toolName,
      inputs: List<String>.unmodifiable(inputs),
      outputs: List<String>.unmodifiable(outputs),
      at: _clock(),
    );
    _entries = <HistoryEntry>[e, ..._entries].take(keepEntries).toList();
    await _save();
    notifyListeners();
    await _hook(() => onRecorded?.call(e));
    return e;
  }

  HistoryEntry? entry(String id) {
    for (final HistoryEntry e in _entries) {
      if (e.id == id) {
        return e;
      }
    }
    return null;
  }

  /// Undoes a run: its outputs go to the trash (restorable for 30 days).
  /// The inputs are never touched.
  Future<bool> undo(String entryId) async {
    final HistoryEntry? e = entry(entryId);
    if (e == null || e.undone) {
      return false;
    }
    for (final String out in e.outputs) {
      await _trashOne(out);
    }
    _entries = _entries.map((HistoryEntry x) => x.id == entryId ? x.markUndone() : x).toList();
    await _save();
    notifyListeners();
    return true;
  }

  /// The same tool, on a new file.
  RerunRequest rerun(String entryId, List<String> newInputs) {
    final HistoryEntry? e = entry(entryId);
    if (e == null) {
      throw ArgumentError.value(entryId, 'entryId', 'no such history entry');
    }
    if (newInputs.isEmpty) {
      throw ArgumentError.value(newInputs, 'newInputs', 'pick a file to re-run on');
    }
    return RerunRequest(toolId: e.toolId, inputs: List<String>.unmodifiable(newInputs), from: e.id);
  }

  /// Deletes a file the soft way.
  Future<TrashItem?> delete(String path) async {
    final TrashItem? t = await _trashOne(path);
    await _save();
    notifyListeners();
    return t;
  }

  Future<TrashItem?> _trashOne(String path) async {
    try {
      final String id = _id();
      final String where = await _bin.moveIn(path, id);
      final TrashItem t = TrashItem(id: id, originalPath: path, trashedPath: where, deletedAt: _clock());
      _trash = <TrashItem>[t, ..._trash];
      return t;
    } on FileSystemException {
      return null; // already gone
    }
  }

  /// Puts a trashed file back. Returns where it went.
  Future<String?> restore(String trashId) async {
    TrashItem? t;
    for (final TrashItem x in _trash) {
      if (x.id == trashId) {
        t = x;
      }
    }
    if (t == null) {
      return null;
    }
    final String back = await _bin.moveOut(t.trashedPath, t.originalPath);
    _trash = _trash.where((TrashItem x) => x.id != trashId).toList();
    await _save();
    notifyListeners();
    return back;
  }

  /// Removes trash older than [retention]. Returns how many went.
  Future<int> purgeExpired() async {
    final DateTime n = _clock();
    final List<TrashItem> old = _trash.where((TrashItem t) => !t.expiresAt.isAfter(n)).toList();
    for (final TrashItem t in old) {
      await _bin.purge(t.trashedPath);
    }
    if (old.isNotEmpty) {
      _trash = _trash.where((TrashItem t) => !old.contains(t)).toList();
      await _save();
      notifyListeners();
    }
    return old.length;
  }

  Future<void> emptyTrash() async {
    for (final TrashItem t in _trash) {
      await _bin.purge(t.trashedPath);
    }
    _trash = <TrashItem>[];
    await _save();
    notifyListeners();
    await _hook(() => onTrashEmptied?.call());
  }

  static Future<void> _hook(Future<void>? Function() call) async {
    try {
      await call();
    } catch (_) {
      // A hook must never break history.
    }
  }

  /// Plain-text log for Share and Save.
  String asText() {
    final StringBuffer b = StringBuffer('Action history\n');
    for (final HistoryEntry e in _entries) {
      b.writeln('${formatWhen(e.at)}  ${e.toolName}${e.undone ? ' (undone)' : ''}: '
          '${e.inputs.map(baseName).join(', ')} → ${e.outputs.map(baseName).join(', ')}');
    }
    return b.toString();
  }

  static String formatWhen(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.day)}/${two(t.month)}/${t.year} ${two(t.hour)}:${two(t.minute)}';
  }

  /// One shared instance; bootstrap installs the file-backed one.
  static ActionHistory instance = ActionHistory(store: MemoryHistoryStore(), bin: _NoTrash());

  static void install(ActionHistory h) {
    instance = h;
  }
}

class _NoTrash implements TrashBin {
  @override
  Future<String> moveIn(String path, String id) async => path;

  @override
  Future<String> moveOut(String trashedPath, String originalPath) async => originalPath;

  @override
  Future<void> purge(String trashedPath) async {}
}
