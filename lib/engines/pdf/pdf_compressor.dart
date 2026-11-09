import 'dart:convert';
import 'dart:io' show ZLibCodec;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Feature 032 — Compress PDF.
///
/// A pure-Dart rewrite of the file: objects are read (object streams are
/// unpacked), anything not reachable from the catalog is dropped, photos are
/// downsampled and re-encoded as JPEG, and other streams are deflated at the
/// highest level. Page content and fonts keep their exact bytes once
/// decoded, so text stays selectable. Runs on the phone; nothing is uploaded.

enum PdfPreset {
  low('Low', 'Smallest file, softer photos', 1200, 50, 0.30),
  medium('Medium', 'Good for email and forms', 1800, 70, 0.50),
  high('High', 'Keeps photos sharp', 2600, 85, 0.75);

  const PdfPreset(this.label, this.hint, this.maxSide, this.quality, this.jpegFactor);

  final String label;
  final String hint;

  /// Longest side, in pixels, an image keeps.
  final int maxSide;
  final int quality;

  /// Rough share of a JPEG's bytes left after re-encoding at [quality].
  final double jpegFactor;
}

/// How hard the run squeezes photos.
@immutable
class PdfSettings {
  const PdfSettings(this.maxSide, this.quality);

  final int maxSide;
  final int quality;

  /// Mildest first. Feature 033 walks this ladder to hit a target size.
  static const List<PdfSettings> ladder = <PdfSettings>[
    PdfSettings(2600, 85),
    PdfSettings(1800, 70),
    PdfSettings(1400, 60),
    PdfSettings(1200, 50),
    PdfSettings(1000, 40),
    PdfSettings(800, 35),
    PdfSettings(600, 30),
    PdfSettings(450, 25),
    PdfSettings(300, 20),
  ];
}

/// The answer for a target size: the mildest result that fits, or the
/// smallest the app could make and why it is not enough.
@immutable
class PdfTargetResult {
  const PdfTargetResult({required this.target, required this.result, required this.reached, required this.message});

  final int target;
  final PdfCompressResult result;
  final bool reached;
  final String message;
}

class PdfCompressError implements Exception {
  const PdfCompressError(this.message);

  final String message;

  @override
  String toString() => message;
}

@immutable
class PdfCompressResult {
  const PdfCompressResult({
    required this.bytes,
    required this.before,
    required this.imagesChanged,
    required this.streamsChanged,
  });

  final Uint8List bytes;
  final int before;
  final int imagesChanged;
  final int streamsChanged;

  int get after => bytes.length;

  bool get smaller => after < before;

  /// Percent saved, 0 when the file did not shrink.
  int get savedPercent => smaller ? ((before - after) * 100 / before).round() : 0;
}

/// What the file holds, for the estimate shown before the run.
@immutable
class PdfAnalysis {
  const PdfAnalysis({
    required this.size,
    required this.pages,
    required this.images,
    required this.plainStreamBytes,
  });

  final int size;
  final int pages;

  /// (bytes, longest side) per image the run can re-encode.
  final List<(int, int)> images;

  /// Bytes in streams stored without compression.
  final int plainStreamBytes;

  int estimate(PdfPreset p) {
    int imageBytes = 0;
    double imageAfter = 0;
    for (final (int bytes, int longest) in images) {
      imageBytes += bytes;
      final double scale = longest > p.maxSide ? p.maxSide / longest : 1.0;
      final double est = bytes * scale * scale * (scale < 1 ? 0.9 : p.jpegFactor);
      imageAfter += est < bytes ? est : bytes.toDouble();
    }
    final int rest = size - imageBytes - plainStreamBytes;
    final double total = rest + plainStreamBytes * 0.3 + imageAfter;
    final int t = total.round();
    return t > size ? size : (t < 0 ? 0 : t);
  }
}

// ---------------------------------------------------------------------------
// Objects

@immutable
class PdfName {
  const PdfName(this.raw);
  final String raw;

  @override
  bool operator ==(Object other) => other is PdfName && other.raw == raw;

