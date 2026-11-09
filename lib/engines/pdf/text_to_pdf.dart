import 'dart:convert';
import 'dart:io' show ZLibCodec;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../convert/convert_registry.dart';
import '../convert/file_kind.dart';
import 'images_to_pdf.dart' show PdfPageSize;

/// Feature 024 — Text to PDF: paste text, choose a font and size, get a PDF.
///
/// Indian scripts (Devanagari, Tamil, Bengali, Telugu…) need real shaping:
/// conjuncts, vowel signs that sit before the consonant, reordering. A PDF
/// writer in Dart would have to do that itself, so instead the phone's own
/// text engine (the one every Flutter screen uses, with the phone's Noto
/// fonts as fallback) lays the text out and draws each page. Pages are
/// stored as lossless greyscale images at [TextPdfOptions.dpi], so what the
/// PDF shows is exactly what the phone shaped. Nothing leaves the phone.

enum TextPdfFont {
  phone('Phone font', null),
  serif('Serif', 'serif'),
  mono('Monospace', 'monospace'),
  inter('Inter', 'Inter');

  const TextPdfFont(this.label, this.family);
  final String label;

  /// Flutter font family; null is the phone's default.
  final String? family;
}

class TextPdfOptions {
  const TextPdfOptions({
    this.font = TextPdfFont.phone,
    this.fontSize = 12,
    this.pageSize = PdfPageSize.a4,
    this.marginPt = 56,
    this.lineHeight = 1.4,
    this.dpi = 200,
  });

  final TextPdfFont font;

  /// Points (1/72 inch), as in a word processor.
  final double fontSize;

  /// A4 or Letter; "fit" is treated as A4.
  final PdfPageSize pageSize;
  final double marginPt;
  final double lineHeight;
  final int dpi;

  static const double minSize = 8;
  static const double maxSize = 32;

  (double, double) get page =>
      pageSize == PdfPageSize.letter ? (PdfPageSize.letter.width, PdfPageSize.letter.height) : (PdfPageSize.a4.width, PdfPageSize.a4.height);

  TextPdfOptions copyWith({TextPdfFont? font, double? fontSize, PdfPageSize? pageSize}) => TextPdfOptions(
        font: font ?? this.font,
        fontSize: fontSize ?? this.fontSize,
        pageSize: pageSize ?? this.pageSize,
        marginPt: marginPt,
        lineHeight: lineHeight,
        dpi: dpi,
      );
}

class TextPdfError implements Exception {
  const TextPdfError(this.message);
  final String message;

  @override
  String toString() => message;
}

/// One laid-out line: its top and bottom in points from the top of the text.
class LineSpan {
  const LineSpan(this.top, this.bottom);
  final double top;
  final double bottom;
}

/// The part of the text one page shows: from [top] down to [bottom].
class PageSlice {
  const PageSlice(this.top, this.bottom);
  final double top;
  final double bottom;

  @override
  bool operator ==(Object other) => other is PageSlice && other.top == top && other.bottom == bottom;

  @override
  int get hashCode => Object.hash(top, bottom);

  @override
  String toString() => 'PageSlice($top, $bottom)';
}

/// One page drawn as 8-bit grey pixels, row by row.
class GreyPage {
  const GreyPage({required this.width, required this.height, required this.pixels, required this.widthPt, required this.heightPt});
  final int width;
  final int height;
  final Uint8List pixels;
  final double widthPt;
  final double heightPt;
}

class TextPdfResult {
  const TextPdfResult({required this.name, required this.bytes, required this.pages});
  final String name;
  final Uint8List bytes;
  final int pages;
}

