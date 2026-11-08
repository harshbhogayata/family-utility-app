import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../app/theme.dart';
import '../../engines/qr/qr_actions.dart';
import '../../engines/qr/qr_payload.dart';
import 'qr_actions_impl.dart';
import 'qr_result_screen.dart';

/// Feature 051 — QR scanner. Live camera, on-device decode (ML Kit on Android,
/// Vision on iOS), then a safe preview on [QrResultScreen]. Nothing is uploaded.
class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key, this.actions = const PlatformQrActions()});

  final QrActions actions;

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const <BarcodeFormat>[BarcodeFormat.qrCode],
  );
  bool _handling = false;
  bool _torch = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_handling) {
      return;
    }
    String? raw;
    for (final Barcode b in capture.barcodes) {
      final String? v = b.rawValue;
      if (v != null && v.isNotEmpty) {
        raw = v;
        break;
      }
    }
    if (raw == null) {
      return;
    }
    _handling = true;
    final QrPayload payload = QrDecoder.decode(raw);
    await _controller.stop();
    if (!mounted) {
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext _) => QrResultScreen(
          payload: payload,
          actions: widget.actions,
        ),
      ),
    );
    if (!mounted) {
      return;
    }
    _handling = false;
    await _controller.start();
  }

  Future<void> _toggleTorch() async {
    await _controller.toggleTorch();
    if (mounted) {
      setState(() => _torch = !_torch);
    }
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('QR scanner'),
        actions: <Widget>[
          IconButton(
            tooltip: _torch ? 'Turn torch off' : 'Turn torch on',
            onPressed: _toggleTorch,
            icon: Icon(_torch ? Icons.flashlight_off_outlined : Icons.flashlight_on_outlined),
          ),
          IconButton(
            tooltip: 'Switch camera',
            onPressed: _controller.switchCamera,
            icon: const Icon(Icons.cameraswitch_outlined),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(AppRadius.card)),
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  MobileScanner(
                    controller: _controller,
                    onDetect: _onDetect,
                  ),
                  IgnorePointer(
                    child: Center(
                      child: Semantics(
                        label: 'Point the camera at a QR code',
                        child: Container(
                          width: 240,
                          height: 240,
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.white, width: 2),
                            borderRadius: BorderRadius.circular(AppRadius.card),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: <Widget>[
                Text(
                  'Point at a QR code. Links, Wi-Fi, UPI, contacts and events are '
                  'previewed before anything opens.',
                  style: text.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                Text(
                  'Decoded on this phone. Nothing is uploaded.',
                  style: text.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