  @override
  int get hashCode => raw.hashCode;
}

@immutable
class PdfNum {
  const PdfNum(this.raw);
  final String raw;

  num get value => num.tryParse(raw) ?? 0;
}

/// A string kept as its exact source bytes, delimiters included.
class PdfString {
  PdfString(this.raw);
  final Uint8List raw;
}

@immutable
class PdfRef {
  const PdfRef(this.num, this.gen);
  final int num;
  final int gen;
}

@immutable
class PdfKeyword {
  const PdfKeyword(this.word);
  final String word;
}

class PdfArray {
  PdfArray(this.items);
  final List<Object> items;
}

class PdfDict {
  PdfDict(this.entries);
  final Map<String, Object> entries;

  Object? operator [](String key) => entries[key];

  String? name(String key) {
    final Object? v = entries[key];
    return v is PdfName ? v.raw : null;
  }

  int? integer(String key) {
    final Object? v = entries[key];
    return v is PdfNum ? v.value.toInt() : null;
  }
}

class PdfObject {
  PdfObject(this.num, this.gen, this.value, {this.stream});
  final int num;
  final int gen;
  Object value;
  Uint8List? stream;
}

// ---------------------------------------------------------------------------
// Lexer and parser

class PdfParser {
  PdfParser(this.b, [this.pos = 0]);

  final Uint8List b;
  int pos;

  static bool isWhite(int c) => c == 0 || c == 9 || c == 10 || c == 12 || c == 13 || c == 32;

  static bool isDelim(int c) =>
      c == 0x28 || c == 0x29 || c == 0x3C || c == 0x3E || c == 0x5B || c == 0x5D || c == 0x7B || c == 0x7D ||
      c == 0x2F || c == 0x25;

  void skipWhite() {
    while (pos < b.length) {
      final int c = b[pos];
      if (isWhite(c)) {
        pos++;
      } else if (c == 0x25) {
        while (pos < b.length && b[pos] != 10 && b[pos] != 13) {
          pos++;
        }
      } else {
        break;
      }
    }
  }

  String _regular() {
    final int start = pos;
    while (pos < b.length && !isWhite(b[pos]) && !isDelim(b[pos])) {
      pos++;
    }
    return latin1.decode(b.sublist(start, pos));
  }

  Object parse() {
    skipWhite();
    if (pos >= b.length) {
      throw const PdfCompressError('This PDF ends too early.');
    }
    final int c = b[pos];
    if (c == 0x2F) {
      pos++;
      return PdfName(_regular());
    }
    if (c == 0x3C && pos + 1 < b.length && b[pos + 1] == 0x3C) {
      pos += 2;
      final Map<String, Object> m = <String, Object>{};
      while (true) {
        skipWhite();
        if (pos + 1 < b.length && b[pos] == 0x3E && b[pos + 1] == 0x3E) {
          pos += 2;
          return PdfDict(m);
        }
        final Object k = parse();
        if (k is! PdfName) {
          throw const PdfCompressError('This PDF has a broken dictionary.');
        }
        m[k.raw] = parse();
      }
    }
    if (c == 0x3C) {
      final int start = pos;
      while (pos < b.length && b[pos] != 0x3E) {
        pos++;
      }
      pos++;
      return PdfString(Uint8List.fromList(b.sublist(start, pos)));
    }
    if (c == 0x28) {
      final int start = pos;
      int depth = 0;
      while (pos < b.length) {
        final int ch = b[pos];
        if (ch == 0x5C) {
          pos += 2;
          continue;
        }
        if (ch == 0x28) {
          depth++;
        } else if (ch == 0x29) {
          depth--;
          if (depth == 0) {
            pos++;
            break;
          }
        }
        pos++;
      }
      return PdfString(Uint8List.fromList(b.sublist(start, pos)));
    }
    if (c == 0x5B) {
      pos++;
      final List<Object> items = <Object>[];
      while (true) {
        skipWhite();
        if (pos < b.length && b[pos] == 0x5D) {
          pos++;
          return PdfArray(items);
        }
        items.add(parse());
      }
    }
    if (c == 0x2B || c == 0x2D || c == 0x2E || (c >= 0x30 && c <= 0x39)) {
      final String n = _regular();
      final int? whole = int.tryParse(n);
      if (whole != null && whole >= 0) {
        final int save = pos;
        skipWhite();
        final int genStart = pos;
        while (pos < b.length && b[pos] >= 0x30 && b[pos] <= 0x39) {
          pos++;
        }
        if (pos > genStart) {
          final int gen = int.parse(latin1.decode(b.sublist(genStart, pos)));
          skipWhite();
          if (pos < b.length && b[pos] == 0x52 && (pos + 1 >= b.length || isWhite(b[pos + 1]) || isDelim(b[pos + 1]))) {
            pos++;
            return PdfRef(whole, gen);
          }
        }
        pos = save;
      }
      return PdfNum(n);
    }
    final String word = _regular();
    if (word.isEmpty) {
      pos++;
      throw const PdfCompressError('This PDF has an unreadable object.');
    }
    return PdfKeyword(word);
  }

