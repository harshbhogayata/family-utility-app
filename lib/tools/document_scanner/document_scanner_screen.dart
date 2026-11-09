import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../app/theme.dart';
import '../../app/widgets/result_bar.dart';
import '../../engines/convert/convert_registry.dart';
import '../../engines/image/document_scanner.dart';
import '../../engines/share/share_engine.dart';
import 'scan_camera.dart';

/// Turns a camera still into a flattened page.
typedef ScanProcessor = Future<ScanPage> Function(Uint8List photo);

ScanPage _processOnDevice(Uint8List photo) => const DocumentScanner().process(photo);

/// Default processor: a background isolate, so the preview never stalls.
Future<ScanPage> processInBackground(Uint8List photo) => compute(_processOnDevice, photo);

/// Where scans are written.
abstract class ScanIo {
  Future<String> write(String name, String extension, Uint8List bytes);
  Future<void> remove(String path);
}

class SystemScanIo implements ScanIo {
  const SystemScanIo();

  @override
  Future<String> write(String name, String extension, Uint8List bytes) async {
    final Directory base = await getApplicationDocumentsDirectory();
    final Directory dir = Directory('${base.path}/scans');
    await dir.create(recursive: true);
    String path = '${dir.path}/$name.$extension';
    int n = 2;
    while (File(path).existsSync()) {
      path = '${dir.path}/$name ($n).$extension';
      n++;
    }
    await File(path).writeAsBytes(bytes, flush: true);
    return path;
  }

  @override
  Future<void> remove(String path) async {
    final File f = File(path);
    if (f.existsSync()) {
      await f.delete();
    }
  }
}

/// Feature 047 — Document scanner.
class DocumentScannerScreen extends StatefulWidget {
  const DocumentScannerScreen({
    super.key,
    this.camera,
    this.io = const SystemScanIo(),
    this.process = processInBackground,
    this.detector = const EdgeDetector(),
    this.share,
    this.returnResult = false,
    this.now,
  });

  /// Defaults to the phone's back camera.
  final ScanCamera? camera;
  final ScanIo io;
  final ScanProcessor process;
  final EdgeDetector detector;
  final ShareEngine? share;

  /// Opened by another app: pop with the saved paths once saved.
  final bool returnResult;

  /// Clock for file names (tests).
  final DateTime Function()? now;

  @override
  State<DocumentScannerScreen> createState() => _DocumentScannerScreenState();
}

class _DocumentScannerScreenState extends State<DocumentScannerScreen> {
  late final ScanCamera _camera = widget.camera ?? DeviceScanCamera();
  final ScanSession _session = ScanSession();
  final SteadyDetector _steady = SteadyDetector();
  ScanQuad? _quad;
  int _frameW = 1;
  int _frameH = 1;
  bool _cameraReady = false;
  bool _auto = true;
  bool _busy = false;
  bool _reviewing = false;
  int? _retakeIndex;
  ScanFormat _format = ScanFormat.pdf;
  List<String> _outputs = <String>[];
  String? _status;

  @override
  void initState() {
    super.initState();
    unawaited(_startCamera());
  }

  Future<void> _startCamera() async {
    final bool ok = await _camera.start(_onFrame);
    if (!mounted) {
      return;
    }
    setState(() {
      _cameraReady = ok;
      if (!ok) {
        _status = 'No camera available. Allow camera access in Settings to scan.';
      }
    });
  }

  @override
  void dispose() {
    unawaited(_camera.dispose());
    super.dispose();
  }

  void _onFrame(ScanFrame f) {
    if (!mounted || _reviewing) {
      return;
    }
    final ScanQuad? q = widget.detector.detect(f);
    final bool fire = _steady.feed(q, f.width, f.height);
    setState(() {
      _quad = q;
      _frameW = f.width;
      _frameH = f.height;
    });
    if (fire && _auto && !_busy) {
      unawaited(_capture());
    }
  }

