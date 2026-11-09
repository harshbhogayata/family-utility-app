import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'action_history.dart';

/// Feature 117 — File manager.
///
/// Browse the app's own folder and device storage, sort, move, rename,
/// delete to the trash (feature 118), keep recents and favourites, and search
/// by name or by the words inside text files. Everything runs on the phone.

/// One file or folder.
@immutable
class FileNode {
  const FileNode({
    required this.path,
    required this.isDir,
    this.size = 0,
    required this.modified,
  });

  final String path;
  final bool isDir;
  final int size;
  final DateTime modified;

  String get name => baseName(path);

  /// Lower-case extension, empty for folders and names without one.
  String get extension {
    if (isDir) {
      return '';
    }
    final int dot = name.lastIndexOf('.');
    return dot <= 0 || dot == name.length - 1 ? '' : name.substring(dot + 1).toLowerCase();
  }

  @override
  bool operator ==(Object other) => other is FileNode && other.path == path;

  @override
  int get hashCode => path.hashCode;
}

String parentOf(String path) {
  final int slash = path.lastIndexOf('/');
  return slash <= 0 ? '/' : path.substring(0, slash);
}

/// The file system, behind an interface so tests and the UI need no disk.
abstract class FileSource {
  Future<List<FileNode>> list(String dir);

  Future<FileNode?> stat(String path);

  /// The start of a text file, for content search; null when unreadable.
  Future<String?> readText(String path, int maxBytes);

  Future<void> rename(String from, String to);

  Future<void> createFolder(String path);
}

class LocalFileSource implements FileSource {
  const LocalFileSource();

  @override
  Future<List<FileNode>> list(String dir) async {
    final List<FileNode> out = <FileNode>[];
    await for (final FileSystemEntity e in Directory(dir).list(followLinks: false)) {
      final FileStat s = await e.stat();
      out.add(FileNode(
        path: e.path,
        isDir: s.type == FileSystemEntityType.directory,
        size: s.size,
        modified: s.modified,
      ));
    }
    return out;
  }

  @override
  Future<FileNode?> stat(String path) async {
    final FileStat s = await FileStat.stat(path);
    if (s.type == FileSystemEntityType.notFound) {
      return null;
    }
    return FileNode(path: path, isDir: s.type == FileSystemEntityType.directory, size: s.size, modified: s.modified);
  }

  @override
  Future<String?> readText(String path, int maxBytes) async {
    try {
      final RandomAccessFile f = await File(path).open();
      try {
        final List<int> bytes = await f.read(maxBytes);
        return utf8.decode(bytes, allowMalformed: true);
      } finally {
        await f.close();
      }
    } on FileSystemException {
      return null;
    }
  }

  @override
  Future<void> rename(String from, String to) async {
    if (await FileSystemEntity.isDirectory(from)) {
      await Directory(from).rename(to);
      return;
    }
    try {
      await File(from).rename(to);
    } on FileSystemException {
      await File(from).copy(to);
      await File(from).delete();
    }
  }

  @override
  Future<void> createFolder(String path) => Directory(path).create(recursive: true);
}

enum SortBy { name, date, size, type }

/// Pure sorting: folders first, then by the chosen key.
List<FileNode> sortNodes(List<FileNode> nodes, SortBy by, {bool ascending = true}) {
  int byName(FileNode a, FileNode b) => a.name.toLowerCase().compareTo(b.name.toLowerCase());

  int cmp(FileNode a, FileNode b) {
    final int c = switch (by) {
      SortBy.name => byName(a, b),
      SortBy.date => a.modified.compareTo(b.modified),
      SortBy.size => a.size.compareTo(b.size),
      SortBy.type => a.extension.compareTo(b.extension),
    };
    return c != 0 ? c : byName(a, b);
  }

  final List<FileNode> dirs = nodes.where((FileNode n) => n.isDir).toList()
    ..sort(byName);
  final List<FileNode> files = nodes.where((FileNode n) => !n.isDir).toList()
    ..sort((FileNode a, FileNode b) => ascending ? cmp(a, b) : cmp(b, a));
  return <FileNode>[...dirs, ...files];
}

