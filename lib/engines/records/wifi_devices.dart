import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../qr/qr_generator.dart';
import '../security/secure_notes.dart';

/// Feature 097 — Wi-Fi and devices.
///
/// Router names and passwords (shown as a Wi-Fi QR guests can scan to
/// join), and the devices in the house with serial numbers, model and
/// purchase date. Encrypted on this phone with the secure notes key (057);
/// nothing is uploaded. Shared text leaves passwords out.

class WifiNetwork {
  const WifiNetwork({
    required this.id,
    required this.ssid,
    this.password = '',
    this.auth = WifiAuth.wpa,
    this.hidden = false,
    this.where = '',
  });

  final String id;
  final String ssid;
  final String password;
  final WifiAuth auth;
  final bool hidden;

  /// "Home", "Guest", "Office"…
  final String where;

  String get qrData => QrContent.wifi(ssid, password, auth: auth, hidden: hidden);

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'ssid': ssid,
        'password': password,
        'auth': auth.name,
        'hidden': hidden,
        'where': where,
      };

  static WifiNetwork? fromJson(Object? o) {
    if (o is! Map) {
      return null;
    }
    final String ssid = '${o['ssid'] ?? ''}';
    if (ssid.isEmpty) {
      return null;
    }
    return WifiNetwork(
      id: '${o['id'] ?? ssid}',
      ssid: ssid,
      password: '${o['password'] ?? ''}',
      auth: WifiAuth.values.firstWhere((WifiAuth a) => a.name == o['auth'], orElse: () => WifiAuth.wpa),
      hidden: o['hidden'] == true,
      where: '${o['where'] ?? ''}',
    );
  }
}

class HomeDevice {
  const HomeDevice({
    required this.id,
    required this.name,
    this.model = '',
    this.serial = '',
    this.bought,
    this.networkId,
    this.note = '',
  });

  final String id;
  final String name;
  final String model;
  final String serial;
  final DateTime? bought;

  /// The Wi-Fi network it is connected to, if any.
  final String? networkId;
  final String note;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'name': name,
        'model': model,
        'serial': serial,
        if (bought != null) 'bought': bought!.toIso8601String(),
        if (networkId != null) 'net': networkId,
        'note': note,
      };

  static HomeDevice? fromJson(Object? o) {
    if (o is! Map) {
      return null;
    }
    final String name = '${o['name'] ?? ''}';
    if (name.isEmpty) {
      return null;
    }
    final Object? net = o['net'];
    return HomeDevice(
      id: '${o['id'] ?? name}',
      name: name,
      model: '${o['model'] ?? ''}',
      serial: '${o['serial'] ?? ''}',
      bought: o['bought'] == null ? null : DateTime.tryParse('${o['bought']}'),
      networkId: net is String ? net : null,
      note: '${o['note'] ?? ''}',
    );
  }
}

class WifiDevicesData {
  const WifiDevicesData({this.networks = const <WifiNetwork>[], this.devices = const <HomeDevice>[]});

  final List<WifiNetwork> networks;
  final List<HomeDevice> devices;

  static const WifiDevicesData empty = WifiDevicesData();

  Map<String, Object?> toJson() => <String, Object?>{
        'networks': networks.map((WifiNetwork n) => n.toJson()).toList(),
        'devices': devices.map((HomeDevice d) => d.toJson()).toList(),
      };

  static WifiDevicesData fromJson(Map<String, Object?> j) {
    final Object? n = j['networks'];
    final Object? d = j['devices'];
    return WifiDevicesData(
      networks: n is List ? n.map(WifiNetwork.fromJson).whereType<WifiNetwork>().toList() : const <WifiNetwork>[],
      devices: d is List ? d.map(HomeDevice.fromJson).whereType<HomeDevice>().toList() : const <HomeDevice>[],
    );
  }
}

