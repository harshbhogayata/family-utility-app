import 'dart:io';
import 'dart:typed_data';

import 'zip_codec.dart';

/// Feature 037 — Zip with optional password. Bundles several files, picked
/// from the phone or from the app's own results, into one ZIP. A password
/// turns on WinZip AES-256. Built in pure Dart; nothing leaves the phone.

class ZipBundleError implements Exception {
  const ZipBundleError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// One file the person chose to bundle.
class BundleItem {
  const BundleItem(this.path, {this.fromResults = false});
  final String path;

  /// True when it came from the app's own results rather than the picker.
  final bool fromResults;

  String get name => path.substring(path.lastIndexOf('/') + 1);

  @override
  bool operator ==(Object other) => other is BundleItem && other.path == path;

  @override
  int get hashCode => path.hashCode;
}

/// The app's earlier results (compressed pictures, merged PDFs, scans...).
abstract class ResultLibrary {
  Future<List<String>> list();
}

/// Lists the files under the app's documents folder, newest first. Skips
/// hidden files, the app's own settings and the saved signatures.
class DirectoryResultLibrary implements ResultLibrary {
  const DirectoryResultLibrary(this.folder);
  final Future<Directory> Function() folder;

  static const Set<String> _private = <String>{'signatures', 'secure', 'notes', 'trash', '.trash'};

  @override
  Future<List<String>> list() async {
    final Directory base = await folder();
    if (!base.existsSync()) {
      return <String>[];
    }
    final List<File> files = <File>[];
    await for (final FileSystemEntity e in base.list()) {
      if (e is! Directory) {
        continue;
      }
      final String sub = e.path.substring(e.path.lastIndexOf('/') + 1);
      if (sub.startsWith('.') || _private.contains(sub)) {
        continue;
      }
      await for (final FileSystemEntity f in e.list(recursive: true)) {
        if (f is File && !f.path.substring(f.path.lastIndexOf('/') + 1).startsWith('.')) {
          files.add(f);
        }
      }
    }
    files.sort((File a, File b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    return files.map((File f) => f.path).toList();
  }
}

class ZipBundler {
  ZipBundler({ZipWriter? writer}) : _writer = writer ?? ZipWriter();
  final ZipWriter _writer;

  /// Shortest password the tool accepts when locking is on.
  static const int minPassword = 4;

  /// Problem with the password, or null when it can be used.
  static String? checkPassword(String password, String confirm) {
    if (password.length < minPassword) {
      return 'Use at least $minPassword characters';
    }
    if (password != confirm) {
      return 'The two passwords do not match';
    }
    return null;
  }

  /// A safe ZIP file name from what the person typed.
  static String archiveName(String typed, List<BundleItem> items) {
    String base = typed.trim().replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    if (base.toLowerCase().endsWith('.zip')) {
      base = base.substring(0, base.length - 4);
    }
    if (base.isEmpty) {
      if (items.length == 1) {
        final String n = items.first.name;
        final int dot = n.lastIndexOf('.');
        base = dot > 0 ? n.substring(0, dot) : n;
      } else {
        base = 'Files';
      }
    }
    return '$base.zip';
  }

  /// Names inside the ZIP, with "(2)" added where two files share a name.
  static List<String> entryNames(List<BundleItem> items) {
    final Set<String> used = <String>{};
    final List<String> out = <String>[];
    for (final BundleItem item in items) {
      String name = item.name;
      if (!used.add(name.toLowerCase())) {
        final int dot = name.lastIndexOf('.');
        int n = 2;
        String candidate;
        do {
          candidate = dot > 0 ? '${name.substring(0, dot)} ($n)${name.substring(dot)}' : '$name ($n)';
          n++;
        } while (!used.add(candidate.toLowerCase()));
        name = candidate;
      }
      out.add(name);
    }
    return out;
  }

  /// Builds the ZIP. [read] loads each file's bytes; [password] null or
  /// empty means no lock.
  Future<Uint8List> build(
    List<BundleItem> items,
    Future<Uint8List> Function(String path) read, {
    String? password,
    DateTime? now,
  }) async {
    if (items.isEmpty) {
      throw const ZipBundleError('Choose at least one file');
    }
    final List<String> names = entryNames(items);
    final List<ZipInput> inputs = <ZipInput>[];
    for (int i = 0; i < items.length; i++) {
      final Uint8List bytes;
      try {
        bytes = await read(items[i].path);
      } on FileSystemException {
        throw ZipBundleError('${items[i].name} could not be read');
      }
      inputs.add(ZipInput(names[i], bytes, modified: now));
    }
    final String? pw = password == null || password.isEmpty ? null : password;
    return _writer.build(inputs, password: pw, now: now);
  }
}
