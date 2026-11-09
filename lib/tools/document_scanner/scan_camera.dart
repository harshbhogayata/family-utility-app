import 'dart:math' as math;
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../engines/image/document_scanner.dart';

/// The live camera behind the scanner, as an interface so tests can feed
/// frames without a phone.
abstract class ScanCamera {
  /// Starts the preview and the frame stream. False when there is no camera
  /// or permission was refused.
  Future<bool> start(void Function(ScanFrame frame) onFrame);

  /// The live preview, filling its box.
  Widget preview(BuildContext context);

  /// A full-resolution still.
  Future<Uint8List> takePicture();

  Future<void> dispose();
}

/// Back camera through the `camera` package. Frames are reduced to a small,
/// upright brightness grid (long side [gridLongSide]) before detection, so
/// the detector keeps up with the 30 fps preview.
class DeviceScanCamera implements ScanCamera {
  DeviceScanCamera({this.gridLongSide = 240});

  final int gridLongSide;
  CameraController? _controller;
  void Function(ScanFrame frame)? _onFrame;
  int _sensorTurns = 0;
  bool _streaming = false;

  @override
  Future<bool> start(void Function(ScanFrame frame) onFrame) async {
    _onFrame = onFrame;
    try {
      final List<CameraDescription> cams = await availableCameras();
      if (cams.isEmpty) {
        return false;
      }
      final CameraDescription back = cams.firstWhere(
        (CameraDescription c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cams.first,
      );
      _sensorTurns = (back.sensorOrientation ~/ 90) % 4;
      final CameraController c = CameraController(
        back,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await c.initialize();
      _controller = c;
      await _startStream();
      return true;
    } on CameraException {
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<void> _startStream() async {
    final CameraController? c = _controller;
    if (c == null || _streaming) {
      return;
    }
    await c.startImageStream(_frame);
    _streaming = true;
  }

  Future<void> _stopStream() async {
    final CameraController? c = _controller;
    if (c == null || !_streaming) {
      return;
    }
    await c.stopImageStream();
    _streaming = false;
  }

  void _frame(CameraImage image) {
    final void Function(ScanFrame frame)? cb = _onFrame;
    if (cb == null || image.planes.isEmpty) {
      return;
    }
    final Plane y = image.planes.first;
    cb(reduceLuma(y.bytes, image.width, image.height, y.bytesPerRow, _sensorTurns, gridLongSide));
  }

  @override
  Widget preview(BuildContext context) {
    final CameraController? c = _controller;
    if (c == null || !c.value.isInitialized) {
      return const ColoredBox(color: Colors.black);
    }
    return CameraPreview(c);
  }

  @override
  Future<Uint8List> takePicture() async {
    final CameraController c = _controller!;
    await _stopStream();
    try {
      final XFile f = await c.takePicture();
      return await f.readAsBytes();
    } finally {
      await _startStream();
    }
  }

  @override
  Future<void> dispose() async {
    _onFrame = null;
    final CameraController? c = _controller;
    _controller = null;
    if (c != null) {
      if (_streaming) {
        try {
          await c.stopImageStream();
        } catch (_) {}
        _streaming = false;
      }
      await c.dispose();
    }
  }
}

/// Samples a Y plane down to a grid whose long side is [longSide] and turns
/// it upright by [quarterTurns] clockwise (the sensor's orientation).
ScanFrame reduceLuma(Uint8List bytes, int width, int height, int rowStride, int quarterTurns, int longSide) {
  final int step = math.max(1, (math.max(width, height) / longSide).ceil());
  final int sw = width ~/ step;
  final int sh = height ~/ step;
  final bool swap = quarterTurns.isOdd;
  final int ow = swap ? sh : sw;
  final int oh = swap ? sw : sh;
  final Uint8List out = Uint8List(ow * oh);
  for (int y = 0; y < sh; y++) {
    final int row = y * step * rowStride;
    for (int x = 0; x < sw; x++) {
      final int i = row + x * step;
      final int v = i < bytes.length ? bytes[i] : 0;
      int ox;
      int oy;
      switch (quarterTurns % 4) {
        case 1:
          ox = sh - 1 - y;
          oy = x;
        case 2:
          ox = sw - 1 - x;
          oy = sh - 1 - y;
        case 3:
          ox = y;
          oy = sw - 1 - x;
        default:
          ox = x;
          oy = y;
      }
      out[oy * ow + ox] = v;
    }
  }
  return ScanFrame(luma: out, width: ow, height: oh);
}
