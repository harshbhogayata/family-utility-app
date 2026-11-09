import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import 'exact_kb.dart';

/// Feature 043 — Passport photo maker.
///
/// Pure Dart. The face box comes from on-device face detection (ML Kit,
/// behind [FaceFinder] in the tool), the engine turns it into a crop that
/// puts the head at the size the country asks for, fills anything outside
/// the original with a plain colour, and lays copies out on a print sheet.

const int passportDpi = 300;

@immutable
class PassportSpec {
  const PassportSpec({
    required this.id,
    required this.label,
    required this.widthMm,
    required this.heightMm,
    required this.headMin,
    required this.headMax,
  });

  /// A size the person typed. Head share of the height: the common 70–80%.
  factory PassportSpec.custom(double widthMm, double heightMm) => PassportSpec(
        id: 'custom',
        label: 'Custom ${_mm(widthMm)} × ${_mm(heightMm)} mm',
        widthMm: widthMm,
        heightMm: heightMm,
        headMin: 0.70,
        headMax: 0.80,
      );

  final String id;
  final String label;
  final double widthMm;
  final double heightMm;

  /// Chin to crown as a share of the photo height.
  final double headMin;
  final double headMax;

  int get widthPx => mmToPx(widthMm, dpi: passportDpi);
  int get heightPx => mmToPx(heightMm, dpi: passportDpi);
  double get headTarget => (headMin + headMax) / 2;

  static String _mm(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
}

/// Presets from the issuing authorities' published photo rules.
const List<PassportSpec> passportPresets = <PassportSpec>[
  // India: 35 × 45 mm, face about 70–80% of the frame.
  PassportSpec(id: 'in', label: 'India 35 × 45 mm', widthMm: 35, heightMm: 45, headMin: 0.70, headMax: 0.80),
  // US: 2 × 2 in, head 1 to 1⅜ in of the 2 in height.
  PassportSpec(id: 'us', label: 'US 2 × 2 in', widthMm: 50.8, heightMm: 50.8, headMin: 0.50, headMax: 0.69),
  // UK: 35 × 45 mm, head 29–34 mm.
  PassportSpec(id: 'uk', label: 'UK 35 × 45 mm', widthMm: 35, heightMm: 45, headMin: 29 / 45, headMax: 34 / 45),
  // Schengen (ICAO): 35 × 45 mm, head 32–36 mm.
  PassportSpec(id: 'schengen', label: 'Schengen 35 × 45 mm', widthMm: 35, heightMm: 45, headMin: 32 / 45, headMax: 36 / 45),
];

/// A face as the detector reports it, in pixels of the upright source.
/// The box runs roughly from the eyebrows to the chin.
@immutable
class FaceBox {
  const FaceBox(this.left, this.top, this.width, this.height);
  final double left;
  final double top;
  final double width;
  final double height;

  double get centerX => left + width / 2;
  double get bottom => top + height;
}

/// How much taller the whole head (crown to chin) is than the detector box.
const double headPerFaceBox = 1.45;

/// A crop in source pixels; may run past the edges (filled with background).
@immutable
class PassportCrop {
  const PassportCrop(this.left, this.top, this.width, this.height, {required this.centred});
  final double left;
  final double top;
  final double width;
  final double height;

  /// True when a face set the crop; false for a plain centre crop.
  final bool centred;
}

enum SheetPaper {
  r4x6('4 × 6 in', 101.6, 152.4),
  a4('A4', 210, 297);

  const SheetPaper(this.label, this.widthMm, this.heightMm);
  final String label;
  final double widthMm;
  final double heightMm;
}

@immutable
class PassportSheet {
  const PassportSheet(this.image, this.count, this.columns, this.rows);
  final img.Image image;
  final int count;
  final int columns;
  final int rows;
}

class PassportError implements Exception {
  const PassportError(this.message);
  final String message;
  @override
  String toString() => message;
}

abstract final class PassportPhoto {
  /// Where to cut so the head fills [PassportSpec.headTarget] of the height,
  /// centred side to side, with the crown a little below the top edge.
  static PassportCrop crop(int srcW, int srcH, PassportSpec spec, FaceBox? face) {
    final double aspect = spec.widthMm / spec.heightMm;
    if (face == null || face.height <= 0) {
      double h = srcH.toDouble();
      double w = h * aspect;
      if (w > srcW) {
        w = srcW.toDouble();
        h = w / aspect;
      }
      return PassportCrop((srcW - w) / 2, (srcH - h) / 2, w, h, centred: false);
    }
    final double head = face.height * headPerFaceBox;
    final double crown = face.bottom - head;
    final double h = head / spec.headTarget;
    final double w = h * aspect;
    // Split the space left above and below the head 45 : 55.
    final double top = crown - (h - head) * 0.45;
    return PassportCrop(face.centerX - w / 2, top, w, h, centred: true);
  }

  /// The finished photo at the spec's exact pixel size (300 dpi).
  static img.Image render(Uint8List input, PassportSpec spec, FaceBox? face, {int background = 0xFFFFFF}) {
    final img.Image? decoded = img.decodeImage(input);
    if (decoded == null) {
      throw const PassportError('This file is not a picture the app can read');
    }
    final img.Image src = img.bakeOrientation(decoded);
    return renderImage(src, spec, face, background: background);
  }

