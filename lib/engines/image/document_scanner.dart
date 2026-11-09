import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../convert/convert_registry.dart';
import '../pdf/images_to_pdf.dart';

/// Feature 047 — Document scanner.
///
/// Pure-Dart engine: finds the page in a camera frame, waits for the phone
/// to be steady, flattens the page with a perspective fix and keeps a
/// multi-page session that saves as one PDF or a set of JPGs. Everything
/// runs on the phone; nothing is uploaded.

/// A point in image pixels.
class ScanPoint {
  const ScanPoint(this.x, this.y);
  final double x;
  final double y;

  double distanceTo(ScanPoint o) => math.sqrt((x - o.x) * (x - o.x) + (y - o.y) * (y - o.y));

  ScanPoint scale(double sx, double sy) => ScanPoint(x * sx, y * sy);

  @override
  String toString() => '(${x.toStringAsFixed(1)}, ${y.toStringAsFixed(1)})';
}

/// The four page corners, clockwise from top left.
class ScanQuad {
  const ScanQuad(this.topLeft, this.topRight, this.bottomRight, this.bottomLeft);

  final ScanPoint topLeft;
  final ScanPoint topRight;
  final ScanPoint bottomRight;
  final ScanPoint bottomLeft;

  List<ScanPoint> get corners => <ScanPoint>[topLeft, topRight, bottomRight, bottomLeft];

  ScanQuad scale(double sx, double sy) => ScanQuad(
        topLeft.scale(sx, sy),
        topRight.scale(sx, sy),
        bottomRight.scale(sx, sy),
        bottomLeft.scale(sx, sy),
      );

  /// Largest corner movement between two quads.
  double maxShift(ScanQuad o) {
    double m = 0;
    for (int i = 0; i < 4; i++) {
      m = math.max(m, corners[i].distanceTo(o.corners[i]));
    }
    return m;
  }

  /// Shoelace area in square pixels.
  double get area {
    final List<ScanPoint> c = corners;
    double s = 0;
    for (int i = 0; i < 4; i++) {
      final ScanPoint a = c[i];
      final ScanPoint b = c[(i + 1) % 4];
      s += a.x * b.y - b.x * a.y;
    }
    return s.abs() / 2;
  }

  @override
  String toString() => 'ScanQuad($topLeft, $topRight, $bottomRight, $bottomLeft)';
}

/// One camera frame's brightness plane (the Y plane of YUV), row-packed.
class ScanFrame {
  const ScanFrame({required this.luma, required this.width, required this.height});
  final Uint8List luma;
  final int width;
  final int height;
}

/// Finds a sheet of paper: the largest bright region, its four extreme
/// corners. Works on a grid at most [gridWidth] wide, so a frame costs a few
/// milliseconds and keeps up with a 30 fps preview.
class EdgeDetector {
  const EdgeDetector({this.gridWidth = 160, this.minAreaFraction = 0.12});

  final int gridWidth;

  /// The page must cover at least this share of the frame.
  final double minAreaFraction;