  /// True and past the word when [word] comes next.
  bool expect(String word) {
    skipWhite();
    final List<int> w = latin1.encode(word);
    if (pos + w.length > b.length) {
      return false;
    }
    for (int i = 0; i < w.length; i++) {
      if (b[pos + i] != w[i]) {
        return false;
      }
    }
    pos += w.length;
    return true;
  }
}

// ---------------------------------------------------------------------------
// Writer

class _Out {
  final BytesBuilder bb = BytesBuilder(copy: false);

  int get length => bb.length;

  void s(String text) => bb.add(latin1.encode(text));

  void bytes(List<int> data) => bb.add(data);

  void value(Object v) {
    if (v is PdfName) {
      s('/${v.raw}');
    } else if (v is PdfNum) {
      s(v.raw);
    } else if (v is PdfString) {
      bytes(v.raw);
    } else if (v is PdfRef) {
      s('${v.num} ${v.gen} R');
    } else if (v is PdfKeyword) {
      s(v.word);
    } else if (v is PdfArray) {
      s('[');
      for (int i = 0; i < v.items.length; i++) {
        if (i > 0) {
          s(' ');
        }
        value(v.items[i]);
      }
      s(']');
    } else if (v is PdfDict) {
      s('<<');
      v.entries.forEach((String k, Object e) {
        s('/$k ');
        value(e);
        s('\n');
      });
      s('>>');
    }
  }
}

// ---------------------------------------------------------------------------
// The document

/// Undoes a PDF security handler while the file is parsed (used by 012
/// Unlock a known password). Strings and streams of direct objects go
/// through it, and object streams are decrypted before they are unpacked.
abstract class PdfDecryptor {
  Object value(int num, int gen, Object v);

  Uint8List stream(int num, int gen, PdfDict dict, Uint8List data);
}

/// Builds the decryptor from the /Encrypt dictionary and the trailer; throws
/// [PdfCompressError] when the password does not open the file.
typedef PdfDecryptorFactory = PdfDecryptor Function(PdfDict encrypt, PdfDict trailer);

class PdfDocumentModel {
  PdfDocumentModel._(this.objects, this.trailer);

  /// A document built in memory (used by 002 Merge PDF).
  PdfDocumentModel.build(this.objects, this.trailer);

  final Map<int, PdfObject> objects;
  final PdfDict trailer;

  static final RegExp _objRe = RegExp(r'(\d+)\s+(\d+)\s+obj\b');
  static final ZLibCodec _inflate = ZLibCodec();

  Object? resolve(Object? v) {
    int guard = 0;
    while (v is PdfRef && guard++ < 32) {
      v = objects[v.num]?.value;
    }
    return v;
  }

