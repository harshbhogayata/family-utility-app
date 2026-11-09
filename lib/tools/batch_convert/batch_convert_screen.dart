import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../app/widgets/result_bar.dart';
import '../../engines/convert/batch_convert.dart';
import '../../engines/convert/convert_registry.dart';
import '../../engines/convert/file_kind.dart';
import '../../engines/share/share_engine.dart';
import '../convert_anything/convert_anything_screen.dart';

/// Picks several files. Behind an interface so tests need no picker.
abstract class BatchFileChooser {
  Future<List<BatchFile>> pick();
}

class SystemBatchFileChooser implements BatchFileChooser {
  const SystemBatchFileChooser();

  @override
  Future<List<BatchFile>> pick() async {
    final FilePickerResult? r = await FilePicker.platform.pickFiles(allowMultiple: true);
    final List<BatchFile> out = <BatchFile>[];
    for (final PlatformFile f in r?.files ?? <PlatformFile>[]) {
      final String? path = f.path;
      if (path == null) {
        continue;
      }
      final Uint8List bytes = await File(path).readAsBytes();
      out.add(BatchFile(name: f.name, kind: sniffFileKind(bytes), read: () => File(path).readAsBytes()));
    }
    return out;
  }
}

/// Feature 031 — Batch convert. Pick many files, choose one format, convert
/// them all in one background job with progress per file.
class BatchConvertScreen extends StatefulWidget {
  const BatchConvertScreen({
    super.key,
    this.chooser = const SystemBatchFileChooser(),
    this.sink = const FolderConvertSink(),
    this.converter,
    this.share,
  });

  final BatchFileChooser chooser;
  final ConvertSink sink;
  final BatchConverter? converter;
  final ShareEngine? share;

  @override
  State<BatchConvertScreen> createState() => _BatchConvertScreenState();
}

class _BatchConvertScreenState extends State<BatchConvertScreen> {
  late final BatchConverter _batch = widget.converter ?? BatchConverter();
  FileKind? _target;
  BatchResult? _result;
  String? _status;

  void _toast(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(m)));
    }
  }

  Future<void> _pick() async {
    if (_batch.running) {
      return;
    }
    final List<BatchFile> files = await widget.chooser.pick();
    if (files.isEmpty || !mounted) {
      return;
    }
    _batch.setFiles(files);
    final List<BatchTarget> t = _batch.targets();
    setState(() {
      _result = null;
      _target = t.isEmpty ? null : t.first.kind;
      _status = t.isEmpty ? 'No converter on this phone takes these files yet.' : null;
    });
  }

  Future<void> _run() async {
    final FileKind? target = _target;
    if (target == null || _batch.running) {
      return;
    }
    setState(() {
      _status = 'Converting in the background…';
      _result = null;
    });
    try {
      final BatchResult r = await _batch.run(target, widget.sink.write);
      if (mounted) {
        setState(() {
          _result = r;
          _status = '${r.summary}. Saved in Files › converted';
        });
      }
    } on ConvertException catch (e) {
      if (mounted) {
        setState(() => _status = e.message);
      }
    }
  }

  Future<void> _share() async {
    final List<String> out = _result?.outputs ?? <String>[];
    if (out.isEmpty) {
      _toast('Convert something first');
      return;
    }
    await (widget.share ?? ShareEngine.instance).shareFiles(out);
  }

  void _save() {
    if ((_result?.outputs ?? <String>[]).isEmpty) {
      _toast('Nothing to save yet');
      return;
    }
    _toast('Saved in Files › converted');
  }

  Future<void> _undo() async {
    final BatchResult? r = _result;
    if (r != null && r.outputs.isNotEmpty) {
      for (final String p in r.outputs) {
        await widget.sink.remove(p);
      }
      if (mounted) {
        setState(() {
          _result = null;
          _status = 'Removed ${r.outputs.length} converted ${r.outputs.length == 1 ? 'file' : 'files'}';
        });
      }
      return;
    }
    if (_batch.files.isNotEmpty && !_batch.running) {
      _batch.setFiles(<BatchFile>[]);
      setState(() {
        _target = null;
        _status = null;
      });
      return;
    }
    unawaited(Navigator.of(context).maybePop());
  }

  IconData _icon(BatchItemState s) {
    switch (s) {
      case BatchItemState.waiting:
        return Icons.schedule;
      case BatchItemState.running:
        return Icons.autorenew;
      case BatchItemState.done:
        return Icons.check_circle_outline;
      case BatchItemState.failed:
        return Icons.error_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Batch convert')),
      body: ListenableBuilder(
        listenable: _batch,
        builder: (BuildContext context, Widget? _) {
          final List<BatchFile> files = _batch.files;
          final List<BatchTarget> targets = files.isEmpty ? <BatchTarget>[] : _batch.targets();
          final int finished = files.where((BatchFile f) => f.state == BatchItemState.done || f.state == BatchItemState.failed).length;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              Text(
                files.isEmpty
                    ? 'Pick many files, choose one format, and convert them all at once. Nothing leaves the phone.'
                    : '${files.length} ${files.length == 1 ? 'file' : 'files'} picked',
                style: text.bodyLarge,
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const Key('batch-pick'),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                onPressed: _batch.running ? null : _pick,
                icon: const Icon(Icons.file_open_outlined),
                label: Text(files.isEmpty ? 'Choose files' : 'Choose other files'),
              ),
              if (targets.isNotEmpty) ...<Widget>[
                const SizedBox(height: 16),
                Text('Convert to', style: text.titleSmall),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    for (final BatchTarget t in targets)
                      ChoiceChip(
                        key: Key('batch-target-${t.kind.extension}'),
                        materialTapTargetSize: MaterialTapTargetSize.padded,
                        label: Text(t.count == files.length ? t.label : '${t.label} (${t.count} of ${files.length})'),
                        selected: _target == t.kind,
                        onSelected: _batch.running ? null : (bool _) => setState(() => _target = t.kind),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  key: const Key('batch-run'),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  onPressed: _batch.running || _target == null ? null : _run,
                  icon: const Icon(Icons.play_arrow),
                  label: Text('Convert all to ${_target?.label ?? '…'}'),
                ),
              ],
              if (_batch.running || finished > 0) ...<Widget>[
                const SizedBox(height: 12),
                LinearProgressIndicator(
                  value: files.isEmpty ? 0 : finished / files.length,
                  semanticsLabel: 'Batch progress',
                  semanticsValue: '$finished of ${files.length} files',
                ),
              ],
              if (_status != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(_status!, key: const Key('batch-status'), style: text.bodyMedium),
                  ),
                ),
              const SizedBox(height: 8),
              for (int i = 0; i < files.length; i++)
                ListTile(
                  key: Key('batch-file-$i'),
                  contentPadding: EdgeInsets.zero,
                  minVerticalPadding: 12,
                  leading: Icon(_icon(files[i].state), semanticLabel: files[i].state.name),
                  title: Text(files[i].name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text('${files[i].kind.label} · ${files[i].statusLine}', key: Key('batch-file-status-$i')),
                ),
            ],
          );
        },
      ),
      bottomNavigationBar: ResultBar(onShare: _share, onSave: _save, onUndo: () => unawaited(_undo())),
    );
  }
}
