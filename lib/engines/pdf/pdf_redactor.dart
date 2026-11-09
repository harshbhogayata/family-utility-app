import 'dart:convert';
import 'dart:io' show ZLibCodec;
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import 'pdf_compressor.dart';
import 'pdf_protector.dart';

/// Feature 013 — Redact.
///
/// True redaction, plain Dart and offline. For every box the person marks:
/// * text drawn under it is cut out of the page's content stream glyph by
///   glyph (the letters around it keep their places);
/// * pictures under it have those pixels overwritten with black, or are
///   dropped when their format cannot be rewritten;
/// * annotations and form fields over it are deleted;
/// * a black box is painted on top so the result looks redacted.
/// Old revisions, page thumbnails and unreachable objects are not carried
/// over, so nothing under a box can be recovered from the file.

@immutable
class RedactBox {
  const RedactBox({required this.page, required this.left, required this.top, required this.width, required this.height});

  /// 0-based page index.
  final int page;

  /// 0–1 units of the page, top-left origin (like 010 Sign PDF).
  final double left;
  final double top;
  final double width;
  final double height;

  bool get isUsable => width > 0.002 && height > 0.002;
}

@immutable
class RedactPageBox {
  const RedactPageBox(this.x0, this.y0, this.x1, this.y1);
  final double x0;
  final double y0;
  final double x1;
  final double y1;

  double get width => x1 - x0;
  double get height => y1 - y0;

  /// A box in page units (bottom-left origin, as PDF text positions are)
  /// turned into a [RedactBox], with a little padding around it.
  RedactBox boxFor(int page, double left, double bottom, double right, double top, {double pad = 1}) {
    final double l = (math.min(left, right) - pad - x0) / width;
    final double t = (y1 - math.max(top, bottom) - pad) / height;
    final double w = ((right - left).abs() + 2 * pad) / width;
    final double h = ((top - bottom).abs() + 2 * pad) / height;
    return RedactBox(page: page, left: l, top: t, width: w, height: h);
  }
}

class RedactError implements Exception {
  const RedactError(this.message);
  final String message;

  @override
  String toString() => message;
}

@immutable
class PdfRedactResult {
  const PdfRedactResult({
    required this.bytes,
    required this.pages,
    required this.glyphsRemoved,
    required this.imagesChanged,
    required this.annotationsRemoved,
  });

  final Uint8List bytes;
  final int pages;
  final int glyphsRemoved;
  final int imagesChanged;
  final int annotationsRemoved;
}

/// What the check after redaction found.
@immutable
class RedactCheck {
  const RedactCheck({required this.glyphsLeft, required this.wordsFound});

  /// Letters still drawn inside any box.
  final int glyphsLeft;

  /// Searched words that can still be found on a redacted page.
  final List<String> wordsFound;

  bool get passed => glyphsLeft == 0 && wordsFound.isEmpty;
}

// ---------------------------------------------------------------------------
// Small helpers

typedef _M = List<double>;

const _M _identity = <double>[1, 0, 0, 1, 0, 0];

_M _mul(_M a, _M b) => <double>[
      a[0] * b[0] + a[1] * b[2],
      a[0] * b[1] + a[1] * b[3],
      a[2] * b[0] + a[3] * b[2],
      a[2] * b[1] + a[3] * b[3],
      a[4] * b[0] + a[5] * b[2] + b[4],
      a[4] * b[1] + a[5] * b[3] + b[5],
    ];

(double, double) _apply(_M m, double x, double y) => (x * m[0] + y * m[2] + m[4], x * m[1] + y * m[3] + m[5]);

_M? _invert(_M m) {
  final double det = m[0] * m[3] - m[1] * m[2];
  if (det.abs() < 1e-12) {
    return null;
  }
  final double a = m[3] / det;
  final double b = -m[1] / det;
  final double c = -m[2] / det;
  final double d = m[0] / det;
  return <double>[a, b, c, d, -(m[4] * a + m[5] * c), -(m[4] * b + m[5] * d)];
}

/// An axis-aligned rectangle in page units.
@immutable
class _Rect {
  const _Rect(this.x0, this.y0, this.x1, this.y1);
  final double x0;
  final double y0;
  final double x1;
  final double y1;

  static _Rect around(List<(double, double)> pts) {
    double x0 = double.infinity, y0 = double.infinity, x1 = -double.infinity, y1 = -double.infinity;
    for (final (double x, double y) in pts) {
      x0 = math.min(x0, x);
      y0 = math.min(y0, y);
      x1 = math.max(x1, x);
      y1 = math.max(y1, y);
    }
    return _Rect(x0, y0, x1, y1);
  }

  static _Rect of(_M m, double x0, double y0, double x1, double y1) =>
      around(<(double, double)>[_apply(m, x0, y0), _apply(m, x1, y0), _apply(m, x0, y1), _apply(m, x1, y1)]);

  double get area => math.max(0, x1 - x0) * math.max(0, y1 - y0);

  double overlap(_Rect o) {
    final double w = math.min(x1, o.x1) - math.max(x0, o.x0);
    final double h = math.min(y1, o.y1) - math.max(y0, o.y0);
    return w <= 0 || h <= 0 ? 0 : w * h;
  }

  bool contains(double x, double y) => x >= x0 && x <= x1 && y >= y0 && y <= y1;
}

