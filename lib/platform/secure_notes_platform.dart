import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import '../engines/security/secure_notes.dart';

/// The notes key in Keystore / Keychain.
class SecureKeyStore implements KeyStore {
  const SecureKeyStore();

  static const String _key = 'secure_notes_key';
  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  @override
  Future<List<int>?> readKey() async {
    final String? text = await _storage.read(key: _key);
    if (text == null || text.isEmpty) {
      return null;
    }
    return base64Url.decode(text);
  }

  @override
  Future<void> writeKey(List<int> key) async {
    await _storage.write(key: _key, value: base64Url.encode(key));
  }
}

/// The encrypted blob in the app's private support folder (not backed up to
/// the gallery, not visible to other apps).
class FileNoteBlobStore implements NoteBlobStore {
  const FileNoteBlobStore();

  Future<File> _file() async {
    final Directory dir = await getApplicationSupportDirectory();
    return File('${dir.path}${Platform.pathSeparator}secure_notes.enc');
  }

  @override
  Future<String?> read() async {
    final File f = await _file();
    if (!await f.exists()) {
      return null;
    }
    return f.readAsString();
  }

  @override
  Future<void> write(String blob) async {
    final File f = await _file();
    await f.writeAsString(blob, flush: true);
  }
}

/// The system clipboard.
class SystemClipboard implements ClipboardSink {
  const SystemClipboard();

  @override
  Future<void> set(String text) => Clipboard.setData(ClipboardData(text: text));

  @override
  Future<String?> get() async => (await Clipboard.getData(Clipboard.kTextPlain))?.text;

  @override
  Future<void> clear() => Clipboard.setData(const ClipboardData(text: ''));
}
