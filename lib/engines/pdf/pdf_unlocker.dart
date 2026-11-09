import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import 'pdf_compressor.dart';
import 'pdf_protector.dart';

/// Feature 012 — Unlock a known password.
///
/// Pure-Dart removal of a password the person already knows, for every
/// standard security handler in use: RC4 40-bit (R2), RC4 128-bit (R3),
/// RC4 or AES-128 crypt filters (R4), and AES-256 (R5, R6). The password
/// may be either the opening (user) password or the owner password. It is
/// used once to derive the key and is never stored. Encrypted object
/// streams are decrypted before they are unpacked, so files saved by
/// banks, UIDAI and most PDF tools open.

class PdfWrongPasswordError extends PdfCompressError {
  const PdfWrongPasswordError() : super('That password did not open this PDF. Check capitals and the hints below.');
}

class PdfUnlockResult {
  const PdfUnlockResult({required this.bytes, required this.method, required this.pages});

  /// The password-free copy.
  final Uint8List bytes;

  /// The protection that was removed, for example "AES-256".
  final String method;

  final int pages;
}

/// One common password format, shown as hint text.
class PdfPasswordHint {
  const PdfPasswordHint(this.title, this.format, this.example);
  final String title;
  final String format;
  final String example;
}

enum _Cipher { identity, rc4, aes128, aes256 }

/// What a password opened: the file key and how each part is encrypted.
class PdfUnlockKey {
  const PdfUnlockKey._(this.key, this.revision, this._strings, this._streams, this._encryptMetadata);

  final Uint8List key;
  final int revision;
  final _Cipher _strings;
  final _Cipher _streams;
  final bool _encryptMetadata;

  String get method {
    final _Cipher c = _streams == _Cipher.identity ? _strings : _streams;
    return switch (c) {
      _Cipher.aes256 => 'AES-256',
      _Cipher.aes128 => 'AES-128',
      _Cipher.rc4 => key.length <= 5 ? 'RC4 40-bit' : 'RC4 ${key.length * 8}-bit',
      _Cipher.identity => 'no encryption',
    };
  }
}

class _Decryptor implements PdfDecryptor {
  _Decryptor(this.k);
  final PdfUnlockKey k;

  Uint8List _objectKey(int num, int gen, bool aes) {
    if (k.revision >= 5) {
      return k.key;
    }
    final List<int> seed = <int>[
      ...k.key,
      num & 0xFF,
      (num >> 8) & 0xFF,
      (num >> 16) & 0xFF,
      gen & 0xFF,
      (gen >> 8) & 0xFF,
      if (aes) ...ascii.encode('sAlT'),
    ];
    final Uint8List h = PdfUnlocker.md5(seed);
    final int n = k.key.length + 5 > 16 ? 16 : k.key.length + 5;
    return Uint8List.sublistView(h, 0, n);
  }

  Uint8List _run(_Cipher c, int num, int gen, Uint8List data) {
    if (c == _Cipher.identity) {
      return data;
    }
    if (c == _Cipher.rc4) {
      return PdfUnlocker.rc4(_objectKey(num, gen, false), data);
    }
    if (data.isEmpty) {
      return data;
    }
    return PdfProtector.decryptAes(_objectKey(num, gen, true), data) ?? data;
  }

  @override
  Uint8List stream(int num, int gen, PdfDict dict, Uint8List data) {
    if (!k._encryptMetadata && dict.name('Type') == 'Metadata') {
      return data;
    }
    return _run(k._streams, num, gen, data);
  }

  @override
  Object value(int num, int gen, Object v) {
    if (v is PdfString) {
      return PdfProtector.hexString(_run(k._strings, num, gen, PdfProtector.stringBytes(v.raw)));
    }
    if (v is PdfArray) {
      return PdfArray(<Object>[for (final Object i in v.items) value(num, gen, i)]);
    }
    if (v is PdfDict) {
      return PdfDict(<String, Object>{
        for (final MapEntry<String, Object> e in v.entries.entries) e.key: value(num, gen, e.value),
      });
    }
    return v;
  }
}