bool _hitsAny(_Rect glyph, List<_Rect> rects) {
  final double cx = (glyph.x0 + glyph.x1) / 2;
  final double cy = (glyph.y0 + glyph.y1) / 2;
  final double area = glyph.area;
  for (final _Rect r in rects) {
    if (r.contains(cx, cy)) {
      return true;
    }
    final double o = glyph.overlap(r);
    if (o > 0 && (area <= 0 || o / area >= 0.3)) {
      return true;
    }
  }
  return false;
}

int _clip(int v, int hi) => math.max(0, math.min(hi, v));

String _num(double v) {
  if (v == v.roundToDouble() && v.abs() < 1e9) {
    return v.toInt().toString();
  }
  String s = v.toStringAsFixed(4);
  s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  return s == '-0' ? '0' : s;
}

double _n(Object? v) => v is PdfNum ? v.value.toDouble() : 0;

void _writeValue(StringBuffer o, Object v) {
  if (v is PdfName) {
    o.write('/${v.raw}');
  } else if (v is PdfNum) {
    o.write(v.raw);
  } else if (v is PdfString) {
    o.write(latin1.decode(v.raw));
  } else if (v is PdfRef) {
    o.write('${v.num} ${v.gen} R');
  } else if (v is PdfKeyword) {
    o.write(v.word);
  } else if (v is PdfArray) {
    o.write('[');
    for (int i = 0; i < v.items.length; i++) {
      if (i > 0) {
        o.write(' ');
      }
      _writeValue(o, v.items[i]);
    }
    o.write(']');
  } else if (v is PdfDict) {
    o.write('<<');
    v.entries.forEach((String k, Object e) {
      o.write('/$k ');
      _writeValue(o, e);
      o.write(' ');
    });
    o.write('>>');
  }
}

String _hex(List<int> bytes) =>
    '<${bytes.map((int b) => b.toRadixString(16).padLeft(2, '0')).join()}>';

// ---------------------------------------------------------------------------
// Content stream operations

class _Op {
  _Op(this.operands, this.op, {this.raw});
  List<Object> operands;
  String op;

  /// The exact source of an inline image (BI … EI).
  final Uint8List? raw;

  /// Replaces the whole operation in the output when set.
  String? replacement;
  bool drop = false;
}

List<_Op> _tokenize(Uint8List data) {
  final List<_Op> ops = <_Op>[];
  final PdfParser p = PdfParser(data);
  List<Object> operands = <Object>[];
  while (true) {
    p.skipWhite();
    if (p.pos >= data.length) {
      break;
    }
    final int start = p.pos;
    Object v;
    try {
      v = p.parse();
    } catch (_) {
      p.pos = start + 1;
      continue;
    }
    if (v is PdfKeyword && v.word != 'true' && v.word != 'false' && v.word != 'null') {
      if (v.word == 'BI') {
        // Inline image: find "ID", then the data up to "EI".
        int i = p.pos;
        int idAt = -1;
        while (i + 1 < data.length) {
          if (data[i] == 0x49 && data[i + 1] == 0x44 && PdfParser.isWhite(data[i - 1]) &&
              (i + 2 >= data.length || PdfParser.isWhite(data[i + 2]))) {
            idAt = i;
            break;
          }
          i++;
        }
        int end = data.length;
        if (idAt >= 0) {
          int j = idAt + 3;
          while (j + 1 < data.length) {
            if (data[j] == 0x45 && data[j + 1] == 0x49 && PdfParser.isWhite(data[j - 1]) &&
                (j + 2 >= data.length || PdfParser.isWhite(data[j + 2]))) {
              end = j + 2;
              break;
            }
            j++;
          }
        }
        ops.add(_Op(<Object>[], 'BI', raw: Uint8List.fromList(data.sublist(start, end))));
        p.pos = end;
        operands = <Object>[];
        continue;
      }
      ops.add(_Op(operands, v.word));
      operands = <Object>[];
    } else {
      operands.add(v);
    }
  }
  return ops;
}

String _serialize(List<_Op> ops) {
  final StringBuffer o = StringBuffer();
  for (final _Op op in ops) {
    if (op.drop) {
      continue;
    }
    final String? rep = op.replacement;
    if (rep != null) {
      o.write(rep);
      o.write('\n');
      continue;
    }
    if (op.raw != null) {
      o.write(latin1.decode(op.raw!));
      o.write('\n');
      continue;
    }
    for (final Object v in op.operands) {
      _writeValue(o, v);
      o.write(' ');
    }
    o.write(op.op);
    o.write('\n');
  }
  return o.toString();
}

// ---------------------------------------------------------------------------
// Fonts

class _Font {
  _Font({required this.twoByte, required this.widths, required this.firstChar, required this.fallback, required this.cidWidths, required this.unicode});

  final bool twoByte;
  final List<double> widths;
  final int firstChar;
  final double fallback;
  final Map<int, double> cidWidths;
  final Map<int, String> unicode;

  static final _Font unknown = _Font(
    twoByte: false,
    widths: const <double>[],
    firstChar: 0,
    fallback: 600,
    cidWidths: const <int, double>{},
    unicode: const <int, String>{},
  );

  double width(int code) {
    if (twoByte) {
      return cidWidths[code] ?? fallback;
    }
    final int i = code - firstChar;
    return i >= 0 && i < widths.length ? widths[i] : fallback;
  }

