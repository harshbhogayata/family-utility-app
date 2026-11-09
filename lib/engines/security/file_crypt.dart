import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

/// Feature 058 — Encrypt any file.
///
/// One portable file per input, readable by the app on any phone:
///
/// ```
/// "FUAENC" (6) · version 1 (1) · kdf 1 = PBKDF2-HMAC-SHA256 (1)
/// iterations (uint32 BE) · salt (16) · nonce (12)
/// AES-256-GCM ciphertext of [name length uint16 BE · name UTF-8 · file bytes]
/// GCM tag (16)
/// ```
///
/// The header is authenticated as associated data, so any change to it, the
/// name or the contents makes decryption fail. The key comes from the
/// password alone; nothing is stored or uploaded.

class FileCryptError implements Exception {
  const FileCryptError(this.message);
  final String message;

  @override
  String toString() => message;
}

/// The password does not open this file (or the file was changed).
class FileCryptWrongPassword extends FileCryptError {
  const FileCryptWrongPassword() : super('Wrong password, or the file was changed after it was locked.');
}

@immutable
class DecryptedFile {
  const DecryptedFile(this.name, this.bytes);
  final String name;
  final Uint8List bytes;
}

abstract final class FileCrypt {
  static const String extension = 'fuaenc';
  static const List<int> magic = <int>[0x46, 0x55, 0x41, 0x45, 0x4E, 0x43]; // FUAENC
  static const int version = 1;
  static const int kdfPbkdf2Sha256 = 1;
  static const int defaultIterations = 210000;
  static const int minPassword = 6;
  static const int headerLength = 6 + 1 + 1 + 4 + 16 + 12;
  static const int tagLength = 16;

  static final Random _random = Random.secure();

  static bool isEncrypted(Uint8List bytes) {
    if (bytes.length < headerLength + tagLength) {
      return false;
    }
    for (int i = 0; i < magic.length; i++) {
      if (bytes[i] != magic[i]) {
        return false;
      }
    }
    return true;
  }

  /// Why [password] is not good enough, or null.
  static String? passwordProblem(String password, String confirm) {
    if (password.length < minPassword) {
      return 'Use at least $minPassword characters';
    }
    if (password != confirm) {
      return 'The two passwords differ';
    }
    return null;
  }

  /// The name the locked copy gets.
  static String lockedName(String name) => '$name.$extension';

  static Future<SecretKey> _key(String password, List<int> salt, int iterations) {
    return Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: iterations, bits: 256)
        .deriveKeyFromPassword(password: password, nonce: salt);
  }

  static Future<Uint8List> encrypt(
    Uint8List data,
    String name,
    String password, {
    int iterations = defaultIterations,
    List<int>? salt,
    List<int>? nonce,
  }) async {
    if (password.length < minPassword) {
      throw const FileCryptError('Use at least $minPassword characters');
    }
    final List<int> s = salt ?? List<int>.generate(16, (int _) => _random.nextInt(256));
    final List<int> n = nonce ?? List<int>.generate(12, (int _) => _random.nextInt(256));
    final ByteData head = ByteData(headerLength);
    for (int i = 0; i < magic.length; i++) {
      head.setUint8(i, magic[i]);
    }
    head.setUint8(6, version);
    head.setUint8(7, kdfPbkdf2Sha256);
    head.setUint32(8, iterations);
    final Uint8List header = head.buffer.asUint8List();
    header.setRange(12, 28, s);
    header.setRange(28, 40, n);

    final List<int> nameBytes = utf8.encode(name);
    final int nameLen = min(nameBytes.length, 0xFFFF);
    final BytesBuilder plain = BytesBuilder(copy: false)
      ..addByte(nameLen >> 8)
      ..addByte(nameLen & 0xFF)
      ..add(nameBytes.sublist(0, nameLen))
      ..add(data);
    final SecretBox box = await AesGcm.with256bits().encrypt(
      plain.takeBytes(),
      secretKey: await _key(password, s, iterations),
      nonce: n,
      aad: header,
    );
    return (BytesBuilder(copy: false)
          ..add(header)
          ..add(box.cipherText)
          ..add(box.mac.bytes))
        .takeBytes();
  }

  static Future<DecryptedFile> decrypt(Uint8List blob, String password) async {
    if (!isEncrypted(blob)) {
      throw const FileCryptError('This file was not locked by this app.');
    }
    final ByteData head = ByteData.sublistView(blob, 0, headerLength);
    if (head.getUint8(6) != version || head.getUint8(7) != kdfPbkdf2Sha256) {
      throw const FileCryptError('This locked file needs a newer version of the app.');
    }
    final int iterations = head.getUint32(8);
    if (iterations < 1000 || iterations > 10000000) {
      throw const FileCryptError('This locked file is damaged.');
    }
    final Uint8List header = Uint8List.sublistView(blob, 0, headerLength);
    final SecretBox box = SecretBox(
      Uint8List.sublistView(blob, headerLength, blob.length - tagLength),
      nonce: Uint8List.sublistView(blob, 28, 40),
      mac: Mac(Uint8List.sublistView(blob, blob.length - tagLength)),
    );
    final List<int> clear;
    try {
      clear = await AesGcm.with256bits().decrypt(
        box,
        secretKey: await _key(password, Uint8List.sublistView(blob, 12, 28), iterations),
        aad: header,
      );
    } on SecretBoxAuthenticationError {
      throw const FileCryptWrongPassword();
    }
    if (clear.length < 2) {
      throw const FileCryptError('This locked file is damaged.');
    }
    final int nameLen = (clear[0] << 8) | clear[1];
    if (2 + nameLen > clear.length) {
      throw const FileCryptError('This locked file is damaged.');
    }
    final String name = utf8.decode(clear.sublist(2, 2 + nameLen), allowMalformed: true);
    return DecryptedFile(_safeName(name), Uint8List.fromList(clear.sublist(2 + nameLen)));
  }

  /// A plain file name: no folders, never empty.
  static String _safeName(String name) {
    final String base = name.split(RegExp(r'[\\/]')).last.trim();
    return base.isEmpty || base == '.' || base == '..' ? 'unlocked file' : base;
  }
}
