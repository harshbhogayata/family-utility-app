import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../convert/convert_registry.dart';
import '../pdf/images_to_pdf.dart';
import 'document_scanner.dart';
import 'exact_kb.dart' show mmToPx;

/// Feature 044 — ID card to A4.
///
/// Pure Dart, on the phone. Each side is flattened with the document
/// scanner's edge finder, turned to landscape, set to the ISO ID-1 card size
/// (85.6 × 53.98 mm) and placed at actual size on an A4 or Letter page, front
/// above back. Saved as a JPG at 300 dpi and a one-page PDF.

const double idCardWidthMm = 85.6;
const double idCardHeightMm = 53.98;
const int idCardDpi = 300;

enum IdPaper {
  a4('A4', 210, 297, PdfPageSize.a4),
  letter('Letter', 215.9, 279.4, PdfPageSize.letter);

  const IdPaper(this.label, this.widthMm, this.heightMm, this.pdfSize);
  final String label;
  final double widthMm;
  final double heightMm;
  final PdfPageSize pdfSize;

  int get widthPx => mmToPx(widthMm, dpi: idCardDpi);
  int get heightPx => mmToPx(heightMm, dpi: idCardDpi);
}

/// One side, ready to place.
class IdCardSide {
  const IdCardSide(this.image, {required this.foundEdges, required this.turned});
  final img.Image image;

  /// False when no card edge was found and the whole picture was used.
  final bool foundEdges;

  /// True when the side was portrait and was turned to landscape.
  final bool turned;
}

class IdCardPage {
  const IdCardPage({
    required this.page,
    required this.jpg,
    required this.pdf,
    required this.front,
    required this.back,
    required this.frontRect,
    required this.backRect,
  });

  final img.Image page;
  final Uint8List jpg;
  final Uint8List pdf;
  final IdCardSide front;
  final IdCardSide? back;

  /// Where each card sits on the page, in pixels: (x, y, width, height).
  final (int, int, int, int) frontRect;
  final (int, int, int, int)? backRect;
}

class IdCardEngine {
  const IdCardEngine({this.scanner = const DocumentScanner()});

  final DocumentScanner scanner;

  int get cardWidthPx => mmToPx(idCardWidthMm, dpi: idCardDpi);
  int get cardHeightPx => mmToPx(idCardHeightMm, dpi: idCardDpi);

  /// Finds the card in a photo, flattens it, turns it landscape and sets it
  /// to the exact card size in pixels.
  IdCardSide side(Uint8List photo) {
    final ScanPage p = scanner.process(photo);
    final img.Image? flat = img.decodeJpg(p.jpeg);
    if (flat == null) {
      throw const ConvertException('The photo could not be read.');
    }
    final bool turn = flat.height > flat.width;
    final img.Image upright = turn ? img.copyRotate(flat, angle: 90) : flat;
    final img.Image sized = img.copyResize(
      upright,
      width: cardWidthPx,
      height: cardHeightPx,
      interpolation: img.Interpolation.average,
    );
    return IdCardSide(sized, foundEdges: p.foundEdges, turned: turn);
  }

  /// Front (and back, when given) on one page at actual size.
  IdCardPage build(Uint8List front, Uint8List? back, IdPaper paper) {
    final IdCardSide f = side(front);
    final IdCardSide? b = back == null ? null : side(back);
    final int pw = paper.widthPx;
    final int ph = paper.heightPx;
    final img.Image page = img.Image(width: pw, height: ph);
    img.fill(page, color: img.ColorRgb8(255, 255, 255));
    final int cw = cardWidthPx;
    final int ch = cardHeightPx;
    final int x = (pw - cw) ~/ 2;
    final int top = mmToPx(30, dpi: idCardDpi);
    final int gap = mmToPx(20, dpi: idCardDpi);
    final img.ColorRgb8 line = img.ColorRgb8(200, 200, 200);
    void place(img.Image card, int y) {
      img.compositeImage(page, card, dstX: x, dstY: y);
      img.drawRect(page, x1: x - 1, y1: y - 1, x2: x + cw, y2: y + ch, color: line);
    }

    place(f.image, top);
    final int backY = top + ch + gap;
    if (b != null) {
      place(b.image, backY);
    }
    final Uint8List jpg = img.encodeJpg(page, quality: 92);
    final Uint8List pdf = ImagesToPdf.writePdf(
      <PreparedImage>[PreparedImage(jpeg: jpg, width: pw, height: ph, components: 3)],
      ImagesToPdfOptions(pageSize: paper.pdfSize, orientation: PdfOrientation.portrait, marginPt: 0),
    );
    return IdCardPage(
      page: page,
      jpg: jpg,
      pdf: pdf,
      front: f,
      back: b,
      frontRect: (x, top, cw, ch),
      backRect: b == null ? null : (x, backY, cw, ch),
    );
  }
}
