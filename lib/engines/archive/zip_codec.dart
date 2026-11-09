import 'dart:convert';
import 'dart:io' show ZLibDecoder, ZLibEncoder;
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// Feature 029 — Archives: a small, pure-Dart ZIP reader and writer.
///
/// Reads stored and deflated entries, including WinZip AES (AE-1 and AE-2)
/// encrypted ones, and writes ZIPs with an optional AES-256 password.
/// Nothing leaves the phone.

/// Why an archive could not be read.
class ArchiveException implements Exception {
  const ArchiveException(this.message, {this.needsPassword = false, this.wrongPassword = false});

  final String message;
  final bool needsPassword;
  final bool wrongPassword;

  @override
  String toString() => 'ArchiveException: $message';
}

/// One file or folder inside a ZIP, read from the central directory only.
class ZipEntry {
  const ZipEntry({
    required this.name,
    required this.size,
    required this.compressedSize,
    required this.method,
    required this.encrypted,
    required this.crc32,
    required this.localHeaderOffset,
    required this.modified,
    this.aesStrength = 0,
    this.aesVendorVersion = 0,
    this.actualMethod = 0,
  });

  final String name;
  final int size;
  final int compressedSize;
  final int method;
  final bool encrypted;
  final int crc32;
  final int localHeaderOffset;
  final DateTime modified;

  /// 1, 2 or 3 for AES-128, 192 or 256; 0 when not AES.
  final int aesStrength;
  final int aesVendorVersion;

  /// The compression method under the AES layer (0 store, 8 deflate).
  final int actualMethod;

  bool get isDirectory => name.endsWith('/');
  bool get isAes => method == 99;
}

/// A file to put into a new ZIP.
class ZipInput {
  const ZipInput(this.name, this.bytes, {this.modified});

  final String name;
  final List<int> bytes;
  final DateTime? modified;
}

/// CRC-32 (IEEE), as ZIP uses it.
class Crc32 {
  Crc32._();

  static final List<int> _table = List<int>.generate(256, (int n) {
    int c = n;
    for (int k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
    }
    return c;
  });

  static int of(List<int> data) {
    int crc = 0xFFFFFFFF;
    for (final int b in data) {
      crc = _table[(crc ^ b) & 0xFF] ^ (crc >> 8);
    }
    return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
  }
}

/// WinZip AES: PBKDF2-HMAC-SHA1 keys, AES in CTR mode with a little-endian
/// counter starting at 1, and a 10-byte HMAC-SHA1 over the ciphertext.
class WinZipAes {
  WinZipAes._();

  static int saltLength(int strength) => 4 + 4 * strength;
  static int keyLength(int strength) => 8 + 8 * strength;

  static Uint8List deriveKeys(String password, Uint8List salt, int strength) {
    final int keyLen = keyLength(strength);
    final PBKDF2KeyDerivator kdf = PBKDF2KeyDerivator(HMac(SHA1Digest(), 64))
      ..init(Pbkdf2Parameters(salt, 1000, keyLen * 2 + 2));
    return kdf.process(Uint8List.fromList(utf8.encode(password)));
  }

  static Uint8List ctr(Uint8List key, Uint8List data) {
    final AESEngine aes = AESEngine()..init(true, KeyParameter(key));
    final Uint8List out = Uint8List(data.length);
    final Uint8List counter = Uint8List(16);
    final Uint8List stream = Uint8List(16);
    for (int off = 0; off < data.length; off += 16) {
      // Increment the 128-bit little-endian counter (first block uses 1).
      for (int i = 0; i < 16; i++) {
        counter[i] = (counter[i] + 1) & 0xFF;
        if (counter[i] != 0) {
          break;
        }
      }
      aes.processBlock(counter, 0, stream, 0);
      final int end = min(off + 16, data.length);
      for (int i = off; i < end; i++) {
        out[i] = data[i] ^ stream[i - off];
      }
    }
    return out;
  }

  static Uint8List mac(Uint8List key, Uint8List data) {
    final HMac h = HMac(SHA1Digest(), 64)..init(KeyParameter(key));
    final Uint8List full = Uint8List(20);
    h.update(data, 0, data.length);
    h.doFinal(full, 0);
    return Uint8List.sublistView(full, 0, 10);
  }
}

