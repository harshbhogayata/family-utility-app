import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../app/widgets/result_bar.dart';
import '../../engines/archive/zip_bundle.dart';
import '../../engines/share/share_engine.dart';

/// Picks, reads and writes files for the ZIP tool. Behind an interface so
/// tests need neither the picker nor the disk.
abstract class ZipFiles {
  Future<List<String>> pick();
  Future<Uint8List> read(String path);

  /// Writes the ZIP into Files › zips and returns its path.
  Future<String> write(String name, Uint8List bytes);
  Future<void> remove(String path);
}

class SystemZipFiles implements ZipFiles {
  const SystemZipFiles();

  @override
  Future<List<String>> pick() async {
    final FilePickerResult? r = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (r == null) {
      return <String>[];
    }
    return <String>[for (final PlatformFile f in r.files) if (f.path != null) f.path!];
  }

  @override
  Future<Uint8List> read(String path) => File(path).readAsBytes();

  @override
  Future<String> write(String name, Uint8List bytes) async {
    final Directory dir = Directory('${(await getApplicationDocumentsDirectory()).path}/zips');
    await dir.create(recursive: true);
    String path = '${dir.path}/$name';
    int n = 2;
    while (File(path).existsSync()) {
      path = '${dir.path}/${name.substring(0, name.length - 4)} ($n).zip';
      n++;
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

/// Feature 037 — Zip with optional password.
class ZipScreen extends StatefulWidget {
  const ZipScreen({super.key, this.files = const SystemZipFiles(), this.results, this.share});

  final ZipFiles files;

  /// The app's earlier results; defaults to everything under Files.
  final ResultLibrary? results;
  final ShareEngine? share;

  @override
  State<ZipScreen> createState() => _ZipScreenState();
}

class _ZipScreenState extends State<ZipScreen> {
  final List<BundleItem> _items = <BundleItem>[];
  final TextEditingController _name = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final TextEditingController _confirm = TextEditingController();
  late final ResultLibrary _library = widget.results ??
      const DirectoryResultLibrary(getApplicationDocumentsDirectory);

  List<String>? _available;
  bool _lock = false;
  bool _working = false;
  String? _made;
  String? _status;

  @override
  void dispose() {
    _name.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _toast(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(m)));
    }
  }

  void _add(BundleItem item) {
    if (!_items.contains(item)) {
      _items.add(item);
    }
  }

  Future<void> _pickPhone() async {
    final List<String> got = await widget.files.pick();
    if (!mounted || got.isEmpty) {
      return;
    }
    setState(() {
      for (final String p in got) {
        _add(BundleItem(p));
      }
    });
  }

  Future<void> _showResults() async {
    final List<String> all = await _library.list();
    if (!mounted) {
      return;
    }
    setState(() => _available = all);
  }

  void _toggleResult(String path, bool on) {
    setState(() {
      if (on) {
        _add(BundleItem(path, fromResults: true));
      } else {
        _items.remove(BundleItem(path));
      }
    });
  }

  Future<void> _run() async {
    if (_items.isEmpty || _working) {
      _toast('Choose files to put in the ZIP');
      return;
    }
    if (_lock) {
      final String? problem = ZipBundler.checkPassword(_password.text, _confirm.text);
      if (problem != null) {
        setState(() => _status = problem);
        return;
      }
    }
    setState(() => _working = true);
    try {
      final Uint8List bytes = await ZipBundler().build(
        List<BundleItem>.of(_items),
        widget.files.read,
        password: _lock ? _password.text : null,
      );
      final String path = await widget.files.write(ZipBundler.archiveName(_name.text, _items), bytes);
      if (!mounted) {
        return;
      }
      setState(() {
        _made = path;
        final int n = _items.length;
        _status = 'Made ${path.substring(path.lastIndexOf('/') + 1)} with $n ${n == 1 ? 'file' : 'files'}'
            '${_lock ? ', locked with AES-256' : ''}';
      });
    } on ZipBundleError catch (e) {
      setState(() => _status = e.message);
    } finally {
      if (mounted) {
        setState(() => _working = false);
      }
    }
  }

  Future<void> _share() async {
    final String? made = _made;
    if (made == null) {
      _toast('Make the ZIP first');
      return;
    }
    await (widget.share ?? ShareEngine.instance).shareFiles(<String>[made]);
  }

  void _save() => _toast(_made == null ? 'Nothing to save yet' : 'Saved in Files › zips');

  Future<void> _undo() async {
    final String? made = _made;
    if (made == null) {
      Navigator.of(context).maybePop();
      return;
    }
    await widget.files.remove(made);
    setState(() {
      _made = null;
      _status = 'Removed the ZIP';
    });
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final List<String>? available = _available;
    return Scaffold(
      appBar: AppBar(title: const Text('Zip files')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Row(children: <Widget>[
            Expanded(
              child: OutlinedButton.icon(
                key: const Key('zip-pick'),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                onPressed: _working ? null : _pickPhone,
                icon: const Icon(Icons.folder_open),
                label: const Text('From phone'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                key: const Key('zip-results'),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                onPressed: _working ? null : _showResults,
                icon: const Icon(Icons.history),
                label: const Text('From results'),
              ),
            ),
          ]),
          if (available != null) ...<Widget>[
            const SizedBox(height: 8),
            Text('Results in this app', style: text.titleSmall),
            if (available.isEmpty) const Text('No results yet.'),
            for (final String p in available)
              CheckboxListTile(
                key: Key('zip-result-$p'),
                value: _items.contains(BundleItem(p)),
                title: Text(p.substring(p.lastIndexOf('/') + 1)),
                onChanged: (bool? v) => _toggleResult(p, v ?? false),
              ),
          ],
          const SizedBox(height: 16),
          Text(_items.isEmpty ? 'Nothing chosen yet' : '${_items.length} chosen', style: text.titleSmall),
          for (final BundleItem item in _items)
            ListTile(
              key: Key('zip-item-${item.path}'),
              leading: Icon(item.fromResults ? Icons.history : Icons.insert_drive_file_outlined,
                  semanticLabel: item.fromResults ? 'From results' : 'From phone'),
              title: Text(item.name),
              trailing: IconButton(
                tooltip: 'Remove ${item.name}',
                icon: const Icon(Icons.close),
                onPressed: () => setState(() => _items.remove(item)),
              ),
            ),
          const SizedBox(height: 8),
          TextField(
            key: const Key('zip-name'),
            controller: _name,
            decoration: const InputDecoration(labelText: 'ZIP name (optional)'),
          ),
          SwitchListTile(
            key: const Key('zip-lock'),
            title: const Text('Lock with a password'),
            subtitle: const Text('AES-256. Without the password nobody can open the files.'),
            value: _lock,
            onChanged: (bool v) => setState(() => _lock = v),
          ),
          if (_lock) ...<Widget>[
            TextField(
              key: const Key('zip-password'),
              controller: _password,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Password'),
            ),
            TextField(
              key: const Key('zip-confirm'),
              controller: _confirm,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Type it again'),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('zip-run'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: _items.isEmpty || _working ? null : _run,
            child: const Text('Make ZIP'),
          ),
          if (_status != null)
            ListTile(
              key: const Key('zip-status'),
              leading: Icon(_made == null ? Icons.info_outline : Icons.check_circle,
                  semanticLabel: _made == null ? 'Note' : 'Done'),
              title: Text(_status!),
            ),
        ],
      ),
      bottomNavigationBar: ResultBar(onShare: _share, onSave: _save, onUndo: _undo),
    );
  }
}
