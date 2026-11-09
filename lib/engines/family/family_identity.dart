import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

/// Feature 068 — who this phone is inside which family, and the invite QR.

String randomId([int bytes = 12]) {
  final Random r = Random.secure();
  return base64Url.encode(List<int>.generate(bytes, (int _) => r.nextInt(256))).replaceAll('=', '');
}

@immutable
class FamilyIdentity {
  const FamilyIdentity({
    required this.familyId,
    required this.familyName,
    required this.secret,
    required this.deviceId,
    required this.memberName,
    this.syncFolder,
  });

  /// A new family with a fresh 256-bit key.
  factory FamilyIdentity.create({required String familyName, required String memberName}) {
    final Random r = Random.secure();
    return FamilyIdentity(
      familyId: randomId(),
      familyName: familyName,
      secret: Uint8List.fromList(List<int>.generate(32, (int _) => r.nextInt(256))),
      deviceId: randomId(8),
      memberName: memberName,
    );
  }

  /// This phone joining the family an invite describes.
  factory FamilyIdentity.join(FamilyInvite invite, {required String memberName}) => FamilyIdentity(
        familyId: invite.familyId,
        familyName: invite.familyName,
        secret: invite.secret,
        deviceId: randomId(8),
        memberName: memberName,
      );

  final String familyId;
  final String familyName;

  /// Shared family key: encrypts every frame on Wi-Fi and every change file.
  final Uint8List secret;
  final String deviceId;
  final String memberName;

  /// Own-cloud folder (Drive, iCloud, Syncthing...) the person picked, if any.
  final String? syncFolder;

  FamilyIdentity withSyncFolder(String? folder) => FamilyIdentity(
        familyId: familyId,
        familyName: familyName,
        secret: secret,
        deviceId: deviceId,
        memberName: memberName,
        syncFolder: folder,
      );

  FamilyInvite invite({List<String> hosts = const <String>[], int? port}) =>
      FamilyInvite(familyId: familyId, familyName: familyName, secret: secret, hosts: hosts, port: port);

  Map<String, Object?> toJson() => <String, Object?>{
        'familyId': familyId,
        'familyName': familyName,
        'secret': base64Url.encode(secret),
        'deviceId': deviceId,
        'memberName': memberName,
        if (syncFolder != null) 'syncFolder': syncFolder,
      };

  static FamilyIdentity fromJson(Map<String, Object?> j) => FamilyIdentity(
        familyId: j['familyId']! as String,
        familyName: j['familyName']! as String,
        secret: Uint8List.fromList(base64Url.decode(j['secret']! as String)),
        deviceId: j['deviceId']! as String,
        memberName: j['memberName'] as String? ?? 'Member',
        syncFolder: j['syncFolder'] as String?,
      );
}

/// What the invite QR carries: the family, its key and where the inviting
/// phone listens on the home Wi-Fi.
@immutable
class FamilyInvite {
  const FamilyInvite({
    required this.familyId,
    required this.familyName,
    required this.secret,
    this.hosts = const <String>[],
    this.port,
  });

  static const String prefix = 'famspace:1:';

  final String familyId;
  final String familyName;
  final Uint8List secret;
  final List<String> hosts;
  final int? port;

  String encode() => prefix +
      base64Url.encode(utf8.encode(jsonEncode(<String, Object?>{
        'f': familyId,
        'n': familyName,
        'k': base64Url.encode(secret),
        if (hosts.isNotEmpty) 'h': hosts,
        if (port != null) 'p': port,
      })));

  /// Null when [text] is not a family invite.
  static FamilyInvite? parse(String text) {
    final String t = text.trim();
    if (!t.startsWith(prefix)) {
      return null;
    }
    try {
      final Object? j = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(t.substring(prefix.length)))));
      if (j is! Map) {
        return null;
      }
      final Uint8List key = Uint8List.fromList(base64Url.decode(j['k'] as String));
      if (key.length != 32 || (j['f'] as String).isEmpty) {
        return null;
      }
      final Object? h = j['h'];
      return FamilyInvite(
        familyId: j['f'] as String,
        familyName: j['n'] as String? ?? 'Family',
        secret: key,
        hosts: h is List ? h.whereType<String>().toList() : const <String>[],
        port: (j['p'] as num?)?.toInt(),
      );
    } catch (_) {
      return null;
    }
  }
}

/// AES-256-GCM with the family key. One sealed blob per frame or file.
class FamilyCipher {
  FamilyCipher(List<int> secret) : _key = SecretKey(secret);

  final SecretKey _key;
  final AesGcm _aes = AesGcm.with256bits();

  /// nonce (12) + ciphertext + mac (16), base64url.
  Future<String> seal(String plain) async {
    final SecretBox box = await _aes.encrypt(utf8.encode(plain), secretKey: _key);
    return base64Url.encode(box.concatenation());
  }

  /// Throws when the blob was not sealed with this family's key.
  Future<String> open(String sealed) async {
    final SecretBox box = SecretBox.fromConcatenation(
      base64Url.decode(sealed.trim()),
      nonceLength: 12,
      macLength: 16,
    );
    return utf8.decode(await _aes.decrypt(box, secretKey: _key));
  }
}

abstract class FamilyIdentityStore {
  Future<FamilyIdentity?> read();
  Future<void> write(FamilyIdentity? identity);
}

class MemoryFamilyIdentityStore implements FamilyIdentityStore {
  MemoryFamilyIdentityStore([this.value]);
  FamilyIdentity? value;

  @override
  Future<FamilyIdentity?> read() async => value;

  @override
  Future<void> write(FamilyIdentity? identity) async => value = identity;
}

/// Kept in the app's private folder next to the store.
class FileFamilyIdentityStore implements FamilyIdentityStore {
  FileFamilyIdentityStore(this.folder);

  final Future<Directory> Function() folder;

  Future<File> _file() async => File('${(await folder()).path}/family_identity.json');

  @override
  Future<FamilyIdentity?> read() async {
    final File f = await _file();
    if (!f.existsSync()) {
      return null;
    }
    return FamilyIdentity.fromJson(Map<String, Object?>.from(jsonDecode(await f.readAsString()) as Map));
  }

  @override
  Future<void> write(FamilyIdentity? identity) async {
    final File f = await _file();
    if (identity == null) {
      if (f.existsSync()) {
        await f.delete();
      }
      return;
    }
    await f.parent.create(recursive: true);
    await f.writeAsString(jsonEncode(identity.toJson()));
  }
}
