import 'dart:math' as math;
import 'dart:typed_data';

import '../convert/word_pdf_renderer.dart' show PdfFontFamily, textWidth;
import 'pdf_compressor.dart';
import 'pdf_signer.dart' show PageBox;

/// Feature 014 — Page numbers.
///
/// Stamps a number on each page at one of six positions, in Helvetica at the
/// chosen size, counting from the chosen start. The first page (a cover) can
/// be left unnumbered; numbering then begins on page 2. The number is drawn
/// into the page content, so it prints and shares like the rest of the page.

enum NumberPosition {
  topLeft('Top left'),
  topCenter('Top centre'),
  topRight('Top right'),
  bottomLeft('Bottom left'),
  bottomCenter('Bottom centre'),
  bottomRight('Bottom right');

  const NumberPosition(this.label);
  final String label;

  bool get isTop => this == topLeft || this == topCenter || this == topRight;
}

class PageNumberOptions {
  const PageNumberOptions({
    this.position = NumberPosition.bottomCenter,
    this.fontSize = 11,
    this.start = 1,
    this.skipFirst = false,
    this.margin = 28,
  });

  final NumberPosition position;
  final double fontSize;
  final int start;

  /// Leaves page 1 unnumbered; page 2 gets [start].
  final bool skipFirst;

  /// Distance from the page edge, in points.
  final double margin;
}

class PageNumberError implements Exception {
  const PageNumberError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// One number drawn on one page.
class PageStamp {
  const PageStamp(this.page, this.label, this.x, this.y);

  /// 0-based page index.
  final int page;
  final String label;

  /// Baseline start, in PDF points.
  final double x;
  final double y;
}

class _Page {
  _Page(this.obj, this.box);
  final PdfObject obj;
  final PageBox box;
}

abstract final class PageNumberer {
  static const String fontName = 'FuaPageNo';

  /// Where each number goes, without touching the file.
  static List<PageStamp> plan(List<PageBox> boxes, PageNumberOptions o) {
    if (o.fontSize < 4 || o.fontSize > 72) {
      throw const PageNumberError('Pick a size between 4 and 72');
    }
    final List<PageStamp> out = <PageStamp>[];
    for (int i = 0; i < boxes.length; i++) {
      if (o.skipFirst && i == 0) {
        continue;
      }
      final int n = o.start + i - (o.skipFirst ? 1 : 0);
      final String label = '$n';
      final PageBox b = boxes[i];
      final double w = textWidth(label, PdfFontFamily.helvetica, o.fontSize);
      final double x = switch (o.position) {
        NumberPosition.topLeft || NumberPosition.bottomLeft => b.x0 + o.margin,
        NumberPosition.topCenter || NumberPosition.bottomCenter => b.x0 + (b.width - w) / 2,
        NumberPosition.topRight || NumberPosition.bottomRight => b.x1 - o.margin - w,
      };
      final double y = o.position.isTop ? b.y1 - o.margin - o.fontSize : b.y0 + o.margin;
      out.add(PageStamp(i, label, x, y));
    }
    return out;
  }

  /// Page boxes in order. Throws [PageNumberError] for files it cannot read.
  static List<PageBox> pages(Uint8List pdf) => _pages(_parse(pdf)).map((_Page p) => p.box).toList();

