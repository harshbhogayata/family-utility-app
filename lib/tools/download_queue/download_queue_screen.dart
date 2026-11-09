import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../app/widgets/result_bar.dart';
import '../../engines/download/download_queue.dart';
import '../../engines/share/share_engine.dart';

/// Asks the system for a folder; null when the person cancels.
typedef FolderPicker = Future<String?> Function();

Future<String?> _systemFolderPicker() => FilePicker.platform.getDirectoryPath(dialogTitle: 'Save downloads to');

/// Feature 127 — Download queue: links in, files out, with pause, resume and
/// retry per file. Waiting downloads go again when the app comes back.
class DownloadQueueScreen extends StatefulWidget {
  const DownloadQueueScreen({super.key, this.queue, this.share, this.pickFolder});

  final DownloadQueue? queue;
  final ShareEngine? share;
  final FolderPicker? pickFolder;

  @override
  State<DownloadQueueScreen> createState() => _DownloadQueueScreenState();
}

class _DownloadQueueScreenState extends State<DownloadQueueScreen> with WidgetsBindingObserver {
  final TextEditingController _link = TextEditingController();
  (DownloadTask, int)? _removed;
  String? _status;
  String _folder = '';

  DownloadQueue get _q => widget.queue ?? DownloadQueue.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_loadFolder());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _link.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _q.reconnected();
    }
  }

  Future<void> _loadFolder() async {
    String f;
    try {
      f = await _q.folder();
    } catch (_) {
      f = 'Not available on this device';
    }
    if (mounted) {
      setState(() => _folder = f);
    }
  }

  Future<void> _add() async {
    try {
      final DownloadTask t = await _q.add(_link.text);
      _link.clear();
      if (mounted) {
        setState(() => _status = 'Added ${t.name}');
      }
    } on DownloadLinkError catch (e) {
      if (mounted) {
        setState(() => _status = e.message);
      }
    }
  }

  Future<void> _chooseFolder() async {
    final String? picked = await (widget.pickFolder ?? _systemFolderPicker)();
    if (picked == null) {
      return;
    }
    await _q.setFolder(picked);
    if (mounted) {
      setState(() {
        _folder = picked;
        _status = 'New downloads go to $picked';
      });
    }
  }

  Future<void> _share() async {
    final List<String> paths = _q.done.map((DownloadTask t) => t.path).toList();
    if (paths.isEmpty) {
      setState(() => _status = 'No finished download to share yet');
      return;
    }
    await (widget.share ?? ShareEngine.instance).shareFiles(paths);
  }

  void _remove(DownloadTask t) {
    final (DownloadTask, int)? r = _q.remove(t.id);
    setState(() {
      _removed = r;
      _status = 'Removed ${t.name}';
    });
  }

  void _undo() {
    final (DownloadTask, int)? r = _removed;
    if (r == null) {
      Navigator.of(context).maybePop();
      return;
    }
    _q.restore(r);
    setState(() {
      _removed = null;
      _status = 'Put back ${r.$1.name}';
    });
  }

  IconData _icon(DownloadState s) {
    switch (s) {
      case DownloadState.queued:
        return Icons.schedule;
      case DownloadState.running:
        return Icons.downloading;
      case DownloadState.paused:
        return Icons.pause_circle_outline;
      case DownloadState.waiting:
        return Icons.wifi_off;
      case DownloadState.done:
        return Icons.check_circle_outline;
      case DownloadState.failed:
        return Icons.error_outline;
    }
  }

  Widget? _action(DownloadTask t) {
    switch (t.state) {
      case DownloadState.queued:
      case DownloadState.running:
      case DownloadState.waiting:
        return IconButton(
          key: Key('dl-pause-${t.id}'),
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          tooltip: 'Pause ${t.name}',
          icon: const Icon(Icons.pause),
          onPressed: () => _q.pause(t.id),
        );
      case DownloadState.paused:
        return IconButton(
          key: Key('dl-resume-${t.id}'),
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          tooltip: 'Resume ${t.name}',
          icon: const Icon(Icons.play_arrow),
          onPressed: () => _q.resume(t.id),
        );
      case DownloadState.failed:
        return IconButton(
          key: Key('dl-retry-${t.id}'),
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          tooltip: 'Retry ${t.name}',
          icon: const Icon(Icons.refresh),
          onPressed: () => _q.retry(t.id),
        );
      case DownloadState.done:
        return null;
    }
  }

  Widget _tile(DownloadTask t) {
    final double? f = t.fraction;
    final Widget? action = _action(t);
    return Card(
      key: Key('dl-${t.id}'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 4, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Row(children: <Widget>[
            Icon(_icon(t.state), semanticLabel: t.state.name),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                Text(t.name, style: Theme.of(context).textTheme.titleSmall, overflow: TextOverflow.ellipsis),
                Text(t.statusLine, key: Key('dl-status-${t.id}')),
              ]),
            ),
            if (action != null) action,
            IconButton(
              key: Key('dl-remove-${t.id}'),
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              tooltip: 'Remove ${t.name}',
              icon: const Icon(Icons.close),
              onPressed: () => _remove(t),
            ),
          ]),
          if (t.state != DownloadState.done)
            Padding(
              padding: const EdgeInsets.only(top: 8, right: 12),
              child: LinearProgressIndicator(
                value: t.state == DownloadState.running ? f : (f ?? 0),
                semanticsLabel: '${t.name} progress',
                semanticsValue: f == null ? 'unknown' : '${(f * 100).round()}%',
              ),
            ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Download queue')),
      body: ListenableBuilder(
        listenable: _q,
        builder: (BuildContext context, Widget? _) {
          final List<DownloadTask> all = _q.tasks;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              const Text('Paste links to fetch. Downloads keep going in the background, pause and resume, '
                  'and pick up where they stopped when the connection comes back. Nothing of yours is uploaded.'),
              const SizedBox(height: 12),
              Row(children: <Widget>[
                Expanded(
                  child: TextField(
                    key: const Key('dl-link'),
                    controller: _link,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(labelText: 'Link'),
                    onSubmitted: (_) => _add(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  key: const Key('dl-add'),
                  style: FilledButton.styleFrom(minimumSize: const Size(64, 48)),
                  onPressed: _add,
                  child: const Text('Add'),
                ),
              ]),
              ListTile(
                key: const Key('dl-folder'),
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.folder_outlined, semanticLabel: 'Folder'),
                title: const Text('Save to'),
                subtitle: Text(_folder),
              ),
              if (all.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Center(child: Text('No downloads yet', key: Key('dl-empty'))),
                ),
              for (final DownloadTask t in all) _tile(t),
              if (_status != null)
                ListTile(
                  key: const Key('dl-note'),
                  leading: const Icon(Icons.info_outline, semanticLabel: 'Note'),
                  title: Text(_status!),
                ),
            ],
          );
        },
      ),
      bottomNavigationBar: ResultBar(onShare: _share, onSave: _chooseFolder, onUndo: _undo, saveLabel: 'Save to…'),
    );
  }
}