class _Reader {
  _Reader(this.bytes) : data = ByteData.sublistView(bytes);

  final Uint8List bytes;
  final ByteData data;

  int u16(int at) => data.getUint16(at, Endian.little);
  int u32(int at) => data.getUint32(at, Endian.little);
}

DateTime _fromDos(int date, int time) {
  final int year = 1980 + ((date >> 9) & 0x7F);
  final int month = max(1, (date >> 5) & 0x0F);
  final int day = max(1, date & 0x1F);
  return DateTime(year, month, day, (time >> 11) & 0x1F, (time >> 5) & 0x3F, (time & 0x1F) * 2);
}

int _dosDate(DateTime t) {
  final int y = t.year < 1980 ? 0 : t.year - 1980;
  return (y << 9) | (t.month << 5) | t.day;
}

int _dosTime(DateTime t) => (t.hour << 11) | (t.minute << 5) | (t.second ~/ 2);

/// Reads the table of contents and individual entries of a ZIP in memory.
class ZipReader {
  ZipReader(Uint8List bytes) : _r = _Reader(bytes) {
    _entries = _readCentralDirectory();
  }

  final _Reader _r;
  late final List<ZipEntry> _entries;

  /// Every entry, without extracting anything.
  List<ZipEntry> get entries => List<ZipEntry>.unmodifiable(_entries);

  bool get anyEncrypted => _entries.any((ZipEntry e) => e.encrypted);

  List<ZipEntry> _readCentralDirectory() {
    final Uint8List b = _r.bytes;
    int eocd = -1;
    final int stop = max(0, b.length - 22 - 0xFFFF);
    for (int i = b.length - 22; i >= stop; i--) {
      if (b[i] == 0x50 && b[i + 1] == 0x4B && b[i + 2] == 0x05 && b[i + 3] == 0x06) {
        eocd = i;
        break;
      }
    }
    if (eocd < 0) {
      throw const ArchiveException('This is not a ZIP file, or it is damaged.');
    }
    final int count = _r.u16(eocd + 10);
    int p = _r.u32(eocd + 16);
    final List<ZipEntry> out = <ZipEntry>[];
    for (int n = 0; n < count; n++) {
      if (p + 46 > b.length || _r.u32(p) != 0x02014B50) {
        throw const ArchiveException('The ZIP table of contents is damaged.');
      }
      final int flags = _r.u16(p + 8);
      final int method = _r.u16(p + 10);
      final int time = _r.u16(p + 12);
      final int date = _r.u16(p + 14);
      final int crc = _r.u32(p + 16);
      final int csize = _r.u32(p + 20);
      final int usize = _r.u32(p + 24);
      final int nameLen = _r.u16(p + 28);
      final int extraLen = _r.u16(p + 30);
      final int commentLen = _r.u16(p + 32);
      final int offset = _r.u32(p + 42);
      final Uint8List rawName = Uint8List.sublistView(b, p + 46, p + 46 + nameLen);
      final String name = (flags & 0x800) != 0
          ? utf8.decode(rawName, allowMalformed: true)
          : latin1.decode(rawName);
      int strength = 0;
      int vendor = 0;
      int actual = method;
      int x = p + 46 + nameLen;
      final int xEnd = x + extraLen;
      while (x + 4 <= xEnd) {
        final int id = _r.u16(x);
        final int len = _r.u16(x + 2);
        if (id == 0x9901 && len >= 7) {
          vendor = _r.u16(x + 4);
          strength = b[x + 8];
          actual = _r.u16(x + 9);
        }
        x += 4 + len;
      }
      out.add(ZipEntry(
        name: name,
        size: usize,
        compressedSize: csize,
        method: method,
        encrypted: (flags & 1) != 0,
        crc32: crc,
        localHeaderOffset: offset,
        modified: _fromDos(date, time),
        aesStrength: strength,
        aesVendorVersion: vendor,
        actualMethod: actual,
      ));
      p = xEnd + commentLen;
    }
    return out;
  }

  ZipEntry? find(String name) {
    for (final ZipEntry e in _entries) {
      if (e.name == name) {
        return e;
      }
    }
    return null;
  }