  /// Returns the PDF with the numbers drawn in.
  static Uint8List stamp(Uint8List pdf, PageNumberOptions o) {
    final PdfDocumentModel doc = _parse(pdf);
    final List<_Page> pages = _pages(doc);
    final List<PageStamp> stamps = plan(pages.map((_Page p) => p.box).toList(), o);
    if (stamps.isEmpty) {
      throw const PageNumberError('There is no page to number');
    }
    int next = doc.objects.keys.fold<int>(0, math.max) + 1;
    final int fontNum = next++;
    doc.objects[fontNum] = PdfObject(
      fontNum,
      0,
      PdfDict(<String, Object>{
        'Type': const PdfName('Font'),
        'Subtype': const PdfName('Type1'),
        'BaseFont': const PdfName('Helvetica'),
        'Encoding': const PdfName('WinAnsiEncoding'),
      }),
    );
    for (final PageStamp s in stamps) {
      final _Page page = pages[s.page];
      final PdfDict pageDict = page.obj.value as PdfDict;
      final Object? res = doc.resolve(pageDict['Resources']) ?? _inherited(doc, pageDict);
      final PdfDict resources = PdfDict(res is PdfDict ? Map<String, Object>.of(res.entries) : <String, Object>{});
      final Object? fo = doc.resolve(resources['Font']);
      final PdfDict fonts = PdfDict(fo is PdfDict ? Map<String, Object>.of(fo.entries) : <String, Object>{});
      fonts.entries[fontName] = PdfRef(fontNum, 0);
      resources.entries['Font'] = fonts;
      pageDict.entries['Resources'] = resources;

      final int pushNum = next++;
      doc.objects[pushNum] = PdfObject(pushNum, 0, PdfDict(<String, Object>{}), stream: Uint8List.fromList('q\n'.codeUnits));
      final int stampNum = next++;
      final String ops = 'Q\nq BT 0 0 0 rg /$fontName ${_n(o.fontSize)} Tf ${_n(s.x)} ${_n(s.y)} Td (${s.label}) Tj ET Q\n';
      doc.objects[stampNum] =
          PdfObject(stampNum, 0, PdfDict(<String, Object>{}), stream: Uint8List.fromList(ops.codeUnits));
      final Object? old = pageDict['Contents'];
      final List<Object> contents = <Object>[PdfRef(pushNum, 0)];
      final Object? resolvedOld = old is PdfArray ? old : doc.resolve(old);
      if (resolvedOld is PdfArray) {
        contents.addAll(resolvedOld.items);
      } else if (old != null) {
        contents.add(old);
      }
      contents.add(PdfRef(stampNum, 0));
      pageDict.entries['Contents'] = PdfArray(contents);
    }
    return doc.write();
  }

  static String _n(double v) => v.toStringAsFixed(2);

  static Object? _inherited(PdfDocumentModel doc, PdfDict page) {
    Object? parent = doc.resolve(page['Parent']);
    for (int depth = 0; depth < 64 && parent is PdfDict; depth++) {
      final Object? r = doc.resolve(parent['Resources']);
      if (r != null) {
        return r;
      }
      parent = doc.resolve(parent['Parent']);
    }
    return null;
  }

  static PdfDocumentModel _parse(Uint8List pdf) {
    try {
      return PdfDocumentModel.parse(pdf);
    } on PdfCompressError catch (e) {
      throw PageNumberError(e.message);
    } catch (_) {
      throw const PageNumberError('This PDF could not be read. It may be damaged or locked.');
    }
  }

  static List<_Page> _pages(PdfDocumentModel doc) {
    final Object? root = doc.resolve(doc.trailer['Root']);
    if (root is! PdfDict) {
      throw const PageNumberError('This PDF has no pages');
    }
    final List<_Page> out = <_Page>[];
    void walk(Object? node, PageBox? box, int depth) {
      if (depth > 64 || node is! PdfRef) {
        return;
      }
      final PdfObject? obj = doc.objects[node.num];
      final Object? v = obj?.value;
      if (obj == null || v is! PdfDict) {
        return;
      }
      final PageBox? useBox = _box(doc.resolve(v['MediaBox'])) ?? box;
      if (v.name('Type') == 'Page' || (v['Kids'] == null && v['Contents'] != null)) {
        out.add(_Page(obj, useBox ?? const PageBox(0, 0, 612, 792)));
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
    if (out.isEmpty) {
      throw const PageNumberError('This PDF has no pages');
    }
    return out;
  }

  static PageBox? _box(Object? v) {
    if (v is! PdfArray || v.items.length != 4) {
      return null;
    }
    final List<double> n = v.items.map((Object o) => o is PdfNum ? o.value.toDouble() : 0.0).toList();
    return PageBox(math.min(n[0], n[2]), math.min(n[1], n[3]), math.max(n[0], n[2]), math.max(n[1], n[3]));
  }
}
