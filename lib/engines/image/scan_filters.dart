import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../convert/convert_registry.dart';

/// Feature 048 — Scan filters.
///
/// Black-and-white, colour boost, grayscale, shadow removal and glare
/// removal for scanned pages, each with adjustable contrast. Pure Dart on
/// the phone; filters always start from the page as captured, so changing
/// your mind never stacks one filter on another.

enum ScanFilter {
  original('Original'),
  blackWhite('Black and white'),
  colorBoost('Colour boost'),
  grayscale('Grayscale'),
  removeShadows('No shadows'),
  removeGlare('No glare');

  const ScanFilter(this.label);
  final String label;
}

class ScanFilterSettings {
  const ScanFilterSettings({this.filter = ScanFilter.original, this.contrast = 1.0});

  static const ScanFilterSettings none = ScanFilterSettings();

  final ScanFilter filter;

  /// 0.5 (flat) to 2.0 (punchy); 1.0 leaves contrast alone.
  final double contrast;

  static const double minContrast = 0.5;
  static const double maxContrast = 2.0;

  bool get isIdentity => filter == ScanFilter.original && (contrast - 1.0).abs() < 1e-6;

  @override
  bool operator ==(Object other) =>
      other is ScanFilterSettings && other.filter == filter && (other.contrast - contrast).abs() < 1e-6;

  @override
  int get hashCode => Object.hash(filter, (contrast * 1000).round());

  @override
  String toString() => '${filter.label}, contrast ${contrast.toStringAsFixed(2)}';
}

int _luma(num r, num g, num b) => ((r * 299 + g * 587 + b * 114) / 1000).round().clamp(0, 255);

int _c(num v) => v.round().clamp(0, 255);

/// Box-filtered local mean via an integral image; [radius] in pixels.
Float64List localMean(Uint8List plane, int w, int h, int radius) {
  final Float64List integral = Float64List((w + 1) * (h + 1));
  for (int y = 0; y < h; y++) {
    double row = 0;
    for (int x = 0; x < w; x++) {
      row += plane[y * w + x];
      integral[(y + 1) * (w + 1) + x + 1] = integral[y * (w + 1) + x + 1] + row;
    }
  }
  final Float64List out = Float64List(w * h);
  for (int y = 0; y < h; y++) {
    final int y0 = math.max(0, y - radius);
    final int y1 = math.min(h, y + radius + 1);
    for (int x = 0; x < w; x++) {
      final int x0 = math.max(0, x - radius);
      final int x1 = math.min(w, x + radius + 1);
      final double sum = integral[y1 * (w + 1) + x1] -
          integral[y0 * (w + 1) + x1] -
          integral[y1 * (w + 1) + x0] +
          integral[y0 * (w + 1) + x0];
      out[y * w + x] = sum / ((x1 - x0) * (y1 - y0));
    }
  }
  return out;
}

/// The paper's brightness under uneven light: the brightest values in
/// blocks of [block] pixels, smoothed. Ink is dark and small, so it drops out.
Float64List paperLevel(Uint8List plane, int w, int h, int block) {
  final int bw = (w + block - 1) ~/ block;
  final int bh = (h + block - 1) ~/ block;
  final Uint8List maxes = Uint8List(bw * bh);
  for (int y = 0; y < h; y++) {
    final int by = y ~/ block;
    for (int x = 0; x < w; x++) {
      final int i = by * bw + x ~/ block;
      final int v = plane[y * w + x];
      if (v > maxes[i]) {
        maxes[i] = v;
      }
    }
  }
  final Float64List smooth = localMean(maxes, bw, bh, 1);
  // Back to full size, bilinear between block centres.
  final Float64List out = Float64List(w * h);
  for (int y = 0; y < h; y++) {
    final double fy = ((y + 0.5) / block - 0.5).clamp(0.0, (bh - 1).toDouble());
    final int y0 = fy.floor();
    final int y1 = math.min(y0 + 1, bh - 1);
    final double ty = fy - y0;
    for (int x = 0; x < w; x++) {
      final double fx = ((x + 0.5) / block - 0.5).clamp(0.0, (bw - 1).toDouble());
      final int x0 = fx.floor();
      final int x1 = math.min(x0 + 1, bw - 1);
      final double tx = fx - x0;
      final double top = smooth[y0 * bw + x0] * (1 - tx) + smooth[y0 * bw + x1] * tx;
      final double bottom = smooth[y1 * bw + x0] * (1 - tx) + smooth[y1 * bw + x1] * tx;
      out[y * w + x] = top * (1 - ty) + bottom * ty;
    }
  }
  return out;
}

Uint8List lumaPlane(img.Image im) {
  final Uint8List p = Uint8List(im.width * im.height);
  int i = 0;
  for (int y = 0; y < im.height; y++) {
    for (int x = 0; x < im.width; x++) {
      final img.Pixel px = im.getPixel(x, y);
      p[i++] = _luma(px.r, px.g, px.b);
    }
  }
  return p;
}