  static img.Image renderImage(img.Image src, PassportSpec spec, FaceBox? face, {int background = 0xFFFFFF}) {
    if (spec.widthMm < 10 || spec.heightMm < 10 || spec.widthMm > 100 || spec.heightMm > 100) {
      throw const PassportError('Choose a size between 10 and 100 mm');
    }
    final PassportCrop c = crop(src.width, src.height, spec, face);
    final int outW = spec.widthPx;
    final int outH = spec.heightPx;
    final img.ColorRgb8 bg = img.ColorRgb8((background >> 16) & 255, (background >> 8) & 255, background & 255);
    final img.Image out = img.Image(width: outW, height: outH);
    img.fill(out, color: bg);
    // Part of the crop that lies inside the source.
    final int sx0 = math.max(0, c.left.floor());
    final int sy0 = math.max(0, c.top.floor());
    final int sx1 = math.min(src.width, (c.left + c.width).ceil());
    final int sy1 = math.min(src.height, (c.top + c.height).ceil());
    if (sx1 <= sx0 || sy1 <= sy0) {
      return out;
    }
    final double scale = outW / c.width;
    final int dx = ((sx0 - c.left) * scale).round();
    final int dy = ((sy0 - c.top) * scale).round();
    final int dw = math.max(1, ((sx1 - sx0) * scale).round());
    final int dh = math.max(1, ((sy1 - sy0) * scale).round());
    final img.Image part = img.copyResize(
      img.copyCrop(src, x: sx0, y: sy0, width: sx1 - sx0, height: sy1 - sy0),
      width: dw,
      height: dh,
      interpolation: img.Interpolation.average,
    );
    img.compositeImage(out, part, dstX: dx, dstY: dy);
    return out;
  }

  /// One copy as a JPG at most [kb] KB, at the exact pixel size.
  static ExactKbResult single(img.Image photo, int kb) {
    final Uint8List png = img.encodePng(photo, level: 1);
    try {
      return ExactKb.fit(png, kb, width: photo.width, height: photo.height);
    } on ExactKbError catch (e) {
      throw PassportError(e.message);
    }
  }

  /// Copies of [photo] on [paper] at 300 dpi with grey cut lines: 2 mm
  /// margins and 1 mm gaps, or edge to edge when that is the only way to fit
  /// the copies asked for. Turns the paper if that fits more. When even that
  /// is short, [PassportSheet.count] says how many fitted.
  static PassportSheet sheet(img.Image photo, SheetPaper paper, int copies) {
    if (copies < 1) {
      throw const PassportError('Choose at least one copy');
    }
    final int pw = mmToPx(paper.widthMm, dpi: passportDpi);
    final int ph = mmToPx(paper.heightMm, dpi: passportDpi);
    _Layout? best;
    for (final (int margin, int gap) in <(int, int)>[
      (mmToPx(2, dpi: passportDpi), mmToPx(1, dpi: passportDpi)),
      (0, 0),
    ]) {
      for (final bool turn in <bool>[false, true]) {
        final _Layout l = _Layout(turn ? ph : pw, turn ? pw : ph, photo.width, photo.height, margin, gap);
        if (best == null || l.capacity > best.capacity) {
          best = l;
        }
      }
      if (best!.capacity >= copies) {
        break;
      }
    }
    final _Layout l = best!;
    if (l.capacity == 0) {
      throw PassportError('This photo is too big for ${paper.label}');
    }
    final int count = math.min(copies, l.capacity);
    final int cols = math.min(l.cols, count);
    final int rows = (count + cols - 1) ~/ cols;
    final img.Image out = img.Image(width: l.sheetW, height: l.sheetH);
    img.fill(out, color: img.ColorRgb8(255, 255, 255));
    final img.ColorRgb8 line = img.ColorRgb8(190, 190, 190);
    for (int i = 0; i < count; i++) {
      final int x = l.margin + (i % cols) * (photo.width + l.gap);
      final int y = l.margin + (i ~/ cols) * (photo.height + l.gap);
      img.compositeImage(out, photo, dstX: x, dstY: y);
      img.drawRect(out, x1: x, y1: y, x2: x + photo.width - 1, y2: y + photo.height - 1, color: line);
    }
    return PassportSheet(out, count, cols, rows);
  }
}

class _Layout {
  _Layout(this.sheetW, this.sheetH, int w, int h, this.margin, this.gap)
      : cols = math.max(0, (sheetW - 2 * margin + gap) ~/ (w + gap)),
        rows = math.max(0, (sheetH - 2 * margin + gap) ~/ (h + gap));

  final int sheetW;
  final int sheetH;
  final int margin;
  final int gap;
  final int cols;
  final int rows;

  int get capacity => cols * rows;
}

/// Finds faces in a picture on the phone. ML Kit in the app, a fake in tests.
abstract class FaceFinder {
  /// Faces in pixels of the upright picture at [path]; empty when none.
  Future<List<FaceBox>> find(String path);
}

/// The face to frame: the largest one.
FaceBox? largestFace(List<FaceBox> faces) {
  FaceBox? best;
  for (final FaceBox f in faces) {
    if (best == null || f.width * f.height > best.width * best.height) {
      best = f;
    }
  }
  return best;
}
