import 'dart:io';
import 'dart:typed_data';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;

import '../engines/pdf/pdf_ocr.dart';

/// Feature 008 — ML Kit text recognition on the phone. The model runs on
/// device; the page image is written to a temporary file and deleted after.
class MlKitTextRecognizer implements TextRecognizerEngine {
  const MlKitTextRecognizer();

  @override
  Future<List<OcrWord>> recognize(img.Image page, Uint8List jpeg, OcrScript script) async {
    final Directory dir = await Directory.systemTemp.createTemp('ocr');
    final File f = File('${dir.path}/page.jpg');
    await f.writeAsBytes(jpeg, flush: true);
    final TextRecognizer r = TextRecognizer(
      script: script == OcrScript.devanagari ? TextRecognitionScript.devanagiri : TextRecognitionScript.latin,
    );
    try {
      final RecognizedText t = await r.processImage(InputImage.fromFilePath(f.path));
      return <OcrWord>[
        for (final TextBlock b in t.blocks)
          for (final TextLine l in b.lines)
            for (final TextElement e in l.elements)
              OcrWord(
                e.text,
                left: e.boundingBox.left,
                top: e.boundingBox.top,
                right: e.boundingBox.right,
                bottom: e.boundingBox.bottom,
              ),
      ];
    } finally {
      await r.close();
      try {
        await dir.delete(recursive: true);
      } catch (_) {
        // The system clears its temp folder.
      }
    }
  }
}