  static PdfDocumentModel parse(Uint8List b, {PdfDecryptorFactory? decrypt}) {
    if (b.length < 8 || latin1.decode(b.sublist(0, 5)) != '%PDF-') {
      throw const PdfCompressError('This file is not a PDF.');
    }
    final String text = latin1.decode(b);
    final Map<int, PdfObject> objects = <int, PdfObject>{};
    final List<(int, int, PdfDict, Uint8List)> objStreams = <(int, int, PdfDict, Uint8List)>[];
    final Map<String, Object> trailer = <String, Object>{};
    final List<(int, PdfDict)> trailerDicts = <(int, PdfDict)>[];

    // Lengths given as references need the target object first.
    final Map<int, int> positions = <int, int>{};
    for (final RegExpMatch m in _objRe.allMatches(text)) {
      positions[int.parse(m.group(1)!)] = m.end;
    }

    int? lengthOf(Object? v) {
      if (v is PdfNum) {
        return v.value.toInt();
      }
      if (v is PdfRef) {
        final int? at = positions[v.num];
        if (at == null) {
          return null;
        }
        try {
          final Object o = PdfParser(b, at).parse();
          return o is PdfNum ? o.value.toInt() : null;
        } catch (_) {
          return null;
        }
      }
      return null;
    }

    int end = 0;
    for (final RegExpMatch m in _objRe.allMatches(text)) {
      if (m.start < end) {
        continue;
      }
      final int num = int.parse(m.group(1)!);
      final int gen = int.parse(m.group(2)!);
      final PdfParser p = PdfParser(b, m.end);
      Object value;
      try {
        value = p.parse();
      } catch (_) {
        continue;
      }
      Uint8List? stream;
      final int afterValue = p.pos;
      if (value is PdfDict && p.expect('stream')) {
        int start = p.pos;
        if (start < b.length && b[start] == 13) {
          start++;
        }
        if (start < b.length && b[start] == 10) {
          start++;
        }
        final int? len = lengthOf(value['Length']);
        int stop = -1;
        if (len != null && start + len <= b.length) {
          final PdfParser check = PdfParser(b, start + len);
          if (check.expect('endstream')) {
            stop = start + len;
            p.pos = check.pos;
          }
        }
        if (stop < 0) {
          final int at = text.indexOf('endstream', start);
          if (at < 0) {
            continue;
          }
          stop = at;
          while (stop > start && (b[stop - 1] == 10 || b[stop - 1] == 13)) {
            stop--;
          }
          p.pos = at + 'endstream'.length;
        }
        stream = Uint8List.sublistView(b, start, stop);
      } else {
        p.pos = afterValue;
      }
      p.expect('endobj');
      end = p.pos;
      if (value is PdfDict && stream != null) {
        final String? type = value.name('Type');
        if (type == 'ObjStm') {
          objStreams.add((num, gen, value, stream));
          continue;
        }
        if (type == 'XRef') {
          trailerDicts.add((m.start, value));
          continue;
        }
      }
      objects[num] = PdfObject(num, gen, value, stream: stream);
    }

    // Classic trailers.
    for (final RegExpMatch m in RegExp(r'trailer\s*<<').allMatches(text)) {
      try {
        final Object t = PdfParser(b, m.start + 'trailer'.length).parse();
        if (t is PdfDict) {
          trailerDicts.add((m.start, t));
        }
      } catch (_) {
        // A damaged trailer: the others may still do.
      }
    }

    trailerDicts.sort(((int, PdfDict) a, (int, PdfDict) b) => a.$1.compareTo(b.$1));
    for (final (int _, PdfDict t) in trailerDicts) {
      for (final String k in <String>['Root', 'Info', 'ID', 'Encrypt']) {
        final Object? v = t[k];
        if (v != null) {
          trailer[k] = v;
        }
      }
    }
    PdfDecryptor? decryptor;
    final Object? encrypt = trailer['Encrypt'];
    if (encrypt != null) {
      if (decrypt == null) {
        throw const PdfCompressError('This PDF is password protected. Unlock it first.');
      }
      final int encNum = encrypt is PdfRef ? encrypt.num : -1;
      final Object? encDict = encrypt is PdfRef ? objects[encrypt.num]?.value : encrypt;
      if (encDict is! PdfDict) {
        throw const PdfCompressError('This PDF has damaged password settings.');
      }
      final PdfDecryptor dec = decrypt(encDict, PdfDict(Map<String, Object>.of(trailer)));
      decryptor = dec;
      for (final PdfObject o in objects.values) {
        if (o.num == encNum) {
          continue;
        }
        final Uint8List? data = o.stream;
        if (data != null && o.value is PdfDict) {
          o.stream = dec.stream(o.num, o.gen, o.value as PdfDict, data);
        }
        o.value = dec.value(o.num, o.gen, o.value);
      }
      objects.remove(encNum);
      trailer.remove('Encrypt');
    }

    // Unpack object streams. Direct objects already read win.
    for (final (int stmNum, int stmGen, PdfDict d, Uint8List raw) in objStreams) {
      final Uint8List data = decryptor == null ? raw : decryptor.stream(stmNum, stmGen, d, raw);
      final Uint8List decoded = _decodeFlate(d, data) ??
          (throw const PdfCompressError('This PDF uses a storage format the app cannot rewrite yet.'));
      final int n = d.integer('N') ?? 0;
      final int first = d.integer('First') ?? 0;
      final PdfParser head = PdfParser(decoded);
      for (int i = 0; i < n; i++) {
        final Object on = head.parse();
        final Object off = head.parse();
        if (on is! PdfNum || off is! PdfNum) {
          break;
        }
        final int objNum = on.value.toInt();
        if (objects.containsKey(objNum)) {
          continue;
        }
        try {
          objects[objNum] = PdfObject(objNum, 0, PdfParser(decoded, first + off.value.toInt()).parse());
        } catch (_) {
          // Skip one unreadable object.
        }
      }
    }

    if (trailer['Root'] == null) {
      throw const PdfCompressError('This PDF has no catalog and cannot be rewritten.');
    }
    return PdfDocumentModel._(objects, PdfDict(trailer));
  }