abstract final class PdfUnlocker {
  /// The 32-byte padding string of Algorithm 2.
  static const List<int> pad = <int>[
    0x28, 0xBF, 0x4E, 0x5E, 0x4E, 0x75, 0x8A, 0x41, 0x64, 0x00, 0x4E, 0x56, 0xFF, 0xFA, 0x01, 0x08, //
    0x2E, 0x2E, 0x00, 0xB6, 0xD0, 0x68, 0x3E, 0x80, 0x2F, 0x0C, 0xA9, 0xFE, 0x64, 0x53, 0x69, 0x7A,
  ];

  static const List<PdfPasswordHint> hints = <PdfPasswordHint>[
    PdfPasswordHint(
      'e-Aadhaar',
      'First 4 letters of your name in CAPITALS, then your birth year (YYYY).',
      'SURESH KUMAR, born 1990 → SURE1990',
    ),
    PdfPasswordHint(
      'Income tax (ITR-V, Form 16)',
      'Your PAN in small letters, then your date of birth as DDMMYYYY.',
      'abcde1234f01011990',
    ),
    PdfPasswordHint(
      'Bank and card statements',
      'Each bank sets its own: usually a mix of your name, date of birth (DDMM or DDMMYYYY), '
          'customer ID or the last digits of your mobile or card. The email the statement came with says which.',
      'Check the statement email',
    ),
  ];

  /// The e-Aadhaar password for [name] and [birthYear]: the first four
  /// letters of the name in capitals (all of it when shorter), then the year.
  static String aadhaarPassword(String name, int birthYear) {
    final String letters = name.toUpperCase().replaceAll(RegExp('[^A-Z]'), '');
    final String head = letters.length > 4 ? letters.substring(0, 4) : letters;
    return '$head$birthYear';
  }

  /// True when [pdf] has a security handler (a password or restrictions).
  static bool isProtected(Uint8List pdf) =>
      RegExp(r'/Encrypt\s*(\d+\s+\d+\s+R|<<)').hasMatch(latin1.decode(pdf));

  /// A password-free copy of [input], when [password] opens it.
  static PdfUnlockResult unlock(Uint8List input, String password) {
    PdfUnlockKey? opened;
    final PdfDocumentModel doc = PdfDocumentModel.parse(input, decrypt: (PdfDict enc, PdfDict trailer) {
      final PdfUnlockKey k = keyFor(enc, trailer, password);
      opened = k;
      return _Decryptor(k);
    });
    final PdfUnlockKey? k = opened;
    if (k == null) {
      throw const PdfCompressError('This PDF has no password to remove.');
    }
    final Set<int> live = doc.reachable();
    final Map<int, PdfObject> out = <int, PdfObject>{
      for (final MapEntry<int, PdfObject> e in doc.objects.entries)
        if (live.contains(e.key)) e.key: e.value,
    };
    final Map<String, Object> trailer = <String, Object>{'Root': doc.trailer['Root']!};
    final Object? id = doc.trailer['ID'];
    if (id != null) {
      trailer['ID'] = id;
    }
    final Object? info = doc.trailer['Info'];
    if (info is PdfRef && out.containsKey(info.num)) {
      trailer['Info'] = info;
    }
    final PdfDocumentModel clean = PdfDocumentModel.build(out, PdfDict(trailer));
    return PdfUnlockResult(bytes: clean.write(), method: k.method, pages: clean.pageCount());
  }

