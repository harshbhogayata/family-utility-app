import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../engines/share/save_anywhere.dart';

/// Feature 064 — the save sheet every tool can open from its Save button.
///
/// Opens on the tool's last choice, shows the exact path the file will land
/// at, writes it on Save and returns that path (null when cancelled).
Future<String?> showSaveAnywhereSheet(
  BuildContext context, {
  required SaveAnywhere saver,
  required String toolId,
  required String fileName,
  required Uint8List bytes,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (BuildContext context) => SaveAnywhereSheet(
      saver: saver,
      toolId: toolId,
      fileName: fileName,
      bytes: bytes,
    ),
  );
}

class SaveAnywhereSheet extends StatefulWidget {
  const SaveAnywhereSheet({
    super.key,
    required this.saver,
    required this.toolId,
    required this.fileName,
    required this.bytes,
  });

  final SaveAnywhere saver;
  final String toolId;
  final String fileName;
  final Uint8List bytes;

  @override
  State<SaveAnywhereSheet> createState() => _SaveAnywhereSheetState();
}

class _SaveAnywhereSheetState extends State<SaveAnywhereSheet> {
  late SaveDestination _destination;
  late SaveDestination _last;
  String? _folder;
  String? _preview;
  bool _saving = false;
  int _lookup = 0;

  @override
  void initState() {
    super.initState();
    _last = widget.saver.lastFor(widget.toolId).destination;
    _destination = _last;
    _resolve();
  }

  Future<void> _resolve() async {
    final int run = ++_lookup;
    final String? folder = await widget.saver.folderFor(widget.toolId, _destination);
    final String? preview = folder == null ? null : await widget.saver.finalPath(folder, widget.fileName);
    if (!mounted || run != _lookup) {
      return;
    }
    setState(() {
      _folder = folder;
      _preview = preview;
    });
  }

  Future<void> _choose(SaveDestination d) async {
    setState(() {
      _destination = d;
      _folder = null;
      _preview = null;
    });
    if (d == SaveDestination.custom && await widget.saver.folderFor(widget.toolId, d) == null) {
      await _pickFolder();
      return;
    }
    await _resolve();
  }

  Future<void> _pickFolder() async {
    final String? picked = await widget.saver.pickFolder(widget.toolId);
    if (picked == null || !mounted) {
      return;
    }
    final String preview = await widget.saver.finalPath(picked, widget.fileName);
    if (!mounted) {
      return;
    }
    setState(() {
      _destination = SaveDestination.custom;
      _folder = picked;
      _preview = preview;
    });
  }

  Future<void> _save() async {
    final String? folder = _folder;
    if (folder == null || _saving) {
      return;
    }
    setState(() => _saving = true);
    try {
      final String path = await widget.saver.save(
        toolId: widget.toolId,
        destination: _destination,
        folder: folder,
        name: widget.fileName,
        bytes: widget.bytes,
      );
      if (mounted) {
        Navigator.of(context).pop(path);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text('Could not save: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final String? preview = _preview;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text('Save to', style: text.titleLarge),
            const SizedBox(height: 8),
            RadioGroup<SaveDestination>(
              groupValue: _destination,
              onChanged: (SaveDestination? d) {
                if (d != null) {
                  _choose(d);
                }
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  for (final SaveDestination d in SaveDestination.values)
                    RadioListTile<SaveDestination>(
                      key: Key('save-to-${d.name}'),
                      value: d,
                      title: Text(d == _last ? '${d.label} · last used' : d.label),
                      subtitle: Text(d.hint),
                    ),
                ],
              ),
            ),
            if (_destination == SaveDestination.custom)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const Key('save-pick-folder'),
                  onPressed: _pickFolder,
                  icon: const Icon(Icons.folder_open_outlined),
                  label: Text(_folder == null ? 'Pick a folder' : 'Change folder'),
                ),
              ),
            const SizedBox(height: 8),
            Semantics(
              liveRegion: true,
              label: preview == null ? 'No folder chosen yet' : 'Will save as $preview',
              child: ExcludeSemantics(
                child: Text(
                  preview == null ? 'Pick a folder to see where it goes' : 'Will save as $preview',
                  key: const Key('save-final-path'),
                  style: text.bodyMedium,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton(
                    key: const Key('save-cancel'),
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    key: const Key('save-confirm'),
                    onPressed: _folder == null || _saving ? null : _save,
                    child: Text(_saving ? 'Saving…' : 'Save here'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
