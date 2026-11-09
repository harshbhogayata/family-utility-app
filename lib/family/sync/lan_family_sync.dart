import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../engines/family/family_identity.dart';
import '../../engines/family/family_store.dart';
import '../../engines/family/family_sync.dart';
import '../../engines/transfer/lan_transfer.dart';

/// Feature 068 — family sync over the home Wi-Fi.
///
/// Each phone listens on a TCP port. Frames are one line each, sealed with
/// the family key (AES-256-GCM), so a device without the key can neither
/// read nor inject anything; a frame that fails to open drops the link.
/// Phones find each other with a sealed UDP broadcast beacon, and a phone
/// that just scanned an invite connects straight to the address in the QR.
/// A change is pushed to every connected phone the moment it is made, and
/// passed on by phones that receive it, so it lands well under 3 s.
/// Nothing here reaches the internet.
class LanFamilySync extends FamilySyncTransport {
  LanFamilySync({
    this.port = 47820,
    this.discovery = true,
    this.beaconPort = 47821,
    this.beaconEvery = const Duration(seconds: 2),
    this.bindAddress,
  });

  /// Preferred listening port; 0 picks any free one.
  final int port;
  final bool discovery;
  final int beaconPort;
  final Duration beaconEvery;
  final InternetAddress? bindAddress;

  FamilySyncContext? _ctx;
  ServerSocket? _server;
  RawDatagramSocket? _beacon;
  Timer? _beaconTimer;
  StreamSubscription<FamilyRecord>? _sub;
  final Set<_Peer> _links = <_Peer>{};
  _Peer? _merging;

  int get listeningPort => _server?.port ?? 0;

  bool get isRunning => _server != null;

  /// Distinct family phones connected right now.
  int get peerCount => _links.map((_Peer p) => p.deviceId).whereType<String>().toSet().length;

  @override
  String get status {
    if (!isRunning) {
      return 'Wi-Fi: off';
    }
    final int n = peerCount;
    if (n == 0) {
      return 'Wi-Fi: looking for family phones';
    }
    return 'Wi-Fi: $n ${n == 1 ? 'phone' : 'phones'} connected';
  }

  @override
  Future<void> start(FamilySyncContext context) async {
    _ctx = context;
    final InternetAddress addr = bindAddress ?? InternetAddress.anyIPv4;
    try {
      _server = await ServerSocket.bind(addr, port, shared: false);
    } on SocketException {
      _server = await ServerSocket.bind(addr, 0);
    }
    _server!.listen((Socket s) => _attach(s), onError: (Object _) {});
    _sub = context.store.changes.listen(_broadcast);
    if (discovery) {
      await _startBeacon();
    }
    notifyListeners();
  }

  /// Puts this phone's Wi-Fi addresses and port into the invite QR.
  @override
  Future<FamilyInvite> address(FamilyInvite invite) async {
    final InternetAddress? bound = bindAddress;
    final List<String> hosts =
        bound != null ? <String>[bound.address] : await LanTransferServer.localAddresses();
    return FamilyInvite(
      familyId: invite.familyId,
      familyName: invite.familyName,
      secret: invite.secret,
      hosts: hosts,
      port: listeningPort,
    );
  }

  /// Dials the inviting phone at each address in the QR until one answers.
  @override
  Future<void> reach(FamilyInvite invite) async {
    final int? p = invite.port;
    if (p == null) {
      return;
    }
    for (final String h in invite.hosts) {
      if (await connect(h, p)) {
        return;
      }
    }
  }

  /// Connects to a family phone at [host]:[port] (from an invite or beacon).
  Future<bool> connect(String host, int port) async {
    if (_ctx == null) {
      return false;
    }
    try {
      final Socket s = await Socket.connect(host, port, timeout: const Duration(seconds: 3));
      _attach(s);
      return true;
    } catch (_) {
      return false;
    }
  }

