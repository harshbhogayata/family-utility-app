import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../../engines/family/family_identity.dart';
import '../../engines/transfer/nearby_share.dart';

/// Feature 061 — the socket side of Nearby share.
///
/// Family phones shout a sealed UDP beacon with their member name and port;
/// only phones holding the family key can read it, so the list shows family
/// devices by name and nobody else. A transfer is one TCP connection:
/// a sealed header line (the offer), the receiver's reply with the offset it
/// already has, then the raw bytes from there at full Wi-Fi speed. If the
/// link drops the sender reconnects and the receiver answers with the new
/// offset, so the file resumes. Nothing touches the internet.
class NearbyShareService extends ChangeNotifier {
  NearbyShareService({
    required this.identity,
    required this.inbox,
    this.port = 47830,
    this.discovery = true,
    this.beaconPort = 47831,
    this.beaconEvery = const Duration(seconds: 2),
    this.bindAddress,
  }) : _cipher = FamilyCipher(identity.secret);

  final FamilyIdentity identity;
  final NearbyInbox inbox;
  final int port;
  final bool discovery;
  final int beaconPort;
  final Duration beaconEvery;
  final InternetAddress? bindAddress;
  final FamilyCipher _cipher;

  ServerSocket? _server;
  RawDatagramSocket? _udp;
  Timer? _beacon;
  final Map<String, NearbyDevice> _devices = <String, NearbyDevice>{};
  final List<NearbyReceived> received = <NearbyReceived>[];

  /// Bytes received so far per incoming transfer id (for progress).
  final Map<String, int> incoming = <String, int>{};

  /// One link per transfer at a time: a resumed link waits for the dropped
  /// one to finish writing before it reads the offset.
  final Map<String, Future<void>> _writing = <String, Future<void>>{};

  int get listeningPort => _server?.port ?? 0;

  List<NearbyDevice> get devices => _devices.values.toList()..sort((NearbyDevice a, NearbyDevice b) => a.name.compareTo(b.name));

  Future<void> start() async {
    final InternetAddress addr = bindAddress ?? InternetAddress.anyIPv4;
    try {
      _server = await ServerSocket.bind(addr, port);
    } on SocketException {
      _server = await ServerSocket.bind(addr, 0);
    }
    _server!.listen(_accept, onError: (Object _) {});
    if (discovery) {
      try {
        final RawDatagramSocket udp = await RawDatagramSocket.bind(InternetAddress.anyIPv4, beaconPort, reuseAddress: true);
        udp.broadcastEnabled = true;
        _udp = udp;
        udp.listen((RawSocketEvent e) {
          final Datagram? d = e == RawSocketEvent.read ? udp.receive() : null;
          if (d != null) {
            unawaited(_heard(d));
          }
        });
        _beacon = Timer.periodic(beaconEvery, (_) => unawaited(_shout()));
        await _shout();
      } catch (_) {
        // No broadcast here; devices can still be added by address.
      }
    }
  }

  Future<void> stop() async {
    _beacon?.cancel();
    _udp?.close();
    _udp = null;
    await _server?.close();
    _server = null;
  }

  /// Adds a device by address (also what the beacon does).
  void addDevice(NearbyDevice d) {
    if (d.deviceId == identity.deviceId) {
      return;
    }
    _devices[d.deviceId] = d;
    notifyListeners();
  }

  Future<void> _shout() async {
    final RawDatagramSocket? udp = _udp;
    if (udp == null) {
      return;
    }
    final String sealed = await _cipher.seal(jsonEncode(<String, Object?>{
      'd': identity.deviceId,
      'n': identity.memberName,
      'p': listeningPort,
    }));
    try {
      udp.send(utf8.encode(sealed), InternetAddress('255.255.255.255'), beaconPort);
    } catch (_) {}
  }

  Future<void> _heard(Datagram d) async {
    try {
      final Map<String, Object?> b = Map<String, Object?>.from(jsonDecode(await _cipher.open(utf8.decode(d.data))) as Map);
      addDevice(NearbyDevice(
        deviceId: b['d']! as String,
        name: b['n'] as String? ?? 'Family phone',
        host: d.address.address,
        port: (b['p']! as num).toInt(),
      ));
    } catch (_) {
      // Not our family.
    }
  }

  // ---- receiving ------------------------------------------------------------