abstract final class TextToPdf {
  /// Splits lines into pages of at most [boxHeight] points. A line never
  /// breaks across pages; a line taller than a page gets a page of its own.
  static List<PageSlice> paginate(List<LineSpan> lines, double boxHeight) {
    if (lines.isEmpty) {
      return <PageSlice>[PageSlice(0, boxHeight)];
    }
    final List<double> tops = <double>[0];
    for (final LineSpan l in lines) {
      final double top = tops.last;
      if (l.bottom - top > boxHeight && l.top > top) {
        tops.add(l.top);
      }
    }
    return <PageSlice>[
      for (int i = 0; i < tops.length; i++) PageSlice(tops[i], i + 1 < tops.length ? tops[i + 1] : tops[i] + boxHeight),
    ];
  }

  /// "Notes 2026-11-09.pdf" from the first words of the text.
  static String nameFor(String text) {
    final String first = text.trim().split('\n').first.trim();
    final String clean = first.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    final String cut = clean.runes.length > 40 ? String.fromCharCodes(clean.runes.take(40)).trim() : clean;
    return '${cut.isEmpty ? 'Text' : cut}.pdf';
  }

  static String _n(double v) => v.toStringAsFixed(2);

  /// A PDF with one full-page greyscale image per page (FlateDecode).
  static Uint8List writePdf(List<GreyPage> pages) {
    if (pages.isEmpty) {
      throw const TextPdfError('There is nothing to put in the PDF.');
    }
    final ZLibCodec zlib = ZLibCodec(level: 9);
    final BytesBuilder out = BytesBuilder(copy: false);
    final List<int> offsets = <int>[];
    void add(String s) => out.add(latin1.encode(s));
    void obj(int id, void Function() body) {
      offsets.add(out.length);
      add('$id 0 obj\n');
      body();
      add('\nendobj\n');
    }

    add('%PDF-1.4\n');
    out.add(const <int>[0x25, 0xE2, 0xE3, 0xCF, 0xD3, 0x0A]);
    final int count = pages.length;
    final String kids = <String>[for (int i = 0; i < count; i++) '${3 + i * 3} 0 R'].join(' ');
    obj(1, () => add('<< /Type /Catalog /Pages 2 0 R >>'));
    obj(2, () => add('<< /Type /Pages /Kids [$kids] /Count $count >>'));
    for (int i = 0; i < count; i++) {
      final GreyPage p = pages[i];
      final int pageId = 3 + i * 3;
      final String content = 'q ${_n(p.widthPt)} 0 0 ${_n(p.heightPt)} 0 0 cm /Im0 Do Q';
      obj(pageId, () => add('<< /Type /Page /Parent 2 0 R /MediaBox [0 0 ${_n(p.widthPt)} ${_n(p.heightPt)}] '
          '/Resources << /XObject << /Im0 ${pageId + 1} 0 R >> >> /Contents ${pageId + 2} 0 R >>'));
      final List<int> packed = zlib.encode(p.pixels);
      obj(pageId + 1, () {
        add('<< /Type /XObject /Subtype /Image /Width ${p.width} /Height ${p.height} '
            '/ColorSpace /DeviceGray /BitsPerComponent 8 /Filter /FlateDecode /Length ${packed.length} >>\nstream\n');
        out.add(packed);
        add('\nendstream');
      });
      obj(pageId + 2, () => add('<< /Length ${content.length} >>\nstream\n$content\nendstream'));
    }
    final int xref = out.length;
    final int size = offsets.length + 1;
    final StringBuffer x = StringBuffer('xref\n0 $size\n0000000000 65535 f \n');
    for (final int off in offsets) {
      x.write('${off.toString().padLeft(10, '0')} 00000 n \n');
    }
    x.write('trailer\n<< /Size $size /Root 1 0 R >>\nstartxref\n$xref\n%%EOF\n');
    add(x.toString());
    return out.takeBytes();
  }
}

/// Lays text out and draws its pages. Behind an interface for tests.
abstract class TextPageRenderer {
  Future<List<GreyPage>> render(String text, TextPdfOptions o);
}

/// Uses the phone's text engine, which shapes every script the phone has
/// fonts for, and falls back to the phone's fonts per character.
class FlutterTextPageRenderer implements TextPageRenderer {
  const FlutterTextPageRenderer();

