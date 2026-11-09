import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../app/theme.dart';
import '../../app/widgets/result_bar.dart';
import '../../engines/archive/archive_engine.dart';
import '../../engines/archive/zip_codec.dart';
import '../../engines/share/share_engine.dart';

/// Picks files from the phone. Behind an interface so tests never open the
/// system picker.
abstract class ArchiveFileChooser {
  Future<String?> pickArchive();
  Future<List<String>> pickFiles();
}

class SystemArchiveFileChooser implements ArchiveFileChooser {
  const SystemArchiveFileChooser();

  @override
  Future<String?> pickArchive() async {
    final FilePickerResult? r = await FilePicker.platform.pickFiles();
    return r?.files.single.path;
  }

  @override
  Future<List<String>> pickFiles() async {
    final FilePickerResult? r = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (r == null) {
      return <String>[];
    }
    return <String>[for (final PlatformFile f in r.files) if (f.path != null) f.path!];
  }
}

/// Feature 029 — Archives. Look inside a ZIP, RAR or 7Z without extracting,
/// extract only what you tick, or make a ZIP with an optional AES password.
class ArchivesScreen extends StatefulWidget {
  const ArchivesScreen({
    super.key,
    this.chooser = const SystemArchiveFileChooser(),
    this.engine,
    this.outputFolder,
    this.share,
  });

  final ArchiveFileChooser chooser;
  final ArchiveEngine? engine;

  /// Where results go; defaults to the app's Files › archives.
  final Future<Directory> Function()? outputFolder;
  final ShareEngine? share;

  @override
  State<ArchivesScreen> createState() => _ArchivesScreenState();
}

class _ArchivesScreenState extends State<ArchivesScreen> {
  late final ArchiveEngine _engine = widget.engine ?? ArchiveEngine();
  final TextEditingController _password = TextEditingController();
  final TextEditingController _zipPassword = TextEditingController();

  OpenedArchive? _archive;
  final Set<String> _selected = <String>{};
  List<String> _toZip = <String>[];

  /// Files written by the last action, for Share and Undo.
  List<String> _results = <String>[];
  String? _status;
  bool _busy = false;

  ShareEngine get _shareEngine => widget.share ?? ShareEngine.instance;

  @override
  void dispose() {
    _password.dispose();
    _zipPassword.dispose();
    super.dispose();
  }

  Future<Directory> _out(String sub) async {
    final Directory base = widget.outputFolder != null
        ? await widget.outputFolder!()
        : Directory('${(await getApplicationDocumentsDirectory()).path}/archives');
    return Directory('${base.path}/$sub');
  }

