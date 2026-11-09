import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../app/theme.dart';
import '../../app/widgets/result_bar.dart';
import '../../engines/pdf/pdf_signer.dart';
import '../../engines/pdf/signature_library.dart';
import '../../engines/share/share_engine.dart';
import '../../platform/pdf_surface.dart';

/// Picks and writes files for Sign PDF. Fakes in tests.
abstract class SignFiles {
  Future<String?> pickPdf();

  Future<String?> pickImage();

  Future<Uint8List> read(String path);

  Future<String> write(String name, Uint8List bytes);

  Future<void> remove(String path);
}

class SystemSignFiles implements SignFiles {
  const SystemSignFiles();

  Future<String?> _pick(List<String> ext) async {
    final FilePickerResult? r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ext);
    return r == null || r.files.isEmpty ? null : r.files.first.path;
  }

  @override
  Future<String?> pickPdf() => _pick(<String>['pdf']);

  @override
  Future<String?> pickImage() => _pick(<String>['png', 'jpg', 'jpeg']);

  @override
  Future<Uint8List> read(String path) => File(path).readAsBytes();

  @override
  Future<String> write(String name, Uint8List bytes) async {
    final Directory base = await getApplicationDocumentsDirectory();
    final Directory dir = Directory('${base.path}/signed');
    await dir.create(recursive: true);
    String path = '${dir.path}/$name';
    int i = 2;
    while (File(path).existsSync()) {
      path = '${dir.path}/${name.replaceAll('.pdf', '')} ($i).pdf';
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

typedef TextStampRenderer = Future<Uint8List> Function(String text, {required bool script});
typedef SignRunner = Future<Uint8List> Function(Uint8List pdf, List<Placement> placements);
typedef PageViewBuilder = Widget Function(BuildContext context, String path, int pageNumber);

/// Renders typed text to a transparent PNG on the phone. The script face is
/// the system's own (Dancing Script on Android, Snell Roundhand on iOS).
Future<Uint8List> renderTextStamp(String text, {required bool script}) async {
  final TextPainter tp = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        fontSize: 96,
        color: const Color(0xFF121840),
        fontFamily: script ? (Platform.isIOS ? 'Snell Roundhand' : 'cursive') : 'Inter',
        fontStyle: script ? FontStyle.italic : FontStyle.normal,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  final ui.PictureRecorder rec = ui.PictureRecorder();
  tp.paint(Canvas(rec), const Offset(8, 8));
  final ui.Image image = await rec.endRecording().toImage(tp.width.ceil() + 16, tp.height.ceil() + 16);
  final ByteData? data = await image.toByteData(format: ui.ImageByteFormat.png);
  if (data == null) {
    throw const SignError('Could not draw the text');
  }
  return data.buffer.asUint8List();
}

Future<Uint8List> signInIsolate(Uint8List pdf, List<Placement> placements) =>
    compute(_signJob, _Job(pdf, placements));

class _Job {
  const _Job(this.pdf, this.placements);
  final Uint8List pdf;
  final List<Placement> placements;
}

Uint8List _signJob(_Job j) => PdfSigner.sign(j.pdf, j.placements);

Widget _pdfrxPage(BuildContext context, String path, int pageNumber) =>
    const PdfrxSurface().thumbnail(context, path, pageNumber);

/// Feature 010 — Sign PDF.
class SignPdfScreen extends StatefulWidget {
  const SignPdfScreen({
    super.key,
    this.files = const SystemSignFiles(),
    this.library,
    this.renderText = renderTextStamp,
    this.runner = signInIsolate,
    this.pageView = _pdfrxPage,
    this.share,
    this.today,
  });

  final SignFiles files;
  final SignatureLibrary? library;
  final TextStampRenderer renderText;
  final SignRunner runner;
  final PageViewBuilder pageView;
  final ShareEngine? share;
  final DateTime Function()? today;

  @override
  State<SignPdfScreen> createState() => _SignPdfScreenState();
}

class _SignPdfScreenState extends State<SignPdfScreen> {
  late final SignatureLibrary _library = widget.library ??
      DirectorySignatureLibrary(() async => Directory('${(await getApplicationDocumentsDirectory()).path}/signatures'));
  List<SavedStamp> _saved = <SavedStamp>[];
  String? _path;
  Uint8List? _pdf;
  List<PageBox> _pages = <PageBox>[];
  int _page = 0;
  final List<Placement> _placements = <Placement>[];
  int? _selected;
  String? _output;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _loadLibrary();
  }

  Future<void> _loadLibrary() async {
    try {
      final List<SavedStamp> list = await _library.list();
      if (mounted) {
        setState(() => _saved = list);
      }
    } catch (_) {
      // No library yet.
    }
  }

  void _toast(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(m)));
    }
  }

  Future<void> _pickPdf() async {
    final String? path = await widget.files.pickPdf();
    if (path == null) {
      return;
    }
    final Uint8List bytes = await widget.files.read(path);
    try {
      final List<PageBox> pages = PdfSigner.pages(bytes);
      setState(() {
        _path = path;
        _pdf = bytes;
        _pages = pages;
        _page = 0;
        _placements.clear();
        _selected = null;
        _output = null;
      });
    } on SignError catch (e) {
      _toast(e.message);
    }
  }

  Future<void> _addToLibrary(StampKind kind, Uint8List png) async {
    final SavedStamp s = await _library.add(kind, png);
    setState(() => _saved = <SavedStamp>[s, ..._saved]);
    _place(png);
  }

  void _place(Uint8List png) {
    if (_pdf == null) {
      _toast('Saved. Choose a PDF to place it.');
      return;
    }
    final PageBox box = _pages[_page];
    final double aspect = SignatureArt.aspect(png);
    const double w = 0.35;
    final double h = math.min(0.9, w * box.width / (aspect * box.height));
    setState(() {
      _placements.add(Placement(page: _page, png: png, left: (1 - w) / 2, top: (1 - h) / 2, width: w, height: h));
      _selected = _placements.length - 1;
      _output = null;
    });
  }

  Future<void> _draw() async {
    final List<List<StrokePoint>>? strokes = await showDialog<List<List<StrokePoint>>>(
      context: context,
      builder: (BuildContext context) => const _DrawDialog(),
    );
    if (strokes == null || strokes.isEmpty) {
      return;
    }
    try {
      await _addToLibrary(StampKind.signature, SignatureArt.fromStrokes(strokes));
    } on SignError catch (e) {
      _toast(e.message);
    }
  }

  Future<void> _type(StampKind kind) async {
    final String? text = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => _TypeDialog(initials: kind == StampKind.initials),
    );
    if (text == null || text.trim().isEmpty) {
      return;
    }
    await _addToLibrary(kind, await widget.renderText(text.trim(), script: true));
  }

  Future<void> _import() async {
    final String? path = await widget.files.pickImage();
    if (path == null) {
      return;
    }
    try {
      await _addToLibrary(StampKind.signature, SignatureArt.fromImport(await widget.files.read(path)));
    } on SignError catch (e) {
      _toast(e.message);
    }
  }

  Future<void> _date() async {
    final DateTime d = (widget.today ?? DateTime.now)();
    final String text =
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
    _place(await widget.renderText(text, script: false));
  }

  void _update(int i, Placement p) {
    setState(() {
      _placements[i] = p;
      _output = null;
    });
  }

  Future<void> _save() async {
    final Uint8List? pdf = _pdf;
    if (pdf == null || _placements.isEmpty) {
      _toast(pdf == null ? 'Choose a PDF first' : 'Place a signature first');
      return;
    }
    if (_working) {
      return;
    }
    setState(() => _working = true);
    try {
      final Uint8List signed = await widget.runner(pdf, List<Placement>.of(_placements));
      final String name = _path!.split('/').last.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '');
      final String out = await widget.files.write('$name-signed.pdf', signed);
      setState(() => _output = out);
      _toast('Signed copy saved in Files › signed. Signatures are flattened into the page.');
    } on SignError catch (e) {
      _toast(e.message);
    } finally {
      if (mounted) {
        setState(() => _working = false);
      }
    }
  }

  Future<void> _share() async {
    if (_output == null) {
      await _save();
    }
    final String? out = _output;
    if (out != null) {
      await (widget.share ?? ShareEngine.instance).shareFiles(<String>[out]);
    }
  }

  Future<void> _undo() async {
    final String? out = _output;
    if (out != null) {
      await widget.files.remove(out);
      setState(() => _output = null);
      _toast('Removed the signed copy');
      return;
    }
    if (_placements.isNotEmpty) {
      setState(() {
        _placements.removeLast();
        _selected = null;
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
    final int? sel = _selected;
    final bool hasSel = sel != null && sel < _placements.length && _placements[sel].page == _page;
    return Scaffold(
      appBar: AppBar(title: const Text('Sign PDF')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          OutlinedButton.icon(
            key: const Key('sign-pick'),
            onPressed: _pickPdf,
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: Text(_pdf == null ? 'Choose a PDF' : 'Choose another'),
          ),
          if (_pdf != null) ...<Widget>[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                IconButton(
                  key: const Key('sign-prev'),
                  tooltip: 'Previous page',
                  onPressed: _page > 0 ? () => setState(() => _page--) : null,
                  icon: const Icon(Icons.chevron_left),
                ),
                Text('Page ${_page + 1} of ${_pages.length}', key: const Key('sign-page')),
                IconButton(
                  key: const Key('sign-next'),
                  tooltip: 'Next page',
                  onPressed: _page < _pages.length - 1 ? () => setState(() => _page++) : null,
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
            _pageCanvas(context),
            if (hasSel) ...<Widget>[
              const SizedBox(height: 8),
              Text('Rotate ${_placements[sel].rotation.round()}°', style: text.titleSmall),
              Slider(
                key: const Key('sign-rotate'),
                value: _placements[sel].rotation,
                min: -180,
                max: 180,
                divisions: 72,
                semanticFormatterCallback: (double v) => 'Rotate ${v.round()} degrees',
                onChanged: (double v) => _update(sel, _placements[sel].copyWith(rotation: v)),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const Key('sign-remove'),
                  onPressed: () => setState(() {
                    _placements.removeAt(sel);
                    _selected = null;
                    _output = null;
                  }),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Remove this stamp'),
                ),
              ),
            ],
          ],
          const SizedBox(height: 16),
          Text('Add', style: text.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              _action('sign-draw', Icons.draw_outlined, 'Draw', _draw),
              _action('sign-type', Icons.keyboard_outlined, 'Type', () => _type(StampKind.signature)),
              _action('sign-import', Icons.image_outlined, 'Import PNG', _import),
              _action('sign-initials', Icons.short_text, 'Initials', () => _type(StampKind.initials)),
              _action('sign-date', Icons.event_outlined, 'Date', _date),
            ],
          ),
          if (_saved.isNotEmpty) ...<Widget>[
            const SizedBox(height: 16),
            Text('Saved signatures', style: text.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                for (final SavedStamp s in _saved)
                  Semantics(
                    button: true,
                    label: 'Place saved ${s.kind == StampKind.initials ? 'initials' : 'signature'}',
                    child: InkWell(
                      key: Key('sign-saved-${s.id}'),
                      onTap: () => _place(s.png),
                      onLongPress: () async {
                        await _library.remove(s.id);
                        await _loadLibrary();
                      },
                      child: Container(
                        width: 120,
                        height: 56,
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          border: Border.all(color: AppColors.line),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Image.memory(s.png, fit: BoxFit.contain, excludeFromSemantics: true),
                      ),
                    ),
                  ),
              ],
            ),
          ],
          if (_working) const Padding(padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator()),
        ],
      ),
      bottomNavigationBar: ResultBar(onShare: _share, onSave: _save, onUndo: _undo),
    );
  }

  Widget _action(String key, IconData icon, String label, VoidCallback onTap) {
    return OutlinedButton.icon(key: Key(key), onPressed: onTap, icon: Icon(icon), label: Text(label));
  }

  Widget _pageCanvas(BuildContext context) {
    final PageBox box = _pages[_page];
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 520),
      child: Center(
        child: AspectRatio(
          aspectRatio: box.width / box.height,
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints c) {
              final double w = c.maxWidth;
              final double h = c.maxHeight;
              return Stack(
                children: <Widget>[
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: AppColors.line)),
                      child: widget.pageView(context, _path!, _page + 1),
                    ),
                  ),
                  for (int i = 0; i < _placements.length; i++)
                    if (_placements[i].page == _page) ..._stamp(i, w, h),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  List<Widget> _stamp(int i, double w, double h) {
    final Placement p = _placements[i];
    final bool selected = _selected == i;
    final Rect r = Rect.fromLTWH(p.left * w, p.top * h, p.width * w, p.height * h);
    const double handle = 48;
    return <Widget>[
      Positioned.fromRect(
        rect: r,
        child: Semantics(
          label: 'Placed stamp ${i + 1}. Drag to move.',
          selected: selected,
          child: GestureDetector(
            key: Key('sign-stamp-$i'),
            dragStartBehavior: DragStartBehavior.down,
            onTap: () => setState(() => _selected = i),
            onPanStart: (_) => setState(() => _selected = i),
            onPanUpdate: (DragUpdateDetails d) {
              final Placement cur = _placements[i];
              _update(
                i,
                cur.copyWith(
                  left: (cur.left + d.delta.dx / w).clamp(0.0, 1 - cur.width).toDouble(),
                  top: (cur.top + d.delta.dy / h).clamp(0.0, 1 - cur.height).toDouble(),
                ),
              );
            },
            child: Transform.rotate(
              angle: p.rotation * math.pi / 180,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: selected ? AppColors.accent : Colors.transparent, width: 2),
                ),
                child: Image.memory(p.png, fit: BoxFit.fill, gaplessPlayback: true, excludeFromSemantics: true),
              ),
            ),
          ),
        ),
      ),
      if (selected)
        Positioned(
          left: (r.right - handle / 2).clamp(0.0, math.max(0.0, w - handle)).toDouble(),
          top: (r.bottom - handle / 2).clamp(0.0, math.max(0.0, h - handle)).toDouble(),
          width: handle,
          height: handle,
          child: Semantics(
            label: 'Resize stamp',
            child: GestureDetector(
              key: Key('sign-resize-$i'),
              behavior: HitTestBehavior.opaque,
              dragStartBehavior: DragStartBehavior.down,
              onPanUpdate: (DragUpdateDetails d) {
                final Placement cur = _placements[i];
                final double ratio = cur.height / cur.width;
                final double nw = (cur.width + d.delta.dx / w).clamp(0.05, 1 - cur.left).toDouble();
                final double nh = math.min(nw * ratio, 1 - cur.top);
                _update(i, cur.copyWith(width: nh / ratio, height: nh));
              },
              child: const Center(
                child: Icon(Icons.open_in_full, size: 20, color: AppColors.accent),
              ),
            ),
          ),
        ),
    ];
  }
}

