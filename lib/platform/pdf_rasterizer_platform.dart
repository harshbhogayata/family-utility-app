import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:pdfrx/pdfrx.dart';

import '../engines/pdf/pdf_to_images.dart';

/// Feature 022 — pages drawn by PDFium on the phone. Nothing is uploaded.
class PdfrxRasterizer implements PdfRasterizer {
  const PdfrxRasterizer();

  @override
  Future<int> pageCount(Uint8List pdf) async {
    final PdfDocument doc = await PdfDocument.openData(pdf);
    try {
      return doc.pages.length;
    } finally {
      await doc.dispose();
    }
  }

  @override
  Future<img.Image> render(Uint8List pdf, int index, int dpi) async {
    final PdfDocument doc = await PdfDocument.openData(pdf);
    try {
      final PdfPage page = doc.pages[index];
      final int w = (page.width * dpi / 72).round();
      final int h = (page.height * dpi / 72).round();
      final PdfImage? im = await page.render(width: w, height: h, fullWidth: w.toDouble(), fullHeight: h.toDouble());
      if (im == null) {
        throw PdfToImagesError('Page ${index + 1} could not be drawn');
      }
      try {
        final img.Image out = img.Image.fromBytes(
          width: im.width,
          height: im.height,
          bytes: Uint8List.fromList(im.pixels).buffer,
          numChannels: 4,
          order: img.ChannelOrder.bgra,
        );
        // Flatten onto white: JPG has no transparency.
        final img.Image white = img.Image(width: out.width, height: out.height);
        img.fill(white, color: img.ColorRgb8(255, 255, 255));
        return img.compositeImage(white, out);
      } finally {
        im.dispose();
      }
    } finally {
      await doc.dispose();
    }
  }
}