/// Names a person may type: no slashes, not empty, not `.` or `..`.
String? validateName(String name) {
  final String n = name.trim();
  if (n.isEmpty) {
    return 'Type a name';
  }
  if (n == '.' || n == '..' || n.contains('/') || n.contains(r'\')) {
    return 'A name cannot contain / or \\';
  }
  return null;
}

/// A search hit and why it matched.
@immutable
class SearchHit {
  const SearchHit(this.node, {required this.inName, this.snippet});

  final FileNode node;
  final bool inName;

  /// The words around the match when it was found inside the file.
  final String? snippet;
}

/// A root the person can browse.
@immutable
class FileRoot {
  const FileRoot(this.label, this.path);

  final String label;
  final String path;
}

/// Where recents and favourites are kept.
abstract class FileManagerStore {
  Future<String?> read();

  Future<void> write(String json);
}

class MemoryFileManagerStore implements FileManagerStore {
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String json) async => value = json;
}

class JsonFileManagerStore implements FileManagerStore {
  JsonFileManagerStore(this.folder);

  final Future<Directory> Function() folder;

  Future<File> _file() async => File('${(await folder()).path}/files.json');

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

class FileManager extends ChangeNotifier {
  FileManager({
    required this.source,
    required this.history,
    required this.store,
    this.roots = const <FileRoot>[],
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final FileSource source;
  final ActionHistory history;
  final FileManagerStore store;
  /// Set once the platform folders are known.
  List<FileRoot> roots;
  final DateTime Function() _clock;

  void setRoots(List<FileRoot> next) {
    roots = List<FileRoot>.unmodifiable(next);
    notifyListeners();
  }

  static const int keepRecents = 30;
  static const int maxSearchFiles = 5000;
  static const int contentBytes = 512 * 1024;
  static const Set<String> textExtensions = <String>{
    'txt', 'md', 'csv', 'json', 'xml', 'html', 'htm', 'vcf', 'ics', 'log', 'yaml', 'yml',
  };

  List<String> _recents = <String>[];
  Set<String> _favourites = <String>{};

  /// Most recently opened first.
  List<String> get recents => List<String>.unmodifiable(_recents);

  Set<String> get favourites => Set<String>.unmodifiable(_favourites);

  Future<void> load() async {
    try {
      final String? raw = await store.read();
      if (raw != null && raw.isNotEmpty) {
        final Map<String, Object?> j = jsonDecode(raw) as Map<String, Object?>;
        _recents = (j['recents'] as List<Object?>? ?? <Object?>[]).cast<String>().toList();
        _favourites = (j['favourites'] as List<Object?>? ?? <Object?>[]).cast<String>().toSet();
      }
    } catch (_) {
      _recents = <String>[];
      _favourites = <String>{};
    }
    notifyListeners();
  }

  Future<void> _save() async {
    try {
      await store.write(jsonEncode(<String, Object?>{
        'recents': _recents,
        'favourites': _favourites.toList(),
      }));
    } catch (_) {
      // Kept in memory for this launch.
    }
  }

  Future<List<FileNode>> list(String dir, {SortBy by = SortBy.name, bool ascending = true}) async {
    return sortNodes(await source.list(dir), by, ascending: ascending);
  }

  /// Called whenever a file is opened from anywhere in the app.
  Future<void> touch(String path) async {
    _recents = <String>[path, ..._recents.where((String p) => p != path)].take(keepRecents).toList();
    await _save();
    notifyListeners();
  }

  Future<bool> toggleFavourite(String path) async {
    final bool now = !_favourites.contains(path);
    if (now) {
      _favourites = <String>{..._favourites, path};
    } else {
      _favourites = _favourites.where((String p) => p != path).toSet();
    }
    await _save();
    notifyListeners();
    return now;
  }

  /// Renames in place. Returns the new path. Throws [ArgumentError] on a bad
  /// name and [StateError] when the name is taken.
  Future<String> rename(String path, String newName) async {
    final String? problem = validateName(newName);
    if (problem != null) {
      throw ArgumentError(problem);
    }
    final String to = '${parentOf(path)}/${newName.trim()}';
    if (to == path) {
      return path;
    }
    if (await source.stat(to) != null) {
      throw StateError('${newName.trim()} already exists here');
    }
    await source.rename(path, to);
    _retarget(path, to);
    await history.record(toolId: 'files', toolName: 'Rename', inputs: <String>[path], outputs: <String>[to]);
    await _save();
    notifyListeners();
    return to;
  }

  Future<String> _free(String path) async {
    String candidate = path;
    final int slash = path.lastIndexOf('/');
    final String dir = path.substring(0, slash + 1);
    final String name = path.substring(slash + 1);
    final int dot = name.lastIndexOf('.');
    final String stem = dot > 0 ? name.substring(0, dot) : name;
    final String ext = dot > 0 ? name.substring(dot) : '';
    int i = 2;
    while (await source.stat(candidate) != null) {
      candidate = '$dir$stem ($i)$ext';
      i++;
    }
    return candidate;
  }

  /// Moves into [folder] under a free name. Returns the new path.
  Future<String> moveTo(String path, String folder) async {
    if (parentOf(path) == folder) {
      return path;
    }
    final String to = await _free('$folder/${baseName(path)}');
    await source.rename(path, to);
    _retarget(path, to);
    await history.record(toolId: 'files', toolName: 'Move', inputs: <String>[path], outputs: <String>[to]);
    await _save();
    notifyListeners();
    return to;
  }

  Future<String> createFolder(String parent, String name) async {
    final String? problem = validateName(name);
    if (problem != null) {
      throw ArgumentError(problem);
    }
    final String path = await _free('$parent/${name.trim()}');
    await source.createFolder(path);
    notifyListeners();
    return path;
  }

  /// Soft delete: the file goes to the trash for 30 days.
  Future<TrashItem?> delete(String path) async {
    final TrashItem? t = await history.delete(path);
    _recents = _recents.where((String p) => p != path).toList();
    _favourites = _favourites.where((String p) => p != path).toSet();
    await _save();
    notifyListeners();
    return t;
  }

  void _retarget(String from, String to) {
    _recents = _recents.map((String p) => p == from ? to : p).toList();
    _favourites = _favourites.map((String p) => p == from ? to : p).toSet();
  }

  /// Walks [root] and matches names, and the words inside text files when
  /// [inContent] is on. Case-insensitive.
  Future<List<SearchHit>> search(String root, String query, {bool inContent = true}) async {
    final String q = query.trim().toLowerCase();
    if (q.isEmpty) {
      return <SearchHit>[];
    }
    final List<SearchHit> hits = <SearchHit>[];
    final List<String> todo = <String>[root];
    int seen = 0;
    while (todo.isNotEmpty && seen < maxSearchFiles) {
      final String dir = todo.removeLast();
      List<FileNode> nodes;
      try {
        nodes = await source.list(dir);
      } on FileSystemException {
        continue; // no permission: skip that folder
      }
      for (final FileNode n in sortNodes(nodes, SortBy.name)) {
        seen++;
        if (n.isDir) {
          todo.add(n.path);
        }
        if (n.name.toLowerCase().contains(q)) {
          hits.add(SearchHit(n, inName: true));
          continue;
        }
        if (inContent && !n.isDir && textExtensions.contains(n.extension)) {
          final String? text = await source.readText(n.path, contentBytes);
          final String? snip = text == null ? null : snippetFor(text, q);
          if (snip != null) {
            hits.add(SearchHit(n, inName: false, snippet: snip));
          }
        }
      }
    }
    return hits;
  }

  /// The words around the first match, or null.
  static String? snippetFor(String text, String lowerQuery) {
    final int at = text.toLowerCase().indexOf(lowerQuery);
    if (at < 0) {
      return null;
    }
    final int from = at - 30 < 0 ? 0 : at - 30;
    final int to = at + lowerQuery.length + 30 > text.length ? text.length : at + lowerQuery.length + 30;
    final String s = text.substring(from, to).replaceAll(RegExp(r'\s+'), ' ').trim();
    return '${from > 0 ? '…' : ''}$s${to < text.length ? '…' : ''}';
  }

  DateTime get now => _clock();

  static FileManager instance = FileManager(
    source: const _EmptySource(),
    history: ActionHistory.instance,
    store: MemoryFileManagerStore(),
  );

  static void install(FileManager m) {
    instance = m;
  }
}

class _EmptySource implements FileSource {
  const _EmptySource();

  @override
  Future<List<FileNode>> list(String dir) async => <FileNode>[];

  @override
  Future<FileNode?> stat(String path) async => null;

  @override
  Future<String?> readText(String path, int maxBytes) async => null;

  @override
  Future<void> rename(String from, String to) async {}

  @override
  Future<void> createFolder(String path) async {}
}
