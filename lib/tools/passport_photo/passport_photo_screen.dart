import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../../app/widgets/result_bar.dart';
import '../../engines/image/exact_kb.dart';
import '../../engines/image/passport_photo.dart';
import '../../engines/share/share_engine.dart';
import '../../platform/face_platform.dart';
import '../compress_images/compress_images_screen.dart' show ImageFiles, SystemImageFiles;

/// Plain backgrounds offered for the space around the person.
const List<(String, int)> passportBackgrounds = <(String, int)>[
  ('White', 0xFFFFFF),
  ('Off-white', 0xF2F2EE),
  ('Light blue', 0xDCE9F5),
];

/// Feature 043 — Passport photo maker.
class PassportPhotoScreen extends StatefulWidget {
  const PassportPhotoScreen({
    super.key,
    this.files = const SystemImageFiles(),
    this.faces = const MlKitFaceFinder(),
    this.share,
  });

  final ImageFiles files;
  final FaceFinder faces;
  final ShareEngine? share;

  @override
  State<PassportPhotoScreen> createState() => _PassportPhotoScreenState();
}

class _PassportPhotoScreenState extends State<PassportPhotoScreen> {
  String? _path;
  Uint8List? _input;
  FaceBox? _face;
  int _faceCount = 0;
  String _preset = passportPresets.first.id;
  final TextEditingController _cw = TextEditingController(text: '35');
  final TextEditingController _ch = TextEditingController(text: '45');
  final TextEditingController _kb = TextEditingController(text: '100');
  int _background = passportBackgrounds.first.$2;
  SheetPaper _paper = SheetPaper.r4x6;
  int _copies = 8;
  img.Image? _photo;
  Uint8List? _preview;
  final List<String> _saved = <String>[];
  String? _status;
  bool _working = false;

  @override
  void dispose() {
    _cw.dispose();
    _ch.dispose();
    _kb.dispose();
    super.dispose();
  }