  String text(int code) {
    final String? u = unicode[code];
    if (u != null) {
      return u;
    }
    return twoByte ? '' : String.fromCharCode(code);
  }

  List<int> codes(Uint8List bytes) {
    if (!twoByte) {
      return bytes.toList();
    }
    return <int>[for (int i = 0; i + 1 < bytes.length; i += 2) (bytes[i] << 8) | bytes[i + 1]];
  }
}

// ---------------------------------------------------------------------------
// The engine

abstract final class PdfRedactor {
  static final ZLibCodec _deflate = ZLibCodec(level: 6);
  static final ZLibCodec _inflate = ZLibCodec();

  /// Page boxes in order (MediaBox). Throws [RedactError].
  static List<RedactPageBox> pageBoxes(Uint8List pdf) => _pages(_parse(pdf)).map((_Page p) => p.box).toList();

  /// Cuts everything under [boxes] out of the file and returns the new PDF.
  static PdfRedactResult redact(Uint8List pdf, List<RedactBox> boxes) {
    final List<RedactBox> usable = boxes.where((RedactBox b) => b.isUsable).toList();
    if (usable.isEmpty) {
      throw const RedactError('Mark something to black out first');
    }
    final PdfDocumentModel doc = _parse(pdf);
    final List<_Page> pages = _pages(doc);
    final _Run run = _Run(doc, edit: true);
    final Map<int, List<RedactBox>> byPage = <int, List<RedactBox>>{};
    for (final RedactBox b in usable) {
      if (b.page < 0 || b.page >= pages.length) {
        throw RedactError('Page ${b.page + 1} does not exist');
      }
      byPage.putIfAbsent(b.page, () => <RedactBox>[]).add(b);
    }

    int annots = 0;
    byPage.forEach((int index, List<RedactBox> list) {
      final _Page page = pages[index];
      final PdfDict dict = page.obj.value as PdfDict;
      final List<_Rect> rects = list.map((RedactBox b) => _rectOf(b, page.box)).toList();

      // Page resources, copied so other pages sharing them stay as they were.
      final Object? res = doc.resolve(dict['Resources']) ?? page.inheritedResources;
      final PdfDict resources = PdfDict(res is PdfDict ? Map<String, Object>.of(res.entries) : <String, Object>{});
      final Uint8List content = _pageContent(doc, dict);
      final String rewritten = run.process(content, resources, _identity, rects, 0);

      final StringBuffer cover = StringBuffer('Q\nq 0 0 0 rg\n');
      for (final _Rect r in rects) {
        cover.write('${_num(r.x0)} ${_num(r.y0)} ${_num(r.x1 - r.x0)} ${_num(r.y1 - r.y0)} re f\n');
      }
      cover.write('Q\n');
      final int contentNum = run.add(
        PdfDict(<String, Object>{'Filter': const PdfName('FlateDecode')}),
        Uint8List.fromList(_deflate.encode(latin1.encode('q\n$rewritten$cover'))),
      );
      dict.entries['Contents'] = PdfRef(contentNum, 0);
      dict.entries['Resources'] = resources;
      dict.entries.remove('Thumb');
      dict.entries.remove('PieceInfo');
      annots += _dropAnnotations(doc, dict, rects);
    });

    // Only what the new file still points at is written: old copies of
    // the content, replaced pictures and earlier revisions are gone.
    final Set<int> keep = doc.reachable();
    doc.objects.removeWhere((int n, PdfObject _) => !keep.contains(n));
    return PdfRedactResult(
      bytes: doc.write(),
      pages: pages.length,
      glyphsRemoved: run.glyphsRemoved,
      imagesChanged: run.imagesChanged,
      annotationsRemoved: annots,
    );
  }

  /// Reads the redacted file back: no letter may still be drawn under a
  /// box, and none of [words] may still be found on a redacted page.
  static RedactCheck verify(Uint8List pdf, List<RedactBox> boxes, {List<String> words = const <String>[]}) {
    final PdfDocumentModel doc = _parse(pdf);
    final List<_Page> pages = _pages(doc);
    int left = 0;
    final Set<int> touched = boxes.map((RedactBox b) => b.page).toSet();
    final StringBuffer text = StringBuffer();
    for (final int index in touched) {
      if (index < 0 || index >= pages.length) {
        continue;
      }
      final _Page page = pages[index];
      final PdfDict dict = page.obj.value as PdfDict;
      final List<_Rect> rects = boxes.where((RedactBox b) => b.page == index).map((RedactBox b) => _rectOf(b, page.box)).toList();
      final Object? res = doc.resolve(dict['Resources']) ?? page.inheritedResources;
      final _Run run = _Run(doc, edit: false);
      run.process(_pageContent(doc, dict), res is PdfDict ? res : PdfDict(<String, Object>{}), _identity, rects, 0);
      left += run.glyphsInside;
      text.write(run.text);
      text.write(' ');
    }
    final String flat = _flat(text.toString());
    final List<String> found = <String>[
      for (final String w in words)
        if (_flat(w).isNotEmpty && flat.contains(_flat(w))) w,
    ];
    return RedactCheck(glyphsLeft: left, wordsFound: found);
  }

