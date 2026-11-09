import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'pdf_compressor.dart';
import 'pdf_merger.dart' show PdfMerger;
import 'pdf_signer.dart' show PageBox;

/// Feature 009 — Fill forms.
///
/// Reads the AcroForm fields of a PDF (text, check box, radio, choice),
/// writes new values with a fresh appearance so every viewer shows them,
/// and can flatten the fields into the page on export. PDFs without a form
/// are filled by placing text boxes anywhere on a page. Pure Dart on the
/// 032 PDF object model; nothing leaves the phone.

enum FormFieldKind { text, checkbox, radio, choice, signature, button }

/// One fillable field, by its full name ("applicant.name").
class FormFieldInfo {
  const FormFieldInfo({
    required this.name,
    required this.kind,
    required this.value,
    required this.page,
    required this.rect,
    this.options = const <String>[],
    this.readOnly = false,
    this.multiline = false,
    this.maxLength,
    this.caption,
  });

  final String name;
  final FormFieldKind kind;

  /// Text, the chosen option, or the on-state name ("Off" when unticked).
  final String value;

  /// 0-based page of the first widget, -1 when it has none.
  final int page;

  /// The first widget's rectangle in PDF points.
  final PageBox? rect;

  /// Choice options, or the on-states of a check box / radio group.
  final List<String> options;
  final bool readOnly;
  final bool multiline;
  final int? maxLength;

  /// The /TU tooltip, which forms often use for the visible caption.
  final String? caption;

  bool get editable => !readOnly && kind != FormFieldKind.signature && kind != FormFieldKind.button;

  /// The label a person sees: the caption, else the last part of the name.
  String get label {
    final String? c = caption;
    if (c != null && c.trim().isNotEmpty) {
      return c.trim();
    }
    final String last = name.split('.').last;
    return last.replaceAll(RegExp(r'[_\-]+'), ' ').replaceAllMapped(RegExp(r'([a-z])([A-Z])'), (Match m) => '${m[1]} ${m[2]}').trim();
  }

  bool get checked => (kind == FormFieldKind.checkbox || kind == FormFieldKind.radio) && value != 'Off' && value.isNotEmpty;
}

/// Text placed anywhere on a page (for PDFs without a form). [left] and
/// [top] are fractions of the page from its top-left corner.
class PlacedText {
  const PlacedText({required this.page, required this.left, required this.top, required this.text, this.fontSize = 12});

  final int page;
  final double left;
  final double top;
  final String text;
  final double fontSize;

  PlacedText copyWith({double? left, double? top, String? text, double? fontSize}) => PlacedText(
        page: page,
        left: left ?? this.left,
        top: top ?? this.top,
        text: text ?? this.text,
        fontSize: fontSize ?? this.fontSize,
      );
}

class FormInfo {
  const FormInfo({required this.fields, required this.pages});

  final List<FormFieldInfo> fields;
  final List<PageBox> pages;

  bool get hasForm => fields.isNotEmpty;
}

class FormFillError implements Exception {
  const FormFillError(this.message);
  final String message;
  @override
  String toString() => message;
}

class _Field {
  _Field(this.name, this.dict, this.widgets, this.ft, this.ff);
  final String name;
  final PdfDict dict;
  final List<PdfDict> widgets;
  final String? ft;
  final int ff;
}

class _Doc {
  _Doc(this.model, this.pages, this.pageDicts, this.widgetPage, this.fields, this.acroForm);
  final PdfDocumentModel model;
  final List<PageBox> pages;
  final List<PdfDict> pageDicts;
  final Map<PdfDict, int> widgetPage;
  final List<_Field> fields;
  final PdfDict? acroForm;
}

abstract final class PdfFormFiller {
  static const String fontName = 'FuaHelv';

  /// Fields and page sizes, without changing the file.
  static FormInfo detect(Uint8List pdf) {
    final _Doc d = _open(pdf);
    return FormInfo(fields: d.fields.map((_Field f) => _info(d, f)).toList(), pages: d.pages);
  }

