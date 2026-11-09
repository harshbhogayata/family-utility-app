import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import 'pdf_compressor.dart';

/// Feature 011 — Protect with password.
///
/// Pure-Dart PDF encryption with AES-256 (the PDF 2.0 standard security
/// handler, V 5 / R 6, crypt filter AESV3). The person sets an opening
/// password and may stop printing or copying. The password is used once to
/// derive the keys and is never written anywhere; the owner password that
/// guards the restrictions is random and thrown away.

class PdfProtectOptions {
  const PdfProtectOptions({required this.password, this.allowPrint = true, this.allowCopy = true});

  final String password;
  final bool allowPrint;
  final bool allowCopy;
}

class PdfProtectResult {
  const PdfProtectResult(this.bytes, this.permissions);
  final Uint8List bytes;

  /// The /P value written into the file.
  final int permissions;
}

enum PasswordStrength {
  empty('Type a password', 0),
  weak('Weak', 1),
  fair('Fair', 2),
  good('Good', 3),
  strong('Strong', 4);

  const PasswordStrength(this.label, this.level);
  final String label;

  /// 0 to 4, for the meter.
  final int level;

  static const Set<String> _common = <String>{
    'password', 'passw0rd', '12345678', '123456789', '1234567890', 'qwerty', 'qwertyuiop', 'iloveyou',
    'admin', 'welcome', 'letmein', 'abc123', '111111', '000000', 'football', 'monkey', 'sunshine',
  };

  /// Length and variety, with common and repeated passwords marked weak.
  static PasswordStrength of(String pw) {
    if (pw.isEmpty) {
      return PasswordStrength.empty;
    }
    final String lower = pw.toLowerCase();
    if (pw.length < 6 || _common.contains(lower) || pw.split('').toSet().length <= 2) {
      return PasswordStrength.weak;
    }
    int kinds = 0;
    if (RegExp('[a-z]').hasMatch(pw)) {
      kinds++;
    }
    if (RegExp('[A-Z]').hasMatch(pw)) {
      kinds++;
    }
    if (RegExp('[0-9]').hasMatch(pw)) {
      kinds++;
    }
    if (RegExp('[^A-Za-z0-9]').hasMatch(pw)) {
      kinds++;
    }
    int score = 0;
    if (pw.length >= 8) {
      score++;
    }
    if (pw.length >= 12) {
      score++;
    }
    if (pw.length >= 16) {
      score++;
    }
    if (kinds >= 2) {
      score++;
    }
    if (kinds >= 3) {
      score++;
    }
    if (score <= 1) {
      return PasswordStrength.weak;
    }
    if (score == 2) {
      return PasswordStrength.fair;
    }
    if (score == 3) {
      return PasswordStrength.good;
    }
    return PasswordStrength.strong;
  }
}

/// The keys and dictionary entries the standard handler needs.
class PdfEncryptKeys {
  const PdfEncryptKeys({
    required this.fileKey,
    required this.o,
    required this.u,
    required this.oe,
    required this.ue,
    required this.perms,
    required this.p,
  });

  final Uint8List fileKey;
  final Uint8List o;
  final Uint8List u;
  final Uint8List oe;
  final Uint8List ue;
  final Uint8List perms;
  final int p;
}

abstract final class PdfProtector {
  /// Bits 7, 8 and 13–32 must be set; 1–2 clear. Bit 10 (accessibility
  /// extraction) stays on so screen readers keep working.
  static const int _base = 0xFFFFF0C0 | (1 << 9);
  static const int _print = (1 << 2) | (1 << 11);
  static const int _modify = 1 << 3;
  static const int _copy = 1 << 4;
  static const int _annotate = 1 << 5;
  static const int _fill = 1 << 8;
  static const int _assemble = 1 << 10;

  /// The signed 32-bit /P value for the chosen restrictions.
  static int permissions({required bool allowPrint, required bool allowCopy}) {
    int p = _base | _modify | _annotate | _fill | _assemble;
    if (allowPrint) {
      p |= _print;
    }
    if (allowCopy) {
      p |= _copy;
    }
    return p.toSigned(32);
  }

