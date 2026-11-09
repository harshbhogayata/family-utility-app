import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'pdf_signer.dart';

/// Feature 010 — saved signatures and initials, kept on the phone only.
@immutable
class SavedStamp {
  const SavedStamp({required this.id, required this.kind, required this.png});

  final String id;
  final StampKind kind;
  final Uint8List png;
}

abstract class SignatureLibrary {
  Future<List<SavedStamp>> list();

  Future<SavedStamp> add(StampKind kind, Uint8List png);

  Future<void> remove(String id);
}

class MemorySignatureLibrary implements SignatureLibrary {
  final List<SavedStamp> items = <SavedStamp>[];
  int _n = 0;

  @override
  Future<List<SavedStamp>> list() async => List<SavedStamp>.of(items);

  @override
  Future<SavedStamp> add(StampKind kind, Uint8List png) async {
    final SavedStamp s = SavedStamp(id: '${kind.name}-${_n++}', kind: kind, png: png);
    items.insert(0, s);
    return s;
  }

  @override
  Future<void> remove(String id) async => items.removeWhere((SavedStamp s) => s.id == id);
}

/// PNG files in a private app folder: `signature-<time>.png`.
class DirectorySignatureLibrary implements SignatureLibrary {
  DirectorySignatureLibrary(this.folder);

  final Future<Directory> Function() folder;

  @override
  Future<List<SavedStamp>> list() async {
    final Directory dir = await folder();
    if (!dir.existsSync()) {
      return <SavedStamp>[];
    }
    final List<File> files = dir.listSync().whereType<File>().where((File f) => f.path.endsWith('.png')).toList()
      ..sort((File a, File b) => b.path.compareTo(a.path));
    final List<SavedStamp> out = <SavedStamp>[];
    for (final File f in files) {
      final String id = f.uri.pathSegments.last.replaceAll('.png', '');
      final StampKind kind = id.startsWith('initials') ? StampKind.initials : StampKind.signature;
      out.add(SavedStamp(id: id, kind: kind, png: await f.readAsBytes()));
    }
    return out;
  }

  @override
  Future<SavedStamp> add(StampKind kind, Uint8List png) async {
    final Directory dir = await folder();
    await dir.create(recursive: true);
    final String id = '${kind.name}-${DateTime.now().microsecondsSinceEpoch}';
    await File('${dir.path}/$id.png').writeAsBytes(png, flush: true);
    return SavedStamp(id: id, kind: kind, png: png);
  }

  @override
  Future<void> remove(String id) async {
    final File f = File('${(await folder()).path}/$id.png');
    if (f.existsSync()) {
      await f.delete();
    }
  }
}
