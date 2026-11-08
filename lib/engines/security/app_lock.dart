import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

/// Feature 055 — App lock.
///
/// PIN with optional biometrics on the whole app and on chosen tools. The PIN
/// is never stored: only a salted, stretched hash is kept, in the platform's
/// secure storage behind [LockStore]. Biometrics go through [Biometrics] so
/// the engine stays pure Dart and tests use fakes.

/// How long the app may stay in the background before it locks again.
enum LockTimeout {
  immediately(Duration.zero, 'Immediately'),
  oneMinute(Duration(minutes: 1), 'After 1 minute'),
  fiveMinutes(Duration(minutes: 5), 'After 5 minutes'),
  fifteenMinutes(Duration(minutes: 15), 'After 15 minutes'),
  oneHour(Duration(hours: 1), 'After 1 hour');

  const LockTimeout(this.duration, this.label);

  final Duration duration;
  final String label;

  static LockTimeout fromName(String? name) {
    for (final LockTimeout t in values) {
      if (t.name == name) {
        return t;
      }
    }
    return fiveMinutes;
  }
}

/// Ids of the places that can carry their own lock besides the whole app.
abstract final class LockableIds {
  static const String records = 'records';
  static const String vault = 'private-vault';
  static const String secureNotes = 'secure-notes';
  static const String receipts = 'receipt-vault';

  static const Map<String, String> labels = <String, String>{
    records: 'Records tab (money, health, home, documents)',
    vault: 'Private vault',
    secureNotes: 'Secure notes',
    receipts: 'Receipt vault',
  };
}

/// Everything the lock remembers. Immutable; use [copyWith].
@immutable
class LockSettings {
  const LockSettings({
    this.enabled = false,
    this.pinHash,
    this.salt,
    this.pinLength = 0,
    this.biometrics = false,
    this.timeout = LockTimeout.fiveMinutes,
    this.lockedIds = const <String>{},
  });

  final bool enabled;
  final String? pinHash;
  final String? salt;
  final int pinLength;
  final bool biometrics;
  final LockTimeout timeout;

  /// Tools or tabs that ask for the PIN even when the app itself is open.
  final Set<String> lockedIds;

  bool get hasPin => pinHash != null && salt != null && pinLength >= PinHasher.minLength;

  LockSettings copyWith({
    bool? enabled,
    String? pinHash,
    String? salt,
    int? pinLength,
    bool? biometrics,
    LockTimeout? timeout,
    Set<String>? lockedIds,
  }) {
    return LockSettings(
      enabled: enabled ?? this.enabled,
      pinHash: pinHash ?? this.pinHash,
      salt: salt ?? this.salt,
      pinLength: pinLength ?? this.pinLength,
      biometrics: biometrics ?? this.biometrics,
      timeout: timeout ?? this.timeout,
      lockedIds: lockedIds ?? this.lockedIds,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'enabled': enabled,
        'pinHash': pinHash,
        'salt': salt,
        'pinLength': pinLength,
        'biometrics': biometrics,
        'timeout': timeout.name,
        'lockedIds': lockedIds.toList()..sort(),
      };

  static LockSettings fromJson(Map<String, Object?> json) {
    final Object? ids = json['lockedIds'];
    return LockSettings(
      enabled: json['enabled'] == true,
      pinHash: json['pinHash'] as String?,
      salt: json['salt'] as String?,
      pinLength: (json['pinLength'] as num?)?.toInt() ?? 0,
      biometrics: json['biometrics'] == true,
      timeout: LockTimeout.fromName(json['timeout'] as String?),
      lockedIds: ids is List<Object?> ? ids.whereType<String>().toSet() : const <String>{},
    );
  }

  String encode() => jsonEncode(toJson());

  static LockSettings decode(String text) {
    final Object? parsed = jsonDecode(text);
    if (parsed is Map<String, Object?>) {
      return LockSettings.fromJson(parsed);
    }
    return const LockSettings();
  }
}

/// Salted, stretched SHA-256. Enough to keep a 4–6 digit PIN from being read
/// straight out of storage; the real protection is secure storage plus the
/// attempt limit in [AppLock].
abstract final class PinHasher {
  static const int minLength = 4;
  static const int maxLength = 6;
  static const int rounds = 20000;

