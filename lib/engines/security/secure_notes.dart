import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

/// Feature 057 — Secure notes.
///
/// Small notes (IDs, Wi-Fi keys, card last-four) kept as one AES-256-GCM
/// blob on disk. The key lives in the platform keystore behind [KeyStore];
/// the blob behind [NoteBlobStore]; the clipboard behind [ClipboardSink] so
/// copies can be cleared after a short while. Pure Dart otherwise.

/// One labelled value inside a note. Secret fields are masked in lists.
@immutable
class NoteField {
  const NoteField({required this.label, required this.value, this.secret = true});

  final String label;
  final String value;
  final bool secret;

  NoteField copyWith({String? label, String? value, bool? secret}) => NoteField(
        label: label ?? this.label,
        value: value ?? this.value,
        secret: secret ?? this.secret,
      );

  Map<String, Object?> toJson() => <String, Object?>{'label': label, 'value': value, 'secret': secret};

  static NoteField fromJson(Map<String, Object?> j) => NoteField(
        label: (j['label'] as String?) ?? '',
        value: (j['value'] as String?) ?? '',
        secret: j['secret'] != false,
      );

  @override
  bool operator ==(Object other) =>
      other is NoteField && other.label == label && other.value == value && other.secret == secret;

  @override
  int get hashCode => Object.hash(label, value, secret);
}

@immutable
class SecureNote {
  const SecureNote({
    required this.id,
    required this.title,
    this.fields = const <NoteField>[],
    this.note = '',
    required this.updatedAt,
  });

  final String id;
  final String title;
  final List<NoteField> fields;

  /// Free text under the fields.
  final String note;
  final DateTime updatedAt;

  SecureNote copyWith({String? title, List<NoteField>? fields, String? note, DateTime? updatedAt}) =>
      SecureNote(
        id: id,
        title: title ?? this.title,
        fields: fields ?? this.fields,
        note: note ?? this.note,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'title': title,
        'fields': fields.map((NoteField f) => f.toJson()).toList(),
        'note': note,
        'updatedAt': updatedAt.toUtc().toIso8601String(),
      };

  static SecureNote fromJson(Map<String, Object?> j) {
    final Object? rawFields = j['fields'];
    return SecureNote(
      id: (j['id'] as String?) ?? '',
      title: (j['title'] as String?) ?? '',
      fields: rawFields is List<Object?>
          ? rawFields.whereType<Map<String, Object?>>().map(NoteField.fromJson).toList()
          : const <NoteField>[],
      note: (j['note'] as String?) ?? '',
      updatedAt: DateTime.tryParse((j['updatedAt'] as String?) ?? '')?.toLocal() ?? DateTime(2000),
    );
  }

  /// Plain text for Share; the person chose to send it.
  String toPlainText() {
    final StringBuffer b = StringBuffer(title);
    for (final NoteField f in fields) {
      b.write('\n${f.label}: ${f.value}');
    }
    if (note.trim().isNotEmpty) {
      b.write('\n\n$note');
    }
    return b.toString();
  }
}

/// Field label suggestions for the three things the spec names.
abstract final class NoteTemplates {
  static const Map<String, List<String>> fields = <String, List<String>>{
    'ID card': <String>['Number', 'Name on card', 'Expiry'],
    'Wi-Fi': <String>['Network', 'Password'],
    'Card': <String>['Last four', 'Bank', 'Expiry'],
    'Login': <String>['Username', 'Password'],
  };
}

// ---- interfaces to the platform ------------------------------------------

/// Holds the 32-byte key in Keystore / Keychain.
abstract class KeyStore {
  Future<List<int>?> readKey();

  Future<void> writeKey(List<int> key);
}

class MemoryKeyStore implements KeyStore {
  List<int>? _key;

  @override
  Future<List<int>?> readKey() async => _key;

  @override
  Future<void> writeKey(List<int> key) async => _key = List<int>.of(key);
}

/// Holds the encrypted blob (a short JSON string) on disk.
abstract class NoteBlobStore {
  Future<String?> read();

  Future<void> write(String blob);
}

class MemoryNoteBlobStore implements NoteBlobStore {
  String? blob;

  @override
  Future<String?> read() async => blob;

  @override
  Future<void> write(String value) async => blob = value;
}

/// The system clipboard.
abstract class ClipboardSink {
  Future<void> set(String text);

  Future<String?> get();

  Future<void> clear();
}

class MemoryClipboard implements ClipboardSink {
  String? text;

  @override
  Future<void> set(String value) async => text = value;

  @override
  Future<String?> get() async => text;

  @override
  Future<void> clear() async => text = null;
}

// ---- crypto ---------------------------------------------------------------

/// AES-256-GCM over the notes JSON. Each write uses a fresh nonce.
class NoteCipher {
  NoteCipher(this._keyStore);

  final KeyStore _keyStore;
  final AesGcm _aes = AesGcm.with256bits();
  SecretKey? _key;

  static final Random _random = Random.secure();

  Future<SecretKey> _secretKey() async {
    final SecretKey? cached = _key;
    if (cached != null) {
      return cached;
    }
    List<int>? bytes = await _keyStore.readKey();
    if (bytes == null || bytes.length != 32) {
      bytes = List<int>.generate(32, (int _) => _random.nextInt(256));
      await _keyStore.writeKey(bytes);
    }
    final SecretKey key = SecretKey(bytes);
    _key = key;
    return key;
  }