  /// The text the engine reads on one page (0-based), in drawing order.
  static String pageText(Uint8List pdf, int index) {
    final PdfDocumentModel doc = _parse(pdf);
    final List<_Page> pages = _pages(doc);
    if (index < 0 || index >= pages.length) {
      return '';
    }
    final _Page page = pages[index];
    final PdfDict dict = page.obj.value as PdfDict;
    final Object? res = doc.resolve(dict['Resources']) ?? page.inheritedResources;
    final _Run run = _Run(doc, edit: false);
    run.process(_pageContent(doc, dict), res is PdfDict ? res : PdfDict(<String, Object>{}), _identity, const <_Rect>[], 0);
    return run.text.toString();
  }

  static String _flat(String s) => s.toLowerCase().replaceAll(RegExp(r'\s+'), '');

  static _Rect _rectOf(RedactBox b, RedactPageBox box) {
    final double x0 = box.x0 + b.left * box.width;
    final double x1 = box.x0 + (b.left + b.width) * box.width;
    final double y1 = box.y1 - b.top * box.height;
    final double y0 = box.y1 - (b.top + b.height) * box.height;
    return _Rect(x0, y0, x1, y1);
  }

  static int _dropAnnotations(PdfDocumentModel doc, PdfDict page, List<_Rect> rects) {
    final Object? a = doc.resolve(page['Annots']);
    if (a is! PdfArray) {
      return 0;
    }
    final List<Object> kept = <Object>[];
    final Set<int> dropped = <int>{};
    for (final Object item in a.items) {
      final Object? annot = doc.resolve(item);
      final Object? r = annot is PdfDict ? doc.resolve(annot['Rect']) : null;
      if (r is PdfArray && r.items.length == 4) {
        final List<double> v = r.items.map(_n).toList();
        final _Rect ar = _Rect(math.min(v[0], v[2]), math.min(v[1], v[3]), math.max(v[0], v[2]), math.max(v[1], v[3]));
        if (rects.any((_Rect x) => ar.overlap(x) > 0)) {
          if (item is PdfRef) {
            dropped.add(item.num);
          }
          continue;
        }
      }
      kept.add(item);
    }
    final int removed = a.items.length - kept.length;
    if (removed == 0) {
      return 0;
    }
    page.entries['Annots'] = PdfArray(kept);
    if (dropped.isNotEmpty) {
      // Form fields that were dropped leave the form too.
      final Object? root = doc.resolve(doc.trailer['Root']);
      final Object? form = root is PdfDict ? doc.resolve(root['AcroForm']) : null;
      final Object? fields = form is PdfDict ? doc.resolve(form['Fields']) : null;
      if (form is PdfDict && fields is PdfArray) {
        form.entries['Fields'] = PdfArray(<Object>[
          for (final Object f in fields.items)
            if (!(f is PdfRef && dropped.contains(f.num))) f,
        ]);
      }
    }
    return removed;
  }

  static PdfDocumentModel _parse(Uint8List pdf) {
    try {
      return PdfDocumentModel.parse(pdf);
    } on PdfCompressError catch (e) {
      throw RedactError(e.message);
    }
  }

  static Uint8List _pageContent(PdfDocumentModel doc, PdfDict page) {
    final Object? c = page['Contents'];
    final List<Object> parts = <Object>[];
    final Object? resolved = doc.resolve(c);
    if (c is PdfArray) {
      parts.addAll(c.items);
    } else if (resolved is PdfArray) {
      parts.addAll(resolved.items);
    } else if (c != null) {
      parts.add(c);
    }
    final BytesBuilder bb = BytesBuilder(copy: false);
    for (final Object p in parts) {
      if (p is! PdfRef) {
        continue;
      }
      final PdfObject? o = doc.objects[p.num];
      if (o == null || o.stream == null || o.value is! PdfDict) {
        continue;
      }
      bb.add(decode(o.value as PdfDict, o.stream!) ??
          (throw const RedactError('This PDF stores its pages in a way the app cannot redact yet.')));
      bb.addByte(10);
    }
    return bb.takeBytes();
  }

  /// The stream's bytes with Flate undone; null for other filters.
  static Uint8List? decode(PdfDict d, Uint8List data) {
    final List<String> f = PdfDocumentModel.filters(d);
    if (f.isEmpty) {
      return data;
    }
    if (f.length != 1 || f.first != 'FlateDecode') {
      return null;
    }
    final Object? parms = d['DecodeParms'];
    if (parms is PdfDict && (parms.integer('Predictor') ?? 1) > 1) {
      return null;
    }
    try {
      return Uint8List.fromList(_inflate.decode(data));
    } catch (_) {
      return null;
    }
  }

  static List<_Page> _pages(PdfDocumentModel doc) {
    final Object? root = doc.resolve(doc.trailer['Root']);
    if (root is! PdfDict) {
      throw const RedactError('This PDF has no pages');
    }
    final List<_Page> out = <_Page>[];
    void walk(Object? node, RedactPageBox? box, Object? res, int depth) {
      if (depth > 64 || node is! PdfRef) {
        return;
      }
      final PdfObject? obj = doc.objects[node.num];
      final Object? v = obj?.value;
      if (obj == null || v is! PdfDict) {
        return;
      }
      final RedactPageBox? useBox = _box(doc.resolve(v['MediaBox'])) ?? box;
      final Object? useRes = doc.resolve(v['Resources']) ?? res;
      if (v.name('Type') == 'Page' || (v['Kids'] == null && v['Contents'] != null)) {
        out.add(_Page(obj, useBox ?? const RedactPageBox(0, 0, 612, 792), useRes));
        return;
      }
      final Object? kids = doc.resolve(v['Kids']);
      if (kids is PdfArray) {
        for (final Object k in kids.items) {
          walk(k, useBox, useRes, depth + 1);
        }
      }
    }

    walk(root['Pages'], null, null, 0);
    if (out.isEmpty) {
      throw const RedactError('This PDF has no pages');
    }
    return out;
  }

