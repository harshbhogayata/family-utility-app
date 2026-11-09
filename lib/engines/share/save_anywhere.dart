import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Feature 064 — Save anywhere.
///
/// Where a tool's result goes: the app's Files, the phone's Downloads, or a
/// folder the person picks. The last choice is remembered per tool, so the
/// save sheet opens on it next time. Everything stays on the phone.

enum SaveDestination {
  files('Files', 'The app\'s own Files tab'),
  downloads('Downloads', 'The phone\'s Downloads folder'),
  custom('Choose a folder…', 'Pick any folder on the phone');

  const SaveDestination(this.label, this.hint);
  final String label;
  final String hint;

  static SaveDestination parse(String? name) {
    for (final SaveDestination d in SaveDestination.values) {
      if (d.name == name) {
        return d;
      }
    }
    return SaveDestination.files;
  }
}

/// What a tool chose last time.
@immutable
class SaveChoice {
  const SaveChoice(this.destination, {this.folder});

  final SaveDestination destination;

  /// The folder last used for this destination (custom folders only matter).
  final String? folder;

  Map<String, Object?> toJson() => <String, Object?>{'d': destination.name, 'f': folder};

  static SaveChoice fromJson(Map<String, Object?> json) {
    final Object? f = json['f'];
    return SaveChoice(SaveDestination.parse(json['d'] as String?), folder: f is String ? f : null);
  }

  @override
  bool operator ==(Object other) =>
      other is SaveChoice && other.destination == destination && other.folder == folder;

  @override
  int get hashCode => Object.hash(destination, folder);
}

/// The phone side: folders and writing. Fakes in tests.
abstract class SavePlatform {
  Future<String> filesFolder();

  Future<String> downloadsFolder();

  /// Asks the system for a folder. Null when the person cancels.
  Future<String?> pickFolder({String? initialFolder});

  Future<bool> exists(String path);

  /// Writes the bytes to exactly [path], creating folders as needed.
  Future<void> write(String path, Uint8List bytes);
}

abstract class SaveChoiceStore {
  Future<String?> read();

  Future<void> write(String json);
}

class MemorySaveChoiceStore implements SaveChoiceStore {
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String json) async => value = json;
}

class SaveAnywhere extends ChangeNotifier {
  SaveAnywhere({required this.platform, required this.store});

  final SavePlatform platform;
  final SaveChoiceStore store;
  final Map<String, SaveChoice> _byTool = <String, SaveChoice>{};

  Future<void> load() async {
    try {
      final String? raw = await store.read();
      if (raw == null || raw.isEmpty) {
        return;
      }
      final Object? decoded = jsonDecode(raw);
      if (decoded is Map<String, Object?>) {
        decoded.forEach((String tool, Object? v) {
          if (v is Map<String, Object?>) {
            _byTool[tool] = SaveChoice.fromJson(v);
          }
        });
      }
      notifyListeners();
    } catch (_) {
      // A broken file just means no remembered choices.
    }
  }

  /// The choice the save sheet opens on for [toolId]. Files when new.
  SaveChoice lastFor(String toolId) => _byTool[toolId] ?? const SaveChoice(SaveDestination.files);

  /// The folder a destination resolves to; for custom, the remembered folder
  /// or null when none has been picked yet.
  Future<String?> folderFor(String toolId, SaveDestination destination) async {
    switch (destination) {
      case SaveDestination.files:
        return platform.filesFolder();
      case SaveDestination.downloads:
        return platform.downloadsFolder();
      case SaveDestination.custom:
        final SaveChoice last = lastFor(toolId);
        return last.destination == SaveDestination.custom ? last.folder : null;
    }
  }

  /// The full path the file would land at: a free name in [folder].
  Future<String> finalPath(String folder, String name) async {
    final String clean = safeName(name);
    final String base = folder.endsWith('/') ? folder.substring(0, folder.length - 1) : folder;
    String path = '$base/$clean';
    final int dot = clean.lastIndexOf('.');
    final String stem = dot > 0 ? clean.substring(0, dot) : clean;
    final String ext = dot > 0 ? clean.substring(dot) : '';
    int i = 2;
    while (await platform.exists(path)) {
      path = '$base/$stem ($i)$ext';
      i++;
    }
    return path;
  }

  /// Asks the system for a folder and returns it (null on cancel).
  Future<String?> pickFolder(String toolId) {
    final SaveChoice last = lastFor(toolId);
    return platform.pickFolder(initialFolder: last.destination == SaveDestination.custom ? last.folder : null);
  }

  /// Writes the file into [folder] and remembers the choice for the tool.
  /// Returns the final path.
  Future<String> save({
    required String toolId,
    required SaveDestination destination,
    required String folder,
    required String name,
    required Uint8List bytes,
  }) async {
    final String path = await finalPath(folder, name);
    await platform.write(path, bytes);
    await remember(toolId, SaveChoice(destination, folder: destination == SaveDestination.custom ? folder : null));
    return path;
  }

  Future<void> remember(String toolId, SaveChoice choice) async {
    _byTool[toolId] = choice;
    notifyListeners();
    final Map<String, Object?> out = <String, Object?>{};
    _byTool.forEach((String k, SaveChoice v) => out[k] = v.toJson());
    try {
      await store.write(jsonEncode(out));
    } catch (_) {
      // Remembering is a convenience; the file is already saved.
    }
  }

  /// Strips path separators and characters file systems refuse.
  static String safeName(String name) {
    final String trimmed = name.split('/').last.split('\\').last.trim();
    final String cleaned = trimmed.replaceAll(RegExp(r'[<>:"|?*\x00-\x1F]'), '_');
    return cleaned.isEmpty || cleaned == '.' || cleaned == '..' ? 'file' : cleaned;
  }

  /// Shortens a path for display: the last three parts after an ellipsis.
  static String shortPath(String path) {
    final List<String> parts = path.split('/').where((String p) => p.isNotEmpty).toList();
    if (parts.length <= 3) {
      return '/${parts.join('/')}';
    }
    return '…/${parts.sublist(parts.length - 3).join('/')}';
  }

  static SaveAnywhere? _instance;

  static SaveAnywhere? get maybeInstance => _instance;

  static void install(SaveAnywhere s) => _instance = s;
}
