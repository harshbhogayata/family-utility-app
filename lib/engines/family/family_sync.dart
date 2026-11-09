import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'family_identity.dart';
import 'family_store.dart';

/// Feature 068 — how records travel between family phones.
///
/// Two transports share this interface: home Wi-Fi (lib/family/sync/, the
/// only folder allowed to open sockets) and an own-cloud folder the person
/// picks, which only ever holds change files sealed with the family key.

class FamilySyncContext {
  FamilySyncContext({required this.store, required this.identity}) : cipher = FamilyCipher(identity.secret);

  final FamilyStore store;
  final FamilyIdentity identity;
  final FamilyCipher cipher;

  String get deviceId => identity.deviceId;

  /// Records as one sealed blob.
  Future<String> sealRecords(Iterable<FamilyRecord> records) =>
      cipher.seal(jsonEncode(records.map((FamilyRecord r) => r.toJson()).toList()));

  /// Opens a blob from [sealRecords]; throws on a foreign or damaged blob.
  Future<List<FamilyRecord>> openRecords(String sealed) async {
    final Object? json = jsonDecode(await cipher.open(sealed));
    if (json is! List) {
      throw const FormatException('not a record list');
    }
    return json.whereType<Map>().map((Map m) => FamilyRecord.fromJson(Map<String, Object?>.from(m))).toList();
  }
}

abstract class FamilySyncTransport extends ChangeNotifier {
  /// Short status for the Family tab, e.g. "2 phones on Wi-Fi".
  String get status;

  Future<void> start(FamilySyncContext context);

  Future<void> stop();

  /// Adds where this transport can be reached to an invite (Wi-Fi address).
  Future<FamilyInvite> address(FamilyInvite invite) async => invite;

  /// Reaches the phone that made [invite], right after joining.
  Future<void> reach(FamilyInvite invite) async {}
}

/// Own-cloud: a folder synced by the person's own Drive, iCloud Drive or
/// Syncthing. Each phone writes its changes as sealed files and reads the
/// files other phones wrote. Propagation is bounded by [pollEvery] plus the
/// folder provider's own delay; the default polls well inside a minute.
class FolderFamilySync extends FamilySyncTransport {
  FolderFamilySync(
    this.folderPath, {
    this.pollEvery = const Duration(seconds: 15),
    this.writeDelay = const Duration(seconds: 1),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final String folderPath;
  final Duration pollEvery;
  final Duration writeDelay;
  final DateTime Function() _now;

  FamilySyncContext? _ctx;
  StreamSubscription<FamilyRecord>? _sub;
  Timer? _poll;
  Timer? _write;
  final Map<String, FamilyRecord> _pending = <String, FamilyRecord>{};
  final Set<String> _seen = <String>{};
  int _seq = 0;
  bool _merging = false;
  DateTime? lastSync;
  String? lastError;

  Directory get _dir => Directory('$folderPath/family-space');

  @override
  String get status {
    if (lastError != null) {
      return 'Sync folder: $lastError';
    }
    final DateTime? t = lastSync;
    if (t == null) {
      return 'Sync folder: waiting';
    }
    final String hh = t.hour.toString().padLeft(2, '0');
    final String mm = t.minute.toString().padLeft(2, '0');
    return 'Sync folder: checked $hh:$mm';
  }

  @override
  Future<void> start(FamilySyncContext context) async {
    _ctx = context;
    _sub = context.store.changes.listen((FamilyRecord r) {
      if (_merging) {
        return; // came from this folder already
      }
      _pending[r.key] = r;
      _write ??= Timer(writeDelay, () => unawaited(flushOut()));
    });
    // First run in this folder: publish everything this phone holds.
    _pending.addAll(<String, FamilyRecord>{for (final FamilyRecord r in context.store.allRecords) r.key: r});
    await flushOut();
    await pollIn();
    _poll = Timer.periodic(pollEvery, (_) => unawaited(pollIn()));
  }

  /// Writes pending changes as one sealed file.
  Future<void> flushOut() async {
    _write?.cancel();
    _write = null;
    final FamilySyncContext? ctx = _ctx;
    if (ctx == null || _pending.isEmpty) {
      return;
    }
    final List<FamilyRecord> batch = _pending.values.toList();
    _pending.clear();
    try {
      await _dir.create(recursive: true);
      final String name = '${ctx.deviceId}-${_now().millisecondsSinceEpoch}-${_seq++}.fam';
      final File tmp = File('${_dir.path}/.$name.part');
      await tmp.writeAsString(await ctx.sealRecords(batch));
      await tmp.rename('${_dir.path}/$name');
      _seen.add(name);
      lastError = null;
    } catch (_) {
      for (final FamilyRecord r in batch) {
        _pending.putIfAbsent(r.key, () => r);
      }
      lastError = 'cannot write';
    }
    notifyListeners();
  }

  /// Reads change files this phone has not seen yet.
  Future<int> pollIn() async {
    final FamilySyncContext? ctx = _ctx;
    if (ctx == null) {
      return 0;
    }
    int changed = 0;
    try {
      if (_dir.existsSync()) {
        final List<File> files = _dir
            .listSync()
            .whereType<File>()
            .where((File f) => f.path.endsWith('.fam'))
            .toList()
          ..sort((File a, File b) => a.path.compareTo(b.path));
        for (final File f in files) {
          final String name = f.uri.pathSegments.last;
          if (_seen.contains(name)) {
            continue;
          }
          _seen.add(name);
          try {
            final List<FamilyRecord> records = await ctx.openRecords(await f.readAsString());
            _merging = true;
            changed += ctx.store.mergeAll(records);
          } catch (_) {
            // Not ours (another family's key) or half-synced; skip it.
          } finally {
            _merging = false;
          }
        }
      }
      lastSync = _now();
      lastError = null;
    } catch (_) {
      lastError = 'folder not reachable';
    }
    notifyListeners();
    return changed;
  }

  @override
  Future<void> stop() async {
    await flushOut();
    await _sub?.cancel();
    _sub = null;
    _poll?.cancel();
    _poll = null;
    _ctx = null;
  }
}