  static RedactPageBox? _box(Object? v) {
    if (v is! PdfArray || v.items.length != 4) {
      return null;
    }
    final List<double> n = v.items.map(_n).toList();
    return RedactPageBox(math.min(n[0], n[2]), math.min(n[1], n[3]), math.max(n[0], n[2]), math.max(n[1], n[3]));
  }
}

class _Page {
  _Page(this.obj, this.box, this.inheritedResources);
  final PdfObject obj;
  final RedactPageBox box;
  final Object? inheritedResources;
}

/// One pass over content streams: rewrites them (edit) or reads them (check).
class _Run {
  _Run(this.doc, {required this.edit}) : next = doc.objects.keys.fold<int>(0, math.max) + 1;

  final PdfDocumentModel doc;
  final bool edit;
  int next;
  int glyphsRemoved = 0;
  int glyphsInside = 0;
  int imagesChanged = 0;
  int _names = 0;
  final StringBuffer text = StringBuffer();
  final Map<PdfDict, _Font> _fonts = <PdfDict, _Font>{};

  int add(PdfDict dict, Uint8List stream) {
    final int n = next++;
    doc.objects[n] = PdfObject(n, 0, dict, stream: stream);
    return n;
  }

  String _freshName(PdfDict xobjects) {
    String name;
    do {
      _names++;
      name = 'FuaRed$_names';
    } while (xobjects.entries.containsKey(name));
    return name;
  }

