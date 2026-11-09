import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import 'images_to_pdf.dart' show jpegInfo;
import 'pdf_to_images.dart';

/// Feature 008 — OCR a scan.
///
/// Each page of a scanned PDF is drawn on the phone, read by on-device text
/// recognition (ML Kit, behind [TextRecognizerEngine]), and written back as
/// the page image with an invisible text layer (render mode 3) so the PDF
/// can be searched and its text selected. Nothing is uploaded.

enum OcrScript {
  latin('Latin (English and more)'),
  devanagari('Devanagari (Hindi, Marathi and more)');

  const OcrScript(this.label);
  final String label;
}

/// One recognised word and its box in image pixels (y grows downwards).
@immutable
class OcrWord {
  const OcrWord(this.text, {required this.left, required this.top, required this.right, required this.bottom});

  final String text;
  final double left;
  final double top;
  final double right;
  final double bottom;
}

/// On-device text recognition of one page image.
abstract class TextRecognizerEngine {
  Future<List<OcrWord>> recognize(img.Image page, Uint8List jpeg, OcrScript script);
}

/// One page as it goes into the output PDF.
@immutable
class OcrPage {
  const OcrPage({
    required this.jpeg,
    required this.pixelWidth,
    required this.pixelHeight,
    required this.widthPt,
    required this.heightPt,
    required this.words,
  });

  final Uint8List jpeg;
  final int pixelWidth;
  final int pixelHeight;
  final double widthPt;
  final double heightPt;
  final List<OcrWord> words;

  /// The words in reading order, one line of text per row of words.
  String get text => wordsToText(words);
}

/// Words joined into lines: words whose vertical centres are close share a line.
String wordsToText(List<OcrWord> words) {
  if (words.isEmpty) {
    return '';
  }
  final List<OcrWord> sorted = List<OcrWord>.of(words)
    ..sort((OcrWord a, OcrWord b) => a.top.compareTo(b.top));
  final List<List<OcrWord>> lines = <List<OcrWord>>[];
  for (final OcrWord w in sorted) {
    final double mid = (w.top + w.bottom) / 2;
    final List<OcrWord>? last = lines.isEmpty ? null : lines.last;
    if (last != null) {
      final OcrWord f = last.first;
      if ((mid - (f.top + f.bottom) / 2).abs() < (f.bottom - f.top) * 0.6) {
        last.add(w);
        continue;
      }
    }
    lines.add(<OcrWord>[w]);
  }
  return lines.map((List<OcrWord> l) {
    l.sort((OcrWord a, OcrWord b) => a.left.compareTo(b.left));
    return l.map((OcrWord w) => w.text).join(' ');
  }).join('\n');
}

class OcrResult {
  const OcrResult(this.pdf, this.pages);

  final Uint8List pdf;
  final List<OcrPage> pages;

  int get wordCount => pages.fold(0, (int n, OcrPage p) => n + p.words.length);

  /// Page texts, index 0 is page 1.
  List<String> get pageTexts => <String>[for (final OcrPage p in pages) p.text];
}

class PdfOcrError implements Exception {
  const PdfOcrError(this.message);
  final String message;

  @override
  String toString() => message;
}

class PdfOcr {
  const PdfOcr({required this.rasterizer, required this.recognizer, this.dpi = 200, this.jpegQuality = 80});

  final PdfRasterizer rasterizer;
  final TextRecognizerEngine recognizer;
  final int dpi;
  final int jpegQuality;

  Future<OcrResult> run(
    Uint8List pdf,
    OcrScript script, {
    void Function(int done, int total)? progress,
  }) async {
    final int count = await rasterizer.pageCount(pdf);
    if (count == 0) {
      throw const PdfOcrError('This PDF has no pages');
    }
    final List<OcrPage> pages = <OcrPage>[];
    for (int i = 0; i < count; i++) {
      final img.Image page = await rasterizer.render(pdf, i, dpi);
      final Uint8List jpeg = Uint8List.fromList(img.encodeJpg(page, quality: jpegQuality));
      final List<OcrWord> words = await recognizer.recognize(page, jpeg, script);
      pages.add(OcrPage(
        jpeg: jpeg,
        pixelWidth: page.width,
        pixelHeight: page.height,
        widthPt: page.width * 72 / dpi,
        heightPt: page.height * 72 / dpi,
        words: words.where((OcrWord w) => w.text.trim().isNotEmpty).toList(),
      ));
      progress?.call(i + 1, count);
    }
    return OcrResult(writeSearchablePdf(pages), pages);
  }
}

/// Character codes for the invisible font: every distinct character gets a
/// two-byte code, and the ToUnicode map turns codes back into text, so
/// copying and searching give the recognised words in any script.
class _Codes {
  final Map<int, int> byRune = <int, int>{};

  int code(int rune) => byRune.putIfAbsent(rune, () => byRune.length + 1);

  String hex(String s) {
    final StringBuffer b = StringBuffer();
    for (final int r in s.runes) {
      b.write(code(r).toRadixString(16).padLeft(4, '0'));
    }
    return b.toString();
  }

  static String _utf16(int rune) {
    final List<int> units = String.fromCharCode(rune).codeUnits;
    return units.map((int u) => u.toRadixString(16).padLeft(4, '0')).join();
  }