  ScanQuad? detect(ScanFrame f) {
    if (f.width < 8 || f.height < 8 || f.luma.length < f.width * f.height) {
      return null;
    }
    final int step = math.max(1, (f.width / gridWidth).ceil());
    final int gw = f.width ~/ step;
    final int gh = f.height ~/ step;
    final Uint8List g = Uint8List(gw * gh);
    final List<int> hist = List<int>.filled(256, 0);
    for (int y = 0; y < gh; y++) {
      final int row = y * step * f.width;
      for (int x = 0; x < gw; x++) {
        final int v = f.luma[row + x * step];
        g[y * gw + x] = v;
        hist[v]++;
      }
    }
    final int t = otsu(hist, gw * gh);
    // Too little contrast: nothing to find.
    int lo = 0;
    int hi = 0;
    int nLo = 0;
    int nHi = 0;
    for (int v = 0; v < 256; v++) {
      if (v <= t) {
        lo += v * hist[v];
        nLo += hist[v];
      } else {
        hi += v * hist[v];
        nHi += hist[v];
      }
    }
    if (nLo == 0 || nHi == 0 || hi / nHi - lo / nLo < 25) {
      return null;
    }

    // Largest 4-connected bright region.
    final Int32List label = Int32List(gw * gh);
    final Int32List queue = Int32List(gw * gh);
    int best = 0;
    int bestLabel = 0;
    int next = 0;
    for (int i = 0; i < g.length; i++) {
      if (g[i] <= t || label[i] != 0) {
        continue;
      }
      next++;
      int head = 0;
      int tail = 0;
      queue[tail++] = i;
      label[i] = next;
      while (head < tail) {
        final int p = queue[head++];
        final int px = p % gw;
        final int py = p ~/ gw;
        if (px > 0) {
          final int q = p - 1;
          if (label[q] == 0 && g[q] > t) {
            label[q] = next;
            queue[tail++] = q;
          }
        }
        if (px < gw - 1) {
          final int q = p + 1;
          if (label[q] == 0 && g[q] > t) {
            label[q] = next;
            queue[tail++] = q;
          }
        }
        if (py > 0) {
          final int q = p - gw;
          if (label[q] == 0 && g[q] > t) {
            label[q] = next;
            queue[tail++] = q;
          }
        }
        if (py < gh - 1) {
          final int q = p + gw;
          if (label[q] == 0 && g[q] > t) {
            label[q] = next;
            queue[tail++] = q;
          }
        }
      }
      if (tail > best) {
        best = tail;
        bestLabel = next;
      }
    }
    if (best < minAreaFraction * gw * gh) {
      return null;
    }

    // Extreme points: top left has the smallest x + y, and so on.
    int tl = -1, tr = -1, br = -1, bl = -1;
    int minSum = 1 << 30, maxSum = -(1 << 30), minDiff = 1 << 30, maxDiff = -(1 << 30);
    for (int i = 0; i < label.length; i++) {
      if (label[i] != bestLabel) {
        continue;
      }
      final int x = i % gw;
      final int y = i ~/ gw;
      final int s = x + y;
      final int d = x - y;
      if (s < minSum) {
        minSum = s;
        tl = i;
      }
      if (s > maxSum) {
        maxSum = s;
        br = i;
      }
      if (d > maxDiff) {
        maxDiff = d;
        tr = i;
      }
      if (d < minDiff) {
        minDiff = d;
        bl = i;
      }
    }
    ScanPoint at(int i, double dx, double dy) =>
        ScanPoint(((i % gw) + dx) * step, ((i ~/ gw) + dy) * step);
    final ScanQuad quad = ScanQuad(at(tl, 0, 0), at(tr, 1, 0), at(br, 1, 1), at(bl, 0, 1));
    if (quad.area < minAreaFraction * f.width * f.height) {
      return null;
    }
    return quad;
  }

  /// Otsu's threshold on a 256-bin histogram.
  static int otsu(List<int> hist, int total) {
    double sum = 0;
    for (int i = 0; i < 256; i++) {
      sum += i * hist[i];
    }
    double sumB = 0;
    int wB = 0;
    double bestVar = -1;
    int best = 127;
    for (int t = 0; t < 256; t++) {
      wB += hist[t];
      if (wB == 0) {
        continue;
      }
      final int wF = total - wB;
      if (wF == 0) {
        break;
      }
      sumB += t * hist[t];
      final double mB = sumB / wB;
      final double mF = (sum - sumB) / wF;
      final double between = wB * wF * (mB - mF) * (mB - mF);
      if (between > bestVar) {
        bestVar = between;
        best = t;
      }
    }
    return best;
  }
}

/// Auto-capture: fires once when the page has stayed put for [steadyFrames]
/// frames (about half a second at 30 fps), then waits for the page to move
/// or leave before it can fire again.
class SteadyDetector {
  SteadyDetector({this.steadyFrames = 15, this.tolerance = 0.02});

  final int steadyFrames;

  /// Allowed corner drift, as a share of the frame diagonal.
  final double tolerance;

  ScanQuad? _anchor;
  int _count = 0;
  bool _fired = false;

  /// 0..1, how close the current hold is to a capture.
  double get progress => _fired ? 1 : math.min(1, _count / steadyFrames);

  void reset() {
    _anchor = null;
    _count = 0;
    _fired = false;
  }

  /// Feed one frame's result; true exactly when a capture should happen.
  bool feed(ScanQuad? quad, int frameWidth, int frameHeight) {
    if (quad == null) {
      reset();
      return false;
    }
    final double limit = tolerance * math.sqrt(frameWidth * frameWidth + frameHeight * frameHeight);
    final ScanQuad? anchor = _anchor;
    if (anchor == null || anchor.maxShift(quad) > limit) {
      _anchor = quad;
      _count = 1;
      _fired = false;
      return false;
    }
    _count++;
    if (!_fired && _count >= steadyFrames) {
      _fired = true;
      return true;
    }
    return false;
  }
}

