import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

/// Feature 063 — Cloud import and save.
///
/// Google Drive, Dropbox, OneDrive and iCloud appear inside the system
/// document picker once their apps are installed, so the app uses that
/// picker for both directions and never talks to a cloud itself: no
/// accounts, no keys. Bytes move only between the phone and the provider
/// app the person chose.

@immutable
class PickedDocument {
  const PickedDocument(this.name, this.bytes);
  final String name;
  final Uint8List bytes;
}

/// The system picker. Behind an interface so tests need no phone.
abstract class DocumentPicker {
  /// Opens the system picker (cloud providers included). Empty on cancel.
  Future<List<PickedDocument>> open({bool multiple = true});

  /// Opens the system "save to" sheet. Returns where it went, null on cancel.
  Future<String?> saveAs(String name, Uint8List bytes);
}

/// Where imported copies are kept in the app's Files.
abstract class ImportSink {
  Future<String> write(String name, Uint8List bytes);
  Future<void> remove(String path);
}

enum SaveDefault { ask, cloud, files }

abstract class CloudPrefsStore {
  Future<String?> read();
  Future<void> write(String value);
}

class MemoryCloudPrefsStore implements CloudPrefsStore {
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String v) async => value = v;
}

class CloudBridge {
  CloudBridge({required this.picker, required this.sink, required this.store});

  final DocumentPicker picker;
  final ImportSink sink;
  final CloudPrefsStore store;

  SaveDefault _default = SaveDefault.ask;
  String? _lastSavedTo;

  SaveDefault get saveDefault => _default;

  /// The place the system sheet last saved to, shown as a hint.
  String? get lastSavedTo => _lastSavedTo;

  Future<void> load() async {
    final String? raw = await store.read();
    if (raw == null) {
      return;
    }
    try {
      final Object? j = jsonDecode(raw);
      if (j is Map) {
        _default = SaveDefault.values.firstWhere((SaveDefault d) => d.name == j['default'], orElse: () => SaveDefault.ask);
        final Object? last = j['last'];
        _lastSavedTo = last is String ? last : null;
      }
    } on FormatException {
      // A damaged preference: start over.
    }
  }

  Future<void> _persist() =>
      store.write(jsonEncode(<String, Object?>{'default': _default.name, 'last': _lastSavedTo}));

  Future<void> setDefault(SaveDefault d) async {
    _default = d;
    await _persist();
  }

  /// Copies picked documents into the app's Files. Returns the new paths.
  Future<List<String>> import() async {
    final List<PickedDocument> docs = await picker.open();
    final List<String> out = <String>[];
    for (final PickedDocument d in docs) {
      out.add(await sink.write(d.name, d.bytes));
    }
    return out;
  }

  /// Hands a file to the system save sheet (Drive, Dropbox, OneDrive,
  /// iCloud or the phone). Remembers where it went.
  Future<String?> saveToCloud(String name, Uint8List bytes) async {
    final String? where = await picker.saveAs(name, bytes);
    if (where != null) {
      _lastSavedTo = where;
      await _persist();
    }
    return where;
  }
}
