import 'dart:convert';
import 'dart:typed_data';

import '../pdf/images_to_pdf.dart';
import 'word_document.dart';

/// Feature 018 — Word to PDF: lays a [WordDocument] out on A4 pages and
/// writes the PDF directly (no third-party PDF package), on the phone.
///
/// Text uses the PDF base fonts (Helvetica, Times, Courier in regular, bold,
/// italic and bold italic), chosen from each run's font name. Tables get
/// equal columns with ruled cells; pictures are re-encoded as JPEG and
/// scaled to the text width.

enum PdfFontFamily { helvetica, times, courier }

/// Picks the base font family closest to a Word font name.
PdfFontFamily fontFamilyFor(String? name) {
  final String n = (name ?? '').toLowerCase();
  const List<String> mono = <String>['courier', 'mono', 'consolas', 'menlo', 'lucida console'];
  const List<String> serif = <String>[
    'times', 'georgia', 'garamond', 'cambria', 'serif', 'book antiqua', 'palatino', 'baskerville',
  ];
  if (mono.any(n.contains)) {
    return PdfFontFamily.courier;
  }
  if (serif.any(n.contains) && !n.contains('sans')) {
    return PdfFontFamily.times;
  }
  return PdfFontFamily.helvetica;
}

/// The PDF base-font name for a family and style.
String baseFontName(PdfFontFamily f, {required bool bold, required bool italic}) {
  switch (f) {
    case PdfFontFamily.helvetica:
      return 'Helvetica${bold || italic ? '-' : ''}${bold ? 'Bold' : ''}${italic ? 'Oblique' : ''}';
    case PdfFontFamily.courier:
      return 'Courier${bold || italic ? '-' : ''}${bold ? 'Bold' : ''}${italic ? 'Oblique' : ''}';
    case PdfFontFamily.times:
      if (bold && italic) {
        return 'Times-BoldItalic';
      }
      return bold ? 'Times-Bold' : (italic ? 'Times-Italic' : 'Times-Roman');
  }
}

// Helvetica advance widths (1/1000 em) for ASCII 32..126, from its AFM.
const List<int> _helv = <int>[
  278, 278, 355, 556, 556, 889, 667, 191, 333, 333, 389, 584, 278, 333, 278, 278, //
  556, 556, 556, 556, 556, 556, 556, 556, 556, 556, 278, 278, 584, 584, 584, 556, //
  1015, 667, 667, 722, 722, 667, 611, 778, 722, 278, 500, 667, 556, 833, 722, 778, //
  667, 778, 722, 667, 611, 722, 667, 944, 667, 667, 611, 278, 278, 278, 469, 556, //
  333, 556, 556, 500, 556, 556, 278, 556, 556, 222, 222, 500, 222, 833, 556, 556, //
  556, 556, 333, 500, 278, 556, 500, 722, 500, 500, 500, 334, 260, 334, 584,
];

/// Width of [text] in points for a base font. Exact for Courier and
/// Helvetica; bold and Times are close scalings, good enough to wrap lines.
double textWidth(String text, PdfFontFamily f, double size, {bool bold = false}) {
  if (f == PdfFontFamily.courier) {
    return text.length * 0.6 * size;
  }
  double units = 0;
  for (final int c in text.codeUnits) {
    units += (c >= 32 && c <= 126) ? _helv[c - 32] : 556;
  }
  double scale = f == PdfFontFamily.times ? 0.9 : 1.0;
  if (bold) {
    scale *= 1.06;
  }
  return units * scale * size / 1000;
}

/// Characters the base fonts can draw (WinAnsi); others become '?'.
String winAnsi(String s) {
  final StringBuffer b = StringBuffer();
  for (final int c in s.runes) {
    if (c == 0x2018 || c == 0x2019) {
      b.writeCharCode(0x27);
    } else if (c == 0x201C || c == 0x201D) {
      b.writeCharCode(0x22);
    } else if (c == 0x2013 || c == 0x2014) {
      b.writeCharCode(0x2D);
    } else if (c == 0x2022) {
      b.writeCharCode(0xB7);
    } else if (c == 0xA0) {
      b.writeCharCode(0x20);
    } else if (c < 32 || c > 255 || (c >= 127 && c < 160)) {
      b.write('?');
    } else {
      b.writeCharCode(c);
    }
  }
  return b.toString();
}

