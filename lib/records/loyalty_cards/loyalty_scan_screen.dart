import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart' as ms;

import '../../app/theme.dart';
import '../../engines/records/loyalty_cards.dart';

/// What a scan found: the number and the format it was printed in.
class ScannedCard {
  const ScannedCard(this.number, this.format);
  final String number;
  final CardFormat format;
}

/// Maps the on-device scanner's format to one the app can draw again.
/// Code 93 and UPC-E are redrawn as Code 128, which every till reads.
CardFormat cardFormatFor(ms.BarcodeFormat f) => switch (f) {
      ms.BarcodeFormat.ean13 => CardFormat.ean13,
      ms.BarcodeFormat.ean8 => CardFormat.ean8,
      ms.BarcodeFormat.upcA => CardFormat.upcA,
      ms.BarcodeFormat.code39 => CardFormat.code39,
      ms.BarcodeFormat.itf => CardFormat.itf,
      ms.BarcodeFormat.codabar => CardFormat.codabar,
      ms.BarcodeFormat.qrCode => CardFormat.qr,
      ms.BarcodeFormat.pdf417 => CardFormat.pdf417,
      ms.BarcodeFormat.dataMatrix => CardFormat.dataMatrix,
      ms.BarcodeFormat.aztec => CardFormat.aztec,
      _ => CardFormat.code128,
    };

/// Live camera, decoded on the phone (051's scanner). Pops a [ScannedCard].
class LoyaltyScanScreen extends StatefulWidget {
  const LoyaltyScanScreen({super.key});

  @override
  State<LoyaltyScanScreen> createState() => _LoyaltyScanScreenState();
}

class _LoyaltyScanScreenState extends State<LoyaltyScanScreen> {
  final ms.MobileScannerController _controller = ms.MobileScannerController(detectionSpeed: ms.DetectionSpeed.noDuplicates);
  bool _done = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(ms.BarcodeCapture capture) {
    if (_done) {
      return;
    }
    for (final ms.Barcode b in capture.barcodes) {
      final String? v = b.rawValue;
      if (v != null && v.trim().isNotEmpty) {
        _done = true;
        Navigator.of(context).pop(ScannedCard(v.trim(), cardFormatFor(b.format)));
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan a card')),
      body: Column(
        children: <Widget>[
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(AppRadius.card)),
              child: ms.MobileScanner(controller: _controller, onDetect: _onDetect),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Point at the barcode on the back of the card. Decoded on this phone; nothing is uploaded.',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}