/// Solves the 3x3 projective map that takes the output rectangle to the quad.
class Homography {
  Homography._(this.h);

  /// Row-major h11..h32, with h33 = 1.
  final List<double> h;

  /// Maps (0,0),(w,0),(w,h),(0,h) onto the quad's corners.
  factory Homography.rectToQuad(double w, double hgt, ScanQuad q) {
    final List<ScanPoint> src = <ScanPoint>[
      const ScanPoint(0, 0),
      ScanPoint(w, 0),
      ScanPoint(w, hgt),
      ScanPoint(0, hgt),
    ];
    final List<ScanPoint> dst = q.corners;
    final List<List<double>> a = <List<double>>[];
    for (int i = 0; i < 4; i++) {
      final double x = src[i].x, y = src[i].y, u = dst[i].x, v = dst[i].y;
      a.add(<double>[x, y, 1, 0, 0, 0, -u * x, -u * y, u]);
      a.add(<double>[0, 0, 0, x, y, 1, -v * x, -v * y, v]);
    }
    return Homography._(_solve(a));
  }

  ScanPoint map(double x, double y) {
    final double d = h[6] * x + h[7] * y + 1;
    return ScanPoint((h[0] * x + h[1] * y + h[2]) / d, (h[3] * x + h[4] * y + h[5]) / d);
  }

  /// Gaussian elimination with partial pivoting on an 8x9 augmented matrix.
  static List<double> _solve(List<List<double>> a) {
    const int n = 8;
    for (int c = 0; c < n; c++) {
      int p = c;
      for (int r = c + 1; r < n; r++) {
        if (a[r][c].abs() > a[p][c].abs()) {
          p = r;
        }
      }
      if (a[p][c].abs() < 1e-12) {
        throw const ConvertException('The page corners do not make a page.');
      }
      final List<double> tmp = a[c];
      a[c] = a[p];
      a[p] = tmp;
      for (int r = 0; r < n; r++) {
        if (r == c) {
          continue;
        }
        final double f = a[r][c] / a[c][c];
        if (f == 0) {
          continue;
        }
        for (int k = c; k <= n; k++) {
          a[r][k] -= f * a[c][k];
        }
      }
    }
    return <double>[for (int i = 0; i < n; i++) a[i][n] / a[i][i]];
  }
}

/// Grayscale plane of a decoded image, for detection.
ScanFrame frameFromImage(img.Image im) {
  final Uint8List luma = Uint8List(im.width * im.height);
  int i = 0;
  for (int y = 0; y < im.height; y++) {
    for (int x = 0; x < im.width; x++) {
      final img.Pixel p = im.getPixel(x, y);
      luma[i++] = ((p.r * 299 + p.g * 587 + p.b * 114) ~/ 1000).clamp(0, 255);
    }
  }
  return ScanFrame(luma: luma, width: im.width, height: im.height);
}

/// Flattens the quad into an upright rectangle, bilinear sampled.
img.Image perspectiveFix(img.Image src, ScanQuad q) {
  final double top = q.topLeft.distanceTo(q.topRight);
  final double bottom = q.bottomLeft.distanceTo(q.bottomRight);
  final double left = q.topLeft.distanceTo(q.bottomLeft);
  final double right = q.topRight.distanceTo(q.bottomRight);
  final int w = math.max(1, ((top + bottom) / 2).round());
  final int h = math.max(1, ((left + right) / 2).round());
  final Homography hm = Homography.rectToQuad(w.toDouble(), h.toDouble(), q);
  final img.Image out = img.Image(width: w, height: h);
  final int maxX = src.width - 1;
  final int maxY = src.height - 1;
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      final ScanPoint s = hm.map(x + 0.5, y + 0.5);
      final double sx = (s.x - 0.5).clamp(0.0, maxX.toDouble());
      final double sy = (s.y - 0.5).clamp(0.0, maxY.toDouble());
      final int x0 = sx.floor();
      final int y0 = sy.floor();
      final int x1 = math.min(x0 + 1, maxX);
      final int y1 = math.min(y0 + 1, maxY);
      final double fx = sx - x0;
      final double fy = sy - y0;
      final img.Pixel a = src.getPixel(x0, y0);
      final img.Pixel b = src.getPixel(x1, y0);
      final img.Pixel c = src.getPixel(x0, y1);
      final img.Pixel d = src.getPixel(x1, y1);
      double mix(num pa, num pb, num pc, num pd) =>
          (pa * (1 - fx) + pb * fx) * (1 - fy) + (pc * (1 - fx) + pd * fx) * fy;
      out.setPixelRgb(
        x,
        y,
        mix(a.r, b.r, c.r, d.r).round(),
        mix(a.g, b.g, c.g, d.g).round(),
        mix(a.b, b.b, c.b, d.b).round(),
      );
    }
  }
  return out;
}