/// Applies one filter and the contrast setting; returns a new image.
img.Image applyScanFilter(img.Image src, ScanFilterSettings s) {
  final int w = src.width;
  final int h = src.height;
  final img.Image out = img.Image(width: w, height: h);
  final double k = s.contrast.clamp(ScanFilterSettings.minContrast, ScanFilterSettings.maxContrast);
  int con(num v) => _c((v - 128) * k + 128);
  final int block = math.max(8, math.min(w, h) ~/ 12);

  switch (s.filter) {
    case ScanFilter.original: {
      for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
          final img.Pixel p = src.getPixel(x, y);
          out.setPixelRgb(x, y, con(p.r), con(p.g), con(p.b));
        }
      }
    }
    case ScanFilter.grayscale: {
      for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
          final img.Pixel p = src.getPixel(x, y);
          final int v = con(_luma(p.r, p.g, p.b));
          out.setPixelRgb(x, y, v, v, v);
        }
      }
    }
    case ScanFilter.colorBoost: {
      // More saturation around each pixel's own grey, then contrast.
      const double sat = 1.5;
      for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
          final img.Pixel p = src.getPixel(x, y);
          final int l = _luma(p.r, p.g, p.b);
          out.setPixelRgb(
            x,
            y,
            con(l + (p.r - l) * sat),
            con(l + (p.g - l) * sat),
            con(l + (p.b - l) * sat),
          );
        }
      }
    }
    case ScanFilter.removeShadows: {
      // Divide each channel by the paper level so the page reads evenly white.
      final Uint8List luma = lumaPlane(src);
      final Float64List paper = paperLevel(luma, w, h, block);
      for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
          final img.Pixel p = src.getPixel(x, y);
          final double gain = 255 / math.max(24.0, paper[y * w + x]);
          out.setPixelRgb(x, y, con(p.r * gain), con(p.g * gain), con(p.b * gain));
        }
      }
    }
    case ScanFilter.blackWhite: {
      // Shadow-free first, then a local threshold: ink is clearly darker
      // than its neighbourhood. Higher contrast keeps fainter strokes.
      final Uint8List luma = lumaPlane(src);
      final Float64List paper = paperLevel(luma, w, h, block);
      final Uint8List flat = Uint8List(w * h);
      for (int i = 0; i < flat.length; i++) {
        flat[i] = _c(luma[i] * 255 / math.max(24.0, paper[i]));
      }
      final Float64List mean = localMean(flat, w, h, math.max(4, block ~/ 2));
      final double bias = (0.18 / k).clamp(0.04, 0.4);
      for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
          final int i = y * w + x;
          final bool ink = flat[i] < mean[i] * (1 - bias) || flat[i] < 60;
          final int v = ink ? 0 : 255;
          out.setPixelRgb(x, y, v, v, v);
        }
      }
    }
    case ScanFilter.removeGlare: {
      // Glare: blown-out, colourless spots brighter than the paper around
      // them. Fill each from the paper colour of its block, then contrast.
      final Uint8List luma = lumaPlane(src);
      final int bw = (w + block - 1) ~/ block;
      final int bh = (h + block - 1) ~/ block;
      final Float64List sumR = Float64List(bw * bh);
      final Float64List sumG = Float64List(bw * bh);
      final Float64List sumB = Float64List(bw * bh);
      final Int32List count = Int32List(bw * bh);
      final Uint8List glare = Uint8List(w * h);
      double allR = 0, allG = 0, allB = 0;
      int all = 0;
      for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
          final img.Pixel p = src.getPixel(x, y);
          final int i = y * w + x;
          final num spread = math.max(p.r, math.max(p.g, p.b)) - math.min(p.r, math.min(p.g, p.b));
          if (luma[i] >= 245 && spread <= 18) {
            glare[i] = 1;
            continue;
          }
          final int b = (y ~/ block) * bw + x ~/ block;
          sumR[b] += p.r.toDouble();
          sumG[b] += p.g.toDouble();
          sumB[b] += p.b.toDouble();
          count[b]++;
          allR += p.r.toDouble();
          allG += p.g.toDouble();
          allB += p.b.toDouble();
          all++;
        }
      }
      for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
          final int i = y * w + x;
          if (glare[i] == 0) {
            final img.Pixel p = src.getPixel(x, y);
            out.setPixelRgb(x, y, con(p.r), con(p.g), con(p.b));
            continue;
          }
          // Nearest block (this one, then its ring) that has paper in it.
          final int bx = x ~/ block;
          final int by = y ~/ block;
          double r = 0, g = 0, bl = 0;
          int n = 0;
          for (int ring = 0; ring <= 2 && n == 0; ring++) {
            for (int yy = by - ring; yy <= by + ring; yy++) {
              for (int xx = bx - ring; xx <= bx + ring; xx++) {
                if (yy < 0 || xx < 0 || yy >= bh || xx >= bw) {
                  continue;
                }
                final int b = yy * bw + xx;
                r += sumR[b];
                g += sumG[b];
                bl += sumB[b];
                n += count[b];
              }
            }
          }
          if (n == 0) {
            r = all == 0 ? 235.0 : allR;
            g = all == 0 ? 235.0 : allG;
            bl = all == 0 ? 235.0 : allB;
            n = all == 0 ? 1 : all;
          }
          out.setPixelRgb(x, y, con(r / n), con(g / n), con(bl / n));
        }
      }
    }
  }
  return out;
}

/// The engine behind the filter row: JPEG in, filtered JPEG out.
class ScanFilterEngine {
  const ScanFilterEngine({this.jpegQuality = 88});

  final int jpegQuality;

  Uint8List apply(Uint8List jpeg, ScanFilterSettings s) {
    if (s.isIdentity) {
      return jpeg;
    }
    final img.Image? im = img.decodeImage(jpeg);
    if (im == null) {
      throw const ConvertException('The page could not be read.');
    }
    return img.encodeJpg(applyScanFilter(im, s), quality: jpegQuality);
  }
}
