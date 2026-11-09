import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'pdf_ocr.dart';
import 'pdf_to_images.dart';

/// Feature 015 — Remove blank pages and straighten.
///
/// Every page of a scanned PDF is drawn on the phone and measured: how much
/// ink it carries (blank pages carry almost none), how far its lines of text
/// lean (up to [maxSkewDegrees] either way), and — using on-device text
/// recognition — whether it reads better turned upside down. The person sees
/// the verdicts and chooses before anything is removed; the cleaned PDF is
/// written with the recognised words as an invisible text layer. Nothing is
/// uploaded.

const double maxSkewDegrees = 15;

/// Ink share (0..1) at or below which a page counts as blank by default.
const double defaultBlankInk = 0.004;

/// The slider's ends for the blank threshold.
const double minBlankInk = 0.0005;
const double maxBlankInk = 0.03;

/// One page after measuring.
class CleanPage {
  CleanPage({
    required this.index,
    required this.ink,
    required this.skewDegrees,
    required this.upsideDown,
    required this.jpeg,
    required this.pixelWidth,
    required this.pixelHeight,
    required this.thumbnail,
    required this.words,
  });

  /// 0-based page number in the source.
  final int index;

  /// Share of the page (inside a 5 % margin) that is ink, 0..1.
  final double ink;

  /// Measured lean in degrees (positive: lines rose to the right); the page
  /// has been turned back by this much.
  final double skewDegrees;

  /// True when the page was turned 180° because it read better that way.
  final bool upsideDown;

  /// The corrected page.
  final Uint8List jpeg;
  final int pixelWidth;
  final int pixelHeight;

  /// Small JPEG for the preview grid.
  final Uint8List thumbnail;

  /// Words recognised on the corrected page.
  final List<OcrWord> words;

  /// The person can override the verdict: null follows the threshold.
  bool? keepOverride;

  bool isBlank(double threshold) => ink <= threshold;

  bool keep(double threshold) => keepOverride ?? !isBlank(threshold);
}

class CleanScanOptions {
  const CleanScanOptions({
    this.deskew = true,
    this.autoRotate = true,
    this.script = OcrScript.latin,
    this.dpi = 150,
  });

  final bool deskew;
  final bool autoRotate;
  final OcrScript script;
  final int dpi;
}

class CleanScanResult {
  const CleanScanResult(this.pdf, this.kept, this.removed, this.straightened, this.turned);

  final Uint8List pdf;
  final int kept;
  final int removed;
  final int straightened;
  final int turned;
}

class PdfCleanScan {
  const PdfCleanScan({required this.rasterizer, required this.recognizer, this.jpegQuality = 82});

  final PdfRasterizer rasterizer;
  final TextRecognizerEngine recognizer;
  final int jpegQuality;

  /// Measures and corrects every page. Nothing is removed yet.
  Future<List<CleanPage>> analyze(
    Uint8List pdf,
    CleanScanOptions o, {
    void Function(int done, int total)? progress,
  }) async {
    final int count = await rasterizer.pageCount(pdf);
    if (count == 0) {
      throw const PdfOcrError('This PDF has no pages');
    }
    final List<CleanPage> out = <CleanPage>[];
    for (int i = 0; i < count; i++) {
      final img.Image page = await rasterizer.render(pdf, i, o.dpi);
      out.add(await _measure(i, page, o));
      progress?.call(i + 1, count);
    }
    return out;
  }

