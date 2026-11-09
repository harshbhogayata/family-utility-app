import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../app/widgets/result_bar.dart';
import '../../engines/share/cloud_bridge.dart';
import '../../engines/share/share_engine.dart';
import '../../platform/cloud_platform.dart';

/// Feature 063 — Cloud import and save.
class CloudScreen extends StatefulWidget {
  const CloudScreen({super.key, this.bridge, this.readFile, this.share});

  final CloudBridge? bridge;

  /// Reads an imported file back for "save to cloud"; tests pass a fake.
  final Future<Uint8List> Function(String path)? readFile;
  final ShareEngine? share;

  @override
  State<CloudScreen> createState() => _CloudScreenState();
}

class _CloudScreenState extends State<CloudScreen> {
  late final CloudBridge _bridge = widget.bridge ??
      CloudBridge(picker: const SystemDocumentPicker(), sink: const FolderImportSink(), store: const PrefsCloudStore());
  final List<String> _imported = <String>[];
  String? _status;

  @override
  void initState() {
    super.initState();
    _bridge.load().then((_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  String _name(String path) => path.split('/').last;

  Future<void> _import() async {
    final List<String> got = await _bridge.import();
    if (!mounted || got.isEmpty) {
      return;
    }
    setState(() {
      _imported.addAll(got);
      _status = 'Copied ${got.length} file${got.length == 1 ? '' : 's'} into Files › imported';
    });
  }

  Future<void> _saveOut(String path) async {
    final Future<Uint8List> Function(String) read = widget.readFile ?? (String p) => File(p).readAsBytes();
    final String? where = await _bridge.saveToCloud(_name(path), await read(path));
    if (!mounted) {
      return;
    }
    setState(() => _status = where == null ? 'Not saved' : 'Saved ${_name(path)}');
  }

  Future<void> _share() async {
    if (_imported.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Import something first')));
      return;
    }
    await (widget.share ?? ShareEngine.instance).shareFiles(List<String>.of(_imported));
  }

  Future<void> _save() async {
    if (_imported.isNotEmpty) {
      await _saveOut(_imported.last);
    }
  }

  Future<void> _undo() async {
    if (_imported.isEmpty) {
      Navigator.of(context).maybePop();
      return;
    }
    final String last = _imported.removeLast();
    await _bridge.sink.remove(last);
    setState(() => _status = 'Removed ${_name(last)}');
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Cloud import and save')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Text(
            'Google Drive, Dropbox, OneDrive and iCloud show up in the phone\'s own file picker when their apps '
            'are installed. The app never signs in to them; files move only between this phone and the app you pick.',
            style: text.bodyMedium,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const Key('cloud-import'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: _import,
            icon: const Icon(Icons.cloud_download_outlined),
            label: const Text('Import from Drive, Dropbox, OneDrive or iCloud'),
          ),
          const SizedBox(height: 16),
          Text('When a tool saves', style: text.titleSmall),
          SegmentedButton<SaveDefault>(
            key: const Key('cloud-default'),
            segments: const <ButtonSegment<SaveDefault>>[
              ButtonSegment<SaveDefault>(value: SaveDefault.ask, label: Text('Ask')),
              ButtonSegment<SaveDefault>(value: SaveDefault.files, label: Text('Files')),
              ButtonSegment<SaveDefault>(value: SaveDefault.cloud, label: Text('Cloud')),
            ],
            selected: <SaveDefault>{_bridge.saveDefault},
            onSelectionChanged: (Set<SaveDefault> s) async {
              await _bridge.setDefault(s.first);
              if (mounted) {
                setState(() {});
              }
            },
          ),
          if (_bridge.lastSavedTo != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('Last saved to ${_bridge.lastSavedTo}', key: const Key('cloud-last'), style: text.bodySmall),
            ),
          if (_status != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Semantics(liveRegion: true, child: Text(_status!, key: const Key('cloud-status'))),
            ),
          for (final String p in _imported)
            ListTile(
              key: Key('cloud-item-${_name(p)}'),
              minVerticalPadding: 12,
              leading: const Icon(Icons.insert_drive_file_outlined),
              title: Text(_name(p)),
              trailing: IconButton(
                key: Key('cloud-save-${_name(p)}'),
                tooltip: 'Save to cloud',
                onPressed: () => _saveOut(p),
                icon: const Icon(Icons.cloud_upload_outlined),
              ),
            ),
        ],
      ),
      bottomNavigationBar: ResultBar(onShare: _share, onSave: _save, onUndo: _undo),
    );
  }
}
