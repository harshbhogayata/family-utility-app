import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'action_history.dart';

/// Feature 108 — Versions: each run keeps the original; roll back any time.
///
/// When a tool run is recorded (feature 118), a copy of every input is kept in
/// the app's own versions folder and listed under each output. Rolling a file
/// back first keeps the current bytes as another version, so a roll back can
/// itself be undone. Kept copies stay until the trash is emptied. Nothing
/// leaves the phone.

/// One kept copy of a file.
@immutable
class FileVersion {
  const FileVersion({
    required this.id,
    required this.filePath,
    required this.storedPath,
    required this.sourceName,
    required this.label,
    required this.at,
    required this.size,
  });

  factory FileVersion.fromJson(Map<String, Object?> j) => FileVersion(
        id: j['id']! as String,
        filePath: j['filePath']! as String,
        storedPath: j['storedPath']! as String,
        sourceName: j['sourceName']! as String,
        label: j['label']! as String,
        at: DateTime.fromMillisecondsSinceEpoch(j['at']! as int),
        size: j['size']! as int,
      );

  final String id;

  /// The file this version belongs to (its version list).
  final String filePath;

  /// Where the copy sits in the versions folder.
  final String storedPath;

  /// Name of the file the copy was taken from ("IMG_1.jpg").
  final String sourceName;

  /// "Original before Compress PDF", "Before roll back".
  final String label;
  final DateTime at;
  final int size;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'filePath': filePath,
        'storedPath': storedPath,
        'sourceName': sourceName,
        'label': label,
        'at': at.millisecondsSinceEpoch,
        'size': size,
      };
}

/// Copies files in and out of the versions folder.
abstract class VersionStore {
  /// Copies [path] in under [id]; returns where the copy went and its size.
  /// Throws [FileSystemException] if [path] is gone.
  Future<(String, int)> keep(String path, String id);

  /// Writes the kept copy back over [targetPath] (creating it if missing).
  Future<void> putBack(String storedPath, String targetPath);

  Future<void> purge(String storedPath);
}

class DirectoryVersionStore implements VersionStore {
  DirectoryVersionStore(this.folder);

  final Future<Directory> Function() folder;

  @override
  Future<(String, int)> keep(String path, String id) async {
    final Directory dir = await folder();
    await dir.create(recursive: true);
    final String target = '${dir.path}/$id-${baseName(path)}';
    final File copy = await File(path).copy(target);
    return (copy.path, await copy.length());
  }

  @override
  Future<void> putBack(String storedPath, String targetPath) async {
    await File(targetPath).parent.create(recursive: true);
    await File(storedPath).copy(targetPath);
  }

  @override
  Future<void> purge(String storedPath) async {
    final File f = File(storedPath);
    if (f.existsSync()) {
      await f.delete();
    }
  }
}

/// Where the version index is kept (one JSON document).
abstract class VersionIndexStore {
  Future<String?> read();

  Future<void> write(String json);
}

class MemoryVersionIndexStore implements VersionIndexStore {
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String json) async => value = json;
}

class FileVersionIndexStore implements VersionIndexStore {
  FileVersionIndexStore(this.folder);

  final Future<Directory> Function() folder;

  Future<File> _file() async => File('${(await folder()).path}/versions.json');

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

class Versions extends ChangeNotifier {
  Versions({required VersionStore store, required VersionIndexStore index, DateTime Function()? clock})
      : _store = store,
        _index = index,
        _clock = clock ?? DateTime.now;

  final VersionStore _store;
  final VersionIndexStore _index;
  final DateTime Function() _clock;
  List<FileVersion> _all = <FileVersion>[];
  int _seq = 0;

  String _id() => 'v${_clock().millisecondsSinceEpoch.toRadixString(36)}${(_seq++).toRadixString(36)}';

  /// Every kept copy, newest first.
  List<FileVersion> get all => List<FileVersion>.unmodifiable(_all);

  /// Files that have at least one kept version, most recently changed first.
  List<String> get files {
    final List<String> out = <String>[];
    for (final FileVersion v in _all) {
      if (!out.contains(v.filePath)) {
        out.add(v.filePath);
      }
    }
    return out;
  }