  static List<String> filters(PdfDict d) {
    final Object? f = d['Filter'];
    if (f is PdfName) {
      return <String>[f.raw];
    }
    if (f is PdfArray) {
      return f.items.whereType<PdfName>().map((PdfName n) => n.raw).toList();
    }
    return const <String>[];
  }

  static Uint8List? _decodeFlate(PdfDict d, Uint8List data) {
    final List<String> f = filters(d);
    if (f.isEmpty) {
      return data;
    }
    if (f.length != 1 || f.first != 'FlateDecode' || d['DecodeParms'] != null) {
      return null;
    }
    try {
      return Uint8List.fromList(_inflate.decode(data));
    } catch (_) {
      return null;
    }
  }

  /// Object numbers reachable from the trailer.
  Set<int> reachable() {
    final Set<int> seen = <int>{};
    final List<Object> todo = <Object>[trailer];
    while (todo.isNotEmpty) {
      final Object v = todo.removeLast();
      if (v is PdfRef) {
        if (seen.add(v.num)) {
          final PdfObject? o = objects[v.num];
          if (o != null) {
            todo.add(o.value);
          }
        }
      } else if (v is PdfArray) {
        todo.addAll(v.items);
      } else if (v is PdfDict) {
        todo.addAll(v.entries.values);
      }
    }
    return seen;
  }

  int pageCount() {
    final Object? root = resolve(trailer['Root']);
    if (root is! PdfDict) {
      return 0;
    }
    final Object? pages = resolve(root['Pages']);
    return pages is PdfDict ? (pages.integer('Count') ?? 0) : 0;
  }