  static final Random _random = Random.secure();

  static String newSalt() {
    final List<int> bytes = List<int>.generate(16, (int _) => _random.nextInt(256));
    return base64Url.encode(bytes);
  }

  static bool isValidPin(String pin) =>
      pin.length >= minLength && pin.length <= maxLength && RegExp(r'^\d+$').hasMatch(pin);

  static String hash(String pin, String salt) {
    List<int> digest = utf8.encode('$salt:$pin');
    final List<int> saltBytes = utf8.encode(salt);
    for (int i = 0; i < rounds; i++) {
      digest = sha256.convert(<int>[...saltBytes, ...digest]).bytes;
    }
    return base64Url.encode(digest);
  }

  static bool verify(String pin, String salt, String expectedHash) {
    final String got = hash(pin, salt);
    if (got.length != expectedHash.length) {
      return false;
    }
    int diff = 0;
    for (int i = 0; i < got.length; i++) {
      diff |= got.codeUnitAt(i) ^ expectedHash.codeUnitAt(i);
    }
    return diff == 0;
  }
}

/// Where settings live. The platform implementation uses secure storage.
abstract class LockStore {
  Future<LockSettings?> read();

  Future<void> write(LockSettings settings);
}

class MemoryLockStore implements LockStore {
  MemoryLockStore([this._value]);

  LockSettings? _value;

  @override
  Future<LockSettings?> read() async => _value;

  @override
  Future<void> write(LockSettings settings) async => _value = settings;
}

/// Fingerprint or face through the platform. Null when none is set up.
abstract class Biometrics {
  Future<bool> isAvailable();

  Future<bool> authenticate(String reason);
}

class NoBiometrics implements Biometrics {
  const NoBiometrics();

  @override
  Future<bool> isAvailable() async => false;

  @override
  Future<bool> authenticate(String reason) async => false;
}

/// Why a PIN attempt did not unlock.
enum UnlockFailure { wrongPin, lockedOut, notSetUp }

/// The lock itself. Listen for [isLocked] changes.
class AppLock extends ChangeNotifier {
  AppLock({
    required LockStore store,
    Biometrics biometrics = const NoBiometrics(),
    DateTime Function()? now,
  })  : _store = store,
        _biometrics = biometrics,
        _now = now ?? DateTime.now;

  final LockStore _store;
  final Biometrics _biometrics;
  final DateTime Function() _now;

  static const int maxAttempts = 5;
  static const Duration lockoutFor = Duration(seconds: 30);

  LockSettings _settings = const LockSettings();
  bool _locked = false;
  DateTime? _backgroundedAt;
  int _failedAttempts = 0;
  DateTime? _lockedOutUntil;

  /// Tools unlocked in this session, so a per-tool PIN is asked once.
  final Set<String> _openedIds = <String>{};

  LockSettings get settings => _settings;

  bool get isLocked => _locked;

  bool get isEnabled => _settings.enabled && _settings.hasPin;

  int get failedAttempts => _failedAttempts;

  /// Seconds left before another attempt is allowed, 0 when not locked out.
  int get lockoutSecondsLeft {
    final DateTime? until = _lockedOutUntil;
    if (until == null) {
      return 0;
    }
    final int left = until.difference(_now()).inSeconds;
    return left > 0 ? left : 0;
  }

  Future<void> load() async {
    try {
      final LockSettings? saved = await _store.read();
      if (saved != null) {
        _settings = saved;
      }
    } catch (_) {
      // Keep defaults (no lock) rather than lock the person out of their own data.
    }
    _locked = isEnabled;
    notifyListeners();
  }

  Future<void> _save() async {
    try {
      await _store.write(_settings);
    } catch (_) {
      // In-memory settings still apply for this launch.
    }
    notifyListeners();
  }

  // ---- set up -------------------------------------------------------------

