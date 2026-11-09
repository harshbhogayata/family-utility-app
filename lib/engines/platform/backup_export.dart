import 'dart:convert';
import 'dart:io' show gzip;
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

import '../family/family_identity.dart';
import '../family/family_space.dart';
import '../family/family_store.dart';

/// Feature 120 — Backup and export.
///
/// A full backup is one encrypted file holding every part of the app
/// (family data, settings). It is written to a folder the person picks —
/// usually the same own-cloud folder the family syncs through (079) — and
/// restored on a new phone with the password. Each section can also be
/// exported on its own as CSV or JSON. Nothing is uploaded by the app.
///
/// File format:
/// ```
/// "FUABAK" (6) · version 1 (1) · kdf 1 = PBKDF2-HMAC-SHA256 (1)
/// iterations (uint32 BE) · salt (16) · nonce (12)
/// AES-256-GCM ciphertext of gzip(JSON) · GCM tag (16)
/// ```
/// The header is the associated data, so any change makes restore fail.

class BackupError implements Exception {
  const BackupError(this.message);
  final String message;

  @override
  String toString() => message;
}

class BackupWrongPassword extends BackupError {
  const BackupWrongPassword() : super('Wrong password, or the backup file was changed.');
}

/// One piece of the app that goes into a full backup.
abstract class BackupPart {
  String get id;

  /// Plain JSON-able data for this part.
  Future<Object?> snapshot();

  /// Puts [data] back. Returns how many items changed.
  Future<int> restore(Object? data);

  /// Reverses the last [restore], when it can.
  Future<bool> undoRestore();
}

/// One section the person can export as CSV or JSON.
abstract class ExportSection {
  String get id;
  String get label;
  List<Map<String, Object?>> rows();
}

/// Membership of the family: its key, so a restored phone rejoins the same
/// family (as a new device) and keeps syncing with the others.
class FamilyIdentityBackupPart implements BackupPart {
  FamilyIdentityBackupPart(this.space);

  final FamilySpace space;

  @override
  String get id => 'familyIdentity';

  @override
  Future<Object?> snapshot() async {
    final FamilyIdentity? me = space.identity;
    if (me == null) {
      return null;
    }
    return <String, Object?>{'invite': me.invite().encode(), 'member': me.memberName};
  }

  @override
  Future<int> restore(Object? data) async {
    if (data is! Map || space.identity != null) {
      return 0; // already in a family here: keep it
    }
    final Object? invite = data['invite'];
    if (invite is! String) {
      return 0;
    }
    final FamilyIdentity? joined = await space.join(invite, memberName: '${data['member'] ?? 'Me'}');
    return joined == null ? 0 : 1;
  }

  /// Leaving would wipe the family copy; a rejoin is kept.
  @override
  Future<bool> undoRestore() async => false;
}

/// All family records (tombstones included) — restored by merging, so a
/// restore on a phone that already has newer edits keeps the newer ones.
class FamilyBackupPart implements BackupPart {
  FamilyBackupPart(this.store);

  final FamilyStore store;
  Map<String, FamilyRecord?>? _before;

  @override
  String get id => 'family';

  @override
  Future<Object?> snapshot() async => store.allRecords.map((FamilyRecord r) => r.toJson()).toList();

  @override
  Future<int> restore(Object? data) async {
    if (data is! List) {
      return 0;
    }
    final List<FamilyRecord> records = <FamilyRecord>[
      for (final Object? m in data)
        if (m is Map) FamilyRecord.fromJson(Map<String, Object?>.from(m)),
    ];
    final Map<String, FamilyRecord?> before = <String, FamilyRecord?>{};
    for (final FamilyRecord r in records) {
      before[r.key] = store.get(r.collection, r.id);
    }
    int changed = 0;
    for (final FamilyRecord r in records) {
      if (store.merge(r, via: BackupExport.restoredVia)) {
        changed++;
      }
    }
    _before = before;
    return changed;
  }

  @override
  Future<bool> undoRestore() async {
    final Map<String, FamilyRecord?>? before = _before;
    if (before == null) {
      return false;
    }
    _before = null;
    for (final MapEntry<String, FamilyRecord?> e in before.entries) {
      final int slash = e.key.indexOf('/');
      final String collection = e.key.substring(0, slash);
      final String recordId = e.key.substring(slash + 1);
      final FamilyRecord? now = store.get(collection, recordId);
      final FamilyRecord? old = e.value;
      if (old == null) {
        if (now != null) {
          store.delete(collection, recordId);
        }
      } else if (now == null || jsonEncode(now.fields) != jsonEncode(old.fields)) {
        store.put(collection, recordId, old.fields);
      }
    }
    return true;
  }
}

