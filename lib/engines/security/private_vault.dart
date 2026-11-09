import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

import 'app_lock.dart' show PinHasher;
import 'secure_notes.dart' show KeyStore, MemoryKeyStore;

/// Feature 056 — Private vault.
///
/// Photos and files kept behind a vault PIN, each one AES-256-GCM encrypted
/// at rest with a random key held in Keystore / Keychain ([KeyStore]). The
/// list of names is encrypted too, so the folder on disk holds only random
/// ids and ciphertext.
///
/// A second, decoy PIN opens a separate space with its own key. It starts
/// empty and never shows anything from the real one, nor that a real one
/// exists. Vault files live in app-private storage with `.nomedia`, so no
/// gallery indexes them, and are excluded from backups unless the person
/// turns backups on ([VaultBackend.setIncludedInBackups]).

/// Which vault a PIN opened.
enum VaultSpace { real, decoy }

enum VaultItemKind { photo, file }

@immutable
class VaultItem {
  const VaultItem({
    required this.id,
    required this.name,
    required this.kind,
    required this.size,
    required this.addedAt,
  });

  final String id;
  final String name;
  final VaultItemKind kind;
  final int size;
  final DateTime addedAt;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'name': name,
        'kind': kind.name,
        'size': size,
        'addedAt': addedAt.toUtc().toIso8601String(),
      };

  static VaultItem fromJson(Map<String, Object?> j) => VaultItem(
        id: (j['id'] as String?) ?? '',
        name: (j['name'] as String?) ?? '',
        kind: j['kind'] == 'photo' ? VaultItemKind.photo : VaultItemKind.file,
        size: (j['size'] as int?) ?? 0,
        addedAt: DateTime.tryParse((j['addedAt'] as String?) ?? '')?.toLocal() ?? DateTime(2000),
      );

  static const Set<String> photoExtensions = <String>{
    'jpg', 'jpeg', 'png', 'heic', 'heif', 'webp', 'gif', 'bmp', 'mp4', 'mov', 'm4v', '3gp',
  };

  static VaultItemKind kindFor(String name) {
    final int dot = name.lastIndexOf('.');
    final String ext = dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
    return photoExtensions.contains(ext) ? VaultItemKind.photo : VaultItemKind.file;
  }
}

/// PIN hashes and the backup choice. Stored in secure storage.
@immutable
class VaultSettings {
  const VaultSettings({
    this.pinHash,
    this.pinSalt,
    this.decoyHash,
    this.decoySalt,
    this.includeInBackups = false,
  });

  final String? pinHash;
  final String? pinSalt;
  final String? decoyHash;
  final String? decoySalt;
  final bool includeInBackups;

  bool get hasPin => pinHash != null && pinSalt != null;

  bool get hasDecoy => decoyHash != null && decoySalt != null;

  VaultSettings copyWith({
    String? pinHash,
    String? pinSalt,
    String? decoyHash,
    String? decoySalt,
    bool clearDecoy = false,
    bool? includeInBackups,
  }) =>
      VaultSettings(
        pinHash: pinHash ?? this.pinHash,
        pinSalt: pinSalt ?? this.pinSalt,
        decoyHash: clearDecoy ? null : (decoyHash ?? this.decoyHash),
        decoySalt: clearDecoy ? null : (decoySalt ?? this.decoySalt),
        includeInBackups: includeInBackups ?? this.includeInBackups,
      );

  String encode() => jsonEncode(<String, Object?>{
        'pinHash': pinHash,
        'pinSalt': pinSalt,
        'decoyHash': decoyHash,
        'decoySalt': decoySalt,
        'backups': includeInBackups,
      });

  static VaultSettings decode(String? text) {
    if (text == null || text.isEmpty) {
      return const VaultSettings();
    }
    try {
      final Object? j = jsonDecode(text);
      if (j is Map<String, Object?>) {
        return VaultSettings(
          pinHash: j['pinHash'] as String?,
          pinSalt: j['pinSalt'] as String?,
          decoyHash: j['decoyHash'] as String?,
          decoySalt: j['decoySalt'] as String?,
          includeInBackups: j['backups'] == true,
        );
      }
    } on FormatException {
      // fall through
    }
    return const VaultSettings();
  }
}

// ---- interfaces to the platform ------------------------------------------

abstract class VaultSettingsStore {
  Future<String?> read();

