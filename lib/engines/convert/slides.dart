import 'dart:convert';
import 'dart:typed_data';

import 'package:xml/xml.dart';

import '../archive/zip_codec.dart';
import '../pdf/images_to_pdf.dart';
import 'convert_registry.dart';
import 'file_kind.dart';
import 'pdf_to_word.dart';
import 'word_pdf_renderer.dart' show PdfFontFamily, textWidth, winAnsi;

/// Feature 020 — PowerPoint to PDF and back.
///
/// A PowerPoint deck (.pptx) is read on the phone: every text box and
/// picture keeps its place and size on the slide, and each slide becomes one
/// PDF page of the deck's own size. Speaker notes can follow each slide on
/// a page of their own. A PDF comes back as a deck, one slide per page, with
/// each line of text in a text box where it sat. Nothing is uploaded.

const double _emuPerPt = 12700;

class SlideRun {
  const SlideRun(this.text, {this.size = 18, this.bold = false, this.color});
  final String text;
  final double size;
  final bool bold;

  /// RRGGBB or null for black.
  final String? color;
}

enum SlideAlign { left, center, right }

class SlideParagraph {
  const SlideParagraph(this.runs, {this.align = SlideAlign.left});
  final List<SlideRun> runs;
  final SlideAlign align;

  String get text => runs.map((SlideRun r) => r.text).join();
  double get size => runs.isEmpty ? 18 : runs.first.size;
}

/// A text box or picture at [x], [y] (from the top left), in points.
class SlideShape {
  const SlideShape({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.paragraphs = const <SlideParagraph>[],
    this.image,
    this.fill,
  });

  final double x;
  final double y;
  final double width;
  final double height;
  final List<SlideParagraph> paragraphs;
  final Uint8List? image;

  /// RRGGBB background fill, or null.
  final String? fill;
}

class Slide {
  const Slide(this.shapes, {this.notes = ''});
  final List<SlideShape> shapes;
  final String notes;
}

class SlideDeck {
  const SlideDeck({required this.width, required this.height, required this.slides});

  /// Slide size in points.
  final double width;
  final double height;
  final List<Slide> slides;
}

String? _attr(XmlElement e, String local) {
  for (final XmlAttribute a in e.attributes) {
    if (a.name.local == local) {
      return a.value;
    }
  }
  return null;
}

/// The relationship id (`r:id`), not the plain `id` beside it.
String? _relId(XmlElement e) {
  for (final XmlAttribute a in e.attributes) {
    if (a.name.local == 'id' && a.name.prefix != null) {
      return a.value;
    }
  }
  return null;
}

XmlElement? _kid(XmlElement e, String local) {
  for (final XmlElement c in e.childElements) {
    if (c.name.local == local) {
      return c;
    }
  }
  return null;
}

Iterable<XmlElement> _all(XmlNode n, String local) =>
    n.descendants.whereType<XmlElement>().where((XmlElement e) => e.name.local == local);

String _dir(String path) => path.contains('/') ? path.substring(0, path.lastIndexOf('/')) : '';

/// "../media/image1.png" against "ppt/slides" → "ppt/media/image1.png".
String resolvePartPath(String baseDir, String target) {
  if (target.startsWith('/')) {
    return target.substring(1);
  }
  final List<String> parts = baseDir.isEmpty ? <String>[] : baseDir.split('/');
  for (final String s in target.split('/')) {
    if (s == '..') {
      if (parts.isNotEmpty) {
        parts.removeLast();
      }
    } else if (s != '.' && s.isNotEmpty) {
      parts.add(s);
    }
  }
  return parts.join('/');
}

class PptxReader {
  const PptxReader();