  /// The key [password] opens, as user or owner password; throws
  /// [PdfWrongPasswordError] when it opens neither.
  static PdfUnlockKey keyFor(PdfDict enc, PdfDict trailer, String password) {
    if (enc.name('Filter') != 'Standard') {
      throw const PdfCompressError('This PDF is locked to a certificate, not a password, so it cannot be unlocked here.');
    }
    final int v = enc.integer('V') ?? 0;
    final int r = enc.integer('R') ?? 2;
    final bool encryptMetadata = enc['EncryptMetadata'] is! PdfKeyword || (enc['EncryptMetadata'] as PdfKeyword).word != 'false';
    final _Cipher strings;
    final _Cipher streams;
    if (v >= 4) {
      strings = _filter(enc, enc.name('StrF'));
      streams = _filter(enc, enc.name('StmF'));
    } else if (v == 1 || v == 2) {
      strings = _Cipher.rc4;
      streams = _Cipher.rc4;
    } else {
      throw const PdfCompressError('This PDF uses a kind of protection the app does not know.');
    }
    final Uint8List o = _bytes(enc['O']);
    final Uint8List u = _bytes(enc['U']);
    Uint8List? key;
    if (r >= 5) {
      key = _keyR6(r, password, o, u, _bytes(enc['OE']), _bytes(enc['UE']));
    } else if (r >= 2) {
      final int bits = enc.integer('Length') ?? (v >= 4 ? 128 : 40);
      int n = r == 2 ? 5 : bits ~/ 8;
      if (n < 5) {
        n = 5;
      }
      if (n > 16) {
        n = 16;
      }
      final int p = enc.integer('P') ?? 0;
      final Object? ids = trailer['ID'];
      final Uint8List id0 = ids is PdfArray && ids.items.isNotEmpty && ids.items.first is PdfString
          ? PdfProtector.stringBytes((ids.items.first as PdfString).raw)
          : Uint8List(0);
      final bool skipMeta = r >= 4 && !encryptMetadata;
      final Uint8List user = padPassword(_passwordBytes(password));
      key = _userKey(user, o, p, id0, r, n, skipMeta, u);
      key ??= _userKey(_ownerToUser(_passwordBytes(password), o, r, n), o, p, id0, r, n, skipMeta, u);
    } else {
      throw const PdfCompressError('This PDF uses a kind of protection the app does not know.');
    }
    if (key == null) {
      throw const PdfWrongPasswordError();
    }
    return PdfUnlockKey._(key, r, strings, streams, encryptMetadata);
  }

  static _Cipher _filter(PdfDict enc, String? name) {
    if (name == null || name == 'Identity') {
      return _Cipher.identity;
    }
    final Object? cf = enc['CF'];
    final Object? f = cf is PdfDict ? cf[name] : null;
    final String? cfm = f is PdfDict ? f.name('CFM') : null;
    switch (cfm) {
      case 'V2':
        return _Cipher.rc4;
      case 'AESV2':
        return _Cipher.aes128;
      case 'AESV3':
        return _Cipher.aes256;
      case 'None':
        return _Cipher.identity;
      default:
        throw const PdfCompressError('This PDF uses a kind of protection the app does not know.');
    }
  }

  /// Algorithm 2 then Algorithm 4/5: the file key when [padded] is the
  /// user password, else null.
  static Uint8List? _userKey(
      Uint8List padded, Uint8List o, int p, Uint8List id0, int r, int n, bool skipMeta, Uint8List u) {
    final Uint8List key = fileKey(padded, o, p, id0, r, n, skipMeta);
    if (r == 2) {
      final Uint8List check = rc4(key, pad);
      return _same(check, u, 32) ? key : null;
    }
    Uint8List x = rc4(key, md5(<int>[...pad, ...id0]));
    for (int i = 1; i <= 19; i++) {
      x = rc4(_xor(key, i), x);
    }
    return _same(x, u, 16) ? key : null;
  }

  /// Algorithm 2: the RC4/AES-128 file key from a padded password.
  static Uint8List fileKey(Uint8List padded, Uint8List o, int p, Uint8List id0, int r, int n, bool skipMeta) {
    final List<int> seed = <int>[
      ...padded,
      ...(o.length > 32 ? o.sublist(0, 32) : o),
      p & 0xFF,
      (p >> 8) & 0xFF,
      (p >> 16) & 0xFF,
      (p >> 24) & 0xFF,
      ...id0,
      if (skipMeta) ...<int>[0xFF, 0xFF, 0xFF, 0xFF],
    ];
    Uint8List h = md5(seed);
    if (r >= 3) {
      for (int i = 0; i < 50; i++) {
        h = md5(h.sublist(0, n));
      }
    }
    return Uint8List.fromList(h.sublist(0, n));
  }

