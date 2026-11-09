import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/widgets/result_bar.dart';
import '../../engines/share/share_engine.dart';
import '../../engines/share/shrink_presets.dart';
import '../../engines/video/video_compressor.dart';
import '../../platform/video_encoder_platform.dart';

class PrefsShrinkPresetStore implements ShrinkPresetStore {
  const PrefsShrinkPresetStore();

  static const String _key = 'shrink_presets_v1';

  @override
  Future<String?> read() async => (await SharedPreferences.getInstance()).getString(_key);

  @override
  Future<void> write(String json) async => (await SharedPreferences.getInstance()).setString(_key, json);
}

/// Picking, reading and writing files, behind an interface for tests.
abstract class ShrinkFiles {
  Future<String?> pick();
  Future<Uint8List> read(String path);
  Future<String> write(String name, Uint8List bytes);
  Future<void> remove(String path);
}

class SystemShrinkFiles implements ShrinkFiles {
  const SystemShrinkFiles();

  @override
  Future<String?> pick() async => (await FilePicker.platform.pickFiles())?.files.single.path;

  @override
  Future<Uint8List> read(String path) => File(path).readAsBytes();

  @override
  Future<String> write(String name, Uint8List bytes) async {
    final Directory dir = Directory('${(await getApplicationDocumentsDirectory()).path}/shrunk');
    await dir.create(recursive: true);
    final int dot = name.lastIndexOf('.');
    String out = '${dir.path}/$name';
    int n = 2;
    while (File(out).existsSync()) {
      out = '${dir.path}/${name.substring(0, dot)} ($n)${name.substring(dot)}';
      n++;
    }
    await File(out).writeAsBytes(bytes, flush: true);
    return out;
  }

  @override
  Future<void> remove(String path) async {
    final File f = File(path);
    if (f.existsSync()) {
      await f.delete();
    }
  }
}

String _size(int bytes) =>
    bytes >= 1000 * 1000 ? '${(bytes / 1000 / 1000).toStringAsFixed(1)} MB' : '${(bytes / 1024).round()} KB';

/// Feature 038 — Shrink-to-send presets.
class ShrinkToSendScreen extends StatefulWidget {
  const ShrinkToSendScreen({super.key, this.presets, this.files = const SystemShrinkFiles(), this.share});

  final ShrinkPresets? presets;
  final ShrinkFiles files;
  final ShareEngine? share;

  @override
  State<ShrinkToSendScreen> createState() => _ShrinkToSendScreenState();
}

class _ShrinkToSendScreenState extends State<ShrinkToSendScreen> {
  late final ShrinkPresets _p = widget.presets ??
      (ShrinkPresets(
        backend: EngineShrinkBackend(VideoCompressor(const PlatformVideoEncoder())),
        store: const PrefsShrinkPresetStore(),
      )..load());
  String? _source;
  ShrinkOutcome? _outcome;
  String? _outPath;
  final List<String> _written = <String>[];
  (ShrinkPreset, int)? _removed;
  bool _editing = false;
  bool _busy = false;
  String? _status;

  String get _name => _source == null ? '' : _source!.substring(_source!.lastIndexOf('/') + 1);

  Future<void> _pick() async {
    final String? p = await widget.files.pick();
    if (p == null || !mounted) {
      return;
    }
    setState(() {
      _source = p;
      _outcome = null;
      _outPath = null;
      _status = null;
    });
  }