  static PdfProtectResult protect(Uint8List input, PdfProtectOptions options, {Random? random}) {
    if (options.password.isEmpty) {
      throw const PdfCompressError('Type a password to open the file with.');
    }
    final Random rnd = random ?? Random.secure();
    final PdfDocumentModel doc = PdfDocumentModel.parse(input);
    final int p = permissions(allowPrint: options.allowPrint, allowCopy: options.allowCopy);
    final PdfEncryptKeys keys = makeKeys(options.password, _bytes(rnd, 32), p, rnd);

    // Keep only what the document uses (drops old xref and object streams).
    final Set<int> live = doc.reachable();
    final Map<int, PdfObject> out = <int, PdfObject>{};
    int max = 0;
    for (final MapEntry<int, PdfObject> e in doc.objects.entries) {
      if (!live.contains(e.key)) {
        continue;
      }
      final PdfObject o = e.value;
      final Uint8List? data = o.stream;
      out[e.key] = PdfObject(
        o.num,
        o.gen,
        _encryptValue(o.value, keys.fileKey, rnd),
        stream: data == null ? null : encryptAes(keys.fileKey, data, _bytes(rnd, 16)),
      );
      if (e.key > max) {
        max = e.key;
      }
    }
    final int encryptNum = max + 1;
    out[encryptNum] = PdfObject(encryptNum, 0, PdfDict(<String, Object>{
      'Filter': const PdfName('Standard'),
      'V': const PdfNum('5'),
      'R': const PdfNum('6'),
      'Length': const PdfNum('256'),
      'CF': PdfDict(<String, Object>{
        'StdCF': PdfDict(<String, Object>{
          'AuthEvent': const PdfName('DocOpen'),
          'CFM': const PdfName('AESV3'),
          'Length': const PdfNum('32'),
        }),
      }),
      'StmF': const PdfName('StdCF'),
      'StrF': const PdfName('StdCF'),
      'O': hexString(keys.o),
      'U': hexString(keys.u),
      'OE': hexString(keys.oe),
      'UE': hexString(keys.ue),
      'P': PdfNum('${keys.p}'),
      'Perms': hexString(keys.perms),
      'EncryptMetadata': const PdfKeyword('true'),
    }));
    final Object? id = doc.trailer['ID'];
    final PdfString fresh = hexString(_bytes(rnd, 16));
    final Map<String, Object> trailer = <String, Object>{
      'Root': doc.trailer['Root']!,
      'Encrypt': PdfRef(encryptNum, 0),
      'ID': id is PdfArray && id.items.length == 2 ? id : PdfArray(<Object>[fresh, fresh]),
    };
    final Object? info = doc.trailer['Info'];
    if (info is PdfRef && out.containsKey(info.num)) {
      trailer['Info'] = info;
    }
    return PdfProtectResult(PdfDocumentModel.build(out, PdfDict(trailer)).write(), p);
  }

  /// Algorithms 8, 9 and 10 of ISO 32000-2 for [fileKey].
  static PdfEncryptKeys makeKeys(String password, Uint8List fileKey, int p, Random rnd) {
    final Uint8List user = _password(password);
    final Uint8List owner = _bytes(rnd, 32);
    final Uint8List uSalts = _bytes(rnd, 16);
    final Uint8List u = Uint8List.fromList(<int>[...hash(user, uSalts.sublist(0, 8), Uint8List(0)), ...uSalts]);
    final Uint8List ue = _cbcNoPad(hash(user, uSalts.sublist(8, 16), Uint8List(0)), fileKey);
    final Uint8List oSalts = _bytes(rnd, 16);
    final Uint8List o = Uint8List.fromList(<int>[...hash(owner, oSalts.sublist(0, 8), u), ...oSalts]);
    final Uint8List oe = _cbcNoPad(hash(owner, oSalts.sublist(8, 16), u), fileKey);
    final Uint8List perms = Uint8List(16)
      ..setRange(0, 4, <int>[p & 0xFF, (p >> 8) & 0xFF, (p >> 16) & 0xFF, (p >> 24) & 0xFF])
      ..setRange(4, 8, <int>[0xFF, 0xFF, 0xFF, 0xFF])
      ..setRange(8, 12, ascii.encode('Tadb'))
      ..setRange(12, 16, _bytes(rnd, 4));
    final AESEngine ecb = AESEngine()..init(true, KeyParameter(fileKey));
    final Uint8List permsEnc = Uint8List(16);
    ecb.processBlock(perms, 0, permsEnc, 0);
    return PdfEncryptKeys(fileKey: fileKey, o: o, u: u, oe: oe, ue: ue, perms: permsEnc, p: p);
  }

