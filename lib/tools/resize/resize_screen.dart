import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../app/widgets/result_bar.dart';
import '../../engines/image/image_resizer.dart';
import '../../engines/share/share_engine.dart';
import '../compress_images/compress_images_screen.dart' show ImageFiles, SystemImageFiles;

typedef ResizeRunner = Future<ResizeResult> Function(Uint8List input, ResizeSpec spec);

Future<ResizeResult> resizeDirect(Uint8List input, ResizeSpec spec) async => ImageResizer.resize(input, spec);

/// Feature 040 — Resize. Pick one or many pictures; set pixels, percent or
/// a form preset; every picture is resized on the phone.
class ResizeScreen extends StatefulWidget {
  const ResizeScreen({super.key, this.files = const SystemImageFiles(), this.runner = resizeDirect, this.share});

  final ImageFiles files;
  final ResizeRunner runner;
  final ShareEngine? share;

  @override
  State<ResizeScreen> createState() => _ResizeScreenState();
}

class _ResizeScreenState extends State<ResizeScreen> {
  List<String> _paths = <String>[];
  ResizeMode _mode = ResizeMode.preset;
  ResizePreset _preset = resizePresets.first;
  double _percent = 50;
  bool _lock = true;
  final TextEditingController _w = TextEditingController();
  final TextEditingController _h = TextEditingController();
  final List<String> _saved = <String>[];
  String? _status;
  bool _working = false;

  @override
  void dispose() {
    _w.dispose();
    _h.dispose();
    super.dispose();
  }

  ResizeSpec get _spec => switch (_mode) {
        ResizeMode.preset => ResizeSpec.preset(_preset),
        ResizeMode.percent => ResizeSpec.percent(_percent),
        ResizeMode.pixels =>
          ResizeSpec.pixels(width: int.tryParse(_w.text), height: int.tryParse(_h.text), lockAspect: _lock),
      };

  void _toast(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(m)));
    }
  }

  Future<void> _pick() async {
    final List<String> p = await widget.files.pick();
    if (!mounted || p.isEmpty) {
      return;
    }
    setState(() {
      _paths = p;
      _status = '${p.length} picture${p.length == 1 ? '' : 's'} ready';
    });
  }

  Future<void> _resize() async {
    if (_paths.isEmpty || _working) {
      return;
    }
    final ResizeSpec spec = _spec;
    setState(() => _working = true);
    int done = 0;
    String? error;
    for (final String path in _paths) {
      try {
        final ResizeResult r = await widget.runner(await widget.files.read(path), spec);
        final String name = path.split('/').last;
        final int dot = name.lastIndexOf('.');
        final String stem = dot > 0 ? name.substring(0, dot) : name;
        _saved.add(await widget.files.write('$stem ${r.width}x${r.height}.${r.extension}', r.bytes));
        done++;
      } on ResizeError catch (e) {
        error = e.message;
      }
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _working = false;
      _status = error == null ? 'Resized $done picture${done == 1 ? '' : 's'}' : 'Resized $done; $error';
    });
  }

  Future<void> _share() async {
    if (_saved.isEmpty) {
      _toast('Resize something first');
      return;
    }
    await (widget.share ?? ShareEngine.instance).shareFiles(List<String>.of(_saved));
  }

  void _save() => _toast(_saved.isEmpty ? 'Nothing to save yet' : 'Saved in Files › compressed');

  Future<void> _undo() async {
    if (_saved.isEmpty) {
      Navigator.of(context).maybePop();
      return;
    }
    final List<String> gone = List<String>.of(_saved);
    _saved.clear();
    for (final String p in gone) {
      await widget.files.remove(p);
    }
    setState(() => _status = 'Removed ${gone.length} resized picture${gone.length == 1 ? '' : 's'}');
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Resize')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          OutlinedButton.icon(
            key: const Key('resize-pick'),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: _pick,
            icon: const Icon(Icons.photo_library_outlined),
            label: Text(_paths.isEmpty ? 'Choose pictures' : 'Choose others'),
          ),
          const SizedBox(height: 16),
          SegmentedButton<ResizeMode>(
            key: const Key('resize-mode'),
            segments: const <ButtonSegment<ResizeMode>>[
              ButtonSegment<ResizeMode>(value: ResizeMode.preset, label: Text('Presets')),
              ButtonSegment<ResizeMode>(value: ResizeMode.pixels, label: Text('Pixels')),
              ButtonSegment<ResizeMode>(value: ResizeMode.percent, label: Text('Percent')),
            ],
            selected: <ResizeMode>{_mode},
            onSelectionChanged: (Set<ResizeMode> s) => setState(() => _mode = s.first),
          ),
          const SizedBox(height: 12),
          if (_mode == ResizeMode.preset)
            for (final ResizePreset p in resizePresets)
              RadioListTile<ResizePreset>(
                key: Key('resize-preset-${p.id}'),
                value: p,
                // ignore: deprecated_member_use
                groupValue: _preset,
                // ignore: deprecated_member_use
                onChanged: (ResizePreset? v) => setState(() => _preset = v ?? _preset),
                title: Text(p.label),
                subtitle: Text(p.exact ? '${p.width} × ${p.height} px' : 'fits in ${p.width} × ${p.height} px'),
              ),
          if (_mode == ResizeMode.pixels) ...<Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    key: const Key('resize-width'),
                    controller: _w,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Width (px)'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    key: const Key('resize-height'),
                    controller: _h,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Height (px)'),
                  ),
                ),
              ],
            ),
            SwitchListTile(
              key: const Key('resize-lock'),
              value: _lock,
              onChanged: (bool v) => setState(() => _lock = v),
              title: const Text('Keep proportions'),
            ),
          ],
          if (_mode == ResizeMode.percent) ...<Widget>[
            Text('${_percent.round()} %', style: text.titleMedium),
            Slider(
              key: const Key('resize-percent'),
              value: _percent,
              min: 5,
              max: 200,
              divisions: 39,
              label: '${_percent.round()} %',
              semanticFormatterCallback: (double v) => '${v.round()} percent',
              onChanged: (double v) => setState(() => _percent = v),
            ),
          ],
          const SizedBox(height: 12),
          FilledButton(
            key: const Key('resize-run'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: _paths.isEmpty || _working ? null : _resize,
            child: Text(_paths.length > 1 ? 'Resize ${_paths.length} pictures' : 'Resize'),
          ),
          if (_status != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Semantics(
                liveRegion: true,
                child: Text(_status!, key: const Key('resize-status'), style: text.bodyMedium),
              ),
            ),
        ],
      ),
      bottomNavigationBar: ResultBar(onShare: _share, onSave: _save, onUndo: _undo),
    );
  }
}
