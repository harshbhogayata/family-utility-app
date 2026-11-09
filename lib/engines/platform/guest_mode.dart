import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../security/app_lock.dart';

/// Where guest mode keeps its state between launches.
abstract class GuestModeStore {
  Future<String?> read();

  Future<void> write(String json);
}

class MemoryGuestModeStore implements GuestModeStore {
  MemoryGuestModeStore([this.value]);

  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String json) async => value = json;
}

/// Outcome of trying to leave guest mode.
enum GuestExit { exited, wrongPin, lockedOut, notActive }

/// Feature 119 — Guest mode.
///
/// The owner picks which tools a guest (a child, a relative) may use, sets a
/// PIN, and hands the phone over. While guest mode is on, home shows only
/// those tools and the other tabs are gone; leaving needs the owner's PIN.
/// It survives a restart. Only a salted hash of the PIN is kept, on the phone.
class GuestMode extends ChangeNotifier {
  GuestMode(this._store, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  final GuestModeStore _store;
  final DateTime Function() _now;

  static const int maxAttempts = 5;
  static const Duration lockoutFor = Duration(seconds: 30);

  List<String> _allowed = <String>[];
  bool _active = false;
  String? _pinHash;
  String? _pinSalt;
  int _failures = 0;
  DateTime? _lockedUntil;

  /// Tools a guest may open, in the order the owner ticked them.
  List<String> get allowed => List<String>.unmodifiable(_allowed);

  bool get active => _active;

  bool isAllowed(String toolId) => _allowed.contains(toolId);

  /// Seconds left before another PIN try, or 0.
  int get lockoutSeconds {
    final DateTime? until = _lockedUntil;
    if (until == null) {
      return 0;
    }
    final int s = until.difference(_now()).inSeconds;
    return s > 0 ? s + 1 : 0;
  }

  /// Only the allowed tools, in [all]'s order, while guest mode is on;
  /// otherwise [all] unchanged.
  List<String> filter(List<String> all) {
    if (!_active) {
      return List<String>.of(all);
    }
    final Set<String> ok = _allowed.toSet();
    return all.where(ok.contains).toList();
  }

  Future<void> load() async {
    try {
      final String? text = await _store.read();
      if (text == null || text.isEmpty) {
        return;
      }
      final Object? data = jsonDecode(text);
      if (data is! Map) {
        return;
      }
      final Object? list = data['allowed'];
      _allowed = list is List ? list.whereType<String>().toList() : <String>[];
      _pinHash = data['pinHash'] as String?;
      _pinSalt = data['pinSalt'] as String?;
      // Never come back in guest mode without a PIN to leave it.
      _active = data['active'] == true && _pinHash != null && _pinSalt != null;
      notifyListeners();
    } catch (_) {
      // A broken file means no guest mode; the owner's phone stays open.
    }
  }

  String encode() => jsonEncode(<String, Object?>{
        'allowed': _allowed,
        'active': _active,
        'pinHash': _pinHash,
        'pinSalt': _pinSalt,
      });

  Future<void> _save() async {
    notifyListeners();
    try {
      await _store.write(encode());
    } catch (_) {
      // Kept in memory for this run.
    }
  }

  /// Ticks or unticks [toolId] for guests. Ignored while a guest is using
  /// the phone.
  Future<void> toggleAllowed(String toolId) async {
    if (_active) {
      return;
    }
    _allowed = _allowed.contains(toolId)
        ? _allowed.where((String t) => t != toolId).toList()
        : <String>[..._allowed, toolId];
    await _save();
  }

  /// Replaces the whitelist (used by Undo). Ignored while active.
  Future<void> setAllowed(List<String> ids) async {
    if (_active) {
      return;
    }
    _allowed = List<String>.of(ids);
    await _save();
  }

  /// Why guest mode cannot start yet, or null when it can.
  String? whyNotStart(String pin) {
    if (_allowed.isEmpty) {
      return 'Pick at least one tool for the guest';
    }
    if (!PinHasher.isValidPin(pin)) {
      return 'Use a PIN of ${PinHasher.minLength} to ${PinHasher.maxLength} digits';
    }
    return null;
  }

  /// Hands the phone over: only allowed tools until [pin] is entered.
  Future<bool> start(String pin) async {
    if (_active || whyNotStart(pin) != null) {
      return false;
    }
    final String salt = PinHasher.newSalt();
    _pinSalt = salt;
    _pinHash = PinHasher.hash(pin, salt);
    _failures = 0;
    _lockedUntil = null;
    _active = true;
    await _save();
    return true;
  }

  /// Leaves guest mode when [pin] is the owner's. Five wrong tries lock it
  /// for 30 seconds.
  Future<GuestExit> exit(String pin) async {
    if (!_active) {
      return GuestExit.notActive;
    }
    if (lockoutSeconds > 0) {
      return GuestExit.lockedOut;
    }
    final String? salt = _pinSalt;
    final String? hash = _pinHash;
    if (salt == null || hash == null || !PinHasher.verify(pin, salt, hash)) {
      _failures++;
      if (_failures >= maxAttempts) {
        _failures = 0;
        _lockedUntil = _now().add(lockoutFor);
        notifyListeners();
        return GuestExit.lockedOut;
      }
      notifyListeners();
      return GuestExit.wrongPin;
    }
    _active = false;
    _failures = 0;
    _lockedUntil = null;
    _pinHash = null;
    _pinSalt = null;
    await _save();
    return GuestExit.exited;
  }

  static GuestMode instance = GuestMode(MemoryGuestModeStore());

  static void install(GuestMode mode) {
    instance = mode;
  }
}