/// One scanned page, already flattened, as JPEG.
class ScanPage {
  ScanPage({required this.jpeg, required this.width, required this.height, required this.foundEdges});

  final Uint8List jpeg;
  final int width;
  final int height;

  /// False when no page edge was found and the whole photo was kept.
  final bool foundEdges;
}

/// Turns a camera photo into a flattened page.
class DocumentScanner {
  const DocumentScanner({this.detector = const EdgeDetector(), this.maxSide = 2400, this.jpegQuality = 88});

  final EdgeDetector detector;

  /// Photos are scaled so the long side is at most this many pixels.
  final int maxSide;
  final int jpegQuality;

  /// Decodes, finds the page (or uses [quad], given in photo pixels), fixes
  /// perspective and returns the page.
  ScanPage process(Uint8List photo, {ScanQuad? quad}) {
    final img.Image? decoded = img.decodeImage(photo);
    if (decoded == null) {
      throw const ConvertException('The photo could not be read.');
    }
    img.Image im = img.bakeOrientation(decoded);
    double scale = 1;
    final int longSide = math.max(im.width, im.height);
    if (longSide > maxSide) {
      scale = maxSide / longSide;
      im = img.copyResize(im, width: (im.width * scale).round(), height: (im.height * scale).round());
    }
    ScanQuad? q = quad?.scale(scale, scale);
    if (q == null) {
      // Detect on a small copy, then scale the corners back up.
      final int dw = math.min(320, im.width);
      final img.Image small = dw == im.width ? im : img.copyResize(im, width: dw);
      final ScanQuad? found = detector.detect(frameFromImage(small));
      q = found?.scale(im.width / small.width, im.height / small.height);
    }
    final img.Image page = q == null ? im : perspectiveFix(im, q);
    return ScanPage(
      jpeg: img.encodeJpg(page, quality: jpegQuality),
      width: page.width,
      height: page.height,
      foundEdges: q != null,
    );
  }
}

/// Saved output: one PDF or one JPG per page.
enum ScanFormat {
  pdf('PDF'),
  jpg('JPG');

  const ScanFormat(this.label);
  final String label;
}

/// The pages of one scanning session, with retake, reorder and undo.
class ScanSession {
  final List<ScanPage> _pages = <ScanPage>[];
  final List<List<ScanPage>> _undo = <List<ScanPage>>[];

  List<ScanPage> get pages => List<ScanPage>.unmodifiable(_pages);
  int get length => _pages.length;
  bool get isEmpty => _pages.isEmpty;
  bool get canUndo => _undo.isNotEmpty;

  void _snapshot() => _undo.add(List<ScanPage>.of(_pages));

  void add(ScanPage p) {
    _snapshot();
    _pages.add(p);
  }

  void retake(int index, ScanPage p) {
    RangeError.checkValidIndex(index, _pages);
    _snapshot();
    _pages[index] = p;
  }

  void remove(int index) {
    RangeError.checkValidIndex(index, _pages);
    _snapshot();
    _pages.removeAt(index);
  }

  /// ReorderableListView semantics: [to] counts the moved item still in place.
  void move(int from, int to) {
    RangeError.checkValidIndex(from, _pages);
    final int target = to > from ? to - 1 : to;
    if (target == from) {
      return;
    }
    _snapshot();
    final ScanPage p = _pages.removeAt(from);
    _pages.insert(target.clamp(0, _pages.length), p);
  }

  bool undo() {
    if (_undo.isEmpty) {
      return false;
    }
    _pages
      ..clear()
      ..addAll(_undo.removeLast());
    return true;
  }

  void clear() {
    _pages.clear();
    _undo.clear();
  }

  /// One PDF, a page per scan, each page sized to the scan.
  Future<Uint8List> toPdf({ImagesToPdf? engine}) {
    if (_pages.isEmpty) {
      throw const ConvertException('Scan a page first.');
    }
    return (engine ?? ImagesToPdf()).build(
      <Uint8List>[for (final ScanPage p in _pages) p.jpeg],
      const ImagesToPdfOptions(pageSize: PdfPageSize.a4, marginPt: 0),
    );
  }

  /// The JPGs in page order.
  List<Uint8List> toJpgs() => <Uint8List>[for (final ScanPage p in _pages) p.jpeg];
}
