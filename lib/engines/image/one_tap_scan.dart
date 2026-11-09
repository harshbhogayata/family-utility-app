import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../pdf/pdf_compressor.dart';
import '../pdf/pdf_ocr.dart';
import 'document_scanner.dart';
import 'scan_namer.dart';

/// Feature 054 — One-tap searchable scan.
///
/// One action after capture: read every page on the phone (feature 008),
/// write the pages with an invisible text layer, squeeze the photos to a
/// preset (feature 032) and name the file from its title and date (feature
/// 053). The caller saves the bytes. Nothing is uploaded.

/// A4 width in points; scanned pages keep their own shape at this width.
const double scanPageWidthPt = 595.28;

class OneTapResult {
  const OneTapResult({
    required this.name,
    required this.pdf,
    required this.pageTexts,
    required this.wordCount,
    required this.uncompressedBytes,
  });

  /// Auto-name, without extension.
  final String name;
  final Uint8List pdf;
  final List<String> pageTexts;
  final int wordCount;
  final int uncompressedBytes;
}

class OneTapScan {
  OneTapScan({
    required this.recognizer,
    required this.namer,
    this.preset = PdfPreset.medium,
    this.script = OcrScript.latin,
  });

  final TextRecognizerEngine recognizer;
  final ScanAutoNamer namer;
  final PdfPreset preset;
  final OcrScript script;

  Future<OneTapResult> run(
    List<ScanPage> pages,
    DateTime now, {
    void Function(String step)? progress,
  }) async {
    if (pages.isEmpty) {
      throw const PdfOcrError('Scan a page first');
    }
    final List<OcrPage> out = <OcrPage>[];
    for (int i = 0; i < pages.length; i++) {
      progress?.call('Reading page ${i + 1} of ${pages.length}…');
      final ScanPage p = pages[i];
      List<OcrWord> words = const <OcrWord>[];
      int w = p.width;
      int h = p.height;
      try {
        final img.Image? decoded = img.decodeJpg(p.jpeg);
        if (decoded != null) {
          w = decoded.width;
          h = decoded.height;
          words = await recognizer.recognize(decoded, p.jpeg, script);
        }
      } catch (_) {
        // The page is kept as an image; it just has no text layer.
      }
      out.add(OcrPage(
        jpeg: p.jpeg,
        pixelWidth: w,
        pixelHeight: h,
        widthPt: scanPageWidthPt,
        heightPt: scanPageWidthPt * h / (w == 0 ? 1 : w),
        words: words.where((OcrWord x) => x.text.trim().isNotEmpty).toList(),
      ));
    }
    progress?.call('Compressing…');
    final Uint8List searchable = writeSearchablePdf(out);
    Uint8List pdf = searchable;
    try {
      final PdfCompressResult c = PdfCompressor.compress(searchable, preset);
      if (c.bytes.length < searchable.length) {
        pdf = c.bytes;
      }
    } catch (_) {
      // Saved as written; still searchable.
    }
    progress?.call('Naming…');
    final List<String> texts = <String>[for (final OcrPage p in out) p.text];
    final ScanNameSuggestion name = await namer.fromText(texts.first, now);
    return OneTapResult(
      name: name.name,
      pdf: pdf,
      pageTexts: texts,
      wordCount: out.fold(0, (int n, OcrPage p) => n + p.words.length),
      uncompressedBytes: searchable.length,
    );
  }

  static OneTapScan? instance;
}