  /// Writes [values] (by full field name) and [texts] into the PDF. With
  /// [flatten] the fields become part of the page and the form is removed.
  static Uint8List fill(
    Uint8List pdf, {
    Map<String, String> values = const <String, String>{},
    List<PlacedText> texts = const <PlacedText>[],
    bool flatten = false,
  }) {
    final _Doc d = _open(pdf);
    final PdfDocumentModel doc = d.model;
    int next = doc.objects.keys.fold<int>(0, math.max) + 1;
    final int fontNum = next++;
    doc.objects[fontNum] = PdfObject(fontNum, 0, _helvetica());

    for (final _Field f in d.fields) {
      final String? v = values[f.name];
      if (v == null) {
        continue;
      }
      final FormFieldInfo info = _info(d, f);
      if (!info.editable) {
        continue;
      }
      switch (info.kind) {
        case FormFieldKind.text:
        case FormFieldKind.choice:
          final String text = info.maxLength != null && v.length > info.maxLength! ? v.substring(0, info.maxLength) : v;
          f.dict.entries['V'] = PdfMerger.textString(text);
          for (final PdfDict w in f.widgets) {
            next = _textAppearance(doc, w, f, text, fontNum, next, multiline: info.multiline);
          }
        case FormFieldKind.checkbox:
        case FormFieldKind.radio:
          final String on = _onValue(v, info.options);
          f.dict.entries['V'] = PdfName(on);
          for (final PdfDict w in f.widgets) {
            final List<String> states = _onStates(doc, w);
            w.entries['AS'] = PdfName(states.contains(on) ? on : 'Off');
          }
        case FormFieldKind.signature:
        case FormFieldKind.button:
          break;
      }
    }

    final PdfDict? acro = d.acroForm;
    if (acro != null && !flatten) {
      acro.entries['NeedAppearances'] = const PdfKeyword('true');
      final Object? dr = doc.resolve(acro['DR']);
      final PdfDict res = dr is PdfDict ? dr : PdfDict(<String, Object>{});
      final Object? fo = doc.resolve(res['Font']);
      final PdfDict fonts = fo is PdfDict ? fo : PdfDict(<String, Object>{});
      fonts.entries[fontName] = PdfRef(fontNum, 0);
      res.entries['Font'] = fonts;
      acro.entries['DR'] = res;
    }

    if (flatten) {
      next = _flatten(d, next);
    }

    for (final PlacedText t in texts) {
      if (t.text.trim().isEmpty || t.page < 0 || t.page >= d.pages.length) {
        continue;
      }
      next = _stampText(d, t, fontNum, next);
    }
    return doc.write();
  }

  // ---- reading ------------------------------------------------------------

  static _Doc _open(Uint8List pdf) {
    final PdfDocumentModel doc;
    try {
      doc = PdfDocumentModel.parse(pdf);
    } on PdfCompressError catch (e) {
      throw FormFillError(e.message);
    } catch (_) {
      throw const FormFillError('This PDF could not be read. It may be damaged or locked.');
    }
    if (doc.trailer['Encrypt'] != null) {
      throw const FormFillError('This PDF is locked. Unlock it first, then fill it.');
    }
    final Object? root = doc.resolve(doc.trailer['Root']);
    if (root is! PdfDict) {
      throw const FormFillError('This PDF has no pages');
    }
    final List<PageBox> boxes = <PageBox>[];
    final List<PdfDict> pageDicts = <PdfDict>[];
    void walk(Object? node, PageBox? box, int depth) {
      final Object? v = doc.resolve(node);
      if (depth > 64 || v is! PdfDict) {
        return;
      }
      final PageBox? useBox = _box(doc.resolve(v['MediaBox'])) ?? box;
      if (v.name('Type') == 'Page' || (v['Kids'] == null && v['Contents'] != null)) {
        boxes.add(useBox ?? const PageBox(0, 0, 612, 792));
        pageDicts.add(v);
        return;
      }
      final Object? kids = doc.resolve(v['Kids']);
      if (kids is PdfArray) {
        for (final Object k in kids.items) {
          walk(k, useBox, depth + 1);
        }
      }
    }

    walk(root['Pages'], null, 0);
    if (boxes.isEmpty) {
      throw const FormFillError('This PDF has no pages');
    }

    final Map<PdfDict, int> widgetPage = Map<PdfDict, int>.identity();
    for (int i = 0; i < pageDicts.length; i++) {
      final Object? annots = doc.resolve(pageDicts[i]['Annots']);
      if (annots is PdfArray) {
        for (final Object a in annots.items) {
          final Object? ad = doc.resolve(a);
          if (ad is PdfDict) {
            widgetPage[ad] = i;
          }
        }
      }
    }

    final List<_Field> fields = <_Field>[];
    final Object? acro = doc.resolve(root['AcroForm']);
    if (acro is PdfDict) {
      final Object? list = doc.resolve(acro['Fields']);
      if (list is PdfArray) {
        final Set<PdfDict> seen = Set<PdfDict>.identity();
        for (final Object f in list.items) {
          _collect(doc, f, '', null, 0, fields, seen, 0);
        }
      }
    }
    return _Doc(doc, boxes, pageDicts, widgetPage, fields, acro is PdfDict ? acro : null);
  }