  static TextPainter layout(String text, TextPdfOptions o) {
    final (double pw, double _) = o.page;
    final TextPainter painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: const ui.Color(0xFF000000),
          fontFamily: o.font.family,
          fontSize: o.fontSize,
          height: o.lineHeight,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: pw - 2 * o.marginPt);
    return painter;
  }

  @override
  Future<List<GreyPage>> render(String text, TextPdfOptions o) async {
    final (double pw, double ph) = o.page;
    final double boxH = ph - 2 * o.marginPt;
    final TextPainter painter = layout(text, o);
    final List<LineSpan> lines = <LineSpan>[
      for (final ui.LineMetrics m in painter.computeLineMetrics())
        LineSpan(m.baseline - m.ascent, m.baseline + m.descent),
    ];
    final List<PageSlice> slices = TextToPdf.paginate(lines, boxH);
    final double scale = o.dpi / 72;
    final int w = (pw * scale).round();
    final int h = (ph * scale).round();
    final List<GreyPage> pages = <GreyPage>[];
    try {
      for (final PageSlice s in slices) {
        final ui.PictureRecorder rec = ui.PictureRecorder();
        final ui.Canvas c = ui.Canvas(rec);
        c.drawRect(ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), ui.Paint()..color = const ui.Color(0xFFFFFFFF));
        c.scale(scale);
        c.translate(o.marginPt, o.marginPt);
        c.clipRect(ui.Rect.fromLTWH(-o.marginPt, 0, pw, s.bottom - s.top));
        c.translate(0, -s.top);
        painter.paint(c, ui.Offset.zero);
        final ui.Picture picture = rec.endRecording();
        final ui.Image image = await picture.toImage(w, h);
        picture.dispose();
        final ByteData? rgba = await image.toByteData();
        image.dispose();
        if (rgba == null) {
          throw const TextPdfError('The page could not be drawn.');
        }
        final Uint8List px = rgba.buffer.asUint8List(rgba.offsetInBytes, rgba.lengthInBytes);
        final Uint8List grey = Uint8List(w * h);
        for (int i = 0, j = 0; i < grey.length; i++, j += 4) {
          // Rec. 601 luma; the page is opaque white underneath.
          grey[i] = (px[j] * 299 + px[j + 1] * 587 + px[j + 2] * 114) ~/ 1000;
        }
        pages.add(GreyPage(width: w, height: h, pixels: grey, widthPt: pw, heightPt: ph));
      }
    } finally {
      painter.dispose();
    }
    return pages;
  }
}

/// Makes the PDF from pasted text.
class TextPdfMaker {
  const TextPdfMaker({this.renderer = const FlutterTextPageRenderer()});
  final TextPageRenderer renderer;

  Future<TextPdfResult> make(String text, TextPdfOptions o, {String? name}) async {
    final String body = text.replaceAll('\r\n', '\n').replaceAll('\t', '    ').trimRight();
    if (body.trim().isEmpty) {
      throw const TextPdfError('Paste or type some text first.');
    }
    final List<GreyPage> pages = await renderer.render(body, o);
    return TextPdfResult(name: name ?? TextToPdf.nameFor(body), bytes: TextToPdf.writePdf(pages), pages: pages.length);
  }
}

/// Plain .txt files become a PDF in Convert anything (feature 030).
class TextToPdfConverter extends Converter {
  const TextToPdfConverter({this.maker = const TextPdfMaker()});
  final TextPdfMaker maker;

  @override
  String get id => 'text-to-pdf';
  @override
  String get label => 'PDF';
  @override
  FileKind get target => FileKind.pdf;
  @override
  bool accepts(FileKind kind) => kind == FileKind.text;

  @override
  Future<ConvertOutput> convert(ConvertInput input, FileKind kind) async {
    try {
      final TextPdfResult r = await maker.make(utf8.decode(input.bytes, allowMalformed: true), const TextPdfOptions());
      return output(input, r.bytes);
    } on TextPdfError catch (e) {
      throw ConvertException(e.message);
    }
  }
}