  void _attach(Socket socket) {
    final FamilySyncContext? ctx = _ctx;
    if (ctx == null) {
      socket.destroy();
      return;
    }
    socket.setOption(SocketOption.tcpNoDelay, true);
    final _Peer peer = _Peer(socket);
    _links.add(peer);
    peer.send(ctx, <String, Object?>{'t': 'hello', 'd': ctx.deviceId});
    peer.sendRecords(ctx, ctx.store.allRecords);
    socket
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          (String line) => peer.inbox = peer.inbox.then((_) => _receive(peer, line)),
          onDone: () => _drop(peer),
          onError: (Object _) => _drop(peer),
          cancelOnError: true,
        );
    notifyListeners();
  }

  Future<void> _receive(_Peer peer, String line) async {
    final FamilySyncContext? ctx = _ctx;
    if (ctx == null || peer.closed || line.isEmpty) {
      return;
    }
    Map<String, Object?> frame;
    try {
      frame = Map<String, Object?>.from(jsonDecode(await ctx.cipher.open(line)) as Map);
    } catch (_) {
      _drop(peer); // wrong family key or garbage: hang up
      return;
    }
    switch (frame['t']) {
      case 'hello':
        final String? d = frame['d'] as String?;
        if (d == null || d == ctx.deviceId) {
          _drop(peer);
          return;
        }
        peer.deviceId = d;
        notifyListeners();
      case 'recs':
        final Object? list = frame['r'];
        if (list is List) {
          final List<FamilyRecord> records = list
              .whereType<Map>()
              .map((Map m) => FamilyRecord.fromJson(Map<String, Object?>.from(m)))
              .toList();
          _merging = peer;
          try {
            ctx.store.mergeAll(records, via: FamilyPath.wifi);
          } finally {
            _merging = null;
          }
        }
    }
  }

  void _broadcast(FamilyRecord r) {
    final FamilySyncContext? ctx = _ctx;
    if (ctx == null) {
      return;
    }
    for (final _Peer p in _links) {
      if (!identical(p, _merging)) {
        p.sendRecords(ctx, <FamilyRecord>[r]);
      }
    }
  }

  void _drop(_Peer peer) {
    if (peer.closed) {
      return;
    }
    peer.closed = true;
    peer.socket.destroy();
    _links.remove(peer);
    notifyListeners();
  }

  // ---- discovery ------------------------------------------------------------

  Future<void> _startBeacon() async {
    try {
      final RawDatagramSocket udp =
          await RawDatagramSocket.bind(InternetAddress.anyIPv4, beaconPort, reuseAddress: true);
      udp.broadcastEnabled = true;
      _beacon = udp;
      udp.listen((RawSocketEvent e) {
        if (e == RawSocketEvent.read) {
          final Datagram? d = udp.receive();
          if (d != null) {
            unawaited(_heard(d));
          }
        }
      });
      _beaconTimer = Timer.periodic(beaconEvery, (_) => unawaited(_shout()));
      await _shout();
    } catch (_) {
      // No broadcast on this network; invites still connect directly.
    }
  }

  Future<void> _shout() async {
    final FamilySyncContext? ctx = _ctx;
    final RawDatagramSocket? udp = _beacon;
    if (ctx == null || udp == null) {
      return;
    }
    final String sealed = await ctx.cipher.seal(jsonEncode(<String, Object?>{'d': ctx.deviceId, 'p': listeningPort}));
    try {
      udp.send(utf8.encode(sealed), InternetAddress('255.255.255.255'), beaconPort);
    } catch (_) {}
  }

  Future<void> _heard(Datagram d) async {
    final FamilySyncContext? ctx = _ctx;
    if (ctx == null) {
      return;
    }
    try {
      final Map<String, Object?> b =
          Map<String, Object?>.from(jsonDecode(await ctx.cipher.open(utf8.decode(d.data))) as Map);
      final String device = b['d']! as String;
      final int p = (b['p']! as num).toInt();
      final bool known = _links.any((_Peer l) => l.deviceId == device);
      // Only the lower id dials, so two phones make one link.
      if (!known && device != ctx.deviceId && ctx.deviceId.compareTo(device) < 0) {
        await connect(d.address.address, p);
      }
    } catch (_) {
      // Another family's beacon or noise.
    }
  }

  @override
  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    _beaconTimer?.cancel();
    _beaconTimer = null;
    _beacon?.close();
    _beacon = null;
    for (final _Peer p in _links.toList()) {
      _drop(p);
    }
    await _server?.close();
    _server = null;
    _ctx = null;
    notifyListeners();
  }
}

class _Peer {
  _Peer(this.socket);

  final Socket socket;
  String? deviceId;
  bool closed = false;
  Future<void> inbox = Future<void>.value();
  Future<void> _outbox = Future<void>.value();

  void send(FamilySyncContext ctx, Map<String, Object?> frame) {
    _outbox = _outbox.then((_) async {
      if (closed) {
        return;
      }
      final String sealed = await ctx.cipher.seal(jsonEncode(frame));
      try {
        socket.write('$sealed\n');
      } catch (_) {}
    });
  }

  void sendRecords(FamilySyncContext ctx, List<FamilyRecord> records) {
    if (records.isEmpty) {
      return;
    }
    send(ctx, <String, Object?>{'t': 'recs', 'r': records.map((FamilyRecord r) => r.toJson()).toList()});
  }
}