  Future<void> write(String value);
}

class MemoryVaultSettingsStore implements VaultSettingsStore {
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String v) async => value = v;
}

/// Where the encrypted index and files live.
abstract class VaultBackend {
  Future<Uint8List?> readIndex(VaultSpace space);

  Future<void> writeIndex(VaultSpace space, Uint8List data);

  Future<Uint8List?> readObject(VaultSpace space, String id);

  Future<void> writeObject(VaultSpace space, String id, Uint8List data);

  Future<void> deleteObject(VaultSpace space, String id);

  /// Moves the vault in or out of the folder the OS backs up.
  Future<void> setIncludedInBackups(bool included);

  /// Tells the backend which folder the saved choice points at, without
  /// moving anything. Called once on load.
  void useBackupChoice(bool included);
}

class MemoryVaultBackend implements VaultBackend {
  final Map<String, Uint8List> files = <String, Uint8List>{};
  bool includedInBackups = false;

  String _k(VaultSpace s, String id) => '${s.name}/$id';

  @override
  Future<Uint8List?> readIndex(VaultSpace space) async => files[_k(space, 'index')];

  @override
  Future<void> writeIndex(VaultSpace space, Uint8List data) async => files[_k(space, 'index')] = data;

  @override
  Future<Uint8List?> readObject(VaultSpace space, String id) async => files[_k(space, id)];

  @override
  Future<void> writeObject(VaultSpace space, String id, Uint8List data) async => files[_k(space, id)] = data;

  @override
  Future<void> deleteObject(VaultSpace space, String id) async => files.remove(_k(space, id));

  @override
  Future<void> setIncludedInBackups(bool included) async => includedInBackups = included;

  @override
  void useBackupChoice(bool included) => includedInBackups = included;
}

// ---- crypto ---------------------------------------------------------------

/// AES-256-GCM: nonce (12) · ciphertext · tag (16). One random key per space.
class VaultCipher {
  VaultCipher(this._keyStore);

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

  Future<Uint8List> encrypt(List<int> plain) async {
    final SecretBox box = await _aes.encrypt(plain, secretKey: await _secretKey());
    final BytesBuilder b = BytesBuilder(copy: false)
      ..add(box.nonce)
      ..add(box.cipherText)
      ..add(box.mac.bytes);
    return b.toBytes();
  }

  /// Throws [SecretBoxAuthenticationError] when the data was changed or was
  /// written with another key.
  Future<Uint8List> decrypt(Uint8List data) async {
    if (data.length < 28) {
      throw const FormatException('vault data too short');
    }
    final SecretBox box = SecretBox(
      data.sublist(12, data.length - 16),
      nonce: data.sublist(0, 12),
      mac: Mac(data.sublist(data.length - 16)),
    );
    return Uint8List.fromList(await _aes.decrypt(box, secretKey: await _secretKey()));
  }
}

// ---- the vault ------------------------------------------------------------

enum VaultOpenFailure { notSetUp, wrongPin, lockedOut }

class VaultPinError implements Exception {
  const VaultPinError(this.message);
  final String message;

  @override
  String toString() => message;
}

class _UndoStep {
  const _UndoStep.added(this.item) : bytes = null;
  const _UndoStep.removed(this.item, Uint8List this.bytes);

  final VaultItem item;
  final Uint8List? bytes;
}

class PrivateVault extends ChangeNotifier {
  PrivateVault({
    required KeyStore realKeys,
    required KeyStore decoyKeys,
    required VaultBackend backend,
    required VaultSettingsStore settingsStore,
    DateTime Function()? now,
  })  : _ciphers = <VaultSpace, VaultCipher>{
          VaultSpace.real: VaultCipher(realKeys),
          VaultSpace.decoy: VaultCipher(decoyKeys),
        },
        _backend = backend,
        _store = settingsStore,
        _now = now ?? DateTime.now;

  final Map<VaultSpace, VaultCipher> _ciphers;
  final VaultBackend _backend;
  final VaultSettingsStore _store;
  final DateTime Function() _now;

  static const int maxAttempts = 5;
  static const Duration lockoutFor = Duration(seconds: 30);

  VaultSettings _settings = const VaultSettings();
  bool _loaded = false;
  VaultSpace? _space;
  List<VaultItem> _items = <VaultItem>[];
  String? _indexError;
  int _failed = 0;
  DateTime? _lockedOutUntil;
  _UndoStep? _undo;