  PassportSpec? get _spec {
    if (_preset != 'custom') {
      return passportPresets.firstWhere((PassportSpec p) => p.id == _preset);
    }
    final double? w = double.tryParse(_cw.text.trim());
    final double? h = double.tryParse(_ch.text.trim());
    if (w == null || h == null) {
      return null;
    }
    return PassportSpec.custom(w, h);
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
    setState(() => _working = true);
    final Uint8List bytes = await widget.files.read(p.first);
    List<FaceBox> faces = <FaceBox>[];
    try {
      faces = await widget.faces.find(p.first);
    } catch (_) {
      faces = <FaceBox>[];
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _path = p.first;
      _input = bytes;
      _face = largestFace(faces);
      _faceCount = faces.length;
      _working = false;
    });
    _render();
  }

  void _render() {
    final Uint8List? input = _input;
    final PassportSpec? spec = _spec;
    if (input == null) {
      return;
    }
    if (spec == null) {
      setState(() => _status = 'Type a width and height in mm');
      return;
    }
    try {
      final img.Image photo = PassportPhoto.render(input, spec, _face, background: _background);
      setState(() {
        _photo = photo;
        _preview = img.encodeJpg(photo, quality: 85);
        _status = _faceCount == 0
            ? 'No face found, so the picture is centred. Use a front-facing photo for a centred head.'
            : _faceCount > 1
                ? 'Found $_faceCount faces; framed the largest. ${spec.widthPx} × ${spec.heightPx} px'
                : 'Head centred and sized for ${spec.label}. ${spec.widthPx} × ${spec.heightPx} px';
      });
    } on PassportError catch (e) {
      setState(() {
        _photo = null;
        _preview = null;
        _status = e.message;
      });
    }
  }

  String get _stem {
    final String name = (_path ?? 'photo').split('/').last;
    final int dot = name.lastIndexOf('.');
    return '${dot > 0 ? name.substring(0, dot) : name}-passport-$_preset';
  }

  Future<void> _saveSingle() async {
    final img.Image? photo = _photo;
    if (photo == null || _working) {
      return;
    }
    final int kb = int.tryParse(_kb.text.trim()) ?? 100;
    setState(() => _working = true);
    try {
      final ExactKbResult r = PassportPhoto.single(photo, kb);
      final String saved = await widget.files.write('$_stem-${kb}kb.jpg', r.bytes);
      setState(() {
        _saved.add(saved);
        _status = 'Photo saved: ${(r.bytes.length / 1024).toStringAsFixed(1)} KB of $kb KB · '
            '${r.width} × ${r.height} px';
      });
    } on PassportError catch (e) {
      setState(() => _status = e.message);
    } finally {
      if (mounted) {
        setState(() => _working = false);
      }
    }
  }

  Future<void> _saveSheet() async {
    final img.Image? photo = _photo;
    if (photo == null || _working) {
      return;
    }
    setState(() => _working = true);
    try {
      final PassportSheet s = PassportPhoto.sheet(photo, _paper, _copies);
      final String paper = _paper == SheetPaper.a4 ? 'a4' : '4x6';
      final String saved = await widget.files.write('$_stem-sheet-$paper.jpg', img.encodeJpg(s.image, quality: 95));
      setState(() {
        _saved.add(saved);
        _status = s.count < _copies
            ? 'Only ${s.count} of $_copies fit on ${_paper.label}; sheet saved for printing at 300 dpi'
            : 'Print sheet saved: ${s.count} copies on ${_paper.label} at 300 dpi';
      });
    } on PassportError catch (e) {
      setState(() => _status = e.message);
    } finally {
      if (mounted) {
        setState(() => _working = false);
      }
    }
  }

  Future<void> _share() async {
    if (_saved.isEmpty) {
      _toast('Save the photo or a sheet first');
      return;
    }
    await (widget.share ?? ShareEngine.instance).shareFiles(<String>[_saved.last]);
  }

  void _save() => _toast(_saved.isEmpty ? 'Nothing to save yet' : 'Saved in Files › compressed');

  Future<void> _undo() async {
    if (_saved.isEmpty) {
      Navigator.of(context).maybePop();
      return;
    }
    final String last = _saved.removeLast();
    await widget.files.remove(last);
    setState(() => _status = 'Removed ${last.split('/').last}');
  }

  Widget _chips<T>(String keyPrefix, List<(String, T)> items, T selected, ValueChanged<T> onPick) {
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: <Widget>[
        for (final (String label, T value) in items)
          ChoiceChip(
            key: Key('$keyPrefix-$value'),
            materialTapTargetSize: MaterialTapTargetSize.padded,
            label: Text(label),
            selected: value == selected,
            onSelected: (_) => onPick(value),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final bool ready = _photo != null && !_working;
    return Scaffold(
      appBar: AppBar(title: const Text('Passport photo')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          OutlinedButton.icon(
            key: const Key('pp-pick'),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: _working ? null : _pick,
            icon: const Icon(Icons.portrait_outlined),
            label: Text(_path == null ? 'Choose a photo of the face' : _path!.split('/').last),
          ),
          const SizedBox(height: 16),
          Text('Country', style: text.titleSmall),
          _chips<String>('pp-preset', <(String, String)>[
            for (final PassportSpec p in passportPresets) (p.label, p.id),
            ('Custom mm', 'custom'),
          ], _preset, (String v) {
            setState(() => _preset = v);
            _render();
          }),
          if (_preset == 'custom')
            Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    key: const Key('pp-custom-w'),
                    controller: _cw,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Width (mm)'),
                    onChanged: (_) => _render(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    key: const Key('pp-custom-h'),
                    controller: _ch,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Height (mm)'),
                    onChanged: (_) => _render(),
                  ),
                ),
              ],
            ),
          const SizedBox(height: 12),
          Text('Background', style: text.titleSmall),
          _chips<int>('pp-bg', passportBackgrounds, _background, (int v) {
            setState(() => _background = v);
            _render();
          }),
          if (_preview != null) ...<Widget>[
            const SizedBox(height: 16),
            Center(
              child: Semantics(
                label: 'Passport photo preview',
                image: true,
                child: Container(
                  key: const Key('pp-preview'),
                  decoration: BoxDecoration(border: Border.all(color: Colors.black26)),
                  child: Image.memory(_preview!, height: 220, gaplessPlayback: true, excludeFromSemantics: true),
                ),
              ),
            ),
          ],
          if (_status != null)
            ListTile(
              key: const Key('pp-status'),
              leading: Icon(
                _face != null ? Icons.face_retouching_natural : Icons.info_outline,
                semanticLabel: _face != null ? 'Face found' : 'Note',
              ),
              title: Text(_status!),
            ),
          const SizedBox(height: 8),
          Text('Single photo', style: text.titleSmall),
          TextField(
            key: const Key('pp-kb'),
            controller: _kb,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Size limit (KB)'),
          ),
          const SizedBox(height: 8),
          FilledButton(
            key: const Key('pp-single'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: ready ? _saveSingle : null,
            child: const Text('Save photo at this size'),
          ),
          const SizedBox(height: 16),
          Text('Print sheet', style: text.titleSmall),
          _chips<SheetPaper>('pp-paper', <(String, SheetPaper)>[
            for (final SheetPaper p in SheetPaper.values) (p.label, p),
          ], _paper, (SheetPaper v) => setState(() => _paper = v)),
          _chips<int>('pp-copies', const <(String, int)>[('6 copies', 6), ('8 copies', 8)], _copies,
              (int v) => setState(() => _copies = v)),
          const SizedBox(height: 8),
          FilledButton.tonal(
            key: const Key('pp-sheet'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: ready ? _saveSheet : null,
            child: const Text('Make print sheet'),
          ),
        ],
      ),
      bottomNavigationBar: ResultBar(onShare: _share, onSave: _save, onUndo: _undo),
    );
  }
}