  SlideDeck read(Uint8List bytes) {
    final ZipReader zip;
    try {
      zip = ZipReader(bytes);
    } catch (_) {
      throw const ConvertException('This is not a PowerPoint deck (PPTX).');
    }
    Uint8List? part(String name) {
      for (final ZipEntry e in zip.entries) {
        if (e.name == name) {
          return zip.extract(e);
        }
      }
      return null;
    }

    XmlDocument? xml(String name) {
      final Uint8List? b = part(name);
      return b == null ? null : XmlDocument.parse(utf8.decode(b, allowMalformed: true));
    }

    Map<String, (String, String)> rels(String partName) {
      final String relsName = '${_dir(partName)}/_rels/${partName.split('/').last}.rels';
      final XmlDocument? d = xml(relsName);
      final Map<String, (String, String)> out = <String, (String, String)>{};
      if (d == null) {
        return out;
      }
      for (final XmlElement r in _all(d, 'Relationship')) {
        final String? id = _attr(r, 'Id');
        final String? target = _attr(r, 'Target');
        if (id != null && target != null) {
          out[id] = (resolvePartPath(_dir(partName), target), _attr(r, 'Type') ?? '');
        }
      }
      return out;
    }

    final XmlDocument? pres = xml('ppt/presentation.xml');
    if (pres == null) {
      throw const ConvertException('This is not a PowerPoint deck (PPTX).');
    }
    double width = 720;
    double height = 540;
    final XmlElement? sz = _all(pres, 'sldSz').firstOrNull;
    if (sz != null) {
      width = (double.tryParse(_attr(sz, 'cx') ?? '') ?? width * _emuPerPt) / _emuPerPt;
      height = (double.tryParse(_attr(sz, 'cy') ?? '') ?? height * _emuPerPt) / _emuPerPt;
    }
    final Map<String, (String, String)> presRels = rels('ppt/presentation.xml');
    final List<String> slideParts = <String>[
      for (final XmlElement s in _all(pres, 'sldId'))
        if (presRels[_relId(s) ?? ''] != null) presRels[_relId(s)!]!.$1,
    ];
    final List<Slide> slides = <Slide>[];
    for (final String sp in slideParts) {
      final XmlDocument? doc = xml(sp);
      if (doc == null) {
        continue;
      }
      final Map<String, (String, String)> r = rels(sp);
      String notes = '';
      for (final (String, String) rel in r.values) {
        if (rel.$2.endsWith('/notesSlide')) {
          final XmlDocument? nd = xml(rel.$1);
          if (nd != null) {
            notes = _notes(nd);
          }
        }
      }
      slides.add(Slide(_shapes(doc, r, part, width, height), notes: notes));
    }
    if (slides.isEmpty) {
      throw const ConvertException('This deck has no slides.');
    }
    return SlideDeck(width: width, height: height, slides: slides);
  }

  static String _notes(XmlDocument d) {
    final List<String> out = <String>[];
    for (final XmlElement sp in _all(d, 'sp')) {
      final XmlElement? ph = _all(sp, 'ph').firstOrNull;
      if (ph == null || _attr(ph, 'type') != 'body') {
        continue;
      }
      for (final XmlElement p in _all(sp, 'p').where((XmlElement e) => e.name.prefix == 'a')) {
        out.add(_all(p, 't').map((XmlElement t) => t.innerText).join());
      }
    }
    return out.join('\n').trim();
  }

  static (double, double, double, double)? _xfrm(XmlElement shape) {
    final XmlElement? x = _all(shape, 'xfrm').firstOrNull;
    if (x == null) {
      return null;
    }
    final XmlElement? off = _kid(x, 'off');
    final XmlElement? ext = _kid(x, 'ext');
    if (off == null || ext == null) {
      return null;
    }
    double v(XmlElement e, String a) => (double.tryParse(_attr(e, a) ?? '') ?? 0) / _emuPerPt;
    return (v(off, 'x'), v(off, 'y'), v(ext, 'cx'), v(ext, 'cy'));
  }