/// Where the app's settings live (shared preferences on the phone).
abstract class SettingsSource {
  Future<Map<String, Object?>> readAll();
  Future<void> writeAll(Map<String, Object?> values, {required Set<String> remove});
}

class MemorySettingsSource implements SettingsSource {
  MemorySettingsSource([Map<String, Object?>? values]) : values = values ?? <String, Object?>{};
  Map<String, Object?> values;

  @override
  Future<Map<String, Object?>> readAll() async => Map<String, Object?>.of(values);

  @override
  Future<void> writeAll(Map<String, Object?> v, {required Set<String> remove}) async {
    for (final String k in remove) {
      values.remove(k);
    }
    values.addAll(v);
  }
}

/// App settings: language, accessibility, tool order, save choices...
class SettingsBackupPart implements BackupPart {
  SettingsBackupPart(this.source, {this.skip = const <String>{}});

  final SettingsSource source;

  /// Keys that belong to this phone only and never travel.
  final Set<String> skip;
  Map<String, Object?>? _before;

  @override
  String get id => 'settings';

  bool _keep(String k) => !skip.contains(k) && !k.startsWith(BackupExport.ownPrefix);

  @override
  Future<Object?> snapshot() async {
    final Map<String, Object?> all = await source.readAll();
    return <String, Object?>{
      for (final MapEntry<String, Object?> e in all.entries)
        if (_keep(e.key)) e.key: e.value,
    };
  }

  @override
  Future<int> restore(Object? data) async {
    if (data is! Map) {
      return 0;
    }
    final Map<String, Object?> now = await source.readAll();
    final Map<String, Object?> incoming = <String, Object?>{};
    for (final MapEntry<Object?, Object?> e in data.entries) {
      final Object? k = e.key;
      final Object? v = e.value;
      if (k is String && _keep(k) && (v is bool || v is num || v is String || v is List)) {
        incoming[k] = v is List ? v.map((Object? x) => '$x').toList() : v;
      }
    }
    _before = <String, Object?>{for (final String k in incoming.keys) k: now[k]};
    int changed = 0;
    for (final MapEntry<String, Object?> e in incoming.entries) {
      if (jsonEncode(now[e.key]) != jsonEncode(e.value)) {
        changed++;
      }
    }
    await source.writeAll(incoming, remove: const <String>{});
    return changed;
  }

  @override
  Future<bool> undoRestore() async {
    final Map<String, Object?>? before = _before;
    if (before == null) {
      return false;
    }
    _before = null;
    final Map<String, Object?> put = <String, Object?>{};
    final Set<String> remove = <String>{};
    for (final MapEntry<String, Object?> e in before.entries) {
      if (e.value == null) {
        remove.add(e.key);
      } else {
        put[e.key] = e.value;
      }
    }
    await source.writeAll(put, remove: remove);
    return true;
  }
}

/// One family collection as rows.
class FamilyCollectionSection implements ExportSection {
  FamilyCollectionSection(this.store, this.collection, this.label);

  final FamilyStore store;
  final String collection;
  @override
  final String label;

  @override
  String get id => collection;

  @override
  List<Map<String, Object?>> rows() => <Map<String, Object?>>[
        for (final FamilyRecord r in store.list(collection)) <String, Object?>{'id': r.id, ...r.fields},
      ];
}

/// What a full backup held, read back without restoring it.
@immutable
class BackupContents {
  const BackupContents({required this.created, required this.appVersion, required this.parts});
  final DateTime created;
  final int appVersion;
  final Map<String, Object?> parts;
}

/// How often the automatic backup runs.
enum BackupFrequency {
  off('Off', 0),
  daily('Every day', 1),
  weekly('Every week', 7),
  monthly('Every month', 30);

  const BackupFrequency(this.label, this.days);
  final String label;
  final int days;

  static BackupFrequency byName(String? name) =>
      BackupFrequency.values.firstWhere((BackupFrequency f) => f.name == name, orElse: () => BackupFrequency.off);
}

@immutable
class BackupSettings {
  const BackupSettings({this.frequency = BackupFrequency.off, this.folder, this.lastAt, this.keep = 5});

  final BackupFrequency frequency;
  final String? folder;
  final DateTime? lastAt;

  /// How many automatic backups stay in the folder.
  final int keep;