  void _toast(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(m)));
    }
  }

  String _stem(String path) {
    final String name = path.substring(path.lastIndexOf('/') + 1);
    final int dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }

  Future<void> _openArchive() async {
    final String? path = await widget.chooser.pickArchive();
    if (path == null || !mounted) {
      return;
    }
    try {
      final OpenedArchive a = await _engine.open(path);
      if (!mounted) {
        return;
      }
      setState(() {
        _archive = a;
        _selected
          ..clear()
          ..addAll(a.files.map((ArchiveItem i) => i.path));
        _status = '${a.format.label} · ${a.files.length} ${a.files.length == 1 ? 'file' : 'files'} inside'
            '${a.anyEncrypted ? ' · locked' : ''}';
      });
    } on ArchiveException catch (e) {
      setState(() => _status = e.message);
    } on FileSystemException {
      setState(() => _status = 'That file could not be read.');
    }
  }

  Future<void> _extract() async {
    final OpenedArchive? a = _archive;
    if (a == null || _busy) {
      return;
    }
    if (_selected.isEmpty) {
      _toast('Tick at least one file');
      return;
    }
    setState(() => _busy = true);
    try {
      final Directory dest = await _out('extracted/${_stem(a.path)}');
      final List<String> written = await _engine.extract(
        a,
        dest,
        selected: _selected,
        password: _password.text.isEmpty ? null : _password.text,
      );
      setState(() {
        _results = written;
        _status = 'Extracted ${written.length} ${written.length == 1 ? 'file' : 'files'} to Files › archives › extracted';
      });
    } on ArchiveException catch (e) {
      setState(() => _status = e.message);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _pickForZip() async {
    final List<String> got = await widget.chooser.pickFiles();
    if (!mounted || got.isEmpty) {
      return;
    }
    setState(() => _toZip = got);
  }

  Future<void> _createZip() async {
    if (_toZip.isEmpty || _busy) {
      _toast('Choose files to put in the ZIP');
      return;
    }
    setState(() => _busy = true);
    try {
      final Directory dir = await _out('created');
      final String base = _toZip.length == 1 ? _stem(_toZip.first) : 'Archive';
      String path = '${dir.path}/$base.zip';
      int n = 2;
      while (File(path).existsSync()) {
        path = '${dir.path}/$base ($n).zip';
        n++;
      }
      final bool locked = _zipPassword.text.isNotEmpty;
      final File out = await _engine.createZip(_toZip, File(path),
          password: locked ? _zipPassword.text : null);
      setState(() {
        _results = <String>[out.path];
        _status = 'Made ${out.path.substring(out.path.lastIndexOf('/') + 1)}'
            '${locked ? ', locked with AES-256' : ''}';
      });
    } on FileSystemException {
      setState(() => _status = 'One of the files could not be read.');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _shareResults() async {
    if (_results.isEmpty) {
      _toast('Nothing to share yet');
      return;
    }
    await _shareEngine.shareFiles(_results);
  }

  void _save() {
    if (_results.isEmpty) {
      _toast('Nothing to save yet');
      return;
    }
    _toast('Saved in Files › archives');
  }

  Future<void> _undo() async {
    if (_results.isNotEmpty) {
      final int count = _results.length;
      for (final String p in _results) {
        final File f = File(p);
        if (f.existsSync()) {
          await f.delete();
        }
      }
      setState(() {
        _results = <String>[];
        _status = 'Removed $count ${count == 1 ? 'file' : 'files'}';
      });
      return;
    }
    if (_archive != null || _toZip.isNotEmpty) {
      setState(() {
        _archive = null;
        _toZip = <String>[];
        _selected.clear();
        _status = null;
      });
      return;
    }
    Navigator.of(context).maybePop();
  }

  String _size(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    }
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final OpenedArchive? a = _archive;
    return Scaffold(
      appBar: AppBar(title: const Text('Archives')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text('Open an archive', style: text.titleMedium),
                  const SizedBox(height: 6),
                  Text('ZIP, RAR or 7Z. See what is inside before extracting anything.',
                      style: text.bodyMedium),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    key: const Key('archive-open'),
                    onPressed: _busy ? null : _openArchive,
                    icon: const Icon(Icons.folder_zip_outlined),
                    label: Text(a == null ? 'Choose an archive' : 'Choose another'),
                  ),
                ],
              ),
            ),
          ),
          if (a != null) ...<Widget>[
            const SizedBox(height: 12),
            Card(
              child: Column(
                children: <Widget>[
                  for (final ArchiveItem item in a.files)
                    CheckboxListTile(
                      key: Key('archive-item-${item.path}'),
                      value: _selected.contains(item.path),
                      onChanged: (bool? v) => setState(() {
                        if (v ?? false) {
                          _selected.add(item.path);
                        } else {
                          _selected.remove(item.path);
                        }
                      }),
                      secondary: Icon(
                        item.encrypted ? Icons.lock_outline : Icons.insert_drive_file_outlined,
                        semanticLabel: item.encrypted ? 'Locked file' : 'File',
                      ),
                      title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                        item.path == item.name ? _size(item.size) : '${item.path} · ${_size(item.size)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            ),
            if (a.anyEncrypted) ...<Widget>[
              const SizedBox(height: 12),
              TextField(
                key: const Key('archive-password'),
                controller: _password,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Archive password'),
              ),
            ],
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const Key('archive-extract'),
              onPressed: _busy || _selected.isEmpty ? null : _extract,
              icon: const Icon(Icons.unarchive_outlined),
              label: Text('Extract ${_selected.length} selected'),
            ),
          ],
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text('Make a ZIP', style: text.titleMedium),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    key: const Key('archive-pick-files'),
                    onPressed: _busy ? null : _pickForZip,
                    icon: const Icon(Icons.add),
                    label: Text(_toZip.isEmpty
                        ? 'Choose files'
                        : '${_toZip.length} ${_toZip.length == 1 ? 'file' : 'files'} chosen'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const Key('zip-password'),
                    controller: _zipPassword,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Password (optional)',
                      helperText: 'Locks every file with AES-256',
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    key: const Key('archive-create'),
                    onPressed: _busy || _toZip.isEmpty ? null : _createZip,
                    icon: const Icon(Icons.archive_outlined),
                    label: const Text('Create ZIP'),
                  ),
                ],
              ),
            ),
          ),
          if (_status != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  _status!,
                  key: const Key('archive-status'),
                  style: text.bodyMedium?.copyWith(color: AppColors.ink),
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: ResultBar(onShare: _shareResults, onSave: _save, onUndo: _undo),
    );
  }
}