  Future<String> encrypt(String plain) async {
    final SecretBox box = await _aes.encrypt(utf8.encode(plain), secretKey: await _secretKey());
    return jsonEncode(<String, Object?>{
      'v': 1,
      'n': base64Url.encode(box.nonce),
      'c': base64Url.encode(box.cipherText),
      'm': base64Url.encode(box.mac.bytes),
    });
  }

  /// Throws [SecretBoxAuthenticationError] or [FormatException] on a blob
  /// that was tampered with or written with another key.
  Future<String> decrypt(String blob) async {
    final Object? parsed = jsonDecode(blob);
    if (parsed is! Map<String, Object?>) {
      throw const FormatException('not a secure notes blob');
    }
    final SecretBox box = SecretBox(
      base64Url.decode(parsed['c'] as String),
      nonce: base64Url.decode(parsed['n'] as String),
      mac: Mac(base64Url.decode(parsed['m'] as String)),
    );
    final List<int> clear = await _aes.decrypt(box, secretKey: await _secretKey());
    return utf8.decode(clear);
  }
}

// ---- the notes ------------------------------------------------------------

class SecureNotes extends ChangeNotifier {
  SecureNotes({
    required KeyStore keyStore,
    required NoteBlobStore blobStore,
    required ClipboardSink clipboard,
    this.clearClipboardAfter = const Duration(seconds: 30),
    DateTime Function()? now,
  })  : _cipher = NoteCipher(keyStore),
        _blobs = blobStore,
        _clipboard = clipboard,
        _now = now ?? DateTime.now;

  final NoteCipher _cipher;
  final NoteBlobStore _blobs;
  final ClipboardSink _clipboard;
  final DateTime Function() _now;
  final Duration clearClipboardAfter;

  List<SecureNote> _notes = <SecureNote>[];
  bool _loaded = false;
  String? _loadError;
  Timer? _clearTimer;
  String? _lastCopied;

  List<SecureNote> get notes => List<SecureNote>.unmodifiable(_notes);

  bool get isLoaded => _loaded;

  /// Set when the blob on disk could not be read (wrong key or damaged).
  String? get loadError => _loadError;

  SecureNote? byId(String id) {
    for (final SecureNote n in _notes) {
      if (n.id == id) {
        return n;
      }
    }
    return null;
  }

  Future<void> load() async {
    try {
      final String? blob = await _blobs.read();
      if (blob != null && blob.isNotEmpty) {
        final Object? parsed = jsonDecode(await _cipher.decrypt(blob));
        if (parsed is List<Object?>) {
          _notes = parsed.whereType<Map<String, Object?>>().map(SecureNote.fromJson).toList();
        }
      }
      _loadError = null;
    } catch (e) {
      _loadError = 'Could not read the notes on this phone: $e';
      _notes = <SecureNote>[];
    }
    _sort();
    _loaded = true;
    notifyListeners();
  }

  Future<void> _persist() async {
    final String plain = jsonEncode(_notes.map((SecureNote n) => n.toJson()).toList());
    await _blobs.write(await _cipher.encrypt(plain));
    notifyListeners();
  }

  void _sort() => _notes.sort((SecureNote a, SecureNote b) => b.updatedAt.compareTo(a.updatedAt));

  static String newId() {
    final Random r = Random.secure();
    return List<int>.generate(8, (int _) => r.nextInt(256)).map((int b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Adds or replaces a note and writes the blob. Returns the stored note.
  Future<SecureNote> save(SecureNote note) async {
    final SecureNote stored = note.copyWith(updatedAt: _now());
    _notes = <SecureNote>[stored, ..._notes.where((SecureNote n) => n.id != note.id)];
    _sort();
    await _persist();
    return stored;
  }

  Future<void> delete(String id) async {
    _notes = _notes.where((SecureNote n) => n.id != id).toList();
    await _persist();
  }

  /// Puts a field on the clipboard and clears it again after
  /// [clearClipboardAfter], unless something else was copied since.
  Future<void> copy(String value) async {
    await _clipboard.set(value);
    _lastCopied = value;
    _clearTimer?.cancel();
    _clearTimer = Timer(clearClipboardAfter, () {
      unawaited(_clearIfStillOurs());
    });
  }

  Future<void> _clearIfStillOurs() async {
    final String? current = await _clipboard.get();
    if (current != null && current == _lastCopied) {
      await _clipboard.clear();
    }
    _lastCopied = null;
  }

  /// Clears a copied value right away (e.g. when the screen closes).
  Future<void> clearClipboardNow() async {
    _clearTimer?.cancel();
    _clearTimer = null;
    await _clearIfStillOurs();
  }

  @override
  void dispose() {
    _clearTimer?.cancel();
    super.dispose();
  }

  static SecureNotes instance = SecureNotes(
    keyStore: MemoryKeyStore(),
    blobStore: MemoryNoteBlobStore(),
    clipboard: MemoryClipboard(),
  );

  static void install(SecureNotes notes) {
    instance = notes;
  }
}