  bool get isLoaded => _loaded;

  bool get hasPin => _settings.hasPin;

  bool get isOpen => _space != null;

  /// Which space is open. The UI uses it only to hide real-vault settings
  /// while the decoy is open; it never shows the value.
  VaultSpace? get openSpace => _space;

  bool get includeInBackups => _settings.includeInBackups;

  /// Only meaningful in the real vault; the decoy never sees it.
  bool get hasDecoy => _space == VaultSpace.real && _settings.hasDecoy;

  List<VaultItem> get items => List<VaultItem>.unmodifiable(_items);

  String? get indexError => _indexError;

  bool get canUndo => _undo != null;

  int get lockoutSecondsLeft {
    final DateTime? until = _lockedOutUntil;
    if (until == null) {
      return 0;
    }
    final int s = until.difference(_now()).inSeconds;
    return s > 0 ? s + 1 : 0;
  }

  Future<void> load() async {
    try {
      _settings = VaultSettings.decode(await _store.read());
    } catch (_) {
      _settings = const VaultSettings();
    }
    _backend.useBackupChoice(_settings.includeInBackups);
    _loaded = true;
    notifyListeners();
  }

  Future<void> _saveSettings() => _store.write(_settings.encode());

  /// First-time set up, or a change from inside the open real vault.
  Future<void> setPin(String pin) async {
    if (!PinHasher.isValidPin(pin)) {
      throw const VaultPinError('Use 4 to 6 digits.');
    }
    if (_settings.hasPin && _space != VaultSpace.real) {
      throw const VaultPinError('Open the vault first.');
    }
    if (_settings.hasDecoy && PinHasher.verify(pin, _settings.decoySalt!, _settings.decoyHash!)) {
      throw const VaultPinError('Pick a PIN that differs from the decoy PIN.');
    }
    final String salt = PinHasher.newSalt();
    _settings = _settings.copyWith(pinHash: PinHasher.hash(pin, salt), pinSalt: salt);
    await _saveSettings();
    if (_space == null) {
      await _openSpace(VaultSpace.real);
    }
    notifyListeners();
  }

  /// Sets the decoy PIN. Only from the open real vault.
  Future<void> setDecoyPin(String pin) async {
    if (_space != VaultSpace.real) {
      throw const VaultPinError('Open the vault first.');
    }
    if (!PinHasher.isValidPin(pin)) {
      throw const VaultPinError('Use 4 to 6 digits.');
    }
    if (PinHasher.verify(pin, _settings.pinSalt!, _settings.pinHash!)) {
      throw const VaultPinError('The decoy PIN must differ from the vault PIN.');
    }
    final String salt = PinHasher.newSalt();
    _settings = _settings.copyWith(decoyHash: PinHasher.hash(pin, salt), decoySalt: salt);
    await _saveSettings();
    notifyListeners();
  }

  Future<void> clearDecoyPin() async {
    if (_space != VaultSpace.real) {
      throw const VaultPinError('Open the vault first.');
    }
    _settings = _settings.copyWith(clearDecoy: true);
    await _saveSettings();
    notifyListeners();
  }

  /// Null on success. A decoy PIN succeeds just like the real one.
  Future<VaultOpenFailure?> open(String pin) async {
    if (!_settings.hasPin) {
      return VaultOpenFailure.notSetUp;
    }
    if (lockoutSecondsLeft > 0) {
      return VaultOpenFailure.lockedOut;
    }
    _lockedOutUntil = null;
    VaultSpace? space;
    if (PinHasher.verify(pin, _settings.pinSalt!, _settings.pinHash!)) {
      space = VaultSpace.real;
    } else if (_settings.hasDecoy && PinHasher.verify(pin, _settings.decoySalt!, _settings.decoyHash!)) {
      space = VaultSpace.decoy;
    }
    if (space == null) {
      _failed++;
      if (_failed >= maxAttempts) {
        _failed = 0;
        _lockedOutUntil = _now().add(lockoutFor);
        notifyListeners();
        return VaultOpenFailure.lockedOut;
      }
      notifyListeners();
      return VaultOpenFailure.wrongPin;
    }
    _failed = 0;
    await _openSpace(space);
    return null;
  }