  void _toast(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(m)));
    }
  }

  Future<void> _capture() async {
    if (_busy || !_cameraReady) {
      return;
    }
    setState(() => _busy = true);
    try {
      final Uint8List photo = await _camera.takePicture();
      final ScanPage page = await widget.process(photo);
      if (!mounted) {
        return;
      }
      setState(() {
        final int? r = _retakeIndex;
        if (r != null && r < _session.length) {
          _session.retake(r, page);
          _status = 'Retook page ${r + 1}';
          _retakeIndex = null;
          _reviewing = true;
        } else {
          _session.add(page);
          _status = page.foundEdges
              ? 'Page ${_session.length} captured'
              : 'Page ${_session.length} captured — no edges found, kept the whole photo';
        }
        _outputs = <String>[];
      });
      _steady.reset();
    } on ConvertException catch (e) {
      setState(() => _status = e.message);
    } catch (_) {
      setState(() => _status = 'Could not take the photo. Try again.');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  String _baseName() {
    final DateTime t = (widget.now ?? DateTime.now)();
    String two(int v) => v.toString().padLeft(2, '0');
    return 'Scan ${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}.${two(t.minute)}';
  }

  Future<void> _make() async {
    if (_session.isEmpty || _busy) {
      _toast('Scan a page first');
      return;
    }
    setState(() => _busy = true);
    try {
      final String name = _baseName();
      final List<String> written = <String>[];
      if (_format == ScanFormat.pdf) {
        final Uint8List pdf = await _session.toPdf();
        written.add(await widget.io.write(name, 'pdf', pdf));
      } else {
        final List<Uint8List> jpgs = _session.toJpgs();
        for (int i = 0; i < jpgs.length; i++) {
          final String n = jpgs.length == 1 ? name : '$name p${i + 1}';
          written.add(await widget.io.write(n, 'jpg', jpgs[i]));
        }
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _outputs = written;
        _status = _format == ScanFormat.pdf
            ? 'Saved a ${_session.length}-page PDF in Files › scans'
            : 'Saved ${written.length} JPG${written.length == 1 ? '' : 's'} in Files › scans';
      });
      if (widget.returnResult) {
        Navigator.of(context).pop(written);
      }
    } on ConvertException catch (e) {
      setState(() => _status = e.message);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _share() async {
    if (_outputs.isEmpty) {
      _toast('Save the scan first');
      return;
    }
    await (widget.share ?? ShareEngine.instance).shareFiles(_outputs);
  }

  Future<void> _save() async {
    if (_outputs.isNotEmpty) {
      _toast('Saved in Files › scans');
      return;
    }
    await _make();
  }

  Future<void> _undo() async {
    if (_outputs.isNotEmpty) {
      for (final String p in _outputs) {
        await widget.io.remove(p);
      }
      setState(() {
        _outputs = <String>[];
        _status = 'Removed the saved scan';
      });
      return;
    }
    if (_session.canUndo) {
      setState(() {
        _session.undo();
        _status = 'Undone';
        if (_session.isEmpty) {
          _reviewing = false;
        }
      });
      return;
    }
    Navigator.of(context).maybePop();
  }

  void _retake(int i) {
    setState(() {
      _retakeIndex = i;
      _reviewing = false;
      _status = 'Retaking page ${i + 1}';
    });
    _steady.reset();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_reviewing ? 'Scanned pages' : 'Scan document'),
        actions: <Widget>[
          if (!_reviewing && _session.length > 0)
            TextButton(
              key: const Key('scan-review'),
              onPressed: () => setState(() => _reviewing = true),
              child: Text('Done (${_session.length})'),
            ),
        ],
      ),
      body: _reviewing ? _review(context) : _capturePane(context),
      bottomNavigationBar: ResultBar(onShare: _share, onSave: _save, onUndo: _undo),
    );
  }

  Widget _statusLine(BuildContext context) {
    if (_status == null) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Semantics(
        liveRegion: true,
        child: Text(_status!,
            key: const Key('scan-status'),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.ink)),
      ),
    );
  }

  Widget _capturePane(BuildContext context) {
    final bool found = _quad != null;
    return Column(
      children: <Widget>[
        Expanded(
          child: Semantics(
            label: found ? 'Camera preview. Page found.' : 'Camera preview. Point at a page.',
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                _camera.preview(context),
                CustomPaint(
                  key: const Key('scan-overlay'),
                  painter: QuadPainter(quad: _quad, frameWidth: _frameW, frameHeight: _frameH, progress: _steady.progress),
                ),
                if (_busy) const Center(child: CircularProgressIndicator()),
              ],
            ),
          ),
        ),
        _statusLine(context),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(
            children: <Widget>[
              Expanded(
                child: SwitchListTile(
                  key: const Key('scan-auto'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Auto-capture'),
                  value: _auto,
                  onChanged: (bool v) => setState(() => _auto = v),
                ),
              ),
              const SizedBox(width: AppRadius.gridGap),
              SizedBox(
                width: 72,
                height: 72,
                child: FilledButton(
                  key: const Key('scan-shutter'),
                  style: FilledButton.styleFrom(shape: const CircleBorder(), padding: EdgeInsets.zero),
                  onPressed: _cameraReady && !_busy ? _capture : null,
                  child: Semantics(
                    label: _retakeIndex == null ? 'Capture page' : 'Retake page ${_retakeIndex! + 1}',
                    child: const Icon(Icons.camera_alt, size: 32),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _review(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final List<ScanPage> pages = _session.pages;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        _statusLine(context),
        const SizedBox(height: 8),
        Card(
          child: ReorderableListView(
            key: const Key('scan-pages'),
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            onReorder: (int from, int to) => setState(() {
              _session.move(from, to);
              _outputs = <String>[];
            }),
            children: <Widget>[
              for (int i = 0; i < pages.length; i++)
                ListTile(
                  key: ObjectKey(pages[i]),
                  minVerticalPadding: 8,
                  leading: SizedBox(
                    width: 44,
                    height: 56,
                    child: Image.memory(pages[i].jpeg, fit: BoxFit.cover, semanticLabel: 'Page ${i + 1}'),
                  ),
                  title: Text('Page ${i + 1}', style: text.titleMedium),
                  subtitle: Text('${pages[i].width} × ${pages[i].height}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      IconButton(
                        tooltip: 'Retake page ${i + 1}',
                        icon: const Icon(Icons.replay),
                        onPressed: () => _retake(i),
                      ),
                      IconButton(
                        tooltip: 'Remove page ${i + 1}',
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(() {
                          _session.remove(i);
                          _outputs = <String>[];
                          if (_session.isEmpty) {
                            _reviewing = false;
                          }
                        }),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          key: const Key('scan-add'),
          onPressed: () => setState(() => _reviewing = false),
          icon: const Icon(Icons.add_a_photo_outlined),
          label: const Text('Add page'),
        ),
        const SizedBox(height: 12),
        Text('Save as', style: text.titleSmall),
        const SizedBox(height: 6),
        SegmentedButton<ScanFormat>(
          key: const Key('scan-format'),
          segments: <ButtonSegment<ScanFormat>>[
            for (final ScanFormat f in ScanFormat.values) ButtonSegment<ScanFormat>(value: f, label: Text(f.label)),
          ],
          selected: <ScanFormat>{_format},
          onSelectionChanged: (Set<ScanFormat> v) => setState(() {
            _format = v.first;
            _outputs = <String>[];
          }),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          key: const Key('scan-make'),
          onPressed: _session.isEmpty || _busy ? null : _make,
          icon: Icon(_format == ScanFormat.pdf ? Icons.picture_as_pdf_outlined : Icons.image_outlined),
          label: Text(_format == ScanFormat.pdf
              ? 'Save ${_session.length}-page PDF'
              : 'Save ${_session.length} JPG${_session.length == 1 ? '' : 's'}'),
        ),
      ],
    );
  }
}

/// Draws the found page edge over the preview, filling in as the hold
/// steadies towards auto-capture.
class QuadPainter extends CustomPainter {
  QuadPainter({required this.quad, required this.frameWidth, required this.frameHeight, required this.progress});

  final ScanQuad? quad;
  final int frameWidth;
  final int frameHeight;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final ScanQuad? q = quad;
    if (q == null) {
      return;
    }
    final double sx = size.width / frameWidth;
    final double sy = size.height / frameHeight;
    final Path path = Path();
    final List<ScanPoint> c = q.corners;
    path.moveTo(c[0].x * sx, c[0].y * sy);
    for (int i = 1; i < 4; i++) {
      path.lineTo(c[i].x * sx, c[i].y * sy);
    }
    path.close();
    canvas.drawPath(path, Paint()..color = AppColors.accent.withValues(alpha: 0.15 + 0.25 * progress));
    canvas.drawPath(
      path,
      Paint()
        ..color = AppColors.accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(QuadPainter old) =>
      old.quad != quad || old.progress != progress || old.frameWidth != frameWidth || old.frameHeight != frameHeight;
}