  Uint8List write() {
    final _Out o = _Out();
    o.s('%PDF-1.7\n');
    o.bytes(<int>[0x25, 0xE2, 0xE3, 0xCF, 0xD3, 0x0A]);
    final List<int> nums = objects.keys.toList()..sort();
    final Map<int, int> offsets = <int, int>{};
    for (final int n in nums) {
      final PdfObject obj = objects[n]!;
      offsets[n] = o.length;
      o.s('$n ${obj.gen} obj\n');
      final Uint8List? data = obj.stream;
      if (data != null && obj.value is PdfDict) {
        final PdfDict d = obj.value as PdfDict;
        d.entries['Length'] = PdfNum('${data.length}');
        o.value(d);
        o.s('\nstream\n');
        o.bytes(data);
        o.s('\nendstream\nendobj\n');
      } else {
        o.value(obj.value);
        o.s('\nendobj\n');
      }
    }
    final int size = nums.isEmpty ? 1 : nums.last + 1;
    final int xref = o.length;
    o.s('xref\n0 $size\n');
    o.s('0000000000 65535 f \n');
    for (int n = 1; n < size; n++) {
      final int? at = offsets[n];
      if (at == null) {
        o.s('0000000000 65535 f \n');
      } else {
        o.s('${at.toString().padLeft(10, '0')} ${objects[n]!.gen.toString().padLeft(5, '0')} n \n');
      }
    }
    final Map<String, Object> t = <String, Object>{'Size': PdfNum('$size')};
    for (final String k in <String>['Root', 'Info', 'ID', 'Encrypt']) {
      final Object? v = trailer[k];
      if (v != null) {
        t[k] = v;
      }
    }
    o.s('trailer\n');
    o.value(PdfDict(t));
    o.s('\nstartxref\n$xref\n%%EOF\n');
    return o.bb.takeBytes();
  }
}

// ---------------------------------------------------------------------------
// The run

abstract final class PdfCompressor {
  static final ZLibCodec _deflate = ZLibCodec(level: 9);
  static final ZLibCodec _inflate = ZLibCodec();

  static PdfAnalysis analyze(Uint8List input) {
    final PdfDocumentModel doc = PdfDocumentModel.parse(input);
    final Set<int> live = doc.reachable();
    final Set<int> masks = _maskTargets(doc);
    final List<(int, int)> images = <(int, int)>[];
    int plain = 0;
    for (final int n in live) {
      final PdfObject? o = doc.objects[n];
      final Uint8List? data = o?.stream;
      if (o == null || data == null || o.value is! PdfDict) {
        continue;
      }
      final PdfDict d = o.value as PdfDict;
      if (_imageInfo(doc, d, masks.contains(n)) != null) {
        final int w = d.integer('Width') ?? 0;
        final int h = d.integer('Height') ?? 0;
        images.add((data.length, w > h ? w : h));
      } else if (PdfDocumentModel.filters(d).isEmpty) {
        plain += data.length;
      }
    }
    return PdfAnalysis(size: input.length, pages: doc.pageCount(), images: images, plainStreamBytes: plain);
  }

  static PdfCompressResult compress(Uint8List input, PdfPreset preset) =>
      compressWith(input, PdfSettings(preset.maxSide, preset.quality));

  /// Feature 033: tries the ladder until the file is under [target] bytes.
  /// Checks the hardest setting first so an impossible target fails fast,
  /// then searches for the mildest setting that still fits.
  static PdfTargetResult toTarget(Uint8List input, int target, {String Function(int)? format}) {
    final String Function(int) fmt = format ?? ((int n) => '${(n / 1024).round()} KB');
    if (input.length <= target) {
      final PdfCompressResult same =
          PdfCompressResult(bytes: input, before: input.length, imagesChanged: 0, streamsChanged: 0);
      return PdfTargetResult(
        target: target,
        result: same,
        reached: true,
        message: 'Already under ${fmt(target)}. Nothing to do.',
      );
    }
    const List<PdfSettings> ladder = PdfSettings.ladder;
    final PdfCompressResult hardest = compressWith(input, ladder.last);
    if (hardest.after > target) {
      final String why = hardest.imagesChanged == 0
          ? 'Its text, fonts and drawings alone need about ${fmt(hardest.after)}, and they cannot be shrunk '
              'without losing selectable text.'
          : 'Even with photos at their smallest it needs about ${fmt(hardest.after)}.';
      return PdfTargetResult(
        target: target,
        result: hardest,
        reached: false,
        message: 'Cannot get this PDF under ${fmt(target)}. $why Try a bigger limit or split the file.',
      );
    }
    PdfCompressResult best = hardest;
    int lo = 0;
    int hi = ladder.length - 1;
    while (lo < hi) {
      final int mid = (lo + hi) >> 1;
      final PdfCompressResult r = compressWith(input, ladder[mid]);
      if (r.after <= target) {
        best = r;
        hi = mid;
      } else {
        lo = mid + 1;
      }
    }
    return PdfTargetResult(
      target: target,
      result: best,
      reached: true,
      message: '${fmt(best.after)}, under the ${fmt(target)} limit.',
    );
  }

