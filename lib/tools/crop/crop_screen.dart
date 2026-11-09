import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../app/theme.dart';
import '../../app/widgets/result_bar.dart';
import '../../engines/image/crop_engine.dart';
import '../../engines/share/share_engine.dart';

/// Picks one photo, reads it and writes the cropped copy. Behind an interface
/// so tests need neither the picker nor the disk.
abstract class CropFiles {
  Future<String?> pick();

  Future<Uint8List> read(String path);

  /// Saves the copy. Returns the saved path.
  Future<String> write(String name, Uint8List bytes);

  Future<void> remove(String path);
}

class SystemCropFiles implements CropFiles {
  const SystemCropFiles();

  @override
  Future<String?> pick() async {
    final FilePickerResult? r = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: <String>['jpg', 'jpeg', 'png', 'webp'],
    );
    return r == null || r.files.isEmpty ? null : r.files.first.path;
  }

  @override
  Future<Uint8List> read(String path) => File(path).readAsBytes();

  @override
  Future<String> write(String name, Uint8List bytes) async {
    final Directory base = await getApplicationDocumentsDirectory();
    final Directory dir = Directory('${base.path}/cropped');
    await dir.create(recursive: true);
    String path = '${dir.path}/$name';
    int i = 2;
    while (File(path).existsSync()) {
      final int dot = name.lastIndexOf('.');
      path = '${dir.path}/${name.substring(0, dot)} ($i)${name.substring(dot)}';
      i++;
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

typedef CropRunner = Future<CropResult> Function(Uint8List input, CropSpec spec);
typedef CropMeasure = Future<PixelSize> Function(Uint8List input);

Future<CropResult> cropInIsolate(Uint8List input, CropSpec spec) {
  return compute(_run, _Job(input, spec));
}

Future<PixelSize> measureInIsolate(Uint8List input) => compute(CropEngine.measure, input);

class _Job {
  const _Job(this.input, this.spec);
  final Uint8List input;
  final CropSpec spec;
}

CropResult _run(_Job j) => CropEngine.apply(j.input, j.spec);

/// Feature 041 — Crop with ratios.
class CropScreen extends StatefulWidget {
  const CropScreen({
    super.key,
    this.files = const SystemCropFiles(),
    this.runner = cropInIsolate,
    this.measure = measureInIsolate,
    this.share,
  });

  final CropFiles files;
  final CropRunner runner;
  final CropMeasure measure;
  final ShareEngine? share;

  @override
  State<CropScreen> createState() => _CropScreenState();
}

class _CropScreenState extends State<CropScreen> {
  String? _path;
  Uint8List? _bytes;
  PixelSize? _source;
  CropSpec _spec = const CropSpec();
  final List<CropSpec> _history = <CropSpec>[];
  bool _grid = false;
  bool _straightening = false;
  bool _working = false;
  String? _saved;
  CropResult? _result;

  PixelSize get _frame => CropEngine.frame(_source!, _spec.quarterTurns);

  void _toast(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(m)));
    }
  }

  Future<void> _pick() async {
    final String? path = await widget.files.pick();
    if (path == null) {
      return;
    }
    final Uint8List bytes = await widget.files.read(path);
    final PixelSize size;
    try {
      size = await widget.measure(bytes);
    } catch (e) {
      _toast('$e');
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _path = path;
      _bytes = bytes;
      _source = size;
      _spec = const CropSpec();
      _history.clear();
      _saved = null;
      _result = null;
    });
  }

  /// Every edit goes through here so Undo can step back.
  void _edit(CropSpec next, {bool record = true}) {
    if (next == _spec) {
      return;
    }
    setState(() {
      if (record) {
        _history.add(_spec);
      }
      _spec = next;
      _result = null;
    });
  }

  void _setRatio(CropRatio ratio) {
    _edit(_spec.copyWith(ratio: ratio, rect: CropEngine.fitRatio(ratio, _frame)));
  }

  void _turn(int delta) {
    final int turns = (_spec.quarterTurns + delta) % 4;
    final PixelSize f = CropEngine.frame(_source!, turns);
    _edit(_spec.copyWith(quarterTurns: turns, rect: CropEngine.fitRatio(_spec.ratio, f)));
  }

  void _nudgeAngle(double delta) {
    _edit(_spec.copyWith(angle: (_spec.angle + delta).clamp(-45, 45).toDouble()));
  }

  void _reset() => _edit(const CropSpec());

  Future<CropResult?> _render() async {
    final Uint8List? bytes = _bytes;
    if (bytes == null) {
      return null;
    }
    final CropResult? cached = _result;
    if (cached != null) {
      return cached;
    }
    setState(() => _working = true);
    try {
      final CropResult r = await widget.runner(bytes, _spec);
      if (mounted) {
        setState(() => _result = r);
      }
      return r;
    } catch (e) {
      _toast('$e');
      return null;
    } finally {
      if (mounted) {
        setState(() => _working = false);
      }
    }
  }

  Future<void> _save() async {
    if (_bytes == null) {
      _toast('Choose a photo first');
      return;
    }
    if (_working) {
      return;
    }
    final CropResult? r = await _render();
    if (r == null) {
      return;
    }
    final String saved = await widget.files.write(CropEngine.outputName(_path!, r), r.bytes);
    setState(() => _saved = saved);
    _toast('Saved ${r.width}×${r.height} in Files › cropped. The original is untouched.');
  }

  Future<void> _share() async {
    if (_saved == null) {
      await _save();
    }
    final String? saved = _saved;
    if (saved != null) {
      await (widget.share ?? ShareEngine.instance).shareFiles(<String>[saved]);
    }
  }

  Future<void> _undo() async {
    final String? saved = _saved;
    if (saved != null) {
      await widget.files.remove(saved);
      setState(() => _saved = null);
      _toast('Removed the cropped copy');
      return;
    }
    if (_history.isNotEmpty) {
      setState(() {
        _spec = _history.removeLast();
        _result = null;
      });
      return;
    }
    if (_bytes != null) {
      setState(() {
        _path = null;
        _bytes = null;
        _source = null;
      });
      return;
    }
    if (mounted) {
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final Uint8List? bytes = _bytes;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Crop'),
        actions: <Widget>[
          if (bytes != null)
            TextButton(
              key: const Key('crop-reset'),
              onPressed: _spec.isIdentity ? null : _reset,
              child: const Text('Reset'),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          OutlinedButton.icon(
            key: const Key('crop-pick'),
            onPressed: _pick,
            icon: const Icon(Icons.photo_outlined),
            label: Text(bytes == null ? 'Choose a photo' : 'Choose another'),
          ),
          if (bytes != null) ...<Widget>[
            const SizedBox(height: 16),
            _CropCanvas(
              bytes: bytes,
              source: _source!,
              spec: _spec,
              showGrid: _grid || _straightening,
              fineGrid: _straightening,
              onRect: (NormRect r, bool done) => _edit(_spec.copyWith(rect: r), record: done),
              onDragStart: () => _history.add(_spec),
            ),
            const SizedBox(height: 8),
            Semantics(
              liveRegion: true,
              child: Text(
                _summary(),
                key: const Key('crop-summary'),
                style: text.bodyMedium,
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 16),
            Text('Shape', style: text.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                for (final CropRatio r in CropRatio.values)
                  ChoiceChip(
                    key: Key('crop-ratio-${r.name}'),
                    label: Text(r.label),
                    selected: _spec.ratio == r,
                    materialTapTargetSize: MaterialTapTargetSize.padded,
                    onSelected: (_) => _setRatio(r),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: <Widget>[
                Expanded(child: Text('Straighten ${_spec.angle.round()}°', style: text.titleMedium)),
                IconButton(
                  key: const Key('crop-rotate-left'),
                  tooltip: 'Turn left 90°',
                  onPressed: () => _turn(-1),
                  icon: const Icon(Icons.rotate_left),
                ),
                IconButton(
                  key: const Key('crop-rotate-right'),
                  tooltip: 'Turn right 90°',
                  onPressed: () => _turn(1),
                  icon: const Icon(Icons.rotate_right),
                ),
              ],
            ),
            Row(
              children: <Widget>[
                IconButton(
                  key: const Key('crop-angle-minus'),
                  tooltip: 'One degree left',
                  onPressed: () => _nudgeAngle(-1),
                  icon: const Icon(Icons.remove),
                ),
                Expanded(
                  child: Slider(
                    key: const Key('crop-angle'),
                    value: _spec.angle,
                    min: -45,
                    max: 45,
                    divisions: 90,
                    label: '${_spec.angle.round()}°',
                    semanticFormatterCallback: (double v) => 'Straighten ${v.round()} degrees',
                    onChangeStart: (_) => setState(() {
                      _straightening = true;
                      _history.add(_spec);
                    }),
                    onChanged: (double v) => _edit(_spec.copyWith(angle: v), record: false),
                    onChangeEnd: (_) => setState(() => _straightening = false),
                  ),
                ),
                IconButton(
                  key: const Key('crop-angle-plus'),
                  tooltip: 'One degree right',
                  onPressed: () => _nudgeAngle(1),
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            SwitchListTile(
              key: const Key('crop-grid'),
              title: const Text('Straighten grid'),
              subtitle: const Text('Lines to line up horizons and walls'),
              value: _grid,
              onChanged: (bool v) => setState(() => _grid = v),
            ),
            if (_working) const LinearProgressIndicator(),
          ],
        ],
      ),
      bottomNavigationBar: ResultBar(onShare: _share, onSave: _save, onUndo: _undo),
    );
  }

  String _summary() {
    final PixelSize f = _frame;
    final double s = CropEngine.straightenScale(f.width, f.height, _spec.angle);
    int w = (_spec.rect.width * f.width * s).round();
    int h = (_spec.rect.height * f.height * s).round();
    if (_spec.ratio.isCircle) {
      w = math.min(w, h);
      h = w;
    }
    final String saved = _saved == null ? 'Not saved yet' : 'Saved as ${_saved!.split('/').last}';
    return '${_spec.ratio.label} · $w×$h px · $saved';
  }
}

/// The photo with the crop frame, dimmed outside, and four handles.
class _CropCanvas extends StatefulWidget {
  const _CropCanvas({
    required this.bytes,
    required this.source,
    required this.spec,
    required this.showGrid,
    required this.fineGrid,
    required this.onRect,
    required this.onDragStart,
  });

  final Uint8List bytes;
  final PixelSize source;
  final CropSpec spec;
  final bool showGrid;
  final bool fineGrid;

  /// New rect; `done` is false while a drag is still moving.
  final void Function(NormRect rect, bool done) onRect;
  final VoidCallback onDragStart;

  @override
  State<_CropCanvas> createState() => _CropCanvasState();
}

class _CropCanvasState extends State<_CropCanvas> {
  static const double handle = 48;

  @override
  Widget build(BuildContext context) {
    final PixelSize frame = CropEngine.frame(widget.source, widget.spec.quarterTurns);
    final double scale = CropEngine.straightenScale(frame.width, frame.height, widget.spec.angle);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 420),
      child: Center(
        child: AspectRatio(
          aspectRatio: frame.aspect,
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints c) {
              final double w = c.maxWidth;
              final double h = c.maxHeight;
              final NormRect r = widget.spec.rect;
              final Rect box = Rect.fromLTWH(r.left * w, r.top * h, r.width * w, r.height * h);
              return Stack(
                clipBehavior: Clip.none,
                children: <Widget>[
                  Positioned.fill(
                    child: ClipRect(
                      child: Transform.scale(
                        scale: 1 / scale,
                        child: Transform.rotate(
                          angle: widget.spec.angle * math.pi / 180,
                          child: RotatedBox(
                            quarterTurns: widget.spec.quarterTurns,
                            child: Image.memory(
                              widget.bytes,
                              fit: BoxFit.fill,
                              gaplessPlayback: true,
                              semanticLabel: 'Photo being cropped',
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _FramePainter(
                          box: box,
                          circle: widget.spec.ratio.isCircle,
                          grid: widget.showGrid,
                          fine: widget.fineGrid,
                        ),
                      ),
                    ),
                  ),
                  Positioned.fromRect(
                    rect: box,
                    child: Semantics(
                      label: 'Crop area. Drag to move.',
                      child: GestureDetector(
                        key: const Key('crop-area'),
                        behavior: HitTestBehavior.translucent,
                        dragStartBehavior: DragStartBehavior.down,
                        onPanStart: (_) => widget.onDragStart(),
                        onPanUpdate: (DragUpdateDetails d) =>
                            widget.onRect(CropEngine.move(widget.spec.rect, d.delta.dx / w, d.delta.dy / h), false),
                      ),
                    ),
                  ),
                  for (final CropCorner corner in CropCorner.values)
                    Positioned(
                      // Kept inside the canvas so the whole touch target is hittable.
                      left: ((_isRight(corner) ? box.right : box.left) - handle / 2)
                          .clamp(0.0, math.max(0.0, w - handle))
                          .toDouble(),
                      top: ((_isBottom(corner) ? box.bottom : box.top) - handle / 2)
                          .clamp(0.0, math.max(0.0, h - handle))
                          .toDouble(),
                      width: handle,
                      height: handle,
                      child: Semantics(
                        label: '${_name(corner)} crop handle',
                        child: GestureDetector(
                          key: Key('crop-handle-${corner.name}'),
                          behavior: HitTestBehavior.opaque,
                          // Count the finger's travel from touch-down, so small nudges land.
                          dragStartBehavior: DragStartBehavior.down,
                          onPanStart: (_) => widget.onDragStart(),
                          onPanUpdate: (DragUpdateDetails d) => widget.onRect(
                            CropEngine.dragCorner(
                              widget.spec.rect,
                              corner,
                              d.delta.dx / w,
                              d.delta.dy / h,
                              widget.spec.ratio,
                              frame,
                            ),
                            false,
                          ),
                          child: const Center(child: _HandleDot()),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  static bool _isRight(CropCorner c) => c == CropCorner.topRight || c == CropCorner.bottomRight;
  static bool _isBottom(CropCorner c) => c == CropCorner.bottomLeft || c == CropCorner.bottomRight;

  static String _name(CropCorner c) {
    switch (c) {
      case CropCorner.topLeft:
        return 'Top left';
      case CropCorner.topRight:
        return 'Top right';
      case CropCorner.bottomLeft:
        return 'Bottom left';
      case CropCorner.bottomRight:
        return 'Bottom right';
    }
  }
}

class _HandleDot extends StatelessWidget {
  const _HandleDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: AppColors.surface,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.accent, width: 3),
      ),
    );
  }
}

class _FramePainter extends CustomPainter {
  _FramePainter({required this.box, required this.circle, required this.grid, required this.fine});

  final Rect box;
  final bool circle;
  final bool grid;
  final bool fine;

  @override
  void paint(Canvas canvas, Size size) {
    final Path outside = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size);
    if (circle) {
      final double d = math.min(box.width, box.height);
      outside.addOval(Rect.fromCenter(center: box.center, width: d, height: d));
    } else {
      outside.addRect(box);
    }
    canvas.drawPath(outside, Paint()..color = const Color(0x99000000));

    final Paint edge = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRect(box, edge);

    if (grid) {
      final Paint line = Paint()
        ..color = const Color(0x88FFFFFF)
        ..strokeWidth = 1;
      final int n = fine ? 9 : 3;
      for (int i = 1; i < n; i++) {
        final double x = box.left + box.width * i / n;
        final double y = box.top + box.height * i / n;
        canvas.drawLine(Offset(x, box.top), Offset(x, box.bottom), line);
        canvas.drawLine(Offset(box.left, y), Offset(box.right, y), line);
      }
    }
  }

  @override
  bool shouldRepaint(_FramePainter old) =>
      old.box != box || old.circle != circle || old.grid != grid || old.fine != fine;
}
