import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../engines/platform/backup_export.dart';

/// Feature 120 — the app's settings file as a backup part.
class PrefsSettingsSource implements SettingsSource {
  const PrefsSettingsSource();

  @override
  Future<Map<String, Object?>> readAll() async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    return <String, Object?>{for (final String k in p.getKeys()) k: p.get(k)};
  }

  @override
  Future<void> writeAll(Map<String, Object?> values, {required Set<String> remove}) async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    for (final String k in remove) {
      await p.remove(k);
    }
    for (final MapEntry<String, Object?> e in values.entries) {
      final Object? v = e.value;
      if (v is bool) {
        await p.setBool(e.key, v);
      } else if (v is int) {
        await p.setInt(e.key, v);
      } else if (v is double) {
        await p.setDouble(e.key, v);
      } else if (v is String) {
        await p.setString(e.key, v);
      } else if (v is List) {
        await p.setStringList(e.key, v.map((Object? x) => '$x').toList());
      }
    }
  }
}

/// Real files with dart:io: the picked folder or the own-cloud sync folder.
class IoBackupFolder implements BackupFolder {
  const IoBackupFolder();

  @override
  Future<void> write(String path, Uint8List bytes) async {
    final File f = File(path);
    await f.parent.create(recursive: true);
    final File tmp = File('$path.tmp');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(path);
  }

  @override
  Future<List<String>> list(String folder) async {
    final Directory d = Directory(folder);
    if (!d.existsSync()) {
      return <String>[];
    }
    return d.listSync().whereType<File>().map((File f) => f.path).toList();
  }

  @override
  Future<void> remove(String path) async {
    final File f = File(path);
    if (f.existsSync()) {
      await f.delete();
    }
  }
}

/// Schedule in preferences; the automatic-backup password in the phone's
/// secure storage (Keystore / Keychain), never in the backup itself.
class SecureBackupSettingsStore implements BackupSettingsStore {
  const SecureBackupSettingsStore();

  static const String _key = '${BackupExport.ownPrefix}_settings';
  static const String _pwKey = '${BackupExport.ownPrefix}_password';
  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  @override
  Future<BackupSettings> load() async {
    final String? t = (await SharedPreferences.getInstance()).getString(_key);
    if (t == null) {
      return const BackupSettings();
    }
    try {
      return BackupSettings.fromJson(jsonDecode(t));
    } catch (_) {
      return const BackupSettings();
    }
  }

  @override
  Future<void> save(BackupSettings s) async =>
      (await SharedPreferences.getInstance()).setString(_key, jsonEncode(s.toJson()));

  @override
  Future<String?> password() => _storage.read(key: _pwKey);

  @override
  Future<void> setPassword(String? password) async {
    if (password == null) {
      await _storage.delete(key: _pwKey);
    } else {
      await _storage.write(key: _pwKey, value: password);
    }
  }
}