  static PdfCompressResult compressWith(Uint8List input, PdfSettings settings) {
    final PdfDocumentModel doc = PdfDocumentModel.parse(input);
    final Set<int> live = doc.reachable();
    doc.objects.removeWhere((int n, PdfObject _) => !live.contains(n));
    final Set<int> masks = _maskTargets(doc);
    int images = 0;
    int streams = 0;
    for (final PdfObject o in doc.objects.values) {
      final Uint8List? data = o.stream;
      if (data == null || o.value is! PdfDict) {
        continue;
      }
      final PdfDict d = o.value as PdfDict;
      final _ImageInfo? info = _imageInfo(doc, d, masks.contains(o.num));
      if (info != null) {
        if (_recodeImage(o, d, data, info, settings)) {
          images++;
        }
        continue;
      }
      if (d.name('Type') == 'Metadata' || d.name('Subtype') == 'Image') {
        continue;
      }
      final List<String> f = PdfDocumentModel.filters(d);
      try {
        if (f.isEmpty) {
          final Uint8List z = Uint8List.fromList(_deflate.encode(data));
          if (z.length < data.length) {
            o.stream = z;
            d.entries['Filter'] = const PdfName('FlateDecode');
            d.entries.remove('DecodeParms');
            streams++;
          }
        } else if (f.length == 1 && f.first == 'FlateDecode') {
          final List<int> raw = _inflate.decode(data);
          final Uint8List z = Uint8List.fromList(_deflate.encode(raw));
          if (z.length < data.length) {
            o.stream = z;
            streams++;
          }
        }
      } catch (_) {
        // Leave a stream we cannot read exactly as it was.
      }
    }
    final Uint8List out = doc.write();
    return PdfCompressResult(bytes: out, before: input.length, imagesChanged: images, streamsChanged: streams);
  }

  /// Images used as another image's soft mask keep their exact pixels.
  static Set<int> _maskTargets(PdfDocumentModel doc) {
    final Set<int> out = <int>{};
    for (final PdfObject o in doc.objects.values) {
      final Object v = o.value;
      if (v is PdfDict) {
        final Object? m = v['SMask'];
        if (m is PdfRef) {
          out.add(m.num);
        }
      }
    }
    return out;
  }

  static _ImageInfo? _imageInfo(PdfDocumentModel doc, PdfDict d, bool isMask) {
    if (isMask || d.name('Subtype') != 'Image') {
      return null;
    }
    if (d['ImageMask'] != null || d['Mask'] != null || d['Decode'] != null) {
      return null;
    }
    final int w = d.integer('Width') ?? 0;
    final int h = d.integer('Height') ?? 0;
    if (w <= 0 || h <= 0 || (d.integer('BitsPerComponent') ?? 8) != 8) {
      return null;
    }
    final List<String> f = PdfDocumentModel.filters(d);
    if (f.length != 1 || (f.first != 'DCTDecode' && f.first != 'FlateDecode')) {
      return null;
    }
    int channels = 0;
    final Object? cs = doc.resolve(d['ColorSpace']);
    if (cs is PdfName) {
      channels = cs.raw == 'DeviceRGB' ? 3 : (cs.raw == 'DeviceGray' ? 1 : 0);
    } else if (cs is PdfArray && cs.items.length == 2 && cs.items.first == const PdfName('ICCBased')) {
      final Object? icc = doc.resolve(cs.items[1]);
      if (icc is PdfDict) {
        final int n = icc.integer('N') ?? 0;
        channels = n == 3 || n == 1 ? n : 0;
      }
    }
    if (channels == 0) {
      return null;
    }
    // Small flat images (icons, logos) are left alone: JPEG would blur them.
    if (f.first == 'FlateDecode' && w * h < 100000) {
      return null;
    }
    return _ImageInfo(f.first == 'DCTDecode', w, h, channels);
  }

