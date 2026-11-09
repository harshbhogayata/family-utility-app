import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../pdf/pdf_ocr.dart';
import 'passport_photo.dart' show FaceBox, FaceFinder;

/// Feature 045 — Blur faces, plates and Aadhaar numbers.
///
/// Finds faces (ML Kit face detection), number plates and Aadhaar numbers
/// (ML Kit text recognition) on the phone, lets the person add boxes by
/// hand, and bakes the cover into a fresh image: the covered pixels are
/// overwritten, and the file is re-encoded from pixels so no metadata,
/// thumbnail or original layer survives. Nothing is uploaded.

enum RedactKind {
  face('Face'),
  plate('Number plate'),
  aadhaar('Aadhaar digits'),
  manual('Your box');

  const RedactKind(this.label);
  final String label;
}

enum RedactStyle {
  blur('Blur'),
  box('Black box');

  const RedactStyle(this.label);
  final String label;
}

/// A rectangle to cover, in image pixels.
@immutable
class RedactRegion {
  const RedactRegion(this.kind, this.left, this.top, this.width, this.height);

  final RedactKind kind;
  final double left;
  final double top;
  final double width;
  final double height;

  double get right => left + width;
  double get bottom => top + height;

  /// Grown by [f] of its size on every side (covers hair, plate frames).
  RedactRegion inflate(double f) =>
      RedactRegion(kind, left - width * f, top - height * f, width * (1 + 2 * f), height * (1 + 2 * f));

  static RedactRegion around(RedactKind kind, Iterable<OcrWord> words) {
    double l = double.infinity, t = double.infinity, r = -double.infinity, b = -double.infinity;
    for (final OcrWord w in words) {
      l = math.min(l, w.left);
      t = math.min(t, w.top);
      r = math.max(r, w.right);
      b = math.max(b, w.bottom);
    }
    return RedactRegion(kind, l, t, r - l, b - t);
  }

  @override
  String toString() => '${kind.name}(${left.round()},${top.round()} ${width.round()}×${height.round()})';
}

/// Words grouped into rows, left to right.
List<List<OcrWord>> _rows(List<OcrWord> words) {
  final List<OcrWord> sorted = List<OcrWord>.of(words)..sort((OcrWord a, OcrWord b) => a.top.compareTo(b.top));
  final List<List<OcrWord>> rows = <List<OcrWord>>[];
  for (final OcrWord w in sorted) {
    final double mid = (w.top + w.bottom) / 2;
    if (rows.isNotEmpty) {
      final OcrWord f = rows.last.first;
      if ((mid - (f.top + f.bottom) / 2).abs() < (f.bottom - f.top) * 0.6) {
        rows.last.add(w);
        continue;
      }
    }
    rows.add(<OcrWord>[w]);
  }
  for (final List<OcrWord> r in rows) {
    r.sort((OcrWord a, OcrWord b) => a.left.compareTo(b.left));
  }
  return rows;
}

final RegExp _fourDigits = RegExp(r'^\d{4}$');

/// Aadhaar numbers (12 digits, usually 4 4 4): the first 8 digits are
/// covered and the last 4 left readable, as UIDAI's masked Aadhaar does.
List<RedactRegion> aadhaarRegions(List<OcrWord> words) {
  final List<RedactRegion> out = <RedactRegion>[];
  for (final List<OcrWord> row in _rows(words)) {
    for (int i = 0; i < row.length; i++) {
      final String t = row[i].text.replaceAll(RegExp(r'[^0-9]'), '');
      final String raw = row[i].text.trim();
      // One word holding all 12 digits ("1234 5678 9012" read as one, or
      // "1234-5678-9012"): cover the first two thirds of it.
      if (t.length == 12 && RegExp(r'^[\d\s-]+$').hasMatch(raw)) {
        final OcrWord w = row[i];
        out.add(RedactRegion(RedactKind.aadhaar, w.left, w.top, (w.right - w.left) * 8 / 12, w.bottom - w.top));
        continue;
      }
      if (i + 2 < row.length &&
          _fourDigits.hasMatch(raw) &&
          _fourDigits.hasMatch(row[i + 1].text.trim()) &&
          _fourDigits.hasMatch(row[i + 2].text.trim())) {
        out.add(RedactRegion.around(RedactKind.aadhaar, <OcrWord>[row[i], row[i + 1]]));
        i += 2;
      }
    }
  }
  return out;
}