class _DrawDialog extends StatefulWidget {
  const _DrawDialog();

  @override
  State<_DrawDialog> createState() => _DrawDialogState();
}

class _DrawDialogState extends State<_DrawDialog> {
  final List<List<StrokePoint>> _strokes = <List<StrokePoint>>[];

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Draw your signature'),
      content: SizedBox(
        width: 320,
        height: 128,
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints c) {
            StrokePoint at(Offset o) => StrokePoint(
                  (o.dx / c.maxWidth).clamp(0.0, 1.0).toDouble(),
                  (o.dy / c.maxHeight).clamp(0.0, 1.0).toDouble(),
                );
            return Semantics(
              label: 'Signature pad. Draw with your finger.',
              child: GestureDetector(
                key: const Key('sign-pad'),
                dragStartBehavior: DragStartBehavior.down,
                onPanStart: (DragStartDetails d) => setState(() => _strokes.add(<StrokePoint>[at(d.localPosition)])),
                onPanUpdate: (DragUpdateDetails d) => setState(() => _strokes.last.add(at(d.localPosition))),
                child: CustomPaint(
                  painter: _InkPainter(_strokes),
                  child: Container(
                    decoration: BoxDecoration(border: Border.all(color: AppColors.line)),
                  ),
                ),
              ),
            );
          },
        ),
      ),
      actions: <Widget>[
        TextButton(
          key: const Key('sign-pad-clear'),
          onPressed: () => setState(_strokes.clear),
          child: const Text('Clear'),
        ),
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          key: const Key('sign-pad-done'),
          onPressed: () => Navigator.of(context).pop(_strokes),
          child: const Text('Done'),
        ),
      ],
    );
  }
}