  /// The bytes of one entry. Throws [ArchiveException] for a missing or
  /// wrong password, an unsupported method, or damaged data.
  Uint8List extract(ZipEntry e, {String? password}) {
    if (e.isDirectory) {
      return Uint8List(0);
    }
    final int p = e.localHeaderOffset;
    if (p + 30 > _r.bytes.length || _r.u32(p) != 0x04034B50) {
      throw ArchiveException('${e.name} is damaged.');
    }
    final int start = p + 30 + _r.u16(p + 26) + _r.u16(p + 28);
    if (start + e.compressedSize > _r.bytes.length) {
      throw ArchiveException('${e.name} is cut short.');
    }
    Uint8List payload = Uint8List.sublistView(_r.bytes, start, start + e.compressedSize);
    int method = e.method;
    if (e.encrypted) {
      if (!e.isAes) {
        throw ArchiveException(
            '${e.name} uses the old ZIP password scheme, which is not safe and not supported. Re-zip it with AES.');
      }
      if (password == null || password.isEmpty) {
        throw ArchiveException('${e.name} is locked. Enter the password.', needsPassword: true);
      }
      payload = _decryptAes(e, payload, password);
      method = e.actualMethod;
    }
    final Uint8List out = _inflate(e, method, payload);
    final bool checkCrc = !e.isAes || e.aesVendorVersion == 1 || e.crc32 != 0;
    if (checkCrc && Crc32.of(out) != e.crc32) {
      throw ArchiveException('${e.name} failed its checksum: the file is damaged.');
    }
    return out;
  }

  static Uint8List _inflate(ZipEntry e, int method, Uint8List payload) {
    if (method == 0) {
      return Uint8List.fromList(payload);
    }
    if (method != 8) {
      throw ArchiveException('${e.name} uses a compression method (#$method) this app cannot open yet.');
    }
    try {
      return Uint8List.fromList(ZLibDecoder(raw: true).convert(payload));
    } on ArchiveException {
      rethrow;
    } catch (_) {
      throw ArchiveException('${e.name} is damaged.');
    }
  }

  Uint8List _decryptAes(ZipEntry e, Uint8List payload, String password) {
    final int s = e.aesStrength;
    if (s < 1 || s > 3) {
      throw ArchiveException('${e.name} has an unknown AES setting.');
    }
    final int saltLen = WinZipAes.saltLength(s);
    final int keyLen = WinZipAes.keyLength(s);
    if (payload.length < saltLen + 2 + 10) {
      throw ArchiveException('${e.name} is damaged.');
    }
    final Uint8List salt = Uint8List.fromList(payload.sublist(0, saltLen));
    final Uint8List keys = WinZipAes.deriveKeys(password, salt, s);
    if (keys[keyLen * 2] != payload[saltLen] || keys[keyLen * 2 + 1] != payload[saltLen + 1]) {
      throw ArchiveException('Wrong password for ${e.name}.', needsPassword: true, wrongPassword: true);
    }
    final Uint8List cipher = Uint8List.fromList(payload.sublist(saltLen + 2, payload.length - 10));
    final Uint8List tag = WinZipAes.mac(Uint8List.fromList(keys.sublist(keyLen, keyLen * 2)), cipher);
    final Uint8List stored = Uint8List.sublistView(payload, payload.length - 10);
    for (int i = 0; i < 10; i++) {
      if (tag[i] != stored[i]) {
        throw ArchiveException('${e.name} was changed or damaged after it was locked.');
      }
    }
    return WinZipAes.ctr(Uint8List.fromList(keys.sublist(0, keyLen)), cipher);
  }
}

/// Builds a ZIP in memory. With a password every file is AES-256 (AE-2).
class ZipWriter {
  ZipWriter({Random? random}) : _random = random ?? Random.secure();

  final Random _random;