String _esc(String s) => s.replaceAll(r'\', r'\\').replaceAll('(', r'\(').replaceAll(')', r'\)');
String _n(double v) => v.toStringAsFixed(2);

class WordPdfOptions {
  const WordPdfOptions({
    this.pageWidth = 595.28,
    this.pageHeight = 841.89,
    this.margin = 72,
    this.bodySize = 11,
    this.defaultFont,
  });

  final double pageWidth;
  final double pageHeight;
  final double margin;
  final double bodySize;

  /// The font used where a run names none.
  final String? defaultFont;

  double get contentWidth => pageWidth - 2 * margin;
}

/// Heading sizes in points, by level 1..6.
const List<double> headingSizes = <double>[20, 16, 14, 13, 12, 11];

class _Word {
  _Word(this.text, this.run, this.font, this.size, this.width);
  final String text;
  final DocRun run;
  final String font;
  final double size;
  final double width;
  bool breakAfter = false;
  bool get bold => run.bold;
}

class _Line {
  final List<_Word> words = <_Word>[];
  double width = 0;
  double size = 0;
  bool forced = false;
}

class _Page {
  final StringBuffer ops = StringBuffer();
  final Set<String> fonts = <String>{};
  final Map<String, int> images = <String, int>{};
}

class WordPdfRenderer {
  WordPdfRenderer({ImagesToPdf? images}) : _images = images ?? ImagesToPdf();

  final ImagesToPdf _images;

  /// Renders the document. Pictures that cannot be read become a labelled box.
  Future<Uint8List> render(WordDocument doc, {WordPdfOptions options = const WordPdfOptions()}) async {
    final Map<DocImage, PreparedImage?> prepared = <DocImage, PreparedImage?>{};
    for (final DocBlock b in doc.blocks) {
      if (b is DocImage) {
        try {
          prepared[b] = await _images.prepare(b.bytes);
        } catch (_) {
          prepared[b] = null;
        }
      }
    }
    return layout(doc, prepared, options);
  }

  /// Synchronous layout and PDF writing once pictures are JPEG.
  static Uint8List layout(WordDocument doc, Map<DocImage, PreparedImage?> pictures, WordPdfOptions o) {
    final List<_Page> pages = <_Page>[_Page()];
    final List<PreparedImage> xobjects = <PreparedImage>[];
    double y = o.pageHeight - o.margin;
    _Page page = pages.first;

    void newPage() {
      page = _Page();
      pages.add(page);
      y = o.pageHeight - o.margin;
    }

    void ensure(double h) {
      if (y - h < o.margin && y < o.pageHeight - o.margin - 0.5) {
        newPage();
      }
    }

    for (final DocBlock b in doc.blocks) {
      switch (b) {
        case final DocParagraph p:
          final List<_Line> lines = _lines(p, o.contentWidth, o);
          final double before = p.headingLevel > 0 ? 8 : 0;
          if (p.headingLevel > 0) {
            ensure(before + lines.first.size * 1.25 * 2);
            y -= before;
          }
          for (int i = 0; i < lines.length; i++) {
            final _Line l = lines[i];
            final double lh = l.size * 1.25;
            ensure(lh);
            y -= lh;
            _drawLine(page, l, o.margin, y + l.size * 0.25, o.contentWidth, p.align, i == lines.length - 1);
          }
          y -= o.bodySize * 0.5;
        case final DocTable t:
          final int cols = t.rows.fold<int>(0, (int m, List<List<DocParagraph>> r) => r.length > m ? r.length : m);
          if (cols == 0) {
            break;
          }
          final double cw = o.contentWidth / cols;
          const double pad = 4;
          for (final List<List<DocParagraph>> row in t.rows) {
            final List<List<(_Line, DocAlign)>> cells = <List<(_Line, DocAlign)>>[];
            double rowH = 0;
            for (int c = 0; c < cols; c++) {
              final List<(_Line, DocAlign)> ls = <(_Line, DocAlign)>[];
              if (c < row.length) {
                for (final DocParagraph cp in row[c]) {
                  for (final _Line l in _lines(cp, cw - 2 * pad, o)) {
                    ls.add((l, cp.align));
                  }
                }
              }
              final double h = ls.fold<double>(0, (double s, (_Line, DocAlign) e) => s + e.$1.size * 1.25);
              rowH = h > rowH ? h : rowH;
              cells.add(ls);
            }
            rowH += 2 * pad;
            ensure(rowH);
            final double top = y;
            for (int c = 0; c < cols; c++) {
              final double x = o.margin + c * cw;
              page.ops.write('0.5 w 0 0 0 RG ${_n(x)} ${_n(top - rowH)} ${_n(cw)} ${_n(rowH)} re S\n');
              double cy = top - pad;
              for (int i = 0; i < cells[c].length; i++) {
                final (_Line l, DocAlign a) = cells[c][i];
                cy -= l.size * 1.25;
                _drawLine(page, l, x + pad, cy + l.size * 0.25, cw - 2 * pad, a, true);
              }
            }
            y -= rowH;
          }
          y -= o.bodySize * 0.5;
        case final DocImage im:
          double w = im.widthPt > 0 ? im.widthPt : o.contentWidth;
          double h = im.heightPt > 0 ? im.heightPt : w * 0.75;
          final double maxH = o.pageHeight - 2 * o.margin;
          if (w > o.contentWidth) {
            h *= o.contentWidth / w;
            w = o.contentWidth;
          }
          if (h > maxH) {
            w *= maxH / h;
            h = maxH;
          }
          ensure(h);
          y -= h;
          final PreparedImage? pic = pictures[im];
          if (pic == null) {
            page.fonts.add('Helvetica');
            page.ops.write('0.9 g ${_n(o.margin)} ${_n(y)} ${_n(w)} ${_n(h)} re f 0 g '
                'BT /${_fontKey('Helvetica')} 9 Tf ${_n(o.margin + 4)} ${_n(y + h / 2)} Td (\\[image\\]) Tj ET\n');
          } else {
            int idx = xobjects.indexOf(pic);
            if (idx < 0) {
              xobjects.add(pic);
              idx = xobjects.length - 1;
            }
            page.images['Im$idx'] = idx;
            page.ops.write('q ${_n(w)} 0 0 ${_n(h)} ${_n(o.margin)} ${_n(y)} cm /Im$idx Do Q\n');
          }
          y -= o.bodySize * 0.5;
      }
    }
    return _write(pages, xobjects, o);
  }

  static String _fontKey(String base) => 'F${base.replaceAll('-', '')}';

  static List<_Line> _lines(DocParagraph p, double width, WordPdfOptions o) {
    final double base = p.headingLevel > 0 ? headingSizes[p.headingLevel > 6 ? 5 : p.headingLevel - 1] : o.bodySize;
    final List<_Word> words = <_Word>[];
    for (final DocRun r in p.runs) {
      final bool bold = r.bold || p.headingLevel > 0;
      final DocRun run = bold == r.bold
          ? r
          : DocRun(r.text, bold: true, italic: r.italic, underline: r.underline, sizePt: r.sizePt, color: r.color, font: r.font);
      final PdfFontFamily fam = fontFamilyFor(r.font ?? o.defaultFont);
      final String font = baseFontName(fam, bold: run.bold, italic: run.italic);
      final double size = r.sizePt ?? base;
      final List<String> hard =
          r.text.replaceAll('\t', '    ').replaceAll('\r', '').split('\n').map(winAnsi).toList();
      for (int h = 0; h < hard.length; h++) {
        // Keep the trailing space with each word so runs join naturally.
        final RegExp tokens = RegExp(r'\S+\s*|\s+');
        for (final RegExpMatch m in tokens.allMatches(hard[h])) {
          final String t = m.group(0)!;
          words.add(_Word(t, run, font, size, textWidth(t, fam, size, bold: run.bold)));
        }
        if (h < hard.length - 1) {
          if (words.isEmpty) {
            words.add(_Word('', run, font, size, 0));
          }
          words.last.breakAfter = true;
        }
      }
    }
    final List<_Line> lines = <_Line>[_Line()..size = base];
    for (final _Word w in words) {
      _Line l = lines.last;
      final double trimmed = textWidth(w.text.trimRight(), fontFamilyFor(w.run.font ?? o.defaultFont), w.size, bold: w.bold);
      if (l.words.isNotEmpty && l.width + trimmed > width) {
        l = _Line()..size = base;
        lines.add(l);
      }
      l.words.add(w);
      l.width += w.width;
      if (w.size > l.size) {
        l.size = w.size;
      }
      if (w.breakAfter) {
        l.forced = true;
        lines.add(_Line()..size = base);
      }
    }
    if (lines.length > 1 && lines.last.words.isEmpty && !lines[lines.length - 2].forced) {
      lines.removeLast();
    }
    return lines;
  }

  static void _drawLine(_Page page, _Line l, double x0, double baseline, double width, DocAlign align, bool last) {
    if (l.words.isEmpty) {
      return;
    }
    final _Word tail = l.words.last;
    final double trailing = tail.width - textWidth(tail.text.trimRight(), fontFamilyFor(tail.run.font), tail.size, bold: tail.bold);
    final double used = l.width - trailing;
    double x = x0;
    double extraPerSpace = 0;
    switch (align) {
      case DocAlign.center:
        x += (width - used) / 2;
      case DocAlign.right:
        x += width - used;
      case DocAlign.justify:
        if (!last && !l.forced) {
          final int gaps = l.words.take(l.words.length - 1).where((_Word w) => w.text.endsWith(' ')).length;
          if (gaps > 0) {
            extraPerSpace = (width - used) / gaps;
          }
        }
      case DocAlign.left:
        break;
    }
    final int n = l.words.length;
    int i = 0;
    while (i < n) {
      final _Word w = l.words[i];
      // One text object per stretch of words with the same look.
      int j = i + 1;
      while (j < n &&
          l.words[j].font == w.font &&
          l.words[j].size == w.size &&
          l.words[j].run.color == w.run.color &&
          l.words[j].run.underline == w.run.underline) {
        j++;
      }
      final StringBuffer sb = StringBuffer();
      double drawn = 0;
      for (int k = i; k < j; k++) {
        final _Word g = l.words[k];
        if (k == n - 1) {
          sb.write(g.text.trimRight());
          drawn += g.width - trailing;
        } else {
          sb.write(g.text);
          drawn += g.width + (g.text.endsWith(' ') ? extraPerSpace : 0);
        }
      }
      final String text = sb.toString();
      if (text.trim().isNotEmpty) {
        page.fonts.add(w.font);
        final String color = _rgb(w.run.color);
        final String tw = extraPerSpace > 0 ? '${_n(extraPerSpace)} Tw ' : '';
        page.ops.write('BT $color /${_fontKey(w.font)} ${_n(w.size)} Tf $tw${_n(x)} ${_n(baseline)} Td (${_esc(text)}) Tj ET\n');
        if (w.run.underline) {
          final String stroke = color.replaceFirst(' rg', ' RG');
          final double end = x + drawn - (j < n && text.endsWith(' ') ? textWidth(' ', fontFamilyFor(w.run.font), w.size) + extraPerSpace : 0);
          page.ops.write('$stroke ${_n(w.size / 18)} w ${_n(x)} ${_n(baseline - w.size * 0.12)} m '
              '${_n(end)} ${_n(baseline - w.size * 0.12)} l S\n');
        }
      }
      x += drawn;
      i = j;
    }
  }

  static String _rgb(String? hex) {
    if (hex == null || hex.length != 6) {
      return '0 0 0 rg';
    }
    final int? v = int.tryParse(hex, radix: 16);
    if (v == null) {
      return '0 0 0 rg';
    }
    double c(int s) => ((v >> s) & 0xFF) / 255;
    return '${c(16).toStringAsFixed(3)} ${c(8).toStringAsFixed(3)} ${c(0).toStringAsFixed(3)} rg';
  }

  static Uint8List _write(List<_Page> pages, List<PreparedImage> images, WordPdfOptions o) {
    final BytesBuilder out = BytesBuilder(copy: false);
    final Map<int, int> offsets = <int, int>{};
    void add(String s) => out.add(latin1.encode(s));
    void obj(int id, void Function() body) {
      offsets[id] = out.length;
      add('$id 0 obj\n');
      body();
      add('\nendobj\n');
    }

    final List<String> fonts = <String>{for (final _Page p in pages) ...p.fonts}.toList()..sort();
    // 1 catalog, 2 pages, fonts, images, then page + contents per page.
    const int fontStart = 3;
    final int imageStart = fontStart + fonts.length;
    final int pageStart = imageStart + images.length;
    add('%PDF-1.4\n');
    out.add(const <int>[0x25, 0xE2, 0xE3, 0xCF, 0xD3, 0x0A]);
    final String kids = <String>[for (int i = 0; i < pages.length; i++) '${pageStart + i * 2} 0 R'].join(' ');
    obj(1, () => add('<< /Type /Catalog /Pages 2 0 R >>'));
    obj(2, () => add('<< /Type /Pages /Kids [$kids] /Count ${pages.length} >>'));
    for (int i = 0; i < fonts.length; i++) {
      obj(fontStart + i, () => add('<< /Type /Font /Subtype /Type1 /BaseFont /${fonts[i]} /Encoding /WinAnsiEncoding >>'));
    }
    for (int i = 0; i < images.length; i++) {
      final PreparedImage p = images[i];
      obj(imageStart + i, () {
        add('<< /Type /XObject /Subtype /Image /Width ${p.width} /Height ${p.height} '
            '/ColorSpace ${p.components == 1 ? '/DeviceGray' : '/DeviceRGB'} /BitsPerComponent 8 '
            '/Filter /DCTDecode /Length ${p.jpeg.length} >>\nstream\n');
        out.add(p.jpeg);
        add('\nendstream');
      });
    }
    for (int i = 0; i < pages.length; i++) {
      final _Page pg = pages[i];
      final int id = pageStart + i * 2;
      final String fontRes = <String>[
        for (final String f in pg.fonts) '/${_fontKey(f)} ${fontStart + fonts.indexOf(f)} 0 R',
      ].join(' ');
      final String imgRes = <String>[
        for (final MapEntry<String, int> e in pg.images.entries) '/${e.key} ${imageStart + e.value} 0 R',
      ].join(' ');
      obj(id, () => add('<< /Type /Page /Parent 2 0 R /MediaBox [0 0 ${_n(o.pageWidth)} ${_n(o.pageHeight)}] '
          '/Resources << /Font << $fontRes >> /XObject << $imgRes >> >> /Contents ${id + 1} 0 R >>'));
      final List<int> content = latin1.encode(pg.ops.toString());
      obj(id + 1, () {
        add('<< /Length ${content.length} >>\nstream\n');
        out.add(content);
        add('\nendstream');
      });
    }
    final int xref = out.length;
    final int size = pageStart + pages.length * 2;
    final StringBuffer x = StringBuffer('xref\n0 $size\n0000000000 65535 f \n');
    for (int id = 1; id < size; id++) {
      x.write('${offsets[id]!.toString().padLeft(10, '0')} 00000 n \n');
    }
    x.write('trailer\n<< /Size $size /Root 1 0 R >>\nstartxref\n$xref\n%%EOF\n');
    add(x.toString());
    return out.takeBytes();
  }
}