  /// Walks [content] drawn with [resources] under [base]. In edit mode the
  /// returned text is the new content and [resources] may gain entries.
  String process(Uint8List content, PdfDict resources, _M base, List<_Rect> rects, int depth) {
    final List<_Op> ops = _tokenize(content);
    final List<_M> stack = <_M>[];
    _M ctm = base;
    _M tm = _identity;
    _M tlm = _identity;
    _Font font = _Font.unknown;
    double fs = 0, tc = 0, tw = 0, th = 1, tl = 0, rise = 0;
    PdfDict? xobjects;
    final Set<String> replaced = <String>{};

    PdfDict xobjectsDict() {
      if (xobjects != null) {
        return xobjects!;
      }
      final Object? x = doc.resolve(resources['XObject']);
      final PdfDict copy = PdfDict(x is PdfDict ? Map<String, Object>.of(x.entries) : <String, Object>{});
      if (edit) {
        resources.entries['XObject'] = copy;
      }
      return xobjects = copy;
    }

    void nextLine(double tx, double ty) {
      tlm = _mul(<double>[1, 0, 0, 1, tx, ty], tlm);
      tm = tlm;
    }

    /// Shows one string; returns the TJ items to draw instead, or null when
    /// nothing in it was removed.
    List<String>? show(Uint8List bytes) {
      final List<int> codes = font.codes(bytes);
      bool removedAny = false;
      final List<String> items = <String>[];
      final List<int> run = <int>[];
      void flush() {
        if (run.isNotEmpty) {
          items.add(_hex(run));
          run.clear();
        }
      }

      for (final int code in codes) {
        final double w0 = font.width(code) / 1000;
        final double spacing = (!font.twoByte && code == 32) ? tw : 0;
        final _M m = _mul(tm, ctm);
        final _Rect box = _Rect.of(m, 0, rise - 0.2 * fs, w0 * fs * th, rise + 0.8 * fs);
        final bool inside = rects.isNotEmpty && _hitsAny(box, rects);
        final double advance = (w0 * fs + tc + spacing) * th;
        if (inside) {
          glyphsInside++;
        }
        if (edit && inside && fs != 0 && th != 0) {
          removedAny = true;
          glyphsRemoved++;
          flush();
          items.add(_num(-advance / th / fs * 1000));
        } else {
          text.write(font.text(code));
          if (font.twoByte) {
            run.addAll(<int>[(code >> 8) & 0xFF, code & 0xFF]);
          } else {
            run.add(code);
          }
        }
        tm = _mul(<double>[1, 0, 0, 1, advance, 0], tm);
      }
      flush();
      return removedAny ? items : null;
    }

    for (final _Op op in ops) {
      final List<Object> a = op.operands;
      switch (op.op) {
        case 'q':
          stack.add(ctm);
        case 'Q':
          if (stack.isNotEmpty) {
            ctm = stack.removeLast();
          }
        case 'cm':
          if (a.length == 6) {
            ctm = _mul(a.map(_n).toList(), ctm);
          }
        case 'BT':
          tm = _identity;
          tlm = _identity;
        case 'ET':
          text.write(' ');
        case 'Tf':
          if (a.length == 2) {
            fs = _n(a[1]);
            final Object? fonts = doc.resolve(resources['Font']);
            final Object? f = a[0] is PdfName && fonts is PdfDict ? doc.resolve(fonts[(a[0] as PdfName).raw]) : null;
            font = f is PdfDict ? _font(f) : _Font.unknown;
          }
        case 'Tc':
          if (a.isNotEmpty) {
            tc = _n(a[0]);
          }
        case 'Tw':
          if (a.isNotEmpty) {
            tw = _n(a[0]);
          }
        case 'Tz':
          if (a.isNotEmpty) {
            th = _n(a[0]) / 100;
          }
        case 'TL':
          if (a.isNotEmpty) {
            tl = _n(a[0]);
          }
        case 'Ts':
          if (a.isNotEmpty) {
            rise = _n(a[0]);
          }
        case 'Td':
          if (a.length == 2) {
            nextLine(_n(a[0]), _n(a[1]));
          }
          text.write(' ');
        case 'TD':
          if (a.length == 2) {
            tl = -_n(a[1]);
            nextLine(_n(a[0]), _n(a[1]));
          }
          text.write(' ');
        case 'Tm':
          if (a.length == 6) {
            tlm = a.map(_n).toList();
            tm = tlm;
          }
          text.write(' ');
        case 'T*':
          nextLine(0, -tl);
          text.write(' ');
        case 'Tj':
        case "'":
        case '"':
          String prefix = '';
          if (op.op == '"' && a.length == 3) {
            tw = _n(a[0]);
            tc = _n(a[1]);
            prefix = '${_num(tw)} Tw ${_num(tc)} Tc ';
          }
          if (op.op != 'Tj') {
            nextLine(0, -tl);
            text.write(' ');
            prefix = '${prefix}T* ';
          }
          final Object? s = a.isEmpty ? null : a.last;
          if (s is PdfString) {
            final List<String>? items = show(PdfProtector.stringBytes(s.raw));
            if (items != null) {
              op.replacement = '$prefix[${items.join(' ')}] TJ';
            }
          }
        case 'TJ':
          final Object? arr = a.isEmpty ? null : a.last;
          if (arr is PdfArray) {
            bool changed = false;
            final List<String> items = <String>[];
            for (final Object item in arr.items) {
              if (item is PdfString) {
                final Uint8List bytes = PdfProtector.stringBytes(item.raw);
                final List<String>? got = show(bytes);
                if (got != null) {
                  changed = true;
                  items.addAll(got);
                } else {
                  items.add(_hex(bytes));
                }
              } else if (item is PdfNum) {
                final double adj = item.value.toDouble();
                if (adj < -200) {
                  text.write(' ');
                }
                tm = _mul(<double>[1, 0, 0, 1, -adj / 1000 * fs * th, 0], tm);
                items.add(item.raw);
              }
            }
            if (changed) {
              op.replacement = '[${items.join(' ')}] TJ';
            }
          }
        case 'Do':
          if (a.isNotEmpty && a.first is PdfName) {
            final String name = (a.first as PdfName).raw;
            if (_doXObject(op, name, xobjectsDict, resources, ctm, rects, depth)) {
              replaced.add(name);
            }
          }
        case 'BI':
          // An inline picture under a box is dropped whole.
          if (edit && rects.any((_Rect r) => _Rect.of(ctm, 0, 0, 1, 1).overlap(r) > 0)) {
            op.drop = true;
            imagesChanged++;
          }
        case 'BDC':
          // Marked content may carry the hidden words as /ActualText.
          if (edit && rects.isNotEmpty && a.length == 2 && a[1] is PdfDict) {
            final PdfDict props = a[1] as PdfDict;
            props.entries.remove('ActualText');
            props.entries.remove('Alt');
            props.entries.remove('E');
          }
      }
    }
    // A replaced or dropped XObject leaves the resources when nothing on
    // this content draws it any more, so the old copy is not written out.
    final PdfDict? xo = xobjects;
    if (edit && xo != null && replaced.isNotEmpty) {
      final Set<String> used = <String>{
        for (final _Op op in ops)
          if (!op.drop && op.op == 'Do' && op.operands.isNotEmpty && op.operands.first is PdfName)
            (op.operands.first as PdfName).raw,
      };
      xo.entries.removeWhere((String k, Object _) => replaced.contains(k) && !used.contains(k));
    }
    return edit ? _serialize(ops) : '';
  }

