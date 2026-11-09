import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import '../engines/security/private_vault.dart';
import '../engines/security/secure_notes.dart' show KeyStore;

const FlutterSecureStorage _storage = FlutterSecureStorage(
  aOptions: AndroidOptions(encryptedSharedPreferences: true),
);

/// One vault key in Keystore / Keychain. The real and decoy vaults use
/// different names, so neither key opens the other's files.
class SecureVaultKeyStore implements KeyStore {
  const SecureVaultKeyStore(this.name);

  final String name;

  @override
  Future<List<int>?> readKey() async {
    final String? text = await _storage.read(key: name);
    if (text == null || text.isEmpty) {
      return null;
    }
    return base64Url.decode(text);
  }

  @override
  Future<void> writeKey(List<int> key) => _storage.write(key: name, value: base64Url.encode(key));
}

class SecureVaultSettingsStore implements VaultSettingsStore {
  const SecureVaultSettingsStore();

  static const String _key = 'private_vault_settings';

  @override
  Future<String?> read() => _storage.read(key: _key);

  @override
  Future<void> write(String value) => _storage.write(key: _key, value: value);
}

/// Files under the app's private support folder:
///
/// * `vault/` — excluded from Android backup by `res/xml/backup_rules.xml`
///   and `data_extraction_rules.xml`, and flagged excluded on iOS.
/// * `vault_backup/` — used instead when the person turns backups on.
///
/// Both carry `.nomedia`; neither is visible to the gallery or other apps.
class FileVaultBackend implements VaultBackend {
  FileVaultBackend({this.includedInBackups = false});

  bool includedInBackups;

  static const MethodChannel _backupChannel = MethodChannel('family_utility/backup');

  static const String excludedFolder = 'vault';
  static const String backedUpFolder = 'vault_backup';

  Future<Directory> _folder(String name) async {
    final Directory base = await getApplicationSupportDirectory();
    return Directory('${base.path}${Platform.pathSeparator}$name');
  }

  Future<Directory> _root() async {
    final Directory dir = await _folder(includedInBackups ? backedUpFolder : excludedFolder);
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
      await File('${dir.path}${Platform.pathSeparator}.nomedia').writeAsBytes(const <int>[]);
      await _flagBackup(dir, excluded: !includedInBackups);
    }
    return dir;
  }

  Future<File> _file(VaultSpace space, String id) async {
    final Directory root = await _root();
    final Directory dir = Directory('${root.path}${Platform.pathSeparator}${space.name}');
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    return File('${dir.path}${Platform.pathSeparator}$id.bin');
  }

  Future<void> _flagBackup(Directory dir, {required bool excluded}) async {
    if (!Platform.isIOS) {
      return;
    }
    try {
      await _backupChannel.invokeMethod<bool>(
        'setExcludedFromBackup',
        <String, Object?>{'path': dir.path, 'excluded': excluded},
      );
    } on MissingPluginException {
      // Older builds without the channel: files stay encrypted regardless.
    } on PlatformException {
      // Same.
    }
  }

  Future<Uint8List?> _read(File f) async {
    if (!f.existsSync()) {
      return null;
    }
    return f.readAsBytes();
  }

  @override
  Future<Uint8List?> readIndex(VaultSpace space) async => _read(await _file(space, 'index'));

  @override
  Future<void> writeIndex(VaultSpace space, Uint8List data) async {
    await (await _file(space, 'index')).writeAsBytes(data, flush: true);
  }

  @override
  Future<Uint8List?> readObject(VaultSpace space, String id) async => _read(await _file(space, id));

  @override
  Future<void> writeObject(VaultSpace space, String id, Uint8List data) async {
    await (await _file(space, id)).writeAsBytes(data, flush: true);
  }

  @override
  Future<void> deleteObject(VaultSpace space, String id) async {
    final File f = await _file(space, id);
    if (f.existsSync()) {
      await f.delete();
    }
  }

  @override
  void useBackupChoice(bool included) => includedInBackups = included;

  @override
  Future<void> setIncludedInBackups(bool included) async {
    if (included == includedInBackups) {
      return;
    }
    final Directory from = await _root();
    final Directory to = await _folder(included ? backedUpFolder : excludedFolder);
    if (to.existsSync()) {
      await to.delete(recursive: true);
    }
    await from.rename(to.path);
    includedInBackups = included;
    await _flagBackup(to, excluded: !included);
  }
}
