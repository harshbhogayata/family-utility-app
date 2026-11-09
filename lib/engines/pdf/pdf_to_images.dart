import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Feature 022 — PDF to images: one picture per page, or every chosen page
/// stacked into one long picture for sharing in chat. Pages are drawn by
/// PDFium on the phone (behind [PdfRasterizer]); the rest is pure Dart.

enum PdfImageFormat {
  jpg('JPG', 'jpg'),
  png('PNG', 'png');

  const PdfImageFormat(this.label, this.extension);
  final String label;
  final String extension;
}

const List<int> pdfImageDpis = <int>[72, 150, 300];

/// Long images taller than this are scaled down so chat apps accept them.
const int longImageMaxHeight = 16000;

/// Draws PDF pages. PDFium in the app, a fake in tests.
abstract class PdfRasterizer {
  Future<int> pageCount(Uint8List pdf);

  /// Page [index] (0-based) at [dpi], on white.
  Future<img.Image> render(Uint8List pdf, int index, int dpi);
}

class PdfToImagesError implements Exception {
  const PdfToImagesError(this.message);
  final String message;
  @override
  String toString() => message;
}

class PdfImageOut {
  const PdfImageOut(this.name, this.bytes, this.width, this.height);
  final String name;
  final Uint8List bytes;
  final int width;
  final int height;
}

abstract final class PageRange {
  /// Parses "1-3, 5, 8-" into 0-based page indexes, in order, without
  /// repeats. Empty text means every page.
  static List<int> parse(String text, int pageCount) {
    final String t = text.replaceAll(' ', '');
    if (t.isEmpty) {
      return List<int>.generate(pageCount, (int i) => i);
    }
    final List<int> out = <int>[];
    for (final String part in t.split(',')) {
      if (part.isEmpty) {
        continue;
      }
      final List<String> ends = part.split('-');
      if (ends.length > 2) {
        throw PdfToImagesError('"$part" is not a page or a range');
      }
      final int? a = ends[0].isEmpty ? 1 : int.tryParse(ends[0]);
      final int? b = ends.length == 1 ? a : (ends[1].isEmpty ? pageCount : int.tryParse(ends[1]));
      if (a == null || b == null || a < 1 || b < a) {
        throw PdfToImagesError('"$part" is not a page or a range');
      }
      if (b > pageCount) {
        throw PdfToImagesError('This PDF has $pageCount pages');
      }
      for (int p = a; p <= b; p++) {
        if (!out.contains(p - 1)) {
          out.add(p - 1);
        }
      }
    }
    if (out.isEmpty) {
      throw const PdfToImagesError('Choose at least one page');
    }
    return out;
  }
}

class PdfToImages {
  const PdfToImages(this.rasterizer);
  final PdfRasterizer rasterizer;

  static Uint8List encode(img.Image im, PdfImageFormat f) =>
      f == PdfImageFormat.png ? img.encodePng(im, level: 6) : img.encodeJpg(im, quality: 90);

  /// One image per page in [range], named `stem-p<N>.ext`.
  Future<List<PdfImageOut>> perPage(Uint8List pdf, String stem,
      {String range = '', int dpi = 150, PdfImageFormat format = PdfImageFormat.jpg}) async {
    final List<int> pages = PageRange.parse(range, await rasterizer.pageCount(pdf));
    return <PdfImageOut>[
      for (final int i in pages) await _one(pdf, i, dpi, format, '$stem-p${i + 1}.${format.extension}'),
    ];
  }

  Future<PdfImageOut> _one(Uint8List pdf, int i, int dpi, PdfImageFormat format, String name) async {
    final img.Image im = await rasterizer.render(pdf, i, dpi);
    return PdfImageOut(name, encode(im, format), im.width, im.height);
  }

  /// Every page in [range], top to bottom, scaled to the widest page and to at
  /// most [longImageMaxHeight] tall, with a thin grey line between pages.
  Future<PdfImageOut> longImage(Uint8List pdf, String stem,
      {String range = '', int dpi = 150, PdfImageFormat format = PdfImageFormat.jpg}) async {
    final List<int> pages = PageRange.parse(range, await rasterizer.pageCount(pdf));
    final List<img.Image> ims = <img.Image>[for (final int i in pages) await rasterizer.render(pdf, i, dpi)];
    int width = ims.fold<int>(0, (int w, img.Image im) => math.max(w, im.width));
    const int gap = 4;
    int total = 0;
    for (final img.Image im in ims) {
      total += (im.height * width / im.width).round() + gap;
    }
    total -= gap;
    double scale = 1;
    if (total > longImageMaxHeight) {
      scale = longImageMaxHeight / total;
      width = math.max(1, (width * scale).floor());
    }
    final int gapPx = math.max(1, (gap * scale).round());
    final List<img.Image> sized = <img.Image>[
      for (final img.Image im in ims)
        im.width == width
            ? im
            : img.copyResize(im,
                width: width,
                height: math.max(1, (im.height * width / im.width).round()),
                interpolation: img.Interpolation.average),
    ];
    final int height = sized.fold<int>(0, (int h, img.Image im) => h + im.height) + gapPx * (sized.length - 1);
    final img.Image out = img.Image(width: width, height: height);
    img.fill(out, color: img.ColorRgb8(200, 200, 200));
    int y = 0;
    for (final img.Image im in sized) {
      img.compositeImage(out, im, dstX: 0, dstY: y);
      y += im.height + gapPx;
    }
    return PdfImageOut('$stem-long.${format.extension}', encode(out, format), width, height);
  }
}