  Future<void> _run(ShrinkPreset preset) async {
    final String? src = _source;
    if (src == null) {
      setState(() => _status = 'Pick a file first');
      return;
    }
    setState(() {
      _busy = true;
      _status = 'Shrinking for ${preset.label}…';
    });
    try {
      final ShrinkOutcome o = await _p.run(src, preset, widget.files.read);
      String? path = o.outputPath;
      final Uint8List? bytes = o.bytes;
      if (o.unchanged) {
        path = src;
      } else if (bytes != null) {
        final int dot = _name.lastIndexOf('.');
        final String base = dot > 0 ? _name.substring(0, dot) : _name;
        path = await widget.files.write('$base-small.${o.extension}', bytes);
        _written.add(path);
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _outcome = o;
        _outPath = path;
        _status = o.unchanged
            ? 'Already under ${_size(preset.targetBytes)}; send it as it is'
            : '${_size(o.before)} → ${_size(o.after)}${o.reached ? '' : ' (smallest possible; still over the limit)'}';
      });
    } on ShrinkError catch (e) {
      if (mounted) {
        setState(() => _status = e.message);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _status = 'Could not shrink: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _addPreset() async {
    final ShrinkPreset? made = await showDialog<ShrinkPreset>(
      context: context,
      builder: (BuildContext context) => const _NewPresetDialog(),
    );
    if (made == null) {
      return;
    }
    try {
      await _p.put(made);
      if (mounted) {
        setState(() => _status = 'Added ${made.label}');
      }
    } on ShrinkError catch (e) {
      if (mounted) {
        setState(() => _status = e.message);
      }
    }
  }

  Future<void> _remove(ShrinkPreset preset) async {
    final (ShrinkPreset, int)? r = await _p.remove(preset.id);
    if (mounted) {
      setState(() {
        _removed = r;
        _status = 'Removed ${preset.label}';
      });
    }
  }

  Future<void> _save() async {
    final String? p = _outPath;
    if (p == null) {
      setState(() => _status = 'Shrink a file first');
      return;
    }
    setState(() => _status = 'Saved ${p.substring(p.lastIndexOf('/') + 1)} in Files › shrunk');
  }

  Future<void> _share() async {
    final String? p = _outPath;
    if (p == null) {
      setState(() => _status = 'Shrink a file first');
      return;
    }
    await (widget.share ?? ShareEngine.instance).shareFiles(<String>[p]);
  }

  Future<void> _undo() async {
    final (ShrinkPreset, int)? r = _removed;
    if (r != null) {
      await _p.insert(r.$1, r.$2);
      if (mounted) {
        setState(() {
          _removed = null;
          _status = 'Put back ${r.$1.label}';
        });
      }
      return;
    }
    if (_written.isNotEmpty) {
      final String p = _written.removeLast();
      await widget.files.remove(p);
      if (mounted) {
        setState(() {
          _outcome = null;
          _outPath = null;
          _status = 'Removed ${p.substring(p.lastIndexOf('/') + 1)}';
        });
      }
      return;
    }
    if (mounted) {
      await Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Shrink to send'),
        actions: <Widget>[
          IconButton(
            key: const Key('presets-edit'),
            tooltip: _editing ? 'Done editing' : 'Edit presets',
            onPressed: () => setState(() => _editing = !_editing),
            icon: Icon(_editing ? Icons.check : Icons.edit_outlined),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: _p,
        builder: (BuildContext context, Widget? _) => ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            OutlinedButton.icon(
              key: const Key('shrink-pick'),
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              onPressed: _busy ? null : _pick,
              icon: const Icon(Icons.attach_file),
              label: Text(_source == null ? 'Pick a PDF, picture or video' : _name),
            ),
            const SizedBox(height: 12),
            for (final ShrinkPreset preset in _p.presets)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(children: <Widget>[
                  Expanded(
                    child: FilledButton.tonal(
                      key: Key('preset-${preset.id}'),
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                      onPressed: _busy || _editing ? null : () => _run(preset),
                      child: Text(preset.label),
                    ),
                  ),
                  if (_editing)
                    IconButton(
                      key: Key('preset-delete-${preset.id}'),
                      tooltip: 'Remove ${preset.label}',
                      onPressed: () => _remove(preset),
                      icon: const Icon(Icons.delete_outline),
                    ),
                ]),
              ),
            if (_editing)
              Wrap(spacing: 8, children: <Widget>[
                OutlinedButton.icon(
                  key: const Key('preset-add'),
                  style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
                  onPressed: _addPreset,
                  icon: const Icon(Icons.add),
                  label: const Text('Add preset'),
                ),
                TextButton(
                  key: const Key('preset-reset'),
                  style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                  onPressed: _p.reset,
                  child: const Text('Reset to defaults'),
                ),
              ]),
            if (_busy) const LinearProgressIndicator(semanticsLabel: 'Shrinking'),
            if (_status != null)
              ListTile(
                key: const Key('shrink-status'),
                leading: Icon(_outcome?.reached ?? true ? Icons.info_outline : Icons.warning_amber_outlined, semanticLabel: 'Note'),
                title: Text(_status!),
              ),
          ],
        ),
      ),
      bottomNavigationBar: ResultBar(onShare: _share, onSave: _save, onUndo: _undo),
    );
  }
}

/// Dialog for a new preset. It owns its text fields and disposes them with
/// its own state, so nothing outlives the route.
class _NewPresetDialog extends StatefulWidget {
  const _NewPresetDialog();

  @override
  State<_NewPresetDialog> createState() => _NewPresetDialogState();
}

class _NewPresetDialogState extends State<_NewPresetDialog> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _mb = TextEditingController();
  bool _kb = false;

  @override
  void dispose() {
    _name.dispose();
    _mb.dispose();
    super.dispose();
  }

  void _submit() {
    final double? v = double.tryParse(_mb.text.trim());
    if (v == null || v <= 0 || _name.text.trim().isEmpty) {
      return;
    }
    Navigator.pop(
      context,
      ShrinkPreset(
        id: 'p${DateTime.now().microsecondsSinceEpoch}',
        label: _name.text.trim(),
        targetBytes: _kb ? (v * 1024).round() : (v * 1000 * 1000).round(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New preset'),
      content: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
        TextField(key: const Key('preset-name'), controller: _name, decoration: const InputDecoration(labelText: 'Name')),
        TextField(
          key: const Key('preset-size'),
          controller: _mb,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: _kb ? 'Limit in KB' : 'Limit in MB'),
        ),
        Row(children: <Widget>[
          const Expanded(child: Text('Limit in KB instead of MB')),
          Switch(
            key: const Key('preset-kb'),
            value: _kb,
            onChanged: (bool v) => setState(() => _kb = v),
          ),
        ]),
      ]),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(key: const Key('preset-ok'), onPressed: _submit, child: const Text('Add')),
      ],
    );
  }
}