  String toUnicode() {
    final StringBuffer b = StringBuffer()
      ..writeln('/CIDInit /ProcSet findresource begin')
      ..writeln('12 dict begin')
      ..writeln('begincmap')
      ..writeln('/CIDSystemInfo << /Registry (Adobe) /Ordering (UCS) /Supplement 0 >> def')
      ..writeln('/CMapName /Adobe-Identity-UCS def')
      ..writeln('/CMapType 2 def')
      ..writeln('1 begincodespacerange')
      ..writeln('<0000> <FFFF>')
      ..writeln('endcodespacerange');
    final List<MapEntry<int, int>> all = byRune.entries.toList();
    for (int i = 0; i < all.length; i += 100) {
      final List<MapEntry<int, int>> chunk = all.sublist(i, i + 100 > all.length ? all.length : i + 100);
      b.writeln('${chunk.length} beginbfchar');
      for (final MapEntry<int, int> e in chunk) {
        b.writeln('<${e.value.toRadixString(16).padLeft(4, '0')}> <${_utf16(e.key)}>');
      }
      b.writeln('endbfchar');
    }
    b
      ..writeln('endcmap')
      ..writeln('CMapName currentdict /CMap defineresource pop')
      ..writeln('end')
      ..writeln('end');
    return b.toString();
  }
}

String _n(double v) => v.toStringAsFixed(2);

/// Glyph width of the invisible font, in 1/1000 em. Words are stretched to
/// their boxes with Tz, so the exact value only sets the scale.
const int _glyphWidth = 500;

/// The page images with an invisible text layer over each recognised word.
Uint8List writeSearchablePdf(List<OcrPage> pages) {
  final _Codes codes = _Codes();
  final List<String> contents = <String>[];
  for (final OcrPage p in pages) {
    final double sx = p.widthPt / p.pixelWidth;
    final double sy = p.heightPt / p.pixelHeight;
    final StringBuffer c = StringBuffer('q ${_n(p.widthPt)} 0 0 ${_n(p.heightPt)} 0 0 cm /Im0 Do Q\n');
    if (p.words.isNotEmpty) {
      c.write('BT 3 Tr\n');
      for (final OcrWord w in p.words) {
        final String t = '${w.text.trim()} ';
        final int n = t.runes.length;
        final double h = (w.bottom - w.top) * sy;
        final double size = h <= 0 ? 1 : h * 0.9;
        final double target = (w.right - w.left) * sx;
        final double natural = (n - 0.5) * size * _glyphWidth / 1000;
        final double tz = natural <= 0 ? 100 : (target / natural * 100).clamp(1, 1000).toDouble();
        final double x = w.left * sx;
        final double y = p.heightPt - w.bottom * sy + h * 0.1;
        c.write('/F1 ${_n(size)} Tf ${_n(tz)} Tz 1 0 0 1 ${_n(x)} ${_n(y)} Tm <${codes.hex(t)}> Tj\n');
      }
      c.write('ET\n');
    }
    contents.add(c.toString());
  }

  final BytesBuilder out = BytesBuilder(copy: false);
  final List<int> offsets = <int>[];
  void add(String s) => out.add(latin1.encode(s));
  void obj(int id, void Function() body) {
    while (offsets.length < id) {
      offsets.add(0);
    }
    offsets[id - 1] = out.length;
    add('$id 0 obj\n');
    body();
    add('\nendobj\n');
  }

  add('%PDF-1.4\n');
  out.add(const <int>[0x25, 0xE2, 0xE3, 0xCF, 0xD3, 0x0A]);
  final int count = pages.length;
  // 1 catalog, 2 pages, 3 font, 4 CID font, 5 descriptor, 6 ToUnicode,
  // then per page: page, image, contents.
  const int first = 7;
  final String kids = <String>[for (int i = 0; i < count; i++) '${first + i * 3} 0 R'].join(' ');
  obj(1, () => add('<< /Type /Catalog /Pages 2 0 R >>'));
  obj(2, () => add('<< /Type /Pages /Kids [$kids] /Count $count >>'));
  obj(3, () => add('<< /Type /Font /Subtype /Type0 /BaseFont /OcrText /Encoding /Identity-H '
      '/DescendantFonts [4 0 R] /ToUnicode 6 0 R >>'));
  obj(4, () => add('<< /Type /Font /Subtype /CIDFontType2 /BaseFont /OcrText '
      '/CIDSystemInfo << /Registry (Adobe) /Ordering (Identity) /Supplement 0 >> '
      '/FontDescriptor 5 0 R /DW $_glyphWidth /CIDToGIDMap /Identity >>'));
  obj(5, () => add('<< /Type /FontDescriptor /FontName /OcrText /Flags 4 /FontBBox [0 -200 1000 900] '
      '/ItalicAngle 0 /Ascent 900 /Descent -200 /CapHeight 700 /StemV 80 >>'));
  final String cmap = codes.toUnicode();
  obj(6, () => add('<< /Length ${latin1.encode(cmap).length} >>\nstream\n$cmap\nendstream'));
  for (int i = 0; i < count; i++) {
    final OcrPage p = pages[i];
    final int pageId = first + i * 3;
    obj(pageId, () => add('<< /Type /Page /Parent 2 0 R /MediaBox [0 0 ${_n(p.widthPt)} ${_n(p.heightPt)}] '
        '/Resources << /XObject << /Im0 ${pageId + 1} 0 R >> /Font << /F1 3 0 R >> >> '
        '/Contents ${pageId + 2} 0 R >>'));
    obj(pageId + 1, () {
      add('<< /Type /XObject /Subtype /Image /Width ${p.pixelWidth} /Height ${p.pixelHeight} '
          '/ColorSpace ${jpegInfo(p.jpeg)?.components == 1 ? '/DeviceGray' : '/DeviceRGB'} /BitsPerComponent 8 /Filter /DCTDecode /Length ${p.jpeg.length} >>\nstream\n');
      out.add(p.jpeg);
      add('\nendstream');
    });
    final List<int> body = latin1.encode(contents[i]);
    obj(pageId + 2, () {
      add('<< /Length ${body.length} >>\nstream\n');
      out.add(body);
      add('\nendstream');
    });
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