  /// Algorithm 2.B: the R6 password hash.
  static Uint8List hash(Uint8List password, Uint8List salt, Uint8List udata) {
    Uint8List k = SHA256Digest().process(Uint8List.fromList(<int>[...password, ...salt, ...udata]));
    int round = 0;
    while (true) {
      final List<int> one = <int>[...password, ...k, ...udata];
      final Uint8List k1 = Uint8List(one.length * 64);
      for (int i = 0; i < 64; i++) {
        k1.setRange(i * one.length, (i + 1) * one.length, one);
      }
      final CBCBlockCipher cbc = CBCBlockCipher(AESEngine())
        ..init(true, ParametersWithIV<KeyParameter>(KeyParameter(k.sublist(0, 16)), k.sublist(16, 32)));
      final Uint8List e = Uint8List(k1.length);
      for (int off = 0; off < k1.length; off += 16) {
        cbc.processBlock(k1, off, e, off);
      }
      int sum = 0;
      for (int i = 0; i < 16; i++) {
        sum += e[i];
      }
      switch (sum % 3) {
        case 0:
          k = SHA256Digest().process(e);
        case 1:
          k = SHA384Digest().process(e);
        default:
          k = SHA512Digest().process(e);
      }
      round++;
      if (round >= 64 && e[e.length - 1] <= round - 32) {
        break;
      }
    }
    return Uint8List.sublistView(k, 0, 32);
  }

  /// The file key when [password] opens [encrypted] (user password), else null.
  static Uint8List? unlock(Uint8List encrypted, String password) {
    final Map<String, Uint8List> d = _encryptEntries(encrypted);
    final Uint8List? u = d['U'];
    final Uint8List? ue = d['UE'];
    if (u == null || ue == null || u.length < 48) {
      return null;
    }
    final Uint8List pw = _password(password);
    final Uint8List check = hash(pw, u.sublist(32, 40), Uint8List(0));
    for (int i = 0; i < 32; i++) {
      if (check[i] != u[i]) {
        return null;
      }
    }
    final Uint8List key = hash(pw, u.sublist(40, 48), Uint8List(0));
    final CBCBlockCipher cbc = CBCBlockCipher(AESEngine())
      ..init(false, ParametersWithIV<KeyParameter>(KeyParameter(key), Uint8List(16)));
    final Uint8List out = Uint8List(32);
    cbc.processBlock(ue, 0, out, 0);
    cbc.processBlock(ue, 16, out, 16);
    return out;
  }

  /// IV + AES-256-CBC with PKCS#7 padding, as AESV3 streams and strings use.
  static Uint8List encryptAes(Uint8List key, Uint8List data, Uint8List iv) {
    final int pad = 16 - data.length % 16;
    final Uint8List plain = Uint8List(data.length + pad)
      ..setRange(0, data.length, data)
      ..fillRange(data.length, data.length + pad, pad);
    final CBCBlockCipher cbc = CBCBlockCipher(AESEngine())..init(true, ParametersWithIV<KeyParameter>(KeyParameter(key), iv));
    final Uint8List out = Uint8List(16 + plain.length)..setRange(0, 16, iv);
    for (int off = 0; off < plain.length; off += 16) {
      cbc.processBlock(plain, off, out, 16 + off);
    }
    return out;
  }

  /// Reverses [encryptAes]; null when the padding is wrong.
  static Uint8List? decryptAes(Uint8List key, Uint8List data) {
    if (data.length < 32 || data.length % 16 != 0) {
      return null;
    }
    final CBCBlockCipher cbc = CBCBlockCipher(AESEngine())
      ..init(false, ParametersWithIV<KeyParameter>(KeyParameter(key), data.sublist(0, 16)));
    final Uint8List plain = Uint8List(data.length - 16);
    for (int off = 16; off < data.length; off += 16) {
      cbc.processBlock(data, off, plain, off - 16);
    }
    final int pad = plain.last;
    if (pad < 1 || pad > 16) {
      return null;
    }
    return Uint8List.sublistView(plain, 0, plain.length - pad);
  }

