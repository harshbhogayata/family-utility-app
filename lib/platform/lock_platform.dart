import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

import '../engines/security/app_lock.dart';

/// Lock settings (only a salted hash of the PIN) in Keystore / Keychain.
class SecureLockStore implements LockStore {
  const SecureLockStore();

  static const String _key = 'app_lock_settings';
  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  @override
  Future<LockSettings?> read() async {
    final String? text = await _storage.read(key: _key);
    if (text == null || text.isEmpty) {
      return null;
    }
    return LockSettings.decode(text);
  }

  @override
  Future<void> write(LockSettings settings) async {
    await _storage.write(key: _key, value: settings.encode());
  }
}

/// Fingerprint or face through local_auth, with the device PIN as fallback.
class PlatformBiometrics implements Biometrics {
  PlatformBiometrics();

  final LocalAuthentication _auth = LocalAuthentication();

  @override
  Future<bool> isAvailable() async {
    try {
      return await _auth.isDeviceSupported() && await _auth.canCheckBiometrics;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<bool> authenticate(String reason) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(stickyAuth: true),
      );
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