  Future<void> _openSpace(VaultSpace space) async {
    _space = space;
    _undo = null;
    _items = <VaultItem>[];
    _indexError = null;
    try {
      final Uint8List? data = await _backend.readIndex(space);
      if (data != null && data.isNotEmpty) {
        final Object? parsed = jsonDecode(utf8.decode(await _ciphers[space]!.decrypt(data)));
        if (parsed is List<Object?>) {
          _items = parsed.whereType<Map<String, Object?>>().map(VaultItem.fromJson).toList();
        }
      }
    } catch (e) {
      _indexError = 'Could not read the vault on this phone: $e';
    }
    _sort();
    notifyListeners();
  }

  /// Locks the vault again and forgets the names in memory.
  void close() {
    _space = null;
    _items = <VaultItem>[];
    _undo = null;
    _indexError = null;
    notifyListeners();
  }

  void _sort() => _items.sort((VaultItem a, VaultItem b) => b.addedAt.compareTo(a.addedAt));

  VaultSpace _requireOpen() {
    final VaultSpace? s = _space;
    if (s == null) {
      throw StateError('vault is locked');
    }
    return s;
  }

  Future<void> _writeIndex() async {
    final VaultSpace s = _requireOpen();
    final String json = jsonEncode(_items.map((VaultItem i) => i.toJson()).toList());
    await _backend.writeIndex(s, await _ciphers[s]!.encrypt(utf8.encode(json)));
  }

  static String newId() {
    final Random r = Random.secure();
    return List<int>.generate(12, (int _) => r.nextInt(256)).map((int b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Encrypts and stores a copy. The original stays where it was; the UI
  /// reminds the person to delete it from the gallery.
  Future<VaultItem> add(String name, Uint8List bytes, {VaultItemKind? kind}) async {
    final VaultSpace s = _requireOpen();
    final VaultItem item = VaultItem(
      id: newId(),
      name: name,
      kind: kind ?? VaultItem.kindFor(name),
      size: bytes.length,
      addedAt: _now(),
    );
    await _backend.writeObject(s, item.id, await _ciphers[s]!.encrypt(bytes));
    _items = <VaultItem>[item, ..._items];
    _sort();
    await _writeIndex();
    _undo = _UndoStep.added(item);
    notifyListeners();
    return item;
  }

  Future<Uint8List> read(VaultItem item) async {
    final VaultSpace s = _requireOpen();
    final Uint8List? data = await _backend.readObject(s, item.id);
    if (data == null) {
      throw StateError('${item.name} is missing from the vault');
    }
    return _ciphers[s]!.decrypt(data);
  }

  Future<void> remove(VaultItem item) async {
    final VaultSpace s = _requireOpen();
    final Uint8List bytes = await read(item);
    await _backend.deleteObject(s, item.id);
    _items = _items.where((VaultItem i) => i.id != item.id).toList();
    await _writeIndex();
    _undo = _UndoStep.removed(item, bytes);
    notifyListeners();
  }

  /// Reverses the last add or remove. Returns a line for the snackbar.
  Future<String?> undo() async {
    final _UndoStep? step = _undo;
    if (step == null || _space == null) {
      return null;
    }
    final VaultSpace s = _space!;
    _undo = null;
    final Uint8List? bytes = step.bytes;
    if (bytes == null) {
      await _backend.deleteObject(s, step.item.id);
      _items = _items.where((VaultItem i) => i.id != step.item.id).toList();
      await _writeIndex();
      notifyListeners();
      return 'Removed ${step.item.name} from the vault';
    }
    await _backend.writeObject(s, step.item.id, await _ciphers[s]!.encrypt(bytes));
    _items = <VaultItem>[step.item, ..._items];
    _sort();
    await _writeIndex();
    notifyListeners();
    return 'Put ${step.item.name} back';
  }

  Future<void> setIncludeInBackups(bool on) async {
    if (_space != VaultSpace.real) {
      throw const VaultPinError('Open the vault first.');
    }
    await _backend.setIncludedInBackups(on);
    _settings = _settings.copyWith(includeInBackups: on);
    await _saveSettings();
    notifyListeners();
  }

  static PrivateVault instance = PrivateVault(
    realKeys: MemoryKeyStore(),
    decoyKeys: MemoryKeyStore(),
    backend: MemoryVaultBackend(),
    settingsStore: MemoryVaultSettingsStore(),
  );

  static void install(PrivateVault vault) {
    instance = vault;
  }
}
