import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../app/theme.dart';
import '../../app/widgets/result_bar.dart';
import '../../engines/platform/batch_everywhere.dart';
import '../../engines/share/share_engine.dart';

/// Picks many files and writes results. Behind an interface so tests need
/// neither the picker nor the disk.
abstract class BatchIo {
  Future<List<BatchInput>> pick(List<String> extensions);

  Future<String> write(BatchOutput output);

  Future<void> remove(String path);
}

class SystemBatchIo implements BatchIo {
  const SystemBatchIo();

  @override
  Future<List<BatchInput>> pick(List<String> extensions) async {
    final FilePickerResult? r = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: extensions,
      allowMultiple: true,
    );
    final List<BatchInput> out = <BatchInput>[];
    for (final PlatformFile f in r?.files ?? <PlatformFile>[]) {
      final String? path = f.path;
      if (path != null) {
        out.add(BatchInput(path, await File(path).readAsBytes()));
      }
    }
    return out;
  }

  @override
  Future<String> write(BatchOutput output) async {
    final Directory base = await getApplicationDocumentsDirectory();
    final Directory dir = Directory('${base.path}/batch');
    await dir.create(recursive: true);
    final String name = output.name;
    final int dot = name.lastIndexOf('.');
    final String stem = dot > 0 ? name.substring(0, dot) : name;
    final String ext = dot > 0 ? name.substring(dot) : '';
    String path = '${dir.path}/$name';
    int i = 2;
    while (File(path).existsSync()) {
      path = '${dir.path}/$stem ($i)$ext';
      i++;
    }
    await File(path).writeAsBytes(output.bytes, flush: true);
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

/// Feature 107 — Batch everywhere. Runs a one-file tool over many files in
/// one background job, groups the results and shares them all at once.
class BatchScreen extends StatefulWidget {
  const BatchScreen({
    super.key,
    this.io = const SystemBatchIo(),
    this.runner,
    this.share,
    this.actions,
  });

  final BatchIo io;
  final BatchRunner? runner;
  final ShareEngine? share;
  final List<BatchAction>? actions;

  @override
  State<BatchScreen> createState() => _BatchScreenState();
}

class _BatchScreenState extends State<BatchScreen> {
  late final List<BatchAction> _actions = widget.actions ?? BatchActions.all;
  late BatchAction _action = _actions.first;
  List<BatchInput> _inputs = <BatchInput>[];
  BatchReport? _report;
  bool _working = false;

  void _toast(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(m)));
    }
  }

  Future<void> _pick() async {
    final List<BatchInput> got = await widget.io.pick(_action.extensions);
    final List<BatchInput> fit = got.where((BatchInput i) => _action.accepts(i.path)).toList();
    if (!mounted) {
      return;
    }
    setState(() => _inputs = fit);
    if (fit.length < got.length) {
      _toast('${got.length - fit.length} skipped: not ${_action.extensions.join(', ').toUpperCase()}');
    }
  }

  Future<void> _run() async {
    if (_inputs.isEmpty) {
      return;
    }
    setState(() => _working = true);
    final BatchRunner runner = widget.runner ?? BatchRunner();
    final BatchReport report = await runner.run(_action.label, _inputs, _action.step, widget.io.write);
    if (!mounted) {
      return;
    }
    setState(() {
      _working = false;
      _report = report;
    });
  }

  Future<void> _shareAll() async {
    final BatchReport? r = _report;
    if (r == null || r.paths.isEmpty) {
      _toast('Nothing to share');
      return;
    }
    await (widget.share ?? ShareEngine.instance).share(r.shareRequest());
  }

  void _save() {
    final int n = _report?.paths.length ?? 0;
    _toast(n == 1 ? 'Saved 1 file in Files › batch' : 'Saved $n files in Files › batch');
  }

  Future<void> _undo() async {
    final BatchReport? r = _report;
    if (r == null) {
      return;
    }
    for (final String p in r.paths) {
      await widget.io.remove(p);
    }
    if (!mounted) {
      return;
    }
    setState(() => _report = null);
    _toast('Removed ${r.paths.length} results');
  }

  @override
  Widget build(BuildContext context) {
    final BatchReport? report = _report;
    return Scaffold(
      appBar: AppBar(title: const Text('Batch')),
      body: report == null ? _setup(context) : _results(context, report),
      bottomNavigationBar: report == null
          ? null
          : ResultBar(onShare: _shareAll, onSave: _save, onUndo: _undo),
    );
  }

  Widget _setup(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Text('Pick one job, then as many files as you like.', style: text.bodyMedium),
        const SizedBox(height: 12),
        for (final BatchAction a in _actions)
          Semantics(
            selected: a == _action,
            button: true,
            label: '${a.label}. ${a.hint}',
            excludeSemantics: true,
            child: Card(
              key: Key('batch-action-${a.id}'),
              child: InkWell(
                borderRadius: BorderRadius.circular(AppRadius.card),
                onTap: _working
                    ? null
                    : () => setState(() {
                          _action = a;
                          _inputs = _inputs.where((BatchInput i) => a.accepts(i.path)).toList();
                        }),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 56),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: Row(
                      children: <Widget>[
                        Icon(a == _action ? Icons.radio_button_checked : Icons.radio_button_unchecked),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(a.label, style: text.titleSmall),
                              Text(a.hint, style: text.bodySmall),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          key: const Key('batch-pick'),
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          onPressed: _working ? null : _pick,
          icon: const Icon(Icons.library_add_outlined),
          label: Text(_inputs.isEmpty ? 'Pick files' : '${_inputs.length} files picked · change'),
        ),
        const SizedBox(height: 8),
        for (final BatchInput i in _inputs)
          ListTile(dense: true, leading: const Icon(Icons.insert_drive_file_outlined), title: Text(i.name)),
        const SizedBox(height: 8),
        if (_working)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Center(child: CircularProgressIndicator(semanticsLabel: 'Working on your files')),
          )
        else
          FilledButton(
            key: const Key('batch-run'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: _inputs.isEmpty ? null : _run,
            child: Text(_inputs.isEmpty ? 'Run' : 'Run on ${_inputs.length} files'),
          ),
      ],
    );
  }

  Widget _results(BuildContext context, BatchReport report) {
    final TextTheme text = Theme.of(context).textTheme;
    return ListView(
      key: const Key('batch-results'),
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Semantics(
          liveRegion: true,
          child: Text(report.summary, key: const Key('batch-summary'), style: text.titleMedium),
        ),
        for (final BatchGroup g in report.groups) ...<Widget>[
          const SizedBox(height: 16),
          Semantics(
            header: true,
            child: Text('${g.title} · ${g.items.length}', key: Key('batch-group-${g.title}'), style: text.titleSmall),
          ),
          for (final BatchItem i in g.items)
            ListTile(
              leading: Icon(i.ok ? Icons.check_circle_outline : Icons.error_outline),
              title: Text(i.ok ? i.outputs.map((BatchOutput o) => o.name).join(', ') : i.input),
              subtitle: Text(i.ok ? 'from ${i.input}' : i.error ?? ''),
            ),
        ],
      ],
    );
  }
}