  Future<CleanPage> _measure(int index, img.Image page, CleanScanOptions o) async {
    final double ink = inkShare(page);
    double skew = 0;
    img.Image fixed = page;
    // A blank page has no lines to measure and no words to read.
    final bool hasInk = ink > minBlankInk;
    if (o.deskew && hasInk) {
      skew = estimateSkew(page);
      if (skew.abs() >= 0.2) {
        fixed = rotateOnWhite(page, skew);
      } else {
        skew = 0;
      }
    }
    bool turned = false;
    List<OcrWord> words = const <OcrWord>[];
    if (hasInk) {
      words = await _read(fixed, o.script);
      if (o.autoRotate) {
        final img.Image flipped = img.copyRotate(fixed, angle: 180);
        final List<OcrWord> flippedWords = await _read(flipped, o.script);
        if (readsBetterFlipped(words, flippedWords)) {
          fixed = flipped;
          words = flippedWords;
          turned = true;
        }
      }
    }
    final img.Image thumb = img.copyResize(fixed,
        width: math.min(fixed.width, 160), interpolation: img.Interpolation.average);
    return CleanPage(
      index: index,
      ink: ink,
      skewDegrees: skew,
      upsideDown: turned,
      jpeg: Uint8List.fromList(img.encodeJpg(fixed, quality: jpegQuality)),
      pixelWidth: fixed.width,
      pixelHeight: fixed.height,
      thumbnail: Uint8List.fromList(img.encodeJpg(thumb, quality: 70)),
      words: words,
    );
  }

  Future<List<OcrWord>> _read(img.Image im, OcrScript script) async {
    try {
      final Uint8List jpeg = Uint8List.fromList(img.encodeJpg(im, quality: jpegQuality));
      final List<OcrWord> w = await recognizer.recognize(im, jpeg, script);
      return w.where((OcrWord x) => x.text.trim().isNotEmpty).toList();
    } catch (_) {
      return const <OcrWord>[];
    }
  }

  /// Writes the kept pages, in order, as a searchable PDF.
  CleanScanResult build(List<CleanPage> pages, double threshold, {int dpi = 150}) {
    final List<CleanPage> kept = pages.where((CleanPage p) => p.keep(threshold)).toList();
    if (kept.isEmpty) {
      throw const PdfOcrError('Every page would be removed; keep at least one');
    }
    final Uint8List pdf = writeSearchablePdf(<OcrPage>[
      for (final CleanPage p in kept)
        OcrPage(
          jpeg: p.jpeg,
          pixelWidth: p.pixelWidth,
          pixelHeight: p.pixelHeight,
          widthPt: p.pixelWidth * 72 / dpi,
          heightPt: p.pixelHeight * 72 / dpi,
          words: p.words,
        ),
    ]);
    return CleanScanResult(
      pdf,
      kept.length,
      pages.length - kept.length,
      kept.where((CleanPage p) => p.skewDegrees != 0).length,
      kept.where((CleanPage p) => p.upsideDown).length,
    );
  }
}

/// Luminance 0..255 of one pixel.
int _lum(img.Pixel p) => ((p.r * 299 + p.g * 587 + p.b * 114) / 1000).round();

/// A copy at most [maxSide] pixels on the long side, for measuring.
img.Image _small(img.Image im, int maxSide) {
  final int longSide = math.max(im.width, im.height);
  if (longSide <= maxSide) {
    return im;
  }
  return im.width >= im.height
      ? img.copyResize(im, width: maxSide, interpolation: img.Interpolation.average)
      : img.copyResize(im, height: maxSide, interpolation: img.Interpolation.average);
}

/// The paper's brightness: the 90th percentile of luminance, so a grey scan
/// of white paper still counts as paper.
int _paperLevel(img.Image im) {
  final List<int> hist = List<int>.filled(256, 0);
  int n = 0;
  for (final img.Pixel p in im) {
    hist[_lum(p)]++;
    n++;
  }
  int seen = 0;
  for (int v = 0; v < 256; v++) {
    seen += hist[v];
    if (seen >= n * 0.9) {
      return v;
    }
  }
  return 255;
}

/// Share of pixels inside a 5 % margin that are clearly darker than the
/// paper. Scanner shadows at the edges and faint paper grain do not count.
double inkShare(img.Image page) {
  final img.Image im = _small(page, 600);
  final int paper = _paperLevel(im);
  final int cut = paper - math.max(60, paper ~/ 4);
  final int mx = (im.width * 0.05).round();
  final int my = (im.height * 0.05).round();
  int ink = 0;
  int total = 0;
  for (int y = my; y < im.height - my; y++) {
    for (int x = mx; x < im.width - mx; x++) {
      total++;
      if (_lum(im.getPixel(x, y)) < cut) {
        ink++;
      }
    }
  }
  return total == 0 ? 0 : ink / total;
}