  BackupSettings copyWith({BackupFrequency? frequency, String? folder, bool clearFolder = false, DateTime? lastAt}) =>
      BackupSettings(
        frequency: frequency ?? this.frequency,
        folder: clearFolder ? null : (folder ?? this.folder),
        lastAt: lastAt ?? this.lastAt,
        keep: keep,
      );

  /// True when an automatic backup should run at [now].
  bool isDue(DateTime now) {
    if (frequency == BackupFrequency.off || folder == null) {
      return false;
    }
    final DateTime? last = lastAt;
    return last == null || !now.isBefore(last.add(Duration(days: frequency.days)));
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'f': frequency.name,
        if (folder != null) 'd': folder,
        if (lastAt != null) 'l': lastAt!.millisecondsSinceEpoch,
      };

  static BackupSettings fromJson(Object? j) {
    if (j is! Map) {
      return const BackupSettings();
    }
    final Object? l = j['l'];
    return BackupSettings(
      frequency: BackupFrequency.byName(j['f'] as String?),
      folder: j['d'] as String?,
      lastAt: l is num ? DateTime.fromMillisecondsSinceEpoch(l.toInt()) : null,
    );
  }
}

/// Where backups and exports are written. The real one uses dart:io.
abstract class BackupFolder {
  Future<void> write(String path, Uint8List bytes);
  Future<List<String>> list(String folder);
  Future<void> remove(String path);
}

class MemoryBackupFolder implements BackupFolder {
  final Map<String, Uint8List> files = <String, Uint8List>{};

  @override
  Future<void> write(String path, Uint8List bytes) async => files[path] = bytes;

  @override
  Future<List<String>> list(String folder) async =>
      files.keys.where((String p) => p.startsWith('$folder/') && !p.substring(folder.length + 1).contains('/')).toList();

  @override
  Future<void> remove(String path) async => files.remove(path);
}

/// Keeps the settings, the password for automatic backups and nothing else.
abstract class BackupSettingsStore {
  Future<BackupSettings> load();
  Future<void> save(BackupSettings s);
  Future<String?> password();
  Future<void> setPassword(String? password);
}

class MemoryBackupSettingsStore implements BackupSettingsStore {
  BackupSettings settings = const BackupSettings();
  String? pw;

  @override
  Future<BackupSettings> load() async => settings;
  @override
  Future<void> save(BackupSettings s) async => settings = s;
  @override
  Future<String?> password() async => pw;
  @override
  Future<void> setPassword(String? password) async => pw = password;
}

/// The engine.
class BackupExport extends ChangeNotifier {
  BackupExport({
    required this.parts,
    required this.sections,
    required this.folder,
    required this.settingsStore,
    DateTime Function()? now,
    this.iterations = defaultIterations,
  }) : _now = now ?? DateTime.now;

  final List<BackupPart> parts;
  final List<ExportSection> Function() sections;
  final BackupFolder folder;
  final BackupSettingsStore settingsStore;
  final DateTime Function() _now;
  final int iterations;

  static const String extension = 'fuabak';
  static const String filePrefix = 'family-utility-backup-';
  static const String restoredVia = 'Backup';

  /// Settings keys under this prefix are the backup's own and never travel.
  static const String ownPrefix = 'backup_export';
  static const List<int> magic = <int>[0x46, 0x55, 0x41, 0x42, 0x41, 0x4B]; // FUABAK
  static const int version = 1;
  static const int appFormat = 1;
  static const int defaultIterations = 210000;
  static const int minPassword = 6;
  static const int headerLength = 6 + 1 + 1 + 4 + 16 + 12;
  static const int tagLength = 16;
  static final Random _random = Random.secure();

  BackupSettings _settings = const BackupSettings();
  BackupSettings get settings => _settings;

  /// Last file written (backup or export), for Undo and Share.
  String? lastWritten;
  bool _lastWasRestore = false;
  String? lastError;

  Future<void> load() async {
    try {
      _settings = await settingsStore.load();
    } catch (_) {
      _settings = const BackupSettings();
    }
    notifyListeners();
  }

  Future<void> setSchedule(BackupFrequency f, {String? folderPath, String? password}) async {
    if (f != BackupFrequency.off && password != null) {
      await settingsStore.setPassword(password);
    }
    if (f == BackupFrequency.off) {
      await settingsStore.setPassword(null);
    }
    _settings = _settings.copyWith(frequency: f, folder: folderPath);
    await settingsStore.save(_settings);
    notifyListeners();
  }

