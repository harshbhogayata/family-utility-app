import 'package:flutter/foundation.dart';

import 'family_identity.dart';
import 'family_store.dart';
import 'family_sync.dart';

/// Feature 068 — Family space: the one shared store plus the transports
/// that keep it in step with the other phones.
///
/// Start a family on one phone, show its QR, scan it on another phone:
/// both now hold the same family key and every record either adds or edits
/// reaches the other over the home Wi-Fi within seconds, or through the
/// person's own synced folder within a minute when they are apart. Phase 2
/// features (shared list, calendar, vault...) are collections in [store].
class FamilySpace extends ChangeNotifier {
  FamilySpace({
    required this.identityStore,
    FamilyStoreStorage? storage,
    required this.transportsFor,
    DateTime Function()? now,
  })  : _now = now ?? DateTime.now,
        store = FamilyStore(deviceId: '', storage: storage, now: now);

  static const String members = 'members';

  final FamilyIdentityStore identityStore;
  final FamilyStore store;
  final DateTime Function() _now;

  /// Builds the transports for a family: Wi-Fi, plus the sync folder if set.
  final List<FamilySyncTransport> Function(FamilyIdentity identity) transportsFor;

  FamilyIdentity? _identity;
  List<FamilySyncTransport> _transports = <FamilySyncTransport>[];
  bool _loaded = false;

  FamilyIdentity? get identity => _identity;
  bool get inFamily => _identity != null;
  bool get loaded => _loaded;
  List<FamilySyncTransport> get transports => List<FamilySyncTransport>.unmodifiable(_transports);

  List<String> get statusLines => _transports.map((FamilySyncTransport t) => t.status).toList();

  Future<void> load() async {
    try {
      _identity = await identityStore.read();
    } catch (_) {
      _identity = null;
    }
    final FamilyIdentity? id = _identity;
    if (id != null) {
      store.deviceId = id.deviceId;
      await store.load();
      await _startTransports();
    }
    _loaded = true;
    notifyListeners();
  }

  /// Starts a new family on this phone.
  Future<FamilyIdentity> create({required String familyName, required String memberName}) async {
    final FamilyIdentity id = FamilyIdentity.create(
      familyName: familyName.trim().isEmpty ? 'Our family' : familyName.trim(),
      memberName: memberName.trim().isEmpty ? 'Me' : memberName.trim(),
    );
    await _enter(id);
    return id;
  }

  /// Joins the family in a scanned invite. Null when [qrText] is not one.
  Future<FamilyIdentity?> join(String qrText, {required String memberName}) async {
    final FamilyInvite? invite = FamilyInvite.parse(qrText);
    if (invite == null) {
      return null;
    }
    final FamilyIdentity id = FamilyIdentity.join(invite, memberName: memberName.trim().isEmpty ? 'Me' : memberName.trim());
    await _enter(id);
    for (final FamilySyncTransport t in _transports) {
      await t.reach(invite);
    }
    return id;
  }

  /// The invite text for the QR (family key + this phone's Wi-Fi address).
  Future<String?> inviteCode() async {
    final FamilyIdentity? id = _identity;
    if (id == null) {
      return null;
    }
    FamilyInvite invite = id.invite();
    for (final FamilySyncTransport t in _transports) {
      invite = await t.address(invite);
    }
    return invite.encode();
  }

  /// Sets (or clears) the own-cloud folder and restarts sync with it.
  Future<void> setSyncFolder(String? folder) async {
    final FamilyIdentity? id = _identity;
    if (id == null) {
      return;
    }
    _identity = id.withSyncFolder(folder);
    await identityStore.write(_identity);
    await _stopTransports();
    await _startTransports();
    notifyListeners();
  }

  /// Leaves the family on this phone: forgets the key and the local copy.
  /// The other phones keep their data.
  Future<void> leave() async {
    await _stopTransports();
    await store.clear();
    _identity = null;
    await identityStore.write(null);
    notifyListeners();
  }

  /// Members who joined, oldest first.
  List<FamilyRecord> get memberRecords => store.list(members);

  Future<void> _enter(FamilyIdentity id) async {
    await _stopTransports();
    if (_identity?.familyId != id.familyId) {
      await store.clear();
    }
    _identity = id;
    store.deviceId = id.deviceId;
    await identityStore.write(id);
    store.put(members, id.deviceId, <String, Object?>{
      'name': id.memberName,
      'joined': _now().toUtc().toIso8601String(),
    });
    await _startTransports();
    notifyListeners();
  }

  Future<void> _startTransports() async {
    final FamilyIdentity? id = _identity;
    if (id == null) {
      return;
    }
    final FamilySyncContext ctx = FamilySyncContext(store: store, identity: id);
    _transports = transportsFor(id);
    for (final FamilySyncTransport t in _transports) {
      t.addListener(notifyListeners);
      try {
        await t.start(ctx);
      } catch (_) {
        // One transport failing (no Wi-Fi, folder gone) must not stop the rest.
      }
    }
  }

  Future<void> _stopTransports() async {
    for (final FamilySyncTransport t in _transports) {
      t.removeListener(notifyListeners);
      try {
        await t.stop();
      } catch (_) {}
    }
    _transports = <FamilySyncTransport>[];
  }

  /// The app's one family space. Bootstrap installs the real one.
  static FamilySpace instance = FamilySpace(
    identityStore: MemoryFamilyIdentityStore(),
    transportsFor: (FamilyIdentity _) => <FamilySyncTransport>[],
  );

  static void install(FamilySpace space) {
    instance = space;
  }
}