  void _accept(Socket socket) {
    final BytesBuilder head = BytesBuilder(copy: false);
    NearbyOffer? offer;
    IOSink? sink;
    int have = 0;
    bool closed = false;
    final Completer<void> finished = Completer<void>();
    Future<void> chain = Future<void>.value();
    late final StreamSubscription<Uint8List> sub;

    Future<void> close() async {
      if (closed) {
        return;
      }
      closed = true;
      await sink?.flush();
      await sink?.close();
      final NearbyOffer? o = offer;
      if (o != null) {
        final String? path = await inbox.finish(o);
        if (path != null) {
          incoming.remove(o.transferId);
          received.add(NearbyReceived(path: path, from: o.from, size: o.size));
          try {
            socket.add(nearbyLine(<String, Object?>{'done': true}));
            await socket.flush();
          } catch (_) {}
        }
        notifyListeners();
      }
      socket.destroy();
      if (!finished.isCompleted) {
        finished.complete();
      }
    }

    Future<void> onBytes(Uint8List data) async {
      if (closed) {
        return;
      }
      if (offer == null) {
        head.add(data);
        final Uint8List all = head.takeBytes();
        final int nl = all.indexOf(10);
        if (nl < 0) {
          if (all.length > 64 * 1024) {
            await close();
          } else {
            head.add(all);
          }
          return;
        }
        try {
          final String line = utf8.decode(all.sublist(0, nl));
          final NearbyOffer o =
              NearbyOffer.fromJson(Map<String, Object?>.from(jsonDecode(await _cipher.open(line)) as Map));
          await inbox.folder.create(recursive: true);
          final Future<void>? previous = _writing[o.transferId];
          _writing[o.transferId] = finished.future;
          if (previous != null) {
            await previous.timeout(const Duration(seconds: 10), onTimeout: () {});
          }
          have = await inbox.offsetFor(o);
          offer = o;
          sink = inbox.partFile(o).openWrite(mode: FileMode.append);
          socket.add(nearbyLine(<String, Object?>{'offset': have}));
          await socket.flush();
        } catch (_) {
          await close(); // wrong key or garbage
          return;
        }
        data = all.sublist(nl + 1);
        if (data.isEmpty) {
          if (have >= offer!.size) {
            await close();
          }
          return;
        }
      }
      final NearbyOffer o = offer!;
      final int room = o.size - have;
      final Uint8List part = data.length > room ? data.sublist(0, room) : data;
      sink!.add(part);
      have += part.length;
      incoming[o.transferId] = have;
      if (have >= o.size) {
        await close();
      }
    }

    sub = socket.listen(
      (Uint8List data) {
        sub.pause();
        chain = chain.then((_) => onBytes(data)).catchError((Object _) => close()).whenComplete(sub.resume);
      },
      onDone: () => chain = chain.then((_) => close()),
      onError: (Object _) => chain = chain.then((_) => close()),
      cancelOnError: true,
    );
  }

  // ---- sending --------------------------------------------------------------

  /// Sends [path] to [to], resuming after drops, up to [maxAttempts] links.
  /// [dropAfterBytes] cuts each link after that many bytes (tests only).
  Future<NearbySendResult> send(
    NearbyDevice to,
    String path, {
    void Function(int sent, int total)? onProgress,
    int maxAttempts = 6,
    int? dropAfterBytes,
  }) async {
    final File file = File(path);
    final int size = await file.length();
    final NearbyOffer offer = NearbyOffer(
      transferId: '${identity.deviceId}-${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 30)}'
          .replaceAll(RegExp(r'[^\w\-]'), '_'),
      name: path.split(Platform.pathSeparator).last,
      size: size,
      from: identity.memberName,
    );
    final String header = await _cipher.seal(jsonEncode(offer.toJson()));
    final Stopwatch sw = Stopwatch()..start();
    final List<int> starts = <int>[];
    Object? lastError;
    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      Socket? s;
      try {
        s = await Socket.connect(to.host, to.port, timeout: const Duration(seconds: 5));
        s.setOption(SocketOption.tcpNoDelay, true);
        final _Lines lines = _Lines(s);
        s.add(utf8.encode('$header\n'));
        final Map<String, Object?> reply = await lines.next().timeout(const Duration(seconds: 10));
        final int offset = (reply['offset']! as num).toInt();
        starts.add(offset);
        final int end = dropAfterBytes == null ? size : min(size, offset + dropAfterBytes);
        int sent = offset;
        await s.addStream(file.openRead(offset, end).map((List<int> chunk) {
          sent += chunk.length;
          onProgress?.call(sent, size);
          return chunk;
        }));
        await s.flush();
        if (end < size) {
          s.destroy(); // simulated drop
          await Future<void>.delayed(const Duration(milliseconds: 50));
          continue;
        }
        final Map<String, Object?> done = await lines.next().timeout(const Duration(seconds: 30));
        s.destroy();
        if (done['done'] == true) {
          return NearbySendResult(bytes: size, attempts: attempt, resumedFrom: starts, elapsed: sw.elapsed);
        }
      } catch (e) {
        lastError = e;
        s?.destroy();
        await Future<void>.delayed(Duration(milliseconds: 200 * attempt));
      }
    }
    throw NearbyShareException('Could not finish sending after $maxAttempts tries ($lastError)');
  }
}

class NearbyShareException implements Exception {
  NearbyShareException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Reads JSON lines from a socket.
class _Lines {
  _Lines(Socket s) {
    s.listen((Uint8List d) {
      _buf.addAll(d);
      _drain();
    }, onDone: () {
      for (final Completer<Map<String, Object?>> c in _waiting) {
        c.completeError(const SocketException('closed'));
      }
      _waiting.clear();
    }, onError: (Object _) {}, cancelOnError: false);
  }

  final List<int> _buf = <int>[];
  final List<Map<String, Object?>> _ready = <Map<String, Object?>>[];
  final List<Completer<Map<String, Object?>>> _waiting = <Completer<Map<String, Object?>>>[];

  void _drain() {
    int nl;
    while ((nl = _buf.indexOf(10)) >= 0) {
      final String line = utf8.decode(_buf.sublist(0, nl));
      _buf.removeRange(0, nl + 1);
      Map<String, Object?> m;
      try {
        m = Map<String, Object?>.from(jsonDecode(line) as Map);
      } catch (_) {
        continue;
      }
      if (_waiting.isNotEmpty) {
        _waiting.removeAt(0).complete(m);
      } else {
        _ready.add(m);
      }
    }
  }

  Future<Map<String, Object?>> next() {
    if (_ready.isNotEmpty) {
      return Future<Map<String, Object?>>.value(_ready.removeAt(0));
    }
    final Completer<Map<String, Object?>> c = Completer<Map<String, Object?>>();
    _waiting.add(c);
    return c.future;
  }
}