  /// The version list for one file, newest first.
  List<FileVersion> versionsOf(String path) => _all.where((FileVersion v) => v.filePath == path).toList();

  FileVersion? byId(String id) {
    for (final FileVersion v in _all) {
      if (v.id == id) {
        return v;
      }
    }
    return null;
  }

  Future<void> load() async {
    try {
      final String? raw = await _index.read();
      if (raw != null && raw.isNotEmpty) {
        _all = (jsonDecode(raw) as List<Object?>)
            .map((Object? e) => FileVersion.fromJson(e! as Map<String, Object?>))
            .toList();
      }
    } catch (_) {
      _all = <FileVersion>[];
    }
    notifyListeners();
  }

  Future<void> _save() async {
    try {
      await _index.write(jsonEncode(_all.map((FileVersion v) => v.toJson()).toList()));
    } catch (_) {
      // Memory still holds it for this launch.
    }
  }

  /// Keeps a copy of [source]'s current bytes in [filePath]'s version list.
  /// Returns null if [source] is gone.
  Future<FileVersion?> keep(String filePath, String source, String label) async {
    final FileVersion? v = await _keepOne(filePath, source, label);
    if (v != null) {
      await _save();
      notifyListeners();
    }
    return v;
  }

  Future<FileVersion?> _keepOne(String filePath, String source, String label) async {
    try {
      final String id = _id();
      final (String stored, int size) = await _store.keep(source, id);
      final FileVersion v = FileVersion(
        id: id,
        filePath: filePath,
        storedPath: stored,
        sourceName: baseName(source),
        label: label,
        at: _clock(),
        size: size,
      );
      _all = <FileVersion>[v, ..._all];
      return v;
    } on FileSystemException {
      return null;
    }
  }

  /// Wired to [ActionHistory.onRecorded]: each output's version list gets a
  /// copy of every input, as it was when the tool ran.
  Future<List<FileVersion>> recordRun(HistoryEntry run) async {
    final List<FileVersion> kept = <FileVersion>[];
    for (final String out in run.outputs) {
      for (final String input in run.inputs) {
        if (input == out) {
          continue;
        }
        final FileVersion? v = await _keepOne(out, input, 'Original before ${run.toolName}');
        if (v != null) {
          kept.add(v);
        }
      }
    }
    if (kept.isNotEmpty) {
      await _save();
      notifyListeners();
    }
    return kept;
  }

  /// Puts [versionId] back as the current [FileVersion.filePath]. The bytes
  /// there now are kept first as "Before roll back"; that version is returned
  /// so Undo can roll forward again.
  Future<FileVersion?> rollBack(String versionId) async {
    final FileVersion? v = byId(versionId);
    if (v == null) {
      return null;
    }
    final FileVersion? before = await _keepOne(v.filePath, v.filePath, 'Before roll back');
    await _store.putBack(v.storedPath, v.filePath);
    await _save();
    notifyListeners();
    return before;
  }

  /// Wired to [ActionHistory.onTrashEmptied]: kept originals go with the trash.
  Future<int> purgeAll() async {
    final int n = _all.length;
    for (final FileVersion v in _all) {
      await _store.purge(v.storedPath);
    }
    _all = <FileVersion>[];
    await _save();
    notifyListeners();
    return n;
  }

  /// Connects to the history: runs keep originals, emptying trash clears them.
  void attach(ActionHistory history) {
    history
      ..onRecorded = (HistoryEntry e) async {
        await recordRun(e);
      }
      ..onTrashEmptied = () async {
        await purgeAll();
      };
  }

  static String formatSize(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) {
      return '${(bytes / 1024).round()} KB';
    }
    return '$bytes B';
  }

  static Versions instance = Versions(store: _NoStore(), index: MemoryVersionIndexStore());

  static void install(Versions v) => instance = v;
}

class _NoStore implements VersionStore {
  @override
  Future<(String, int)> keep(String path, String id) async => throw FileSystemException('versions off', path);

  @override
  Future<void> putBack(String storedPath, String targetPath) async {}

  @override
  Future<void> purge(String storedPath) async {}
}
