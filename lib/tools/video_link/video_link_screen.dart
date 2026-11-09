import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../app/widgets/result_bar.dart';
import '../../engines/download/download_queue.dart';
import '../../engines/download/shared_link.dart';
import '../../engines/download/video_link.dart';
import '../../engines/share/share_engine.dart';

typedef VideoFolderPicker = Future<String?> Function();

Future<String?> _systemFolderPicker() => FilePicker.platform.getDirectoryPath(dialogTitle: 'Save videos to');

/// Feature 123 — Download video from a link. Paste or share a link, pick a
/// quality, and the video is saved to the chosen folder through the queue.
class VideoLinkScreen extends StatefulWidget {
  const VideoLinkScreen({
    super.key,
    this.downloader,
    this.queue,
    this.share,
    this.pickFolder,
    this.inbox,
    this.initialText,
  });

  final VideoLinkDownloader? downloader;
  final DownloadQueue? queue;
  final ShareEngine? share;
  final VideoFolderPicker? pickFolder;
  final SharedLinkInbox? inbox;

  /// Text shared into the app; resolved as soon as the screen opens.
  final String? initialText;

  @override
  State<VideoLinkScreen> createState() => _VideoLinkScreenState();
}

class _VideoLinkScreenState extends State<VideoLinkScreen> {
  final TextEditingController _link = TextEditingController();
  bool _busy = false;
  VideoLink? _video;
  VideoFormat? _choice;
  DownloadTask? _task;
  String? _status;
  String _folder = '';

  VideoLinkDownloader get _d => widget.downloader ?? VideoLinks.instance;
  DownloadQueue get _q => widget.queue ?? DownloadQueue.instance;
  SharedLinkInbox get _inbox => widget.inbox ?? SharedLinkInbox.instance;

  @override
  void initState() {
    super.initState();
    unawaited(_loadFolder());
    final String? shared = widget.initialText ?? _inbox.take();
    if (shared != null) {
      _link.text = shared;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(_find());
        }
      });
    }
  }

  @override
  void dispose() {
    _link.dispose();
    super.dispose();
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

  /// Shows the personal-use notice the first time; false if the person backs out.
  Future<bool> _notice() async {
    if (!await _d.needsNotice()) {
      return true;
    }
    if (!mounted) {
      return false;
    }
    final bool? ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) => AlertDialog(
        key: const Key('video-notice'),
        title: const Text('For personal use'),
        content: const Text(VideoLinkDownloader.personalUseNotice),
        actions: <Widget>[
          TextButton(
            key: const Key('video-notice-cancel'),
            style: TextButton.styleFrom(minimumSize: const Size(64, 48)),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('video-notice-ok'),
            style: FilledButton.styleFrom(minimumSize: const Size(64, 48)),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('I understand'),
          ),
        ],
      ),
    );
    if (ok != true) {
      return false;
    }
    await _d.noticeSeen();
    return true;
  }

  Future<void> _find() async {
    if (_busy) {
      return;
    }
    if (!await _notice() || !mounted) {
      return;
    }
    setState(() {
      _busy = true;
      _status = 'Looking for the video…';
      _video = null;
      _choice = null;
    });
    try {
      final VideoLink v = await _d.resolve(_link.text);
      if (!mounted) {
        return;
      }
      setState(() {
        _video = v;
        _choice = v.best;
        _status = '${v.formats.length} ${v.formats.length == 1 ? 'quality' : 'qualities'} found';
      });
    } on VideoLinkError catch (e) {
      if (mounted) {
        setState(() => _status = e.message);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _download() async {
    final VideoLink? v = _video;
    final VideoFormat? f = _choice;
    if (v == null || f == null) {
      return;
    }
    try {
      final DownloadTask t = await _d.save(_q, v, f);
      if (mounted) {
        setState(() {
          _task = t;
          _status = 'Saving ${t.name} to ${t.folder}';
        });
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
        _status = 'Videos go to $picked';
      });
    }
  }

  Future<void> _share() async {
    final ShareEngine s = widget.share ?? ShareEngine.instance;
    final DownloadTask? t = _task;
    if (t != null && t.state == DownloadState.done) {
      await s.shareFiles(<String>[t.path]);
      return;
    }
    final VideoLink? v = _video;
    if (v == null) {
      setState(() => _status = 'Find a video first');
      return;
    }
    await s.shareText(v.page.toString(), subject: v.title);
  }

  void _undo() {
    final DownloadTask? t = _task;
    if (t == null) {
      Navigator.of(context).maybePop();
      return;
    }
    _q.remove(t.id);
    setState(() {
      _task = null;
      _status = 'Removed ${t.name} from downloads';
    });
  }

  Widget _formats(VideoLink v) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(v.title, key: const Key('video-title'), style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        const Text('Quality'),
        RadioGroup<VideoFormat>(
          groupValue: _choice,
          onChanged: (VideoFormat? f) => setState(() => _choice = f),
          child: Column(children: <Widget>[
            for (int i = 0; i < v.formats.length; i++)
              RadioListTile<VideoFormat>(
                key: Key('video-format-$i'),
                contentPadding: EdgeInsets.zero,
                value: v.formats[i],
                title: Text(v.formats[i].label),
                subtitle: Text(v.formats[i].ext.toUpperCase()),
              ),
          ]),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          key: const Key('video-download'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          onPressed: _download,
          icon: const Icon(Icons.download),
          label: const Text('Download'),
        ),
      ],
    );
  }

  Widget _progress(DownloadTask t) {
    final double? f = t.fraction;
    return Card(
      key: const Key('video-task'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Text(t.name, style: Theme.of(context).textTheme.titleSmall, overflow: TextOverflow.ellipsis),
          Text(t.statusLine, key: const Key('video-task-status')),
          if (t.state != DownloadState.done)
            Padding(
              padding: const EdgeInsets.only(top: 8),
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
    final VideoLink? v = _video;
    return Scaffold(
      appBar: AppBar(title: const Text('Video from a link')),
      body: ListenableBuilder(
        listenable: _q,
        builder: (BuildContext context, Widget? _) {
          final DownloadTask? t = _task == null ? null : _q.byId(_task!.id);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              const Text('Paste or share a link from Instagram, YouTube, Facebook, X, Pinterest or Threads. '
                  'Public posts only; the app reads the page and saves the video to your folder.'),
              const SizedBox(height: 12),
              Row(children: <Widget>[
                Expanded(
                  child: TextField(
                    key: const Key('video-link'),
                    controller: _link,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(labelText: 'Link'),
                    onSubmitted: (_) => _find(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  key: const Key('video-find'),
                  style: FilledButton.styleFrom(minimumSize: const Size(64, 48)),
                  onPressed: _busy ? null : _find,
                  child: const Text('Find'),
                ),
              ]),
              ListTile(
                key: const Key('video-folder'),
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.folder_outlined, semanticLabel: 'Folder'),
                title: const Text('Save to'),
                subtitle: Text(_folder),
                trailing: TextButton(
                  key: const Key('video-change-folder'),
                  style: TextButton.styleFrom(minimumSize: const Size(64, 48)),
                  onPressed: _chooseFolder,
                  child: const Text('Change'),
                ),
              ),
              if (_busy) const LinearProgressIndicator(semanticsLabel: 'Looking for the video'),
              if (v != null) _formats(v),
              if (t != null) _progress(t),
              if (_status != null)
                ListTile(
                  key: const Key('video-note'),
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