class WifiDevicesBook extends ChangeNotifier {
  WifiDevicesBook({required KeyStore keyStore, required NoteBlobStore blobStore})
      : _cipher = NoteCipher(keyStore),
        _blobs = blobStore;

  final NoteCipher _cipher;
  final NoteBlobStore _blobs;

  WifiDevicesData _data = WifiDevicesData.empty;
  final List<WifiDevicesData> _undo = <WifiDevicesData>[];
  bool _loaded = false;
  String? _loadError;

  List<WifiNetwork> get networks => _data.networks;
  bool get isLoaded => _loaded;
  String? get loadError => _loadError;
  bool get canUndo => _undo.isNotEmpty;

  /// Newest purchase first; undated devices last, by name.
  List<HomeDevice> get devices {
    final List<HomeDevice> l = List<HomeDevice>.of(_data.devices);
    l.sort((HomeDevice a, HomeDevice b) {
      if (a.bought != null && b.bought != null) {
        final int c = b.bought!.compareTo(a.bought!);
        if (c != 0) {
          return c;
        }
      } else if (a.bought != null || b.bought != null) {
        return a.bought == null ? 1 : -1;
      }
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return l;
  }

  WifiNetwork? network(String? id) {
    for (final WifiNetwork n in _data.networks) {
      if (n.id == id) {
        return n;
      }
    }
    return null;
  }

  List<HomeDevice> devicesOn(String networkId) => devices.where((HomeDevice d) => d.networkId == networkId).toList();

  Future<void> load() async {
    try {
      final String? blob = await _blobs.read();
      if (blob != null && blob.isNotEmpty) {
        final Object? parsed = jsonDecode(await _cipher.decrypt(blob));
        if (parsed is Map<String, Object?>) {
          _data = WifiDevicesData.fromJson(parsed);
        }
      }
      _loadError = null;
    } catch (e) {
      _loadError = 'Could not read the saved networks on this phone: $e';
      _data = WifiDevicesData.empty;
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> _commit(WifiDevicesData next) async {
    _undo.add(_data);
    if (_undo.length > 20) {
      _undo.removeAt(0);
    }
    _data = next;
    notifyListeners();
    await _blobs.write(await _cipher.encrypt(jsonEncode(_data.toJson())));
  }

  /// Adds or replaces (same id) a network. Null when the name is empty or
  /// a secured network has no password.
  Future<WifiNetwork?> saveNetwork({
    String? id,
    required String ssid,
    String password = '',
    WifiAuth auth = WifiAuth.wpa,
    bool hidden = false,
    String where = '',
  }) async {
    final String name = ssid.trim();
    if (name.isEmpty || (auth != WifiAuth.open && password.isEmpty)) {
      return null;
    }
    final WifiNetwork n = WifiNetwork(
      id: id ?? SecureNotes.newId(),
      ssid: name,
      password: auth == WifiAuth.open ? '' : password,
      auth: auth,
      hidden: hidden,
      where: where.trim(),
    );
    final List<WifiNetwork> list = <WifiNetwork>[
      for (final WifiNetwork x in _data.networks)
        if (x.id != n.id) x,
    ];
    final int at = _data.networks.indexWhere((WifiNetwork x) => x.id == n.id);
    list.insert(at < 0 ? list.length : at, n);
    await _commit(WifiDevicesData(networks: list, devices: _data.devices));
    return n;
  }

  /// Removes a network; devices on it keep their details but lose the link.
  Future<bool> removeNetwork(String id) async {
    if (network(id) == null) {
      return false;
    }
    await _commit(WifiDevicesData(
      networks: _data.networks.where((WifiNetwork n) => n.id != id).toList(),
      devices: <HomeDevice>[
        for (final HomeDevice d in _data.devices)
          d.networkId == id ? HomeDevice(id: d.id, name: d.name, model: d.model, serial: d.serial, bought: d.bought, note: d.note) : d,
      ],
    ));
    return true;
  }

  /// Adds or replaces (same id) a device. Null when the name is empty or the
  /// purchase date is in the future of [today].
  Future<HomeDevice?> saveDevice({
    String? id,
    required String name,
    String model = '',
    String serial = '',
    DateTime? bought,
    String? networkId,
    String note = '',
    DateTime? today,
  }) async {
    final String n = name.trim();
    final DateTime t = today ?? DateTime.now();
    if (n.isEmpty || (bought != null && bought.isAfter(DateTime(t.year, t.month, t.day, 23, 59)))) {
      return null;
    }
    final HomeDevice d = HomeDevice(
      id: id ?? SecureNotes.newId(),
      name: n,
      model: model.trim(),
      serial: serial.trim(),
      bought: bought == null ? null : DateTime(bought.year, bought.month, bought.day),
      networkId: network(networkId) == null ? null : networkId,
      note: note.trim(),
    );
    await _commit(WifiDevicesData(
      networks: _data.networks,
      devices: <HomeDevice>[
        for (final HomeDevice x in _data.devices)
          if (x.id != d.id) x,
        d,
      ],
    ));
    return d;
  }

  Future<bool> removeDevice(String id) async {
    if (!_data.devices.any((HomeDevice d) => d.id == id)) {
      return false;
    }
    await _commit(WifiDevicesData(networks: _data.networks, devices: _data.devices.where((HomeDevice d) => d.id != id).toList()));
    return true;
  }

  Future<bool> undo() async {
    if (_undo.isEmpty) {
      return false;
    }
    _data = _undo.removeLast();
    notifyListeners();
    await _blobs.write(await _cipher.encrypt(jsonEncode(_data.toJson())));
    return true;
  }

  /// Finds a device by serial number (ignoring spaces, dashes and case).
  HomeDevice? bySerial(String serial) {
    String norm(String s) => s.replaceAll(RegExp(r'[\s\-]'), '').toUpperCase();
    final String q = norm(serial);
    if (q.isEmpty) {
      return null;
    }
    for (final HomeDevice d in _data.devices) {
      if (norm(d.serial) == q) {
        return d;
      }
    }
    return null;
  }

  static const List<String> months = <String>['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  static String dayLabel(DateTime d) => '${d.day} ${months[d.month - 1]} ${d.year}';

  static String authLabel(WifiAuth a) => switch (a) {
        WifiAuth.wpa => 'WPA/WPA2',
        WifiAuth.wep => 'WEP',
        WifiAuth.open => 'No password',
      };

  /// A plain list for sharing or saving. Passwords only when asked for.
  String toText({bool includePasswords = false}) {
    final StringBuffer b = StringBuffer('Wi-Fi and devices\n');
    if (_data.networks.isNotEmpty) {
      b.write('\nNetworks\n');
      for (final WifiNetwork n in _data.networks) {
        b.write('- ${n.ssid}${n.where.isEmpty ? '' : ' (${n.where})'} · ${authLabel(n.auth)}');
        if (includePasswords && n.password.isNotEmpty) {
          b.write(' · password ${n.password}');
        }
        b.write('\n');
      }
    }
    if (_data.devices.isNotEmpty) {
      b.write('\nDevices\n');
      for (final HomeDevice d in devices) {
        final List<String> parts = <String>[
          if (d.model.isNotEmpty) d.model,
          if (d.serial.isNotEmpty) 'S/N ${d.serial}',
          if (d.bought != null) 'bought ${dayLabel(d.bought!)}',
          if (network(d.networkId) != null) 'on ${network(d.networkId)!.ssid}',
          if (d.note.isNotEmpty) d.note,
        ];
        b.write('- ${d.name}${parts.isEmpty ? '' : ' · ${parts.join(' · ')}'}\n');
      }
    }
    return b.toString();
  }

  static WifiDevicesBook instance = WifiDevicesBook(keyStore: MemoryKeyStore(), blobStore: MemoryNoteBlobStore());

  static void install(WifiDevicesBook book) => instance = book;
}