  /// True when the drawing was replaced or dropped.
  bool _doXObject(_Op op, String name, PdfDict Function() xobjectsDict, PdfDict resources, _M ctm, List<_Rect> rects,
      int depth) {
    final PdfDict xobjects = xobjectsDict();
    final Object? ref = xobjects[name];
    final PdfObject? obj = ref is PdfRef ? doc.objects[ref.num] : null;
    final Object? v = obj?.value;
    if (obj == null || v is! PdfDict || obj.stream == null) {
      return false;
    }
    final String? sub = v.name('Subtype');
    if (sub == 'Image') {
      final _Rect area = _Rect.of(ctm, 0, 0, 1, 1);
      final List<_Rect> hit = rects.where((_Rect r) => area.overlap(r) > 0).toList();
      if (hit.isEmpty || !edit) {
        return false;
      }
      imagesChanged++;
      final int? replaced = _blankImage(v, obj.stream!, ctm, hit);
      if (replaced == null) {
        op.drop = true;
        return true;
      }
      final String fresh = _freshName(xobjects);
      xobjects.entries[fresh] = PdfRef(replaced, 0);
      op.operands = <Object>[PdfName(fresh)];
      return true;
    }
    if (sub == 'Form' && depth < 12) {
      final Object? mObj = doc.resolve(v['Matrix']);
      final _M matrix = mObj is PdfArray && mObj.items.length == 6 ? mObj.items.map(_n).toList() : _identity;
      final _M formCtm = _mul(matrix, ctm);
      final Object? bb = doc.resolve(v['BBox']);
      if (bb is PdfArray && bb.items.length == 4) {
        final List<double> b = bb.items.map(_n).toList();
        final _Rect area = _Rect.of(formCtm, b[0], b[1], b[2], b[3]);
        // In check mode its text is still read for the word search.
        if (edit && !rects.any((_Rect r) => area.overlap(r) > 0)) {
          return false;
        }
      }
      final Uint8List? data = PdfRedactor.decode(v, obj.stream!);
      if (data == null) {
        if (edit && rects.isNotEmpty) {
          op.drop = true;
          return true;
        }
        return false;
      }
      final Object? own = doc.resolve(v['Resources']);
      final PdfDict formRes = PdfDict(own is PdfDict ? Map<String, Object>.of(own.entries) : Map<String, Object>.of(resources.entries));
      final int removedBefore = glyphsRemoved;
      final int imagesBefore = imagesChanged;
      final String out = process(data, formRes, formCtm, rects, depth + 1);
      if (!edit || (glyphsRemoved == removedBefore && imagesChanged == imagesBefore)) {
        return false;
      }
      final Map<String, Object> entries = Map<String, Object>.of(v.entries)
        ..remove('DecodeParms')
        ..remove('Length')
        ..['Filter'] = const PdfName('FlateDecode')
        ..['Resources'] = formRes;
      final int n = add(PdfDict(entries), Uint8List.fromList(_deflate.encode(latin1.encode(out))));
      final String fresh = _freshName(xobjects);
      xobjects.entries[fresh] = PdfRef(n, 0);
      op.operands = <Object>[PdfName(fresh)];
      return true;
    }
    return false;
  }

  static final ZLibCodec _deflate = ZLibCodec(level: 6);

  /// A copy of the image with the pixels under [rects] set to black; null
  /// when the image's format cannot be rewritten (the caller drops it).
  int? _blankImage(PdfDict dict, Uint8List stream, _M ctm, List<_Rect> rects) {
    final _M? inv = _invert(ctm);
    final int w = dict.integer('Width') ?? 0;
    final int h = dict.integer('Height') ?? 0;
    if (inv == null || w <= 0 || h <= 0) {
      return null;
    }
    List<(int, int, int, int)> pixelBoxes() {
      final List<(int, int, int, int)> out = <(int, int, int, int)>[];
      for (final _Rect r in rects) {
        final _Rect u = _Rect.of(inv, r.x0, r.y0, r.x1, r.y1);
        out.add((
          _clip((u.x0 * w).floor(), w),
          _clip(((1 - u.y1) * h).floor(), h),
          _clip((u.x1 * w).ceil(), w),
          _clip(((1 - u.y0) * h).ceil(), h),
        ));
      }
      return out;
    }

    final List<String> filters = PdfDocumentModel.filters(dict);
    final Map<String, Object> entries = Map<String, Object>.of(dict.entries)..remove('Length');
    if (filters.length == 1 && filters.first == 'DCTDecode') {
      if (dict.name('ColorSpace') == 'DeviceCMYK') {
        return null;
      }
      final img.Image? im = img.decodeJpg(stream);
      if (im == null || im.width != w || im.height != h) {
        return null;
      }
      for (final (int x0, int y0, int x1, int y1) in pixelBoxes()) {
        if (x1 > x0 && y1 > y0) {
          img.fillRect(im, x1: x0, y1: y0, x2: x1 - 1, y2: y1 - 1, color: img.ColorRgb8(0, 0, 0));
        }
      }
      entries.remove('DecodeParms');
      return add(PdfDict(entries), img.encodeJpg(im, quality: 90));
    }
    if (dict['ImageMask'] is PdfKeyword || (dict.integer('BitsPerComponent') ?? 8) != 8) {
      return null;
    }
    final int? comps = _components(dict['ColorSpace']);
    final Uint8List? raw = PdfRedactor.decode(dict, stream);
    if (comps == null || raw == null || raw.length < w * h * comps) {
      return null;
    }
    final Uint8List px = Uint8List.fromList(raw);
    final List<int> black = comps == 4 ? <int>[0, 0, 0, 255] : List<int>.filled(comps, 0);
    for (final (int x0, int y0, int x1, int y1) in pixelBoxes()) {
      for (int y = y0; y < y1; y++) {
        for (int x = x0; x < x1; x++) {
          final int at = (y * w + x) * comps;
          for (int c = 0; c < comps; c++) {
            px[at + c] = black[c];
          }
        }
      }
    }
    entries
      ..remove('DecodeParms')
      ..['Filter'] = const PdfName('FlateDecode');
    return add(PdfDict(entries), Uint8List.fromList(_deflate.encode(px)));
  }

  int? _components(Object? cs) {
    final Object? v = doc.resolve(cs);
    if (v is PdfName) {
      return switch (v.raw) { 'DeviceGray' || 'G' => 1, 'DeviceRGB' || 'RGB' => 3, 'DeviceCMYK' || 'CMYK' => 4, _ => null };
    }
    if (v is PdfArray && v.items.isNotEmpty && v.items.first is PdfName) {
      final String kind = (v.items.first as PdfName).raw;
      if (kind == 'Indexed' || kind == 'I') {
        return 1;
      }
      if (kind == 'ICCBased' && v.items.length > 1) {
        final Object? s = doc.resolve(v.items[1]);
        return s is PdfDict ? s.integer('N') : null;
      }
      if (kind == 'CalRGB') {
        return 3;
      }
      if (kind == 'CalGray') {
        return 1;
      }
    }
    return null;
  }