  static String? passwordProblem(String password, String confirm) {
    if (password.length < minPassword) {
      return 'Use at least $minPassword characters';
    }
    if (password != confirm) {
      return 'The two passwords differ';
    }
    return null;
  }

  static bool isBackup(Uint8List bytes) {
    if (bytes.length < headerLength + tagLength) {
      return false;
    }
    for (int i = 0; i < magic.length; i++) {
      if (bytes[i] != magic[i]) {
        return false;
      }
    }
    return true;
  }

  static String fileName(DateTime at) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '$filePrefix${at.year}-${two(at.month)}-${two(at.day)}-${two(at.hour)}${two(at.minute)}.$extension';
  }

  static Future<SecretKey> _key(String password, List<int> salt, int iterations) =>
      Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: iterations, bits: 256)
          .deriveKeyFromPassword(password: password, nonce: salt);

  /// The whole app as one encrypted file.
  Future<Uint8List> createBackup(String password) async {
    if (password.length < minPassword) {
      throw const BackupError('Use at least $minPassword characters');
    }
    final Map<String, Object?> body = <String, Object?>{
      'app': 'family_utility_app',
      'format': appFormat,
      'created': _now().toUtc().toIso8601String(),
      'parts': <String, Object?>{for (final BackupPart p in parts) p.id: await p.snapshot()},
    };
    final List<int> plain = gzip.encode(utf8.encode(jsonEncode(body)));
    final List<int> salt = List<int>.generate(16, (int _) => _random.nextInt(256));
    final List<int> nonce = List<int>.generate(12, (int _) => _random.nextInt(256));
    final ByteData head = ByteData(headerLength);
    for (int i = 0; i < magic.length; i++) {
      head.setUint8(i, magic[i]);
    }
    head.setUint8(6, version);
    head.setUint8(7, 1);
    head.setUint32(8, iterations);
    final Uint8List header = head.buffer.asUint8List();
    header.setRange(12, 28, salt);
    header.setRange(28, 40, nonce);
    final SecretBox box = await AesGcm.with256bits().encrypt(
      plain,
      secretKey: await _key(password, salt, iterations),
      nonce: nonce,
      aad: header,
    );
    return (BytesBuilder(copy: false)
          ..add(header)
          ..add(box.cipherText)
          ..add(box.mac.bytes))
        .takeBytes();
  }

  /// Opens a backup file without changing anything.
  static Future<BackupContents> read(Uint8List blob, String password) async {
    if (!isBackup(blob)) {
      throw const BackupError('This is not a backup made by this app.');
    }
    final ByteData head = ByteData.sublistView(blob, 0, headerLength);
    if (head.getUint8(6) != version || head.getUint8(7) != 1) {
      throw const BackupError('This backup needs a newer version of the app.');
    }
    final int iterations = head.getUint32(8);
    if (iterations < 1000 || iterations > 10000000) {
      throw const BackupError('This backup file is damaged.');
    }
    final Uint8List header = Uint8List.sublistView(blob, 0, headerLength);
    final SecretBox box = SecretBox(
      Uint8List.sublistView(blob, headerLength, blob.length - tagLength),
      nonce: Uint8List.sublistView(blob, 28, 40),
      mac: Mac(Uint8List.sublistView(blob, blob.length - tagLength)),
    );
    final List<int> clear;
    try {
      clear = await AesGcm.with256bits().decrypt(
        box,
        secretKey: await _key(password, Uint8List.sublistView(blob, 12, 28), iterations),
        aad: header,
      );
    } on SecretBoxAuthenticationError {
      throw const BackupWrongPassword();
    }
    final Object? json;
    try {
      json = jsonDecode(utf8.decode(gzip.decode(clear)));
    } catch (_) {
      throw const BackupError('This backup file is damaged.');
    }
    if (json is! Map || json['app'] != 'family_utility_app') {
      throw const BackupError('This backup file is damaged.');
    }
    final Object? p = json['parts'];
    return BackupContents(
      created: DateTime.tryParse('${json['created']}')?.toLocal() ?? DateTime.fromMillisecondsSinceEpoch(0),
      appVersion: (json['format'] as num?)?.toInt() ?? 0,
      parts: p is Map ? Map<String, Object?>.from(p) : <String, Object?>{},
    );
  }

  /// Restores a backup into this phone. Returns how many items changed.
  Future<int> restore(Uint8List blob, String password) async {
    final BackupContents c = await read(blob, password);
    int n = 0;
    for (final BackupPart p in parts) {
      if (c.parts.containsKey(p.id)) {
        n += await p.restore(c.parts[p.id]);
      }
    }
    _lastWasRestore = true;
    lastWritten = null;
    notifyListeners();
    return n;
  }

  /// Writes a backup into [folderPath] and prunes old automatic ones.
  Future<String> backupTo(String folderPath, String password, {bool prune = false}) async {
    final Uint8List bytes = await createBackup(password);
    final DateTime at = _now();
    final String path = '$folderPath/${fileName(at)}';
    await folder.write(path, bytes);
    if (prune) {
      final List<String> mine = (await folder.list(folderPath))
          .where((String f) => f.split('/').last.startsWith(filePrefix) && f.endsWith('.$extension'))
          .toList()
        ..sort();
      for (int i = 0; i < mine.length - _settings.keep; i++) {
        await folder.remove(mine[i]);
      }
    }
    _settings = _settings.copyWith(lastAt: at);
    await settingsStore.save(_settings);
    lastWritten = path;
    _lastWasRestore = false;
    notifyListeners();
    return path;
  }

  /// Runs the automatic backup when it is due. Returns the file or null.
  Future<String?> runIfDue() async {
    final String? f = _settings.folder;
    if (!_settings.isDue(_now()) || f == null) {
      return null;
    }
    final String? pw = await settingsStore.password();
    if (pw == null) {
      lastError = 'Set the backup password again';
      notifyListeners();
      return null;
    }
    try {
      final String path = await backupTo(f, pw, prune: true);
      lastError = null;
      return path;
    } catch (_) {
      lastError = 'Backup folder not reachable';
      notifyListeners();
      return null;
    }
  }

  /// Writes one section as CSV or JSON into [folderPath].
  Future<String> exportTo(String folderPath, ExportSection section, {required bool csv}) async {
    final List<Map<String, Object?>> rows = section.rows();
    final String text = csv ? toCsv(rows) : toJson(rows);
    final String path = '$folderPath/${section.label}.${csv ? 'csv' : 'json'}';
    await folder.write(path, Uint8List.fromList(utf8.encode(text)));
    lastWritten = path;
    _lastWasRestore = false;
    notifyListeners();
    return path;
  }

  /// Undo: removes the last written file, or reverses the last restore.
  Future<bool> undo() async {
    if (_lastWasRestore) {
      _lastWasRestore = false;
      bool any = false;
      for (final BackupPart p in parts.reversed) {
        any = await p.undoRestore() || any;
      }
      notifyListeners();
      return any;
    }
    final String? path = lastWritten;
    if (path == null) {
      return false;
    }
    await folder.remove(path);
    lastWritten = null;
    notifyListeners();
    return true;
  }

  static String toJson(List<Map<String, Object?>> rows) => const JsonEncoder.withIndent('  ').convert(rows);

  /// RFC 4180 CSV: header from every key in order of first appearance; lists
  /// joined with "; ", maps as JSON; a leading = + - @ is quoted with a ' so
  /// spreadsheets do not run it as a formula.
  static String toCsv(List<Map<String, Object?>> rows) {
    final List<String> cols = <String>[];
    for (final Map<String, Object?> r in rows) {
      for (final String k in r.keys) {
        if (!cols.contains(k)) {
          cols.add(k);
        }
      }
    }
    final StringBuffer b = StringBuffer()..write(cols.map(_cell).join(','))..write('\r\n');
    for (final Map<String, Object?> r in rows) {
      b
        ..write(cols.map((String c) => _cell(_text(r[c]))).join(','))
        ..write('\r\n');
    }
    return b.toString();
  }

  static String _text(Object? v) {
    if (v == null) {
      return '';
    }
    if (v is List) {
      return v.map((Object? x) => '$x').join('; ');
    }
    if (v is Map) {
      return jsonEncode(v);
    }
    return '$v';
  }

  static String _cell(String s) {
    String t = s;
    if (t.isNotEmpty && '=+-@'.contains(t[0]) && double.tryParse(t) == null) {
      t = "'$t";
    }
    if (t.contains(',') || t.contains('"') || t.contains('\n') || t.contains('\r')) {
      return '"${t.replaceAll('"', '""')}"';
    }
    return t;
  }

  static BackupExport? _instance;
  static BackupExport get instance => _instance ??= BackupExport(
        parts: <BackupPart>[],
        sections: () => <ExportSection>[],
        folder: MemoryBackupFolder(),
        settingsStore: MemoryBackupSettingsStore(),
      );
  static void install(BackupExport b) => _instance = b;
}