/// Indian registration plates: state, district, series, number
/// ("MH 12 AB 1234", "DL3CAB1234"), and BH series ("22 BH 1234 AA").
final RegExp _plate = RegExp(r'^([A-Z]{2}\d{1,2}[A-Z]{0,3}\d{4}|\d{2}BH\d{4}[A-Z]{1,2})$');

bool isPlateText(String s) => _plate.hasMatch(s.toUpperCase().replaceAll(RegExp(r'[\s\-.]'), ''));

/// Number plates found in recognised text: one to four words in a row that
/// read as a registration number.
List<RedactRegion> plateRegions(List<OcrWord> words) {
  final List<RedactRegion> out = <RedactRegion>[];
  for (final List<OcrWord> row in _rows(words)) {
    int i = 0;
    while (i < row.length) {
      int matched = 0;
      for (int n = math.min(4, row.length - i); n >= 1; n--) {
        if (isPlateText(row.sublist(i, i + n).map((OcrWord w) => w.text).join())) {
          matched = n;
          break;
        }
      }
      if (matched > 0) {
        out.add(RedactRegion.around(RedactKind.plate, row.sublist(i, i + matched)).inflate(0.15));
        i += matched;
      } else {
        i++;
      }
    }
  }
  return out;
}

/// What to look for.
@immutable
class RedactTargets {
  const RedactTargets({this.faces = true, this.plates = true, this.aadhaar = true});

  final bool faces;
  final bool plates;
  final bool aadhaar;
}

class Redactor {
  const Redactor({required this.faces, required this.text});

  final FaceFinder faces;
  final TextRecognizerEngine text;

  /// Runs the on-device detectors. A detector that fails is skipped.
  Future<List<RedactRegion>> detect(String path, img.Image image, Uint8List jpeg, RedactTargets targets) async {
    final List<RedactRegion> out = <RedactRegion>[];
    if (targets.faces) {
      try {
        for (final FaceBox f in await faces.find(path)) {
          out.add(RedactRegion(RedactKind.face, f.left, f.top, f.width, f.height).inflate(0.12));
        }
      } catch (_) {
        // No faces found this time.
      }
    }
    if (targets.plates || targets.aadhaar) {
      try {
        final List<OcrWord> words = await text.recognize(image, jpeg, OcrScript.latin);
        if (targets.aadhaar) {
          out.addAll(aadhaarRegions(words));
        }
        if (targets.plates) {
          out.addAll(plateRegions(words));
        }
      } catch (_) {
        // No text read this time.
      }
    }
    return out;
  }

  /// A new image with every region covered. The source is not changed.
  static img.Image apply(img.Image source, List<RedactRegion> regions, RedactStyle style) {
    final img.Image out = img.Image.from(source);
    for (final RedactRegion r in regions) {
      final int x0 = r.left.floor().clamp(0, out.width);
      final int y0 = r.top.floor().clamp(0, out.height);
      final int x1 = r.right.ceil().clamp(0, out.width);
      final int y1 = r.bottom.ceil().clamp(0, out.height);
      if (x1 <= x0 || y1 <= y0) {
        continue;
      }
      if (style == RedactStyle.box) {
        img.fillRect(out, x1: x0, y1: y0, x2: x1 - 1, y2: y1 - 1, color: img.ColorRgb8(0, 0, 0));
        continue;
      }
      // Mosaic: about six blocks across the short side, each the average of
      // its pixels, so no original pixel is left and faces cannot be read.
      final int block = math.max(6, (math.min(x1 - x0, y1 - y0) / 6).ceil());
      for (int by = y0; by < y1; by += block) {
        for (int bx = x0; bx < x1; bx += block) {
          final int ex = math.min(bx + block, x1);
          final int ey = math.min(by + block, y1);
          num sr = 0, sg = 0, sb = 0;
          int n = 0;
          for (int y = by; y < ey; y++) {
            for (int x = bx; x < ex; x++) {
              final img.Pixel p = out.getPixel(x, y);
              sr += p.r;
              sg += p.g;
              sb += p.b;
              n++;
            }
          }
          final img.Color c = img.ColorRgb8((sr / n).round(), (sg / n).round(), (sb / n).round());
          img.fillRect(out, x1: bx, y1: by, x2: ex - 1, y2: ey - 1, color: c);
        }
      }
    }
    return out;
  }

  /// Fresh JPEG from the pixels only: no EXIF, no thumbnail, no original.
  static Uint8List encode(img.Image image) {
    final img.Image clean = img.Image.from(image)..exif = img.ExifData();
    return Uint8List.fromList(img.encodeJpg(clean, quality: 90));
  }
}
