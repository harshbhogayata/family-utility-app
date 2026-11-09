import 'dart:typed_data';

import 'package:pdfrx/pdfrx.dart';

import '../engines/convert/pdf_to_word.dart';

T? _maybe<T>(T? v) => v;

/// Positioned text from PDFium on the phone. Nothing leaves the device.
class PdfrxTextSource implements PdfTextSource {
  const PdfrxTextSource();

  @override
  Future<List<List<PdfTextPiece>>> read(Uint8List pdf) async {
    final PdfDocument doc = await PdfDocument.openData(pdf);
    try {
      final List<List<PdfTextPiece>> out = <List<PdfTextPiece>>[];
      for (final PdfPage page in doc.pages) {
        final PdfPageText? text = _maybe(await page.loadStructuredText());
        final List<PdfTextPiece> pieces = <PdfTextPiece>[];
        if (text != null) {
          for (final PdfPageTextFragment f in text.fragments) {
            final PdfRect b = f.bounds;
            pieces.add(PdfTextPiece(f.text, left: b.left, bottom: b.bottom, right: b.right, top: b.top));
          }
        }
        out.add(pieces);
      }
      return out;
    } finally {
      await doc.dispose();
    }
  }
}
