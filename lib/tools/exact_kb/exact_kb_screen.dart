import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../app/widgets/result_bar.dart';
import '../../engines/image/exact_kb.dart';
import '../../engines/share/share_engine.dart';
import '../compress_images/compress_images_screen.dart' show ImageFiles, SystemImageFiles;

typedef ExactKbRunner = Future<ExactKbResult> Function(Uint8List input, int kb, int? width, int? height);

Future<ExactKbResult> exactKbDirect(Uint8List input, int kb, int? width, int? height) async =>
    ExactKb.fit(input, kb, width: width, height: height);

/// Feature 035 — Image to exact KB.
class ExactKbScreen extends StatefulWidget {
  const ExactKbScreen({super.key, this.files = const SystemImageFiles(), this.runner = exactKbDirect, this.share});

  final ImageFiles files;
  final ExactKbRunner runner;
  final ShareEngine? share;

  @override
  State<ExactKbScreen> createState() => _ExactKbScreenState();
}

class _ExactKbScreenState extends State<ExactKbScreen> {
  String? _path;
  int _kb = 50;
  bool _mm = false;
  final TextEditingController _custom = TextEditingController();
  final TextEditingController _w = TextEditingController();
  final TextEditingController _h = TextEditingController();
  ExactKbResult? _result;
  String? _saved;
  String? _status;
  bool _working = false;

  @override
  void dispose() {
    _custom.dispose();
    _w.dispose();
    _h.dispose();
    super.dispose();
  }

  int? _dim(TextEditingController c) {
    final double? v = double.tryParse(c.text.trim());
    if (v == null || v <= 0) {
      return null;
    }
    return _mm ? mmToPx(v) : v.round();
  }

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
      _path = p.first;
      _result = null;
      _status = null;
    });
  }

  Future<void> _run() async {
    final String? path = _path;
    if (path == null || _working) {
      return;
    }
    final int kb = int.tryParse(_custom.text.trim()) ?? _kb;
    setState(() => _working = true);
    try {
      final ExactKbResult r = await widget.runner(await widget.files.read(path), kb, _dim(_w), _dim(_h));
      final String name = path.split('/').last;
      final int dot = name.lastIndexOf('.');
      final String stem = dot > 0 ? name.substring(0, dot) : name;
      final String saved = await widget.files.write('$stem-${kb}kb.jpg', r.bytes);
      setState(() {
        _result = r;
        _saved = saved;
        _status = '${(r.bytes.length / 1024).toStringAsFixed(1)} KB of $kb KB · ${r.width} × ${r.height} px';
      });
    } on ExactKbError catch (e) {
      setState(() => _status = e.message);
    } finally {
      if (mounted) {
        setState(() => _working = false);
      }
    }
  }

  Future<void> _share() async {
    final String? s = _saved;
    if (s == null) {
      _toast('Make a copy first');
      return;
    }
    await (widget.share ?? ShareEngine.instance).shareFiles(<String>[s]);
  }

  void _save() => _toast(_saved == null ? 'Nothing to save yet' : 'Saved in Files › compressed');

  Future<void> _undo() async {
    final String? s = _saved;
    if (s == null) {
      Navigator.of(context).maybePop();
      return;
    }
    await widget.files.remove(s);
    setState(() {
      _saved = null;
      _result = null;
      _status = 'Removed the copy';
    });
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ExactKbResult? r = _result;
    return Scaffold(
      appBar: AppBar(title: const Text('Image to exact KB')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          OutlinedButton.icon(
            key: const Key('kb-pick'),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: _pick,
            icon: const Icon(Icons.photo_outlined),
            label: Text(_path == null ? 'Choose a picture' : _path!.split('/').last),
          ),
          const SizedBox(height: 16),
          Text('Size limit', style: text.titleSmall),
          Wrap(
            spacing: 8,
            children: <Widget>[
              for (final int kb in exactKbPresets)
                ChoiceChip(
                  key: Key('kb-$kb'),
                  label: Text('$kb KB'),
                  selected: _kb == kb && _custom.text.isEmpty,
                  onSelected: (_) => setState(() {
                    _kb = kb;
                    _custom.clear();
                  }),
                ),
            ],
          ),
          TextField(
            key: const Key('kb-custom'),
            controller: _custom,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Custom KB'),
            onChanged: (_) => setState(() {}),
          ),
          SwitchListTile(
            key: const Key('kb-mm'),
            value: _mm,
            onChanged: (bool v) => setState(() => _mm = v),
            title: const Text('Size in millimetres (300 dpi)'),
          ),
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  key: const Key('kb-width'),
                  controller: _w,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: 'Width ${_mm ? '(mm)' : '(px)'}, optional'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  key: const Key('kb-height'),
                  controller: _h,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: 'Height ${_mm ? '(mm)' : '(px)'}, optional'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('kb-run'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: _path == null || _working ? null : _run,
            child: const Text('Make it fit'),
          ),
          if (_status != null)
            ListTile(
              key: const Key('kb-result'),
              leading: r != null && r.fits
                  ? const Icon(Icons.check_circle, color: Colors.green, semanticLabel: 'Fits the limit')
                  : const Icon(Icons.info_outline),
              title: Text(r != null && r.fits ? 'Fits the limit' : 'Not done'),
              subtitle: Text(_status!),
            ),
        ],
      ),
      bottomNavigationBar: ResultBar(onShare: _share, onSave: _save, onUndo: _undo),
    );
  }
}