  /// Sets or changes the PIN and turns the lock on. Throws on a bad PIN.
  Future<void> setPin(String pin) async {
    if (!PinHasher.isValidPin(pin)) {
      throw ArgumentError('PIN must be ${PinHasher.minLength} to ${PinHasher.maxLength} digits');
    }
    final String salt = PinHasher.newSalt();
    _settings = _settings.copyWith(
      enabled: true,
      salt: salt,
      pinHash: PinHasher.hash(pin, salt),
      pinLength: pin.length,
    );
    _failedAttempts = 0;
    _lockedOutUntil = null;
    await _save();
  }

  /// Turns the lock off and forgets the PIN hash.
  Future<void> disable() async {
    _settings = const LockSettings().copyWith(
      timeout: _settings.timeout,
      lockedIds: _settings.lockedIds,
    );
    _locked = false;
    _openedIds.clear();
    await _save();
  }

  Future<void> setBiometrics(bool on) async {
    _settings = _settings.copyWith(biometrics: on);
    await _save();
  }

  Future<void> setTimeout(LockTimeout timeout) async {
    _settings = _settings.copyWith(timeout: timeout);
    await _save();
  }

  Future<void> setToolLocked(String id, bool locked) async {
    final Set<String> ids = Set<String>.of(_settings.lockedIds);
    if (locked) {
      ids.add(id);
    } else {
      ids.remove(id);
      _openedIds.remove(id);
    }
    _settings = _settings.copyWith(lockedIds: ids);
    await _save();
  }

  // ---- lifecycle ------------------------------------------------------------

  /// Call when the app goes to the background.
  void onBackground() {
    _backgroundedAt ??= _now();
  }

  /// Call when the app comes back. Locks when the timeout has passed.
  void onForeground() {
    final DateTime? since = _backgroundedAt;
    _backgroundedAt = null;
    if (!isEnabled || _locked || since == null) {
      return;
    }
    if (_now().difference(since) >= _settings.timeout.duration) {
      lock();
    }
  }

  void lock() {
    if (!isEnabled) {
      return;
    }
    _locked = true;
    _openedIds.clear();
    notifyListeners();
  }

  // ---- unlock -------------------------------------------------------------

  Future<bool> biometricsAvailable() async {
    try {
      return await _biometrics.isAvailable();
    } catch (_) {
      return false;
    }
  }

  bool get biometricsOffered => _settings.biometrics;

  /// Null on success, otherwise why not.
  Future<UnlockFailure?> unlockWithPin(String pin) async {
    if (!isEnabled) {
      return UnlockFailure.notSetUp;
    }
    if (lockoutSecondsLeft > 0) {
      return UnlockFailure.lockedOut;
    }
    _lockedOutUntil = null;
    final bool ok = PinHasher.verify(pin, _settings.salt!, _settings.pinHash!);
    if (!ok) {
      _failedAttempts++;
      if (_failedAttempts >= maxAttempts) {
        _lockedOutUntil = _now().add(lockoutFor);
        _failedAttempts = 0;
        notifyListeners();
        return UnlockFailure.lockedOut;
      }
      notifyListeners();
      return UnlockFailure.wrongPin;
    }
    _failedAttempts = 0;
    _locked = false;
    notifyListeners();
    return null;
  }

  /// True when the platform confirmed the person. Never bypasses a lockout.
  Future<bool> unlockWithBiometrics({String reason = 'Unlock Family Utility'}) async {
    if (!isEnabled || !_settings.biometrics || lockoutSecondsLeft > 0) {
      return false;
    }
    bool ok;
    try {
      ok = await _biometrics.authenticate(reason);
    } catch (_) {
      ok = false;
    }
    if (ok) {
      _failedAttempts = 0;
      _locked = false;
      notifyListeners();
    }
    return ok;
  }

  // ---- per-tool locks -------------------------------------------------------

  /// Whether opening [id] should ask for the PIN first.
  bool needsUnlockFor(String id) =>
      isEnabled && _settings.lockedIds.contains(id) && !_openedIds.contains(id);

  /// Remember that [id] was unlocked until the app locks again.
  void markOpened(String id) {
    _openedIds.add(id);
    notifyListeners();
  }

  /// The one shared lock; bootstrap installs the secure store and biometrics.
  static AppLock instance = AppLock(store: MemoryLockStore());

  static void install(AppLock lock) {
    instance = lock;
  }
}