  static void _collect(PdfDocumentModel doc, Object node, String parentName, String? parentFt, int parentFf,
      List<_Field> out, Set<PdfDict> seen, int depth) {
    final Object? v = doc.resolve(node);
    if (depth > 32 || v is! PdfDict || !seen.add(v)) {
      return;
    }
    final String? t = decodeText(doc.resolve(v['T']));
    final String name = t == null ? parentName : (parentName.isEmpty ? t : '$parentName.$t');
    final String? ft = v.name('FT') ?? parentFt;
    final int ff = v.integer('Ff') ?? parentFf;
    final Object? kids = doc.resolve(v['Kids']);
    final List<PdfDict> widgets = <PdfDict>[];
    bool hasFieldKids = false;
    if (kids is PdfArray) {
      for (final Object k in kids.items) {
        final Object? kd = doc.resolve(k);
        if (kd is! PdfDict) {
          continue;
        }
        if (kd['T'] != null) {
          hasFieldKids = true;
          _collect(doc, k, name, ft, ff, out, seen, depth + 1);
        } else {
          widgets.add(kd);
        }
      }
    }
    if (hasFieldKids && widgets.isEmpty) {
      return;
    }
    if (widgets.isEmpty && v['Rect'] != null) {
      widgets.add(v);
    }
    if (name.isEmpty) {
      return;
    }
    out.add(_Field(name, v, widgets, ft, ff));
  }

  static FormFieldInfo _info(_Doc d, _Field f) {
    final PdfDocumentModel doc = d.model;
    final FormFieldKind kind;
    if (f.ft == 'Tx') {
      kind = FormFieldKind.text;
    } else if (f.ft == 'Ch') {
      kind = FormFieldKind.choice;
    } else if (f.ft == 'Sig') {
      kind = FormFieldKind.signature;
    } else if (f.ft == 'Btn') {
      if (f.ff & (1 << 16) != 0) {
        kind = FormFieldKind.button;
      } else if (f.ff & (1 << 15) != 0) {
        kind = FormFieldKind.radio;
      } else {
        kind = FormFieldKind.checkbox;
      }
    } else {
      kind = FormFieldKind.text;
    }
    final Object? rawV = doc.resolve(f.dict['V']);
    String value;
    if (rawV is PdfName) {
      value = rawV.raw;
    } else {
      value = decodeText(rawV) ?? '';
    }
    final List<String> options = <String>[];
    if (kind == FormFieldKind.choice) {
      final Object? opt = doc.resolve(f.dict['Opt']);
      if (opt is PdfArray) {
        for (final Object o in opt.items) {
          final Object? ro = doc.resolve(o);
          if (ro is PdfArray && ro.items.length >= 2) {
            options.add(decodeText(doc.resolve(ro.items[1])) ?? '');
          } else {
            final String? s = decodeText(ro);
            if (s != null) {
              options.add(s);
            }
          }
        }
      }
    } else if (kind == FormFieldKind.checkbox || kind == FormFieldKind.radio) {
      for (final PdfDict w in f.widgets) {
        for (final String s in _onStates(doc, w)) {
          if (!options.contains(s)) {
            options.add(s);
          }
        }
      }
      if (value.isEmpty) {
        value = 'Off';
      }
    }
    int page = -1;
    PageBox? rect;
    if (f.widgets.isNotEmpty) {
      final PdfDict w = f.widgets.first;
      page = d.widgetPage[w] ?? _pageOfP(d, w);
      rect = _box(doc.resolve(w['Rect']));
    }
    final int? maxLen = f.dict.integer('MaxLen');
    return FormFieldInfo(
      name: f.name,
      kind: kind,
      value: value,
      page: page,
      rect: rect,
      options: options,
      readOnly: f.ff & 1 != 0,
      multiline: kind == FormFieldKind.text && f.ff & (1 << 12) != 0,
      maxLength: maxLen,
      caption: decodeText(doc.resolve(f.dict['TU'])),
    );
  }

