import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../app/widgets/result_bar.dart';
import '../../engines/pdf/pdf_compressor.dart';
import '../../engines/pdf/pdf_merger.dart';
import '../../engines/share/share_engine.dart';
import '../pdf_viewer/pdf_viewer_screen.dart';

/// Picks PDFs and keeps the merged file. Behind an interface for tests.
abstract class MergeFiles {
  Future<List<MergeInput>> pick();
  Future<String> write(String name, Uint8List bytes);
  Future<void> remove(String path);
}

class SystemMergeFiles implements MergeFiles {
  const SystemMergeFiles();

  @override
  Future<List<MergeInput>> pick() async {
    final FilePickerResult? r = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: <String>['pdf'],
      allowMultiple: true,
    );
    final List<MergeInput> out = <MergeInput>[];
    for (final PlatformFile f in r?.files ?? const <PlatformFile>[]) {
      final String? p = f.path;
      if (p != null) {
        out.add(MergeInput(f.name, await File(p).readAsBytes()));
      }
    }
    return out;
  }

  @override
  Future<String> write(String name, Uint8List bytes) async {
    final Directory base = await getApplicationDocumentsDirectory();
    final Directory dir = Directory('${base.path}/merged');
    await dir.create(recursive: true);
    String path = '${dir.path}/$name';
    int i = 2;
    while (File(path).existsSync()) {
      path = '${dir.path}/${name.substring(0, name.length - 4)} ($i).pdf';
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

typedef MergeRunner = Future<PdfMergeResult> Function(List<MergeInput> inputs);

Future<PdfMergeResult> mergeInIsolate(List<MergeInput> inputs) => compute(PdfMerger.merge, inputs);

/// Feature 002 — Merge PDF.
class MergePdfScreen extends StatefulWidget {
  const MergePdfScreen({
    super.key,
    this.files = const SystemMergeFiles(),
    this.runner = mergeInIsolate,
    this.share,
    this.openViewer,
  });

  final MergeFiles files;
  final MergeRunner runner;
  final ShareEngine? share;

  /// Opens the result; defaults to the app's PDF viewer.
  final void Function(BuildContext context, String path)? openViewer;

  @override
  State<MergePdfScreen> createState() => _MergePdfScreenState();
}

class _MergePdfScreenState extends State<MergePdfScreen> {
  final List<MergeInput> _inputs = <MergeInput>[];
  String? _saved;
  String? _status;
  bool _working = false;

  void _toast(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(m)));
    }
  }

  Future<void> _add() async {
    final List<MergeInput> picked = await widget.files.pick();
    if (!mounted || picked.isEmpty) {
      return;
    }
    setState(() => _inputs.addAll(picked));
  }

  void _move(int from, int to) {
    if (to < 0 || to >= _inputs.length) {
      return;
    }
    setState(() => _inputs.insert(to, _inputs.removeAt(from)));
  }

  Future<void> _merge() async {
    if (_inputs.length < 2 || _working) {
      return;
    }
    setState(() => _working = true);
    try {
      final PdfMergeResult r = await widget.runner(List<MergeInput>.of(_inputs));
      final String first = _inputs.first.name;
      final String stem = first.toLowerCase().endsWith('.pdf') ? first.substring(0, first.length - 4) : first;
      final String path = await widget.files.write('$stem merged.pdf', r.bytes);
      setState(() {
        _saved = path;
        _status = 'Merged ${_inputs.length} files into ${r.pageCount} pages';
      });
    } on PdfCompressError catch (e) {
      setState(() => _status = e.message);
    } finally {
      if (mounted) {
        setState(() => _working = false);
      }
    }
  }

  void _open() {
    final String? p = _saved;
    if (p == null) {
      return;
    }
    final void Function(BuildContext, String)? open = widget.openViewer;
    if (open != null) {
      open(context, p);
      return;
    }
    Navigator.of(context).push<void>(MaterialPageRoute<void>(builder: (BuildContext _) => PdfViewerScreen(path: p)));
  }

  Future<void> _share() async {
    final String? p = _saved;
    if (p == null) {
      _toast('Merge first');
      return;
    }
    await (widget.share ?? ShareEngine.instance).shareFiles(<String>[p]);
  }

  void _save() => _toast(_saved == null ? 'Nothing to save yet' : 'Saved in Files › merged');

  Future<void> _undo() async {
    final String? p = _saved;
    if (p != null) {
      await widget.files.remove(p);
      setState(() {
        _saved = null;
        _status = 'Removed the merged file';
      });
      return;
    }
    if (_inputs.isNotEmpty) {
      setState(_inputs.clear);
      return;
    }
    if (mounted) {
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Merge PDF')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          OutlinedButton.icon(
            key: const Key('merge-add'),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: _add,
            icon: const Icon(Icons.add),
            label: Text(_inputs.isEmpty ? 'Choose PDFs' : 'Add more PDFs'),
          ),
          const SizedBox(height: 8),
          for (int i = 0; i < _inputs.length; i++)
            Card(
              key: ValueKey<String>('merge-item-$i-${_inputs[i].name}'),
              child: ListTile(
                minVerticalPadding: 12,
                leading: CircleAvatar(child: Text('${i + 1}')),
                title: Text(_inputs[i].name, key: Key('merge-name-$i')),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    IconButton(
                      key: Key('merge-up-$i'),
                      tooltip: 'Move up',
                      onPressed: i == 0 ? null : () => _move(i, i - 1),
                      icon: const Icon(Icons.arrow_upward),
                    ),
                    IconButton(
                      key: Key('merge-down-$i'),
                      tooltip: 'Move down',
                      onPressed: i == _inputs.length - 1 ? null : () => _move(i, i + 1),
                      icon: const Icon(Icons.arrow_downward),
                    ),
                    IconButton(
                      tooltip: 'Remove',
                      onPressed: () => setState(() => _inputs.removeAt(i)),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 12),
          FilledButton(
            key: const Key('merge-run'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: _inputs.length < 2 || _working ? null : _merge,
            child: Text(_inputs.length < 2 ? 'Pick at least two PDFs' : 'Merge ${_inputs.length} PDFs'),
          ),
          if (_status != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Semantics(liveRegion: true, child: Text(_status!, key: const Key('merge-status'), style: text.bodyMedium)),
            ),
          if (_saved != null)
            TextButton.icon(
              key: const Key('merge-open'),
              style: TextButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              onPressed: _open,
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: const Text('Open in the PDF viewer'),
            ),
        ],
      ),
      bottomNavigationBar: ResultBar(onShare: _share, onSave: _save, onUndo: _undo),
    );
  }
}