  _Font _font(PdfDict f) {
    return _fonts.putIfAbsent(f, () {
      final Map<int, String> unicode = _toUnicode(f['ToUnicode']);
      if (f.name('Subtype') == 'Type0') {
        final Object? kids = doc.resolve(f['DescendantFonts']);
        final Object? cid = kids is PdfArray && kids.items.isNotEmpty ? doc.resolve(kids.items.first) : null;
        double dw = 1000;
        final Map<int, double> widths = <int, double>{};
        if (cid is PdfDict) {
          if (cid['DW'] is PdfNum) {
            dw = _n(cid['DW']);
          }
          final Object? wArr = doc.resolve(cid['W']);
          if (wArr is PdfArray) {
            final List<Object> items = wArr.items.map((Object o) => doc.resolve(o) ?? o).toList();
            int i = 0;
            while (i < items.length) {
              final Object first = items[i];
              if (first is! PdfNum || i + 1 >= items.length) {
                break;
              }
              final Object second = items[i + 1];
              if (second is PdfArray) {
                int c = first.value.toInt();
                for (final Object wv in second.items) {
                  widths[c++] = _n(doc.resolve(wv));
                }
                i += 2;
              } else if (second is PdfNum && i + 2 < items.length) {
                final int last = second.value.toInt();
                final double wv = _n(items[i + 2]);
                for (int c = first.value.toInt(); c <= last && c - first.value.toInt() < 65536; c++) {
                  widths[c] = wv;
                }
                i += 3;
              } else {
                break;
              }
            }
          }
        }
        return _Font(
          twoByte: true,
          widths: const <double>[],
          firstChar: 0,
          fallback: dw,
          cidWidths: widths,
          unicode: unicode,
        );
      }
      final Object? wArr = doc.resolve(f['Widths']);
      final Object? desc = doc.resolve(f['FontDescriptor']);
      double fallback = 0;
      if (desc is PdfDict && desc['MissingWidth'] is PdfNum) {
        fallback = _n(desc['MissingWidth']);
      }
      if (wArr is! PdfArray) {
        final String base = f.name('BaseFont') ?? '';
        fallback = base.contains('Courier') ? 600 : (base.contains('Times') ? 500 : 556);
      } else if (fallback == 0) {
        fallback = 500;
      }
      return _Font(
        twoByte: false,
        widths: wArr is PdfArray ? wArr.items.map((Object o) => _n(doc.resolve(o))).toList() : const <double>[],
        firstChar: f.integer('FirstChar') ?? 0,
        fallback: fallback,
        cidWidths: const <int, double>{},
        unicode: unicode,
      );
    });
  }

  Map<int, String> _toUnicode(Object? ref) {
    final Map<int, String> out = <int, String>{};
    final PdfObject? o = ref is PdfRef ? doc.objects[ref.num] : null;
    if (o == null || o.stream == null || o.value is! PdfDict) {
      return out;
    }
    final Uint8List? data = PdfRedactor.decode(o.value as PdfDict, o.stream!);
    if (data == null) {
      return out;
    }
    final String s = latin1.decode(data);
    int hex(String h) => int.tryParse(h, radix: 16) ?? 0;
    String utf16(String h) {
      final List<int> units = <int>[for (int i = 0; i + 4 <= h.length; i += 4) hex(h.substring(i, i + 4))];
      return String.fromCharCodes(units);
    }

    for (final RegExpMatch block in RegExp(r'beginbfchar([\s\S]*?)endbfchar').allMatches(s)) {
      for (final RegExpMatch m in RegExp(r'<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]*)>').allMatches(block.group(1)!)) {
        out[hex(m.group(1)!)] = utf16(m.group(2)!);
      }
    }
    for (final RegExpMatch block in RegExp(r'beginbfrange([\s\S]*?)endbfrange').allMatches(s)) {
      final String body = block.group(1)!;
      for (final RegExpMatch m
          in RegExp(r'<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>\s*(<([0-9A-Fa-f]*)>|\[([^\]]*)\])').allMatches(body)) {
        final int lo = hex(m.group(1)!);
        final int hi = hex(m.group(2)!);
        if (hi < lo || hi - lo > 65535) {
          continue;
        }
        if (m.group(4) != null) {
          final String base = m.group(4)!;
          final List<int> units = <int>[for (int i = 0; i + 4 <= base.length; i += 4) hex(base.substring(i, i + 4))];
          if (units.isEmpty) {
            continue;
          }
          for (int c = lo; c <= hi; c++) {
            final List<int> u = List<int>.of(units);
            u[u.length - 1] += c - lo;
            out[c] = String.fromCharCodes(u);
          }
        } else {
          final List<String> list =
              RegExp(r'<([0-9A-Fa-f]*)>').allMatches(m.group(5)!).map((RegExpMatch x) => x.group(1)!).toList();
          for (int i = 0; i < list.length && lo + i <= hi; i++) {
            out[lo + i] = utf16(list[i]);
          }
        }
      }
    }
    return out;
  }
}
