import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../app/theme.dart';
import '../../app/widgets/result_bar.dart';
import '../../engines/image/rotate_flip.dart';
import '../../engines/share/share_engine.dart';
import '../compress_images/compress_images_screen.dart' show ImageFiles;

/// Picks pictures (many at once) and saves the turned copies in "rotated".
class RotateImageFiles implements ImageFiles {
  const RotateImageFiles();

  @override
  Future<List<String>> pick() async {
    final FilePickerResult? r = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: <String>['jpg', 'jpeg', 'png', 'webp', 'bmp', 'gif'],
      allowMultiple: true,
    );
    return r == null ? <String>[] : r.files.map((PlatformFile f) => f.path).whereType<String>().toList();
  }

  @override
  Future<Uint8List> read(String path) => File(path).readAsBytes();

  @override
  Future<String> write(String name, Uint8List bytes) async {
    final Directory base = await getApplicationDocumentsDirectory();
    final Directory dir = Directory('${base.path}/rotated');
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

/// Feature 042 — Rotate and flip, one picture or many.
class RotateFlipScreen extends StatefulWidget {
  const RotateFlipScreen({super.key, this.files = const RotateImageFiles(), this.share});

  final ImageFiles files;
  final ShareEngine? share;

  @override
  State<RotateFlipScreen> createState() => _RotateFlipScreenState();
}

class _RotateFlipScreenState extends State<RotateFlipScreen> {
  List<String> _picked = <String>[];
  final List<RotateOp> _ops = <RotateOp>[];
  List<String> _written = <String>[];
  bool _busy = false;
  String? _status;

  void _toast(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(m)));
    }
  }

  Future<void> _pick() async {
    final List<String> p = await widget.files.pick();
    if (p.isNotEmpty && mounted) {
      setState(() {
        _picked = p;
        _ops.clear();
        _written = <String>[];
        _status = null;
      });
    }
  }

  String get _summary {
    final PhotoOrientation o = PhotoOrientation.upright.thenAll(_ops);
    if (o == PhotoOrientation.upright) {
      return 'No change yet';
    }
    final String turn = switch (o.turns) {
      1 => 'turned right',
      2 => 'turned upside down',
      3 => 'turned left',
      _ => '',
    };
    return <String>[if (o.mirror) 'mirrored', if (turn.isNotEmpty) turn].join(', ');
  }

  Future<void> _apply() async {
    setState(() => _busy = true);
    final List<String> out = <String>[];
    int failed = 0;
    for (final String p in _picked) {
      try {
        final RotateResult r = RotateFlip.apply(await widget.files.read(p), List<RotateOp>.of(_ops));
        out.add(await widget.files.write(RotateFlip.outputName(p, r.extension), r.bytes));
      } catch (_) {
        failed++;
      }
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _busy = false;
      _written = out;
      _status = 'Saved ${out.length} ${out.length == 1 ? 'picture' : 'pictures'} in Files › rotated'
          '${failed > 0 ? '; $failed could not be opened' : ''}';
    });
  }

  Future<void> _share() async {
    if (_written.isEmpty) {
      _toast('Turn a picture first');
      return;
    }
    await (widget.share ?? ShareEngine.instance).shareFiles(_written);
  }

  void _save() => _toast(_written.isEmpty ? 'Nothing to save yet' : 'Saved in Files › rotated');

  Future<void> _undo() async {
    if (_written.isEmpty) {
      if (_ops.isNotEmpty) {
        setState(() => _ops.removeLast());
      } else {
        Navigator.of(context).maybePop();
      }
      return;
    }
    for (final String p in _written) {
      await widget.files.remove(p);
    }
    setState(() {
      _written = <String>[];
      _status = 'Removed the turned copies; your originals are untouched';
    });
  }

  Widget _op(String key, IconData icon, String label, RotateOp op) => Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: OutlinedButton(
            key: Key(key),
            style: OutlinedButton.styleFrom(minimumSize: const Size(44, 56)),
            onPressed: _picked.isEmpty || _busy ? null : () => setState(() => _ops.add(op)),
            child: Tooltip(message: label, child: Icon(icon, semanticLabel: label)),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Rotate and flip')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Text(
            'Photos (JPG) are turned without losing quality: only the orientation note inside the file changes. '
            'Other pictures are redrawn as PNG. Nothing leaves this phone.',
            style: text.bodyMedium?.copyWith(color: AppColors.muted),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            key: const Key('rotate-pick'),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: _busy ? null : _pick,
            icon: const Icon(Icons.photo_library_outlined),
            label: Text(_picked.isEmpty
                ? 'Choose pictures'
                : '${_picked.length} ${_picked.length == 1 ? 'picture' : 'pictures'} chosen'),
          ),
          const SizedBox(height: 16),
          Row(
            children: <Widget>[
              _op('rotate-left', Icons.rotate_left, 'Rotate left', RotateOp.left),
              _op('rotate-right', Icons.rotate_right, 'Rotate right', RotateOp.right),
              _op('flip-h', Icons.flip, 'Flip horizontal', RotateOp.flipHorizontal),
              _op('flip-v', Icons.flip_camera_android_outlined, 'Flip vertical', RotateOp.flipVertical),
            ],
          ),
          const SizedBox(height: 12),
          Semantics(
            liveRegion: true,
            child: Text(_summary, key: const Key('rotate-summary'), style: text.titleMedium),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const Key('rotate-apply'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: _picked.isEmpty || _ops.isEmpty || _busy ? null : _apply,
            icon: const Icon(Icons.check),
            label: const Text('Save turned copies'),
          ),
          if (_status != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_status!, key: const Key('rotate-status'), style: text.bodyMedium),
            ),
        ],
      ),
      bottomNavigationBar: ResultBar(onShare: _share, onSave: _save, onUndo: _undo),
    );
  }
}