  static bool _recodeImage(PdfObject o, PdfDict d, Uint8List data, _ImageInfo info, PdfSettings preset) {
    img.Image? image;
    try {
      if (info.jpeg) {
        image = img.decodeJpg(data);
      } else {
        Uint8List raw = Uint8List.fromList(_inflate.decode(data));
        final Object? parms = d['DecodeParms'];
        if (parms is PdfDict) {
          final int predictor = parms.integer('Predictor') ?? 1;
          if (predictor >= 10) {
            raw = unpredictPng(raw, info.width, info.channels);
          } else if (predictor != 1) {
            return false;
          }
        } else if (parms != null) {
          return false;
        }
        if (raw.length < info.width * info.height * info.channels) {
          return false;
        }
        image = img.Image.fromBytes(
          width: info.width,
          height: info.height,
          bytes: raw.buffer,
          bytesOffset: raw.offsetInBytes,
          numChannels: info.channels,
        );
      }
    } catch (_) {
      return false;
    }
    if (image == null) {
      return false;
    }
    img.Image out = image;
    final int longest = image.width > image.height ? image.width : image.height;
    if (longest > preset.maxSide) {
      out = image.width >= image.height
          ? img.copyResize(image, width: preset.maxSide, interpolation: img.Interpolation.average)
          : img.copyResize(image, height: preset.maxSide, interpolation: img.Interpolation.average);
    }
    if (out.numChannels != 3) {
      out = out.convert(numChannels: 3);
    }
    final Uint8List jpg = img.encodeJpg(out, quality: preset.quality);
    if (jpg.length >= data.length * 0.95) {
      return false;
    }
    o.stream = jpg;
    d.entries
      ..['Filter'] = const PdfName('DCTDecode')
      ..['Width'] = PdfNum('${out.width}')
      ..['Height'] = PdfNum('${out.height}')
      ..['BitsPerComponent'] = const PdfNum('8')
      ..['ColorSpace'] = const PdfName('DeviceRGB')
      ..remove('DecodeParms');
    return true;
  }

  /// Undoes PNG row filters (predictors 10–15) for 8-bit samples.
  static Uint8List unpredictPng(Uint8List data, int width, int channels) {
    final int rowLen = width * channels;
    final int rows = data.length ~/ (rowLen + 1);
    final Uint8List out = Uint8List(rows * rowLen);
    for (int r = 0; r < rows; r++) {
      final int type = data[r * (rowLen + 1)];
      final int src = r * (rowLen + 1) + 1;
      final int dst = r * rowLen;
      for (int i = 0; i < rowLen; i++) {
        final int x = data[src + i];
        final int a = i >= channels ? out[dst + i - channels] : 0;
        final int b = r > 0 ? out[dst - rowLen + i] : 0;
        final int c = (i >= channels && r > 0) ? out[dst - rowLen + i - channels] : 0;
        int v;
        switch (type) {
          case 1:
            v = x + a;
          case 2:
            v = x + b;
          case 3:
            v = x + ((a + b) >> 1);
          case 4:
            final int p = a + b - c;
            final int pa = (p - a).abs();
            final int pb = (p - b).abs();
            final int pc = (p - c).abs();
            v = x + ((pa <= pb && pa <= pc) ? a : (pb <= pc ? b : c));
          default:
            v = x;
        }
        out[dst + i] = v & 0xFF;
      }
    }
    return out;
  }
}

class _ImageInfo {
  const _ImageInfo(this.jpeg, this.width, this.height, this.channels);
  final bool jpeg;
  final int width;
  final int height;
  final int channels;
}