  static int _pageOfP(_Doc d, PdfDict w) {
    final Object? p = d.model.resolve(w['P']);
    for (int i = 0; i < d.pageDicts.length; i++) {
      if (identical(d.pageDicts[i], p)) {
        return i;
      }
    }
    return -1;
  }

  static List<String> _onStates(PdfDocumentModel doc, PdfDict w) {
    final Object? ap = doc.resolve(w['AP']);
    if (ap is! PdfDict) {
      return const <String>[];
    }
    final Object? n = doc.resolve(ap['N']);
    if (n is! PdfDict) {
      return const <String>[];
    }
    return n.entries.keys.where((String k) => k != 'Off').toList();
  }

  /// "true", "yes", "on", "1" or an on-state name tick the box; anything
  /// else ("", "false", "Off") clears it.
  static String _onValue(String v, List<String> options) {
    if (options.contains(v)) {
      return v;
    }
    final String l = v.trim().toLowerCase();
    if (l == 'true' || l == 'yes' || l == 'on' || l == '1' || l == 'x') {
      return options.isEmpty ? 'Yes' : options.first;
    }
    return 'Off';
  }

  /// A PDF string object as text: literal or hex, PDFDoc or UTF-16BE.
  static String? decodeText(Object? v) {
    if (v is! PdfString) {
      return null;
    }
    final Uint8List raw = v.raw;
    if (raw.isEmpty) {
      return '';
    }
    final List<int> bytes = <int>[];
    if (raw.first == 0x3C) {
      final String hex = latin1.decode(raw).replaceAll(RegExp(r'[^0-9A-Fa-f]'), '');
      final String even = hex.length.isOdd ? '${hex}0' : hex;
      for (int i = 0; i + 1 < even.length; i += 2) {
        bytes.add(int.parse(even.substring(i, i + 2), radix: 16));
      }
    } else {
      int i = 1;
      final int end = raw.length - 1;
      while (i < end) {
        final int c = raw[i];
        if (c != 0x5C) {
          bytes.add(c);
          i++;
          continue;
        }
        i++;
        if (i >= end) {
          break;
        }
        final int e = raw[i];
        switch (e) {
          case 0x6E:
            bytes.add(10);
            i++;
          case 0x72:
            bytes.add(13);
            i++;
          case 0x74:
            bytes.add(9);
            i++;
          case 0x62:
            bytes.add(8);
            i++;
          case 0x66:
            bytes.add(12);
            i++;
          case 0x0D:
            i++;
            if (i < end && raw[i] == 0x0A) {
              i++;
            }
          case 0x0A:
            i++;
          default:
            if (e >= 0x30 && e <= 0x37) {
              int n = 0;
              int k = 0;
              while (k < 3 && i < end && raw[i] >= 0x30 && raw[i] <= 0x37) {
                n = n * 8 + raw[i] - 0x30;
                i++;
                k++;
              }
              bytes.add(n & 0xFF);
            } else {
              bytes.add(e);
              i++;
            }
        }
      }
    }
    if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
      final List<int> units = <int>[];
      for (int i = 2; i + 1 < bytes.length; i += 2) {
        units.add((bytes[i] << 8) | bytes[i + 1]);
      }
      return String.fromCharCodes(units);
    }
    if (bytes.length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF) {
      return utf8.decode(bytes.sublist(3), allowMalformed: true);
    }
    return latin1.decode(bytes);
  }

  // ---- writing ------------------------------------------------------------

  static PdfDict _helvetica() => PdfDict(<String, Object>{
        'Type': const PdfName('Font'),
        'Subtype': const PdfName('Type1'),
        'BaseFont': const PdfName('Helvetica'),
        'Encoding': const PdfName('WinAnsiEncoding'),
      });

  /// Text for a Helvetica / WinAnsi string: escaped, with characters the
  /// font cannot show replaced by "?".
  static String pdfLiteral(String s) {
    final StringBuffer b = StringBuffer();
    for (final int c in s.runes) {
      if (c == 0x28 || c == 0x29 || c == 0x5C) {
        b.write('\\${String.fromCharCode(c)}');
      } else if (c >= 32 && c < 127) {
        b.writeCharCode(c);
      } else if (c >= 160 && c <= 255) {
        b.write('\\${c.toRadixString(8).padLeft(3, '0')}');
      } else if (c == 0x20B9) {
        b.write('Rs.');
      } else {
        b.write('?');
      }
    }
    return b.toString();
  }

  /// Helvetica advance widths for ASCII, in 1/1000 em (others ≈ 556).
  static const List<int> _helvWidths = <int>[
    278, 278, 355, 556, 556, 889, 667, 191, 333, 333, 389, 584, 278, 333, 278, 278, //
    556, 556, 556, 556, 556, 556, 556, 556, 556, 556, 278, 278, 584, 584, 584, 556,
    1015, 667, 667, 722, 722, 667, 611, 778, 722, 278, 500, 667, 556, 833, 722, 778,
    667, 778, 722, 667, 611, 722, 667, 944, 667, 667, 611, 278, 278, 278, 469, 556,
    333, 556, 556, 500, 556, 556, 278, 556, 556, 222, 222, 500, 222, 833, 556, 556,
    556, 556, 333, 500, 278, 556, 500, 722, 500, 500, 500, 334, 260, 334, 584,
  ];

  static double textWidth(String s, double size) {
    double w = 0;
    for (final int c in s.runes) {
      w += (c >= 32 && c < 127 ? _helvWidths[c - 32] : 556) * size / 1000;
    }
    return w;
  }

  static String _n(double v) => v.toStringAsFixed(2);

  /// Font size from the field's /DA ("/Helv 0 Tf" means auto).
  static double _daSize(PdfDocumentModel doc, PdfDict field, PdfDict widget) {
    final String? da = decodeText(doc.resolve(widget['DA'])) ?? decodeText(doc.resolve(field['DA']));
    if (da == null) {
      return 0;
    }
    final RegExpMatch? m = RegExp(r'([\d.]+)\s+Tf').firstMatch(da);
    return m == null ? 0 : (double.tryParse(m.group(1)!) ?? 0);
  }

  static int _textAppearance(PdfDocumentModel doc, PdfDict w, _Field f, String text, int fontNum, int next,
      {required bool multiline}) {
    final PageBox? r = _box(doc.resolve(w['Rect']));
    if (r == null) {
      return next;
    }
    final double width = math.max(1.0, r.width);
    final double height = math.max(1.0, r.height);
    double size = _daSize(doc, f.dict, w);
    final List<String> lines = multiline ? _wrap(text, width - 4, size == 0 ? 10 : size) : <String>[text.replaceAll('\n', ' ')];
    if (size == 0) {
      size = multiline ? 10.0 : math.min(12.0, math.max(4.0, height * 0.7));
      if (!multiline) {
        final double tw = textWidth(lines.first, size);
        if (tw > width - 4 && tw > 0) {
          size = math.max(4.0, size * (width - 4) / tw);
        }
      }
    }
    final StringBuffer ops = StringBuffer('/Tx BMC q 1 1 ${_n(width - 2)} ${_n(height - 2)} re W n BT /$fontName ${_n(size)} Tf 0 g ');
    if (multiline) {
      ops.write('${_n(size * 1.15)} TL 2 ${_n(height - 2 - size)} Td ');
      for (int i = 0; i < lines.length; i++) {
        if (i > 0) {
          ops.write('T* ');
        }
        ops.write('(${pdfLiteral(lines[i])}) Tj ');
      }
    } else {
      final double y = (height - size * 0.72) / 2;
      final double x = switch (f.dict.integer('Q') ?? 0) {
        1 => (width - textWidth(lines.first, size)) / 2,
        2 => width - 2 - textWidth(lines.first, size),
        _ => 2.0,
      };
      ops.write('${_n(x)} ${_n(y)} Td (${pdfLiteral(lines.first)}) Tj ');
    }
    ops.write('ET Q EMC\n');
    final int num = next++;
    doc.objects[num] = PdfObject(
      num,
      0,
      PdfDict(<String, Object>{
        'Type': const PdfName('XObject'),
        'Subtype': const PdfName('Form'),
        'BBox': PdfArray(<Object>[PdfNum('0'), PdfNum('0'), PdfNum(_n(width)), PdfNum(_n(height))]),
        'Resources': PdfDict(<String, Object>{
          'Font': PdfDict(<String, Object>{fontName: PdfRef(fontNum, 0)}),
        }),
      }),
      stream: Uint8List.fromList(latin1.encode(ops.toString())),
    );
    w.entries['AP'] = PdfDict(<String, Object>{'N': PdfRef(num, 0)});
    return next;
  }

  static List<String> _wrap(String text, double width, double size) {
    final List<String> out = <String>[];
    for (final String para in text.split('\n')) {
      String line = '';
      for (final String word in para.split(' ')) {
        final String tryLine = line.isEmpty ? word : '$line $word';
        if (line.isNotEmpty && textWidth(tryLine, size) > width) {
          out.add(line);
          line = word;
        } else {
          line = tryLine;
        }
      }
      out.add(line);
    }
    return out;
  }

  /// Draws every widget's normal appearance into its page, then removes the
  /// widgets and the form.
  static int _flatten(_Doc d, int next) {
    final PdfDocumentModel doc = d.model;
    final Set<PdfDict> widgets = Set<PdfDict>.identity();
    for (final _Field f in d.fields) {
      widgets.addAll(f.widgets);
    }
    for (int p = 0; p < d.pageDicts.length; p++) {
      final PdfDict page = d.pageDicts[p];
      final Object? annots = doc.resolve(page['Annots']);
      if (annots is! PdfArray) {
        continue;
      }
      final StringBuffer ops = StringBuffer();
      final Map<String, Object> xobjects = <String, Object>{};
      final List<Object> keep = <Object>[];
      for (final Object a in annots.items) {
        final Object? w = doc.resolve(a);
        if (w is! PdfDict || !(widgets.contains(w) || w.name('Subtype') == 'Widget')) {
          keep.add(a);
          continue;
        }
        final int flags = w.integer('F') ?? 0;
        if (flags & 2 != 0) {
          continue; // hidden
        }
        final Object? ap = doc.resolve(w['AP']);
        Object? n = ap is PdfDict ? ap['N'] : null;
        final Object? nd = doc.resolve(n);
        if (nd is PdfDict && nd['Subtype'] == null && nd['BBox'] == null) {
          // A state dictionary (check box / radio): pick the current state.
          final String? state = w.name('AS');
          n = state == null ? null : nd[state];
        }
        if (n is! PdfRef) {
          continue;
        }
        final Object? xo = doc.resolve(n);
        final PdfObject? xobj = doc.objects[n.num];
        if (xo is! PdfDict || xobj?.stream == null) {
          continue;
        }
        final PageBox? r = _box(doc.resolve(w['Rect']));
        final PageBox bbox = _box(doc.resolve(xo['BBox'])) ?? r ?? const PageBox(0, 0, 1, 1);
        if (r == null || bbox.width <= 0 || bbox.height <= 0) {
          continue;
        }
        xo.entries['Type'] = const PdfName('XObject');
        xo.entries['Subtype'] = const PdfName('Form');
        final String key = 'FuaFlat${xobjects.length}';
        xobjects[key] = n;
        final double sx = r.width / bbox.width;
        final double sy = r.height / bbox.height;
        ops.write('q ${_n(sx)} 0 0 ${_n(sy)} ${_n(r.x0 - bbox.x0 * sx)} ${_n(r.y0 - bbox.y0 * sy)} cm /$key Do Q\n');
      }
      if (keep.isEmpty) {
        page.entries.remove('Annots');
      } else {
        page.entries['Annots'] = PdfArray(keep);
      }
      if (xobjects.isEmpty) {
        continue;
      }
      final PdfDict resources = _resources(doc, page);
      final Object? xo = doc.resolve(resources['XObject']);
      final PdfDict xd = PdfDict(xo is PdfDict ? Map<String, Object>.of(xo.entries) : <String, Object>{});
      xd.entries.addAll(xobjects);
      resources.entries['XObject'] = xd;
      next = _appendContent(doc, page, ops.toString(), next);
    }
    final Object? root = doc.resolve(doc.trailer['Root']);
    if (root is PdfDict) {
      root.entries.remove('AcroForm');
    }
    return next;
  }

  static int _stampText(_Doc d, PlacedText t, int fontNum, int next) {
    final PdfDocumentModel doc = d.model;
    final PdfDict page = d.pageDicts[t.page];
    final PageBox box = d.pages[t.page];
    final PdfDict resources = _resources(doc, page);
    final Object? fo = doc.resolve(resources['Font']);
    final PdfDict fonts = PdfDict(fo is PdfDict ? Map<String, Object>.of(fo.entries) : <String, Object>{});
    fonts.entries[fontName] = PdfRef(fontNum, 0);
    resources.entries['Font'] = fonts;
    final double x = box.x0 + t.left.clamp(0.0, 1.0).toDouble() * box.width;
    final double top = box.y1 - t.top.clamp(0.0, 1.0).toDouble() * box.height;
    final double lead = t.fontSize * 1.2;
    final StringBuffer ops = StringBuffer(
        'BT 0 0 0 rg /$fontName ${_n(t.fontSize)} Tf ${_n(lead)} TL ${_n(x)} ${_n(top - t.fontSize)} Td ');
    final List<String> lines = t.text.split('\n');
    for (int i = 0; i < lines.length; i++) {
      if (i > 0) {
        ops.write('T* ');
      }
      ops.write('(${pdfLiteral(lines[i])}) Tj ');
    }
    ops.write('ET\n');
    return _appendContent(doc, page, ops.toString(), next);
  }

  /// The page's own resources dictionary (copied from an inherited one).
  static PdfDict _resources(PdfDocumentModel doc, PdfDict page) {
    Object? res = doc.resolve(page['Resources']);
    if (res == null) {
      Object? parent = doc.resolve(page['Parent']);
      for (int depth = 0; depth < 64 && parent is PdfDict && res == null; depth++) {
        res = doc.resolve(parent['Resources']);
        parent = doc.resolve(parent['Parent']);
      }
    }
    final PdfDict own = PdfDict(res is PdfDict ? Map<String, Object>.of(res.entries) : <String, Object>{});
    page.entries['Resources'] = own;
    return own;
  }

  /// Wraps the page's drawing in q … Q and adds [ops] after it.
  static int _appendContent(PdfDocumentModel doc, PdfDict page, String ops, int next) {
    final int pushNum = next++;
    doc.objects[pushNum] = PdfObject(pushNum, 0, PdfDict(<String, Object>{}), stream: Uint8List.fromList('q\n'.codeUnits));
    final int addNum = next++;
    doc.objects[addNum] =
        PdfObject(addNum, 0, PdfDict(<String, Object>{}), stream: Uint8List.fromList(latin1.encode('Q\nq\n${ops}Q\n')));
    final Object? old = page['Contents'];
    final List<Object> contents = <Object>[PdfRef(pushNum, 0)];
    final Object? resolvedOld = old is PdfArray ? old : doc.resolve(old);
    if (resolvedOld is PdfArray) {
      contents.addAll(resolvedOld.items);
    } else if (old != null) {
      contents.add(old);
    }
    contents.add(PdfRef(addNum, 0));
    page.entries['Contents'] = PdfArray(contents);
    return next;
  }

  static PageBox? _box(Object? v) {
    if (v is! PdfArray || v.items.length != 4) {
      return null;
    }
    final List<double> n = v.items.map((Object o) => o is PdfNum ? o.value.toDouble() : 0.0).toList();
    return PageBox(math.min(n[0], n[2]), math.min(n[1], n[3]), math.max(n[0], n[2]), math.max(n[1], n[3]));
  }
}