  /// Algorithm 7: the padded user password an owner password reveals.
  static Uint8List _ownerToUser(Uint8List owner, Uint8List o, int r, int n) {
    Uint8List h = md5(padPassword(owner));
    if (r >= 3) {
      for (int i = 0; i < 50; i++) {
        h = md5(h);
      }
    }
    final Uint8List key = Uint8List.fromList(h.sublist(0, n));
    final Uint8List oo = o.length > 32 ? o.sublist(0, 32) : o;
    if (r == 2) {
      return rc4(key, oo);
    }
    Uint8List x = oo;
    for (int i = 19; i >= 0; i--) {
      x = rc4(_xor(key, i), x);
    }
    return x;
  }

  /// Algorithms 2.A / 11 / 12: the AES-256 file key for user or owner.
  static Uint8List? _keyR6(int r, String password, Uint8List o, Uint8List u, Uint8List oe, Uint8List ue) {
    if (o.length < 48 || u.length < 48 || oe.length < 32 || ue.length < 32) {
      throw const PdfCompressError('This PDF has damaged password settings.');
    }
    final List<int> raw = utf8.encode(password);
    final Uint8List pw = Uint8List.fromList(raw.length > 127 ? raw.sublist(0, 127) : raw);
    final Uint8List u48 = u.sublist(0, 48);
    Uint8List h(Uint8List salt, Uint8List udata) {
      if (r == 5) {
        return SHA256Digest().process(Uint8List.fromList(<int>[...pw, ...salt, ...udata]));
      }
      return PdfProtector.hash(pw, salt, udata);
    }

    if (_same(h(u.sublist(32, 40), Uint8List(0)), u, 32)) {
      return _cbcNoPadDecrypt(h(u.sublist(40, 48), Uint8List(0)), ue.sublist(0, 32));
    }
    if (_same(h(o.sublist(32, 40), u48), o, 32)) {
      return _cbcNoPadDecrypt(h(o.sublist(40, 48), u48), oe.sublist(0, 32));
    }
    return null;
  }

  static Uint8List _cbcNoPadDecrypt(Uint8List key, Uint8List data) {
    final CBCBlockCipher cbc = CBCBlockCipher(AESEngine())
      ..init(false, ParametersWithIV<KeyParameter>(KeyParameter(key), Uint8List(16)));
    final Uint8List out = Uint8List(data.length);
    for (int off = 0; off < data.length; off += 16) {
      cbc.processBlock(data, off, out, off);
    }
    return out;
  }

  /// The password padded or cut to 32 bytes.
  static Uint8List padPassword(List<int> pw) {
    final Uint8List out = Uint8List(32);
    final int n = pw.length > 32 ? 32 : pw.length;
    out.setRange(0, n, pw);
    out.setRange(n, 32, pad);
    return out;
  }

  /// R2–R4 passwords are PDFDocEncoding; Latin-1 covers what people type.
  static Uint8List _passwordBytes(String pw) {
    final bool latin = pw.codeUnits.every((int c) => c < 256);
    return Uint8List.fromList(latin ? latin1.encode(pw) : utf8.encode(pw));
  }

  static Uint8List md5(List<int> data) => MD5Digest().process(Uint8List.fromList(data));

  static Uint8List rc4(List<int> key, List<int> data) {
    final List<int> s = List<int>.generate(256, (int i) => i);
    int j = 0;
    for (int i = 0; i < 256; i++) {
      j = (j + s[i] + key[i % key.length]) & 0xFF;
      final int t = s[i];
      s[i] = s[j];
      s[j] = t;
    }
    final Uint8List out = Uint8List(data.length);
    int i = 0;
    j = 0;
    for (int k = 0; k < data.length; k++) {
      i = (i + 1) & 0xFF;
      j = (j + s[i]) & 0xFF;
      final int t = s[i];
      s[i] = s[j];
      s[j] = t;
      out[k] = data[k] ^ s[(s[i] + s[j]) & 0xFF];
    }
    return out;
  }

  static Uint8List _xor(Uint8List key, int i) => Uint8List.fromList(<int>[for (final int b in key) b ^ i]);

  static bool _same(List<int> a, List<int> b, int n) {
    if (a.length < n || b.length < n) {
      return false;
    }
    for (int i = 0; i < n; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }

  static Uint8List _bytes(Object? v) => v is PdfString ? PdfProtector.stringBytes(v.raw) : Uint8List(0);
}