  /// The bytes a PDF string stands for (literal or hex).
  static Uint8List stringBytes(Uint8List raw) {
    if (raw.isEmpty) {
      return raw;
    }
    if (raw[0] == 0x3C) {
      final String hex = latin1.decode(raw).replaceAll(RegExp(r'[<>\s]'), '');
      final String even = hex.length.isOdd ? '${hex}0' : hex;
      return Uint8List.fromList(<int>[
        for (int i = 0; i < even.length; i += 2) int.tryParse(even.substring(i, i + 2), radix: 16) ?? 0,
      ]);
    }
    final List<int> out = <int>[];
    int i = raw[0] == 0x28 ? 1 : 0;
    final int end = raw.isNotEmpty && raw[raw.length - 1] == 0x29 ? raw.length - 1 : raw.length;
    while (i < end) {
      final int c = raw[i];
      if (c != 0x5C) {
        if (c == 0x0D) {
          // An end of line inside a string is read as a single \n.
          out.add(0x0A);
          if (i + 1 < end && raw[i + 1] == 0x0A) {
            i++;
          }
        } else {
          out.add(c);
        }
        i++;
        continue;
      }
      i++;
      if (i >= end) {
        break;
      }
      final int e = raw[i];
      if (e >= 0x30 && e <= 0x37) {
        int v = 0;
        int n = 0;
        while (n < 3 && i < end && raw[i] >= 0x30 && raw[i] <= 0x37) {
          v = v * 8 + raw[i] - 0x30;
          i++;
          n++;
        }
        out.add(v & 0xFF);
        continue;
      }
      i++;
      switch (e) {
        case 0x6E:
          out.add(0x0A);
        case 0x72:
          out.add(0x0D);
        case 0x74:
          out.add(0x09);
        case 0x62:
          out.add(0x08);
        case 0x66:
          out.add(0x0C);
        case 0x0D:
          // Line continuation.
          if (i < end && raw[i] == 0x0A) {
            i++;
          }
        case 0x0A:
          break;
        default:
          out.add(e);
      }
    }
    return Uint8List.fromList(out);
  }

  static PdfString hexString(List<int> bytes) {
    final StringBuffer b = StringBuffer('<');
    for (final int x in bytes) {
      b.write(x.toRadixString(16).padLeft(2, '0'));
    }
    b.write('>');
    return PdfString(Uint8List.fromList(latin1.encode(b.toString())));
  }

  static Object _encryptValue(Object v, Uint8List key, Random rnd) {
    if (v is PdfString) {
      return hexString(encryptAes(key, stringBytes(v.raw), _bytes(rnd, 16)));
    }
    if (v is PdfArray) {
      return PdfArray(<Object>[for (final Object i in v.items) _encryptValue(i, key, rnd)]);
    }
    if (v is PdfDict) {
      return PdfDict(<String, Object>{
        for (final MapEntry<String, Object> e in v.entries.entries) e.key: _encryptValue(e.value, key, rnd),
      });
    }
    return v;
  }

  /// SASLprep is skipped: the password is used as UTF-8, at most 127 bytes.
  static Uint8List _password(String pw) {
    final List<int> b = utf8.encode(pw);
    return Uint8List.fromList(b.length > 127 ? b.sublist(0, 127) : b);
  }

  static Uint8List _cbcNoPad(Uint8List key, Uint8List data) {
    final CBCBlockCipher cbc = CBCBlockCipher(AESEngine())
      ..init(true, ParametersWithIV<KeyParameter>(KeyParameter(key), Uint8List(16)));
    final Uint8List out = Uint8List(data.length);
    for (int off = 0; off < data.length; off += 16) {
      cbc.processBlock(data, off, out, off);
    }
    return out;
  }

  static Uint8List _bytes(Random rnd, int n) => Uint8List.fromList(List<int>.generate(n, (_) => rnd.nextInt(256)));

  /// The hex strings of the /Encrypt dictionary, read straight from the file.
  static Map<String, Uint8List> _encryptEntries(Uint8List pdf) {
    final String s = latin1.decode(pdf);
    final Map<String, Uint8List> out = <String, Uint8List>{};
    for (final String key in <String>['U', 'UE', 'O', 'OE', 'Perms']) {
      final RegExpMatch? m = RegExp('/$key <([0-9a-fA-F]+)>').firstMatch(s);
      if (m != null) {
        out[key] = stringBytes(Uint8List.fromList(latin1.encode('<${m.group(1)}>')));
      }
    }
    return out;
  }
}