/// The lean of the text lines in degrees (positive: lines rise to the right
/// on screen, i.e. the page is turned anticlockwise), within ±[maxSkewDegrees].
///
/// Projection profiles: dark pixels are projected onto rows at each trial
/// angle, and the angle at which rows are most uneven (lines line up with
/// rows, gaps stay empty) wins. Coarse 1° steps, then 0.1° around the best.
double estimateSkew(img.Image page) {
  final img.Image im = _small(page, 800);
  final int paper = _paperLevel(im);
  final int cut = paper - math.max(60, paper ~/ 4);
  final List<double> xs = <double>[];
  final List<double> ys = <double>[];
  final double cx = im.width / 2;
  final double cy = im.height / 2;
  for (int y = 0; y < im.height; y++) {
    for (int x = 0; x < im.width; x++) {
      if (_lum(im.getPixel(x, y)) < cut) {
        xs.add(x - cx);
        ys.add(y - cy);
      }
    }
  }
  if (xs.length < 20) {
    return 0;
  }
  final int rows = (math.sqrt(im.width * im.width + im.height * im.height)).ceil() + 2;
  final double half = rows / 2;
  double score(double deg) {
    final double a = deg * math.pi / 180;
    final double s = math.sin(a);
    final double c = math.cos(a);
    final List<int> bins = List<int>.filled(rows, 0);
    for (int i = 0; i < xs.length; i++) {
      // Row of the point once the page is turned back by [deg].
      final int r = (ys[i] * c + xs[i] * s + half).floor();
      if (r >= 0 && r < rows) {
        bins[r]++;
      }
    }
    double sum = 0;
    for (int r = 1; r < rows; r++) {
      final double d = (bins[r] - bins[r - 1]).toDouble();
      sum += d * d;
    }
    return sum;
  }

  double best = 0;
  double bestScore = score(0);
  for (double d = -maxSkewDegrees; d <= maxSkewDegrees; d += 1) {
    final double sc = score(d);
    if (sc > bestScore) {
      bestScore = sc;
      best = d;
    }
  }
  final double centre = best;
  for (double d = centre - 1; d <= centre + 1 + 1e-9; d += 0.1) {
    if (d.abs() > maxSkewDegrees) {
      continue;
    }
    final double sc = score(d);
    if (sc > bestScore) {
      bestScore = sc;
      best = d;
    }
  }
  return double.parse(best.toStringAsFixed(1));
}

/// Turns [src] by [degrees] (positive: clockwise on screen) about its centre,
/// keeping its size and filling uncovered corners with white.
img.Image rotateOnWhite(img.Image src, double degrees) {
  final img.Image out = img.Image(width: src.width, height: src.height);
  final double a = degrees * math.pi / 180;
  final double s = math.sin(a);
  final double c = math.cos(a);
  final double cx = (src.width - 1) / 2;
  final double cy = (src.height - 1) / 2;
  for (int y = 0; y < out.height; y++) {
    final double dy = y - cy;
    for (int x = 0; x < out.width; x++) {
      final double dx = x - cx;
      // Inverse map: where in the source this output pixel comes from.
      final int sx = (dx * c + dy * s + cx).round();
      final int sy = (-dx * s + dy * c + cy).round();
      if (sx >= 0 && sy >= 0 && sx < src.width && sy < src.height) {
        final img.Pixel p = src.getPixel(sx, sy);
        out.setPixelRgb(x, y, p.r, p.g, p.b);
      } else {
        out.setPixelRgb(x, y, 255, 255, 255);
      }
    }
  }
  return out;
}

/// Words that look like real words: two or more letters or digits.
int _goodWords(List<OcrWord> words) =>
    words.where((OcrWord w) => RegExp(r'[\p{L}\p{N}]{2,}', unicode: true).hasMatch(w.text)).length;

/// Upside-down text reads as little or nothing; the right way up reads as
/// many words. Turn the page only when the flipped reading is clearly better.
bool readsBetterFlipped(List<OcrWord> upright, List<OcrWord> flipped) {
  final int a = _goodWords(upright);
  final int b = _goodWords(flipped);
  return b >= 3 && b > a * 1.5;
}