  static List<SlideShape> _shapes(XmlDocument doc, Map<String, (String, String)> rels,
      Uint8List? Function(String) part, double w, double h) {
    final List<SlideShape> out = <SlideShape>[];
    for (final XmlElement e in doc.descendants.whereType<XmlElement>()) {
      if (e.name.local == 'sp' && e.name.prefix == 'p') {
        (double, double, double, double)? box = _xfrm(e);
        if (box == null) {
          // Placeholder placed by the layout: title at the top, body below.
          final XmlElement? ph = _all(e, 'ph').firstOrNull;
          final String type = ph == null ? '' : (_attr(ph, 'type') ?? 'body');
          box = type == 'title' || type == 'ctrTitle'
              ? (w * 0.06, h * 0.05, w * 0.88, h * 0.18)
              : (w * 0.06, h * 0.27, w * 0.88, h * 0.66);
        }
        final XmlElement? body = _kid(e, 'txBody');
        final List<SlideParagraph> paras = body == null ? <SlideParagraph>[] : _paragraphs(body);
        final XmlElement? spPr = _kid(e, 'spPr');
        final XmlElement? solid = spPr == null ? null : _kid(spPr, 'solidFill');
        final XmlElement? clr = solid == null ? null : _kid(solid, 'srgbClr');
        final String? fill = clr == null ? null : _attr(clr, 'val');
        if (paras.isEmpty && fill == null) {
          continue;
        }
        out.add(SlideShape(x: box.$1, y: box.$2, width: box.$3, height: box.$4, paragraphs: paras, fill: fill));
      } else if (e.name.local == 'pic' && e.name.prefix == 'p') {
        final (double, double, double, double)? box = _xfrm(e);
        final XmlElement? blip = _all(e, 'blip').firstOrNull;
        final String? id = blip == null ? null : _attr(blip, 'embed');
        final (String, String)? rel = id == null ? null : rels[id];
        final Uint8List? bytes = rel == null ? null : part(rel.$1);
        if (box == null || bytes == null) {
          continue;
        }
        out.add(SlideShape(x: box.$1, y: box.$2, width: box.$3, height: box.$4, image: bytes));
      }
    }
    return out;
  }

  static List<SlideParagraph> _paragraphs(XmlElement body) {
    final List<SlideParagraph> out = <SlideParagraph>[];
    for (final XmlElement p in body.childElements.where((XmlElement c) => c.name.local == 'p')) {
      final List<SlideRun> runs = <SlideRun>[];
      for (final XmlElement r in p.childElements) {
        if (r.name.local == 'br') {
          runs.add(const SlideRun('\n'));
          continue;
        }
        if (r.name.local != 'r' && r.name.local != 'fld') {
          continue;
        }
        final XmlElement? t = _kid(r, 't');
        if (t == null) {
          continue;
        }
        final XmlElement? pr = _kid(r, 'rPr');
        final double size = (double.tryParse(pr == null ? '' : (_attr(pr, 'sz') ?? '')) ?? 1800) / 100;
        final bool bold = pr != null && (_attr(pr, 'b') == '1' || _attr(pr, 'b') == 'true');
        final XmlElement? clr = pr == null ? null : _all(pr, 'srgbClr').firstOrNull;
        final String? color = clr == null ? null : _attr(clr, 'val');
        runs.add(SlideRun(t.innerText, size: size, bold: bold, color: color));
      }
      final XmlElement? ppr = _kid(p, 'pPr');
      final String algn = ppr == null ? '' : (_attr(ppr, 'algn') ?? '');
      final SlideAlign align = algn == 'ctr' ? SlideAlign.center : (algn == 'r' ? SlideAlign.right : SlideAlign.left);
      if (runs.isEmpty) {
        out.add(SlideParagraph(const <SlideRun>[], align: align));
      } else {
        out.add(SlideParagraph(runs, align: align));
      }
    }
    while (out.isNotEmpty && out.last.runs.isEmpty) {
      out.removeLast();
    }
    return out.every((SlideParagraph p) => p.runs.isEmpty) ? <SlideParagraph>[] : out;
  }
}