class _InkPainter extends CustomPainter {
  _InkPainter(this.strokes);
  final List<List<StrokePoint>> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint ink = Paint()
      ..color = const Color(0xFF121840)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    for (final List<StrokePoint> s in strokes) {
      final Path path = Path();
      for (int i = 0; i < s.length; i++) {
        final Offset o = Offset(s[i].x * size.width, s[i].y * size.height);
        if (i == 0) {
          path.moveTo(o.dx, o.dy);
        } else {
          path.lineTo(o.dx, o.dy);
        }
      }
      canvas.drawPath(path, ink);
    }
  }

  @override
  bool shouldRepaint(_InkPainter old) => true;
}

class _TypeDialog extends StatefulWidget {
  const _TypeDialog({required this.initials});
  final bool initials;

  @override
  State<_TypeDialog> createState() => _TypeDialogState();
}

class _TypeDialogState extends State<_TypeDialog> {
  final TextEditingController _c = TextEditingController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initials ? 'Your initials' : 'Type your name'),
      content: TextField(
        key: const Key('sign-type-field'),
        controller: _c,
        autofocus: true,
        decoration: InputDecoration(labelText: widget.initials ? 'Initials' : 'Name'),
        onSubmitted: (String v) => Navigator.of(context).pop(v),
      ),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          key: const Key('sign-type-done'),
          onPressed: () => Navigator.of(context).pop(_c.text),
          child: const Text('Use'),
        ),
      ],
    );
  }
}