  Uint8List build(List<ZipInput> files, {String? password, DateTime? now}) {
    final bool lock = password != null && password.isNotEmpty;
    final BytesBuilder out = BytesBuilder(copy: false);
    final BytesBuilder central = BytesBuilder(copy: false);
    final DateTime stamp = now ?? DateTime.now();
    final Set<String> seen = <String>{};
    int count = 0;
    for (final ZipInput f in files) {
      final String name = f.name.replaceAll('\\', '/');
      if (name.isEmpty || !seen.add(name)) {
        continue;
      }
      final bool dir = name.endsWith('/');
      final Uint8List raw = Uint8List.fromList(f.bytes);
      final int crc = Crc32.of(raw);
      int method = 0;
      Uint8List body = raw;
      if (!dir && raw.isNotEmpty) {
        final Uint8List deflated = Uint8List.fromList(ZLibEncoder(raw: true, level: 6).convert(raw));
        if (deflated.length < raw.length) {
          method = 8;
          body = deflated;
        }
      }
      Uint8List extra = Uint8List(0);
      int headerMethod = method;
      int flags = 0x800;
      int headerCrc = crc;
      if (lock && !dir) {
        const int strength = 3;
        final Uint8List salt = Uint8List(WinZipAes.saltLength(strength));
        for (int i = 0; i < salt.length; i++) {
          salt[i] = _random.nextInt(256);
        }
        final Uint8List keys = WinZipAes.deriveKeys(password, salt, strength);
        final Uint8List cipher = WinZipAes.ctr(Uint8List.fromList(keys.sublist(0, 32)), body);
        final Uint8List tag = WinZipAes.mac(Uint8List.fromList(keys.sublist(32, 64)), cipher);
        body = Uint8List.fromList(<int>[...salt, keys[64], keys[65], ...cipher, ...tag]);
        extra = Uint8List.fromList(<int>[
          0x01, 0x99, 7, 0, // header id 0x9901, size 7
          2, 0, // AE-2
          0x41, 0x45, // "AE"
          strength,
          method & 0xFF, method >> 8,
        ]);
        headerMethod = 99;
        flags |= 1;
        headerCrc = 0; // AE-2 leaves the CRC out; the HMAC protects the data.
      }
      final Uint8List nameBytes = Uint8List.fromList(utf8.encode(name));
      final DateTime t = f.modified ?? stamp;
      final int offset = out.length;
      final ByteData local = ByteData(30)
        ..setUint32(0, 0x04034B50, Endian.little)
        ..setUint16(4, lock && !dir ? 51 : 20, Endian.little)
        ..setUint16(6, flags, Endian.little)
        ..setUint16(8, headerMethod, Endian.little)
        ..setUint16(10, _dosTime(t), Endian.little)
        ..setUint16(12, _dosDate(t), Endian.little)
        ..setUint32(14, headerCrc, Endian.little)
        ..setUint32(18, body.length, Endian.little)
        ..setUint32(22, raw.length, Endian.little)
        ..setUint16(26, nameBytes.length, Endian.little)
        ..setUint16(28, extra.length, Endian.little);
      out
        ..add(local.buffer.asUint8List())
        ..add(nameBytes)
        ..add(extra)
        ..add(body);
      final ByteData cd = ByteData(46)
        ..setUint32(0, 0x02014B50, Endian.little)
        ..setUint16(4, 0x0314, Endian.little)
        ..setUint16(6, lock && !dir ? 51 : 20, Endian.little)
        ..setUint16(8, flags, Endian.little)
        ..setUint16(10, headerMethod, Endian.little)
        ..setUint16(12, _dosTime(t), Endian.little)
        ..setUint16(14, _dosDate(t), Endian.little)
        ..setUint32(16, headerCrc, Endian.little)
        ..setUint32(20, body.length, Endian.little)
        ..setUint32(24, raw.length, Endian.little)
        ..setUint16(28, nameBytes.length, Endian.little)
        ..setUint16(30, extra.length, Endian.little)
        ..setUint32(38, dir ? 0x41ED0010 : 0x81A40000, Endian.little)
        ..setUint32(42, offset, Endian.little);
      central
        ..add(cd.buffer.asUint8List())
        ..add(nameBytes)
        ..add(extra);
      count++;
    }
    final int cdOffset = out.length;
    final Uint8List cdBytes = central.takeBytes();
    out.add(cdBytes);
    final ByteData end = ByteData(22)
      ..setUint32(0, 0x06054B50, Endian.little)
      ..setUint16(8, count, Endian.little)
      ..setUint16(10, count, Endian.little)
      ..setUint32(12, cdBytes.length, Endian.little)
      ..setUint32(16, cdOffset, Endian.little);
    out.add(end.buffer.asUint8List());
    return out.takeBytes();
  }
}