String _n(double v) => v.toStringAsFixed(2);
String _esc(String s) => s.replaceAll(r'\', r'\\').replaceAll('(', r'\(').replaceAll(')', r'\)');

String _rgb(String? hex, String op) {
  final int? v = hex == null || hex.length != 6 ? null : int.tryParse(hex, radix: 16);
  if (v == null) {
    return '0 0 0 $op';
  }
  double c(int s) => ((v >> s) & 0xFF) / 255;
  return '${c(16).toStringAsFixed(3)} ${c(8).toStringAsFixed(3)} ${c(0).toStringAsFixed(3)} $op';
}

/// Splits [text] into lines no wider than [width] at [size].
List<String> wrapSlideText(String text, double width, double size, {bool bold = false}) {
  final List<String> lines = <String>[];
  for (final String para in text.split('\n')) {
    String line = '';
    for (final String word in para.split(' ')) {
      final String next = line.isEmpty ? word : '$line $word';
      if (line.isNotEmpty && textWidth(next, PdfFontFamily.helvetica, size, bold: bold) > width) {
        lines.add(line);
        line = word;
      } else {
        line = next;
      }
    }
    lines.add(line);
  }
  return lines;
}

/// Draws a [SlideDeck] as a PDF, one page per slide at the deck's size.
class SlidesPdfWriter {
  SlidesPdfWriter({ImagesToPdf? images}) : _images = images ?? ImagesToPdf();

  final ImagesToPdf _images;

  Future<Uint8List> write(SlideDeck deck, {bool notes = false}) async {
    final List<PreparedImage> pictures = <PreparedImage>[];
    final List<StringBuffer> pages = <StringBuffer>[];
    final List<List<int>> pageImages = <List<int>>[];
    final double w = deck.width;
    final double h = deck.height;
    for (final Slide s in deck.slides) {
      final StringBuffer ops = StringBuffer();
      final List<int> used = <int>[];
      ops.write('1 1 1 rg 0 0 ${_n(w)} ${_n(h)} re f\n');
      for (final SlideShape sh in s.shapes) {
        final double bottom = h - sh.y - sh.height;
        if (sh.fill != null) {
          ops.write('${_rgb(sh.fill, 'rg')} ${_n(sh.x)} ${_n(bottom)} ${_n(sh.width)} ${_n(sh.height)} re f\n');
        }
        final Uint8List? image = sh.image;
        if (image != null) {
          try {
            final PreparedImage p = await _images.prepare(image);
            pictures.add(p);
            used.add(pictures.length - 1);
            ops.write('q ${_n(sh.width)} 0 0 ${_n(sh.height)} ${_n(sh.x)} ${_n(bottom)} cm /Im${pictures.length - 1} Do Q\n');
          } catch (_) {
            // A picture the phone cannot read is left out; the rest still draws.
          }
        }
        _text(ops, sh.paragraphs, sh.x + 7.2, h - sh.y - 3.6, sh.width - 14.4);
      }
      pages.add(ops);
      pageImages.add(used);
      if (notes && s.notes.isNotEmpty) {
        final StringBuffer n = StringBuffer();
        n.write('1 1 1 rg 0 0 ${_n(w)} ${_n(h)} re f\n');
        _text(n, <SlideParagraph>[
          const SlideParagraph(<SlideRun>[SlideRun('Notes', size: 16, bold: true)]),
          SlideParagraph(<SlideRun>[SlideRun(s.notes, size: 12)]),
        ], 36, h - 36, w - 72);
        pages.add(n);
        pageImages.add(<int>[]);
      }
    }
    return _pdf(pages, pageImages, pictures, w, h);
  }

  static void _text(StringBuffer ops, List<SlideParagraph> paras, double x0, double top, double width) {
    double y = top;
    for (final SlideParagraph p in paras) {
      final double size = p.size;
      final bool bold = p.runs.isNotEmpty && p.runs.first.bold;
      final String? color = p.runs.isEmpty ? null : p.runs.first.color;
      for (final String line in wrapSlideText(p.text, width, size, bold: bold)) {
        y -= size * 1.2;
        final String t = winAnsi(line);
        final double lw = textWidth(t, PdfFontFamily.helvetica, size, bold: bold);
        final double x = p.align == SlideAlign.center
            ? x0 + (width - lw) / 2
            : (p.align == SlideAlign.right ? x0 + width - lw : x0);
        if (t.isNotEmpty) {
          ops.write('BT ${_rgb(color, 'rg')} /${bold ? 'FB' : 'FR'} ${_n(size)} Tf ${_n(x)} ${_n(y)} Td (${_esc(t)}) Tj ET\n');
        }
      }
    }
  }

  static Uint8List _pdf(List<StringBuffer> pages, List<List<int>> pageImages, List<PreparedImage> images, double w,
      double h) {
    final BytesBuilder out = BytesBuilder(copy: false);
    final List<int> offsets = <int>[];
    void add(String s) => out.add(latin1.encode(s));
    void obj(void Function() body) {
      offsets.add(out.length);
      add('${offsets.length} 0 obj\n');
      body();
      add('\nendobj\n');
    }

    // 1 catalog, 2 pages, 3 Helvetica, 4 Helvetica-Bold, images, then page + contents.
    const int imageStart = 5;
    final int pageStart = imageStart + images.length;
    add('%PDF-1.4\n');
    out.add(const <int>[0x25, 0xE2, 0xE3, 0xCF, 0xD3, 0x0A]);
    final String kids = <String>[for (int i = 0; i < pages.length; i++) '${pageStart + i * 2} 0 R'].join(' ');
    obj(() => add('<< /Type /Catalog /Pages 2 0 R >>'));
    obj(() => add('<< /Type /Pages /Kids [$kids] /Count ${pages.length} >>'));
    obj(() => add('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>'));
    obj(() => add('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>'));
    for (final PreparedImage p in images) {
      obj(() {
        add('<< /Type /XObject /Subtype /Image /Width ${p.width} /Height ${p.height} '
            '/ColorSpace ${p.components == 1 ? '/DeviceGray' : '/DeviceRGB'} /BitsPerComponent 8 '
            '/Filter /DCTDecode /Length ${p.jpeg.length} >>\nstream\n');
        out.add(p.jpeg);
        add('\nendstream');
      });
    }
    for (int i = 0; i < pages.length; i++) {
      final int id = pageStart + i * 2;
      final String imgRes = pageImages[i].map((int k) => '/Im$k ${imageStart + k} 0 R').join(' ');
      obj(() => add('<< /Type /Page /Parent 2 0 R /MediaBox [0 0 ${_n(w)} ${_n(h)}] '
          '/Resources << /Font << /FR 3 0 R /FB 4 0 R >> /XObject << $imgRes >> >> /Contents ${id + 1} 0 R >>'));
      final List<int> content = latin1.encode(pages[i].toString());
      obj(() {
        add('<< /Length ${content.length} >>\nstream\n');
        out.add(content);
        add('\nendstream');
      });
    }
    final int xref = out.length;
    final StringBuffer x = StringBuffer('xref\n0 ${offsets.length + 1}\n0000000000 65535 f \n');
    for (final int o in offsets) {
      x.write('${o.toString().padLeft(10, '0')} 00000 n \n');
    }
    x.write('trailer\n<< /Size ${offsets.length + 1} /Root 1 0 R >>\nstartxref\n$xref\n%%EOF\n');
    add(x.toString());
    return out.toBytes();
  }
}

/// Turns PDF pages into slides: each line of text becomes a text box where
/// it sat, scaled onto a 16:9 slide.
class PdfToSlides {
  const PdfToSlides({this.width = 960, this.height = 540});

  final double width;
  final double height;

  SlideDeck build(List<List<PdfTextPiece>> pages) {
    final List<Slide> slides = <Slide>[];
    for (final List<PdfTextPiece> page in pages) {
      if (page.isEmpty) {
        slides.add(const Slide(<SlideShape>[]));
        continue;
      }
      double minL = double.infinity, maxR = 0, minB = double.infinity, maxT = 0;
      for (final PdfTextPiece p in page) {
        minL = p.left < minL ? p.left : minL;
        maxR = p.right > maxR ? p.right : maxR;
        minB = p.bottom < minB ? p.bottom : minB;
        maxT = p.top > maxT ? p.top : maxT;
      }
      // Assume even margins, so the page is the text area plus its margins.
      final double pw = maxR + (minL > 0 ? minL : 36);
      final double ph = maxT + (minB > 0 ? minB : 36);
      final double s = (width / pw) < (height / ph) ? width / pw : height / ph;
      final double ox = (width - pw * s) / 2;
      final double oy = (height - ph * s) / 2;
      final List<PdfTextPiece> sorted = List<PdfTextPiece>.of(page)
        ..sort((PdfTextPiece a, PdfTextPiece b) {
          final int c = b.middle.compareTo(a.middle);
          return c != 0 ? c : a.left.compareTo(b.left);
        });
      final List<List<PdfTextPiece>> lines = <List<PdfTextPiece>>[];
      for (final PdfTextPiece p in sorted) {
        if (lines.isNotEmpty && (lines.last.first.middle - p.middle).abs() < p.height * 0.5) {
          lines.last.add(p);
        } else {
          lines.add(<PdfTextPiece>[p]);
        }
      }
      final List<SlideShape> shapes = <SlideShape>[];
      for (final List<PdfTextPiece> l in lines) {
        l.sort((PdfTextPiece a, PdfTextPiece b) => a.left.compareTo(b.left));
        final double left = l.first.left;
        final double right = l.map((PdfTextPiece p) => p.right).reduce((double a, double b) => a > b ? a : b);
        final double top = l.map((PdfTextPiece p) => p.top).reduce((double a, double b) => a > b ? a : b);
        final double bottom = l.map((PdfTextPiece p) => p.bottom).reduce((double a, double b) => a < b ? a : b);
        final String text = l.map((PdfTextPiece p) => p.text).join(' ').replaceAll(RegExp(r'\s+'), ' ').trim();
        if (text.isEmpty) {
          continue;
        }
        final double size = ((top - bottom) * s).clamp(6, 96).toDouble();
        shapes.add(SlideShape(
          x: ox + left * s,
          y: oy + (ph - top) * s,
          width: ((right - left) * s + 14.4) * 1.1,
          height: size * 1.2 + 7.2,
          paragraphs: <SlideParagraph>[
            SlideParagraph(<SlideRun>[SlideRun(text, size: (size * 10).round() / 10)]),
          ],
        ));
      }
      slides.add(Slide(shapes));
    }
    return SlideDeck(width: width, height: height, slides: slides);
  }
}

String _x(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

/// Writes a [SlideDeck] (text boxes and fills) as a .pptx PowerPoint opens.
class PptxWriter {
  const PptxWriter();

  static const String _p = 'http://schemas.openxmlformats.org/presentationml/2006/main';
  static const String _a = 'http://schemas.openxmlformats.org/drawingml/2006/main';
  static const String _r = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
  static const String _rel = 'http://schemas.openxmlformats.org/package/2006/relationships';
  static const String _ot = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships';

  Uint8List write(SlideDeck deck, {DateTime? now}) {
    final int cx = (deck.width * _emuPerPt).round();
    final int cy = (deck.height * _emuPerPt).round();
    final int n = deck.slides.length;
    const String head = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n';
    final StringBuffer types = StringBuffer('$head<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/ppt/presentation.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml"/>'
        '<Override PartName="/ppt/slideMasters/slideMaster1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideMaster+xml"/>'
        '<Override PartName="/ppt/slideLayouts/slideLayout1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideLayout+xml"/>'
        '<Override PartName="/ppt/theme/theme1.xml" ContentType="application/vnd.openxmlformats-officedocument.theme+xml"/>');
    for (int i = 1; i <= n; i++) {
      types.write('<Override PartName="/ppt/slides/slide$i.xml" '
          'ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/>');
    }
    types.write('</Types>');
    final StringBuffer presRels = StringBuffer('$head<Relationships xmlns="$_rel">'
        '<Relationship Id="rId1" Type="$_ot/slideMaster" Target="slideMasters/slideMaster1.xml"/>'
        '<Relationship Id="rId2" Type="$_ot/theme" Target="theme/theme1.xml"/>');
    final StringBuffer ids = StringBuffer();
    for (int i = 1; i <= n; i++) {
      presRels.write('<Relationship Id="rId${i + 2}" Type="$_ot/slide" Target="slides/slide$i.xml"/>');
      ids.write('<p:sldId id="${255 + i}" r:id="rId${i + 2}"/>');
    }
    presRels.write('</Relationships>');
    final String pres = '$head<p:presentation xmlns:a="$_a" xmlns:r="$_r" xmlns:p="$_p">'
        '<p:sldMasterIdLst><p:sldMasterId id="2147483648" r:id="rId1"/></p:sldMasterIdLst>'
        '<p:sldIdLst>$ids</p:sldIdLst><p:sldSz cx="$cx" cy="$cy"/><p:notesSz cx="6858000" cy="9144000"/>'
        '</p:presentation>';
    const String emptyTree = '<p:cSld><p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>'
        '<p:grpSpPr/></p:spTree></p:cSld>';
    final String master = '$head<p:sldMaster xmlns:a="$_a" xmlns:r="$_r" xmlns:p="$_p">$emptyTree'
        '<p:clrMap bg1="lt1" tx1="dk1" bg2="lt2" tx2="dk2" accent1="accent1" accent2="accent2" accent3="accent3" '
        'accent4="accent4" accent5="accent5" accent6="accent6" hlink="hlink" folHlink="folHlink"/>'
        '<p:sldLayoutIdLst><p:sldLayoutId id="2147483649" r:id="rId1"/></p:sldLayoutIdLst></p:sldMaster>';
    final String masterRels = '$head<Relationships xmlns="$_rel">'
        '<Relationship Id="rId1" Type="$_ot/slideLayout" Target="../slideLayouts/slideLayout1.xml"/>'
        '<Relationship Id="rId2" Type="$_ot/theme" Target="../theme/theme1.xml"/></Relationships>';
    final String layout = '$head<p:sldLayout xmlns:a="$_a" xmlns:r="$_r" xmlns:p="$_p" type="blank">$emptyTree'
        '<p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sldLayout>';
    final String layoutRels = '$head<Relationships xmlns="$_rel">'
        '<Relationship Id="rId1" Type="$_ot/slideMaster" Target="../slideMasters/slideMaster1.xml"/></Relationships>';
    final String slideRels = '$head<Relationships xmlns="$_rel">'
        '<Relationship Id="rId1" Type="$_ot/slideLayout" Target="../slideLayouts/slideLayout1.xml"/></Relationships>';
    final List<ZipInput> files = <ZipInput>[
      ZipInput('[Content_Types].xml', utf8.encode(types.toString()), modified: now),
      ZipInput('_rels/.rels', utf8.encode('$head<Relationships xmlns="$_rel">'
          '<Relationship Id="rId1" Type="$_ot/officeDocument" Target="ppt/presentation.xml"/></Relationships>'), modified: now),
      ZipInput('ppt/presentation.xml', utf8.encode(pres), modified: now),
      ZipInput('ppt/_rels/presentation.xml.rels', utf8.encode(presRels.toString()), modified: now),
      ZipInput('ppt/slideMasters/slideMaster1.xml', utf8.encode(master), modified: now),
      ZipInput('ppt/slideMasters/_rels/slideMaster1.xml.rels', utf8.encode(masterRels), modified: now),
      ZipInput('ppt/slideLayouts/slideLayout1.xml', utf8.encode(layout), modified: now),
      ZipInput('ppt/slideLayouts/_rels/slideLayout1.xml.rels', utf8.encode(layoutRels), modified: now),
      ZipInput('ppt/theme/theme1.xml', utf8.encode(_theme()), modified: now),
    ];
    for (int i = 0; i < n; i++) {
      files
        ..add(ZipInput('ppt/slides/slide${i + 1}.xml', utf8.encode(_slide(deck.slides[i])), modified: now))
        ..add(ZipInput('ppt/slides/_rels/slide${i + 1}.xml.rels', utf8.encode(slideRels), modified: now));
    }
    return ZipWriter().build(files, now: now);
  }

  static int _e(double pt) => (pt * _emuPerPt).round();

  String _slide(Slide s) {
    final StringBuffer b = StringBuffer('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
        '<p:sld xmlns:a="$_a" xmlns:r="$_r" xmlns:p="$_p"><p:cSld><p:spTree>'
        '<p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/>');
    int id = 2;
    for (final SlideShape sh in s.shapes) {
      b.write('<p:sp><p:nvSpPr><p:cNvPr id="$id" name="Text $id"/><p:cNvSpPr txBox="1"/><p:nvPr/></p:nvSpPr>'
          '<p:spPr><a:xfrm><a:off x="${_e(sh.x)}" y="${_e(sh.y)}"/><a:ext cx="${_e(sh.width)}" cy="${_e(sh.height)}"/></a:xfrm>'
          '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom>'
          '${sh.fill == null ? '<a:noFill/>' : '<a:solidFill><a:srgbClr val="${sh.fill}"/></a:solidFill>'}</p:spPr>'
          '<p:txBody><a:bodyPr wrap="square"/><a:lstStyle/>');
      final List<SlideParagraph> paras = sh.paragraphs.isEmpty ? const <SlideParagraph>[SlideParagraph(<SlideRun>[])] : sh.paragraphs;
      for (final SlideParagraph p in paras) {
        final String algn = p.align == SlideAlign.center ? ' algn="ctr"' : (p.align == SlideAlign.right ? ' algn="r"' : '');
        b.write('<a:p>${algn.isEmpty ? '' : '<a:pPr$algn/>'}');
        for (final SlideRun r in p.runs) {
          b.write('<a:r><a:rPr lang="en-US" sz="${(r.size * 100).round()}"${r.bold ? ' b="1"' : ''} dirty="0">'
              '${r.color == null ? '' : '<a:solidFill><a:srgbClr val="${r.color}"/></a:solidFill>'}</a:rPr>'
              '<a:t>${_x(r.text)}</a:t></a:r>');
        }
        b.write('</a:p>');
      }
      b.write('</p:txBody></p:sp>');
      id++;
    }
    b.write('</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sld>');
    return b.toString();
  }

  static String _theme() {
    String c(String name, String hex) => '<a:$name><a:srgbClr val="$hex"/></a:$name>';
    const String font = '<a:latin typeface="Calibri"/><a:ea typeface=""/><a:cs typeface=""/>';
    const String fill = '<a:solidFill><a:schemeClr val="phClr"/></a:solidFill>';
    const String line = '<a:ln w="9525"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:ln>';
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
        '<a:theme xmlns:a="$_a" name="Family"><a:themeElements><a:clrScheme name="Family">'
        '<a:dk1><a:sysClr val="windowText" lastClr="000000"/></a:dk1><a:lt1><a:sysClr val="window" lastClr="FFFFFF"/></a:lt1>'
        '${c('dk2', '1F2937')}${c('lt2', 'F3F4F6')}${c('accent1', '2563EB')}${c('accent2', '059669')}'
        '${c('accent3', 'D97706')}${c('accent4', 'DC2626')}${c('accent5', '7C3AED')}${c('accent6', '0891B2')}'
        '${c('hlink', '2563EB')}${c('folHlink', '7C3AED')}</a:clrScheme>'
        '<a:fontScheme name="Family"><a:majorFont>$font</a:majorFont><a:minorFont>$font</a:minorFont></a:fontScheme>'
        '<a:fmtScheme name="Family"><a:fillStyleLst>$fill$fill$fill</a:fillStyleLst>'
        '<a:lnStyleLst>$line$line$line</a:lnStyleLst>'
        '<a:effectStyleLst><a:effectStyle><a:effectLst/></a:effectStyle><a:effectStyle><a:effectLst/></a:effectStyle>'
        '<a:effectStyle><a:effectLst/></a:effectStyle></a:effectStyleLst>'
        '<a:bgFillStyleLst>$fill$fill$fill</a:bgFillStyleLst></a:fmtScheme></a:themeElements></a:theme>';
  }
}

class PptxToPdfConverter extends Converter {
  const PptxToPdfConverter({this.notes = false});

  /// Adds a notes page after each slide that has speaker notes.
  final bool notes;

  @override
  String get id => notes ? 'pptx-to-pdf-notes' : 'pptx-to-pdf';
  @override
  String get label => notes ? 'PDF with speaker notes' : 'PDF';
  @override
  FileKind get target => FileKind.pdf;
  @override
  bool accepts(FileKind kind) => kind == FileKind.pptx;

  @override
  Future<ConvertOutput> convert(ConvertInput input, FileKind kind) async {
    final SlideDeck deck = const PptxReader().read(input.bytes);
    return output(input, await SlidesPdfWriter().write(deck, notes: notes));
  }
}

class PdfToPptxConverter extends Converter {
  const PdfToPptxConverter(this.source);

  final PdfTextSource source;

  @override
  String get id => 'pdf-to-pptx';
  @override
  String get label => 'PowerPoint deck';
  @override
  FileKind get target => FileKind.pptx;
  @override
  bool accepts(FileKind kind) => kind == FileKind.pdf;

  @override
  Future<ConvertOutput> convert(ConvertInput input, FileKind kind) async {
    final List<List<PdfTextPiece>> pages = await source.read(input.bytes);
    if (pages.every((List<PdfTextPiece> p) => p.isEmpty)) {
      throw const ConvertException('This PDF has no text to put on slides; it may be a scan.');
    }
    return output(input, const PptxWriter().write(const PdfToSlides().build(pages)));
  }
}

/// Old binary .ppt files: said plainly rather than converted badly.
class LegacyPptConverter extends Converter {
  const LegacyPptConverter();

  @override
  String get id => 'ppt-to-pdf';
  @override
  String get label => 'PDF';
  @override
  FileKind get target => FileKind.pdf;
  @override
  bool accepts(FileKind kind) => kind == FileKind.ppt;

  @override
  Future<ConvertOutput> convert(ConvertInput input, FileKind kind) async {
    throw const ConvertException(
        'Old PowerPoint 97-2003 (.ppt) files cannot be read on this phone. Save it as .pptx in PowerPoint, then convert it here.');
  }
}

/// Adds the PowerPoint converters to [registry].
void registerSlideConverters(ConvertRegistry registry, PdfTextSource source) {
  registry
    ..register(const PptxToPdfConverter())
    ..register(const PptxToPdfConverter(notes: true))
    ..register(PdfToPptxConverter(source))
    ..register(const LegacyPptConverter());
}
