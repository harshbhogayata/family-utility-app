import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'lan_transfer.dart';

/// Feature 061 — Nearby share: phone to phone with no internet.
///
/// Family phones on the same Wi-Fi (or one phone's hotspot, no internet
/// needed) find each other by name and send files straight across. The
/// receiver keeps a partial file per transfer, so a dropped link resumes
/// from the byte it reached instead of starting again. The socket side
/// lives in lib/platform/network/; this file is the part that needs none.

@immutable
class NearbyDevice {
  const NearbyDevice({required this.deviceId, required this.name, required this.host, required this.port});

  final String deviceId;
  final String name;
  final String host;
  final int port;
}

/// What the sender announces before the bytes.
@immutable
class NearbyOffer {
  const NearbyOffer({required this.transferId, required this.name, required this.size, required this.from});

  /// Same id on every retry, so the receiver can resume.
  final String transferId;
  final String name;
  final int size;

  /// Sender's member name, shown on the receiving phone.
  final String from;

  Map<String, Object?> toJson() => <String, Object?>{'id': transferId, 'name': name, 'size': size, 'from': from};

  static NearbyOffer fromJson(Map<String, Object?> j) => NearbyOffer(
        transferId: SafeNames.clean(j['id']! as String),
        name: SafeNames.clean(j['name']! as String),
        size: (j['size']! as num).toInt(),
        from: j['from'] as String? ?? '',
      );
}

@immutable
class NearbyReceived {
  const NearbyReceived({required this.path, required this.from, required this.size});
  final String path;
  final String from;
  final int size;
}

@immutable
class NearbySendResult {
  const NearbySendResult({required this.bytes, required this.attempts, required this.resumedFrom, required this.elapsed});

  final int bytes;
  final int attempts;

  /// Offset each attempt started from; more than one entry means it resumed.
  final List<int> resumedFrom;
  final Duration elapsed;

  double get megabytesPerSecond =>
      elapsed.inMicroseconds == 0 ? 0 : bytes / (1024 * 1024) / (elapsed.inMicroseconds / 1e6);
}

/// Partial and finished files on the receiving phone.
class NearbyInbox {
  NearbyInbox(this.folder);

  final Directory folder;

  File partFile(NearbyOffer offer) => File('${folder.path}/.${offer.transferId}.part');

  /// Where to resume [offer] from: the bytes already here.
  Future<int> offsetFor(NearbyOffer offer) async {
    final File p = partFile(offer);
    if (!p.existsSync()) {
      return 0;
    }
    final int have = await p.length();
    if (have > offer.size) {
      await p.delete();
      return 0;
    }
    return have;
  }

  /// Moves a complete part file to its real name. Null if still short.
  Future<String?> finish(NearbyOffer offer) async {
    final File p = partFile(offer);
    if (!p.existsSync() || await p.length() != offer.size) {
      return null;
    }
    final String target = '${folder.path}/${SafeNames.unique(folder, offer.name)}';
    await p.rename(target);
    return target;
  }
}

/// One newline-terminated JSON line.
List<int> nearbyLine(Map<String, Object?> json) => utf8.encode('${jsonEncode(json)}\n');
