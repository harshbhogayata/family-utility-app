import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../app/widgets/result_bar.dart';
import '../../engines/download/audio_link.dart';
import '../../engines/download/download_queue.dart';
import '../../engines/download/video_link.dart';
import '../../engines/share/share_engine.dart';

typedef AudioFolderPicker = Future<String?> Function();

Future<String?> _systemFolderPicker() => FilePicker.platform.getDirectoryPath(dialogTitle: 'Save audio to');

/// Feature 124 — Download audio from a link. Paste or share a link, pick
/// the sound, optionally set a start and end, and an M4A (or the site's own
/// sound file) lands in the chosen folder.
class AudioLinkScreen extends StatefulWidget {
  const AudioLinkScreen({
    super.key,
    this.downloader,
    this.queue,
    this.share,
    this.pickFolder,
    this.initialText,
  });

  final AudioLinkDownloader? downloader;
  final DownloadQueue? queue;
  final ShareEngine? share;
  final AudioFolderPicker? pickFolder;
  final String? initialText;

  @override
  State<AudioLinkScreen> createState() => _AudioLinkScreenState();
}

class _AudioLinkScreenState extends State<AudioLinkScreen> {
  final TextEditingController _link = TextEditingController();
  final TextEditingController _start = TextEditingController();
  final TextEditingController _end = TextEditingController();
  bool _busy = false;
  bool _trim = false;
  AudioLink? _audio;
  AudioFormat? _choice;
  DownloadTask? _task;
  String? _saved;
  String? _status;
  String _folder = '';

  AudioLinkDownloader get _d => widget.downloader ?? AudioLinks.instance;
  DownloadQueue get _q => widget.queue ?? DownloadQueue.instance;

  @override
  void initState() {
    super.initState();
    unawaited(_loadFolder());
    final String? shared = widget.initialText;
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
    _start.dispose();
    _end.dispose();
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

  Future<bool> _notice() async {
    if (!await _d.video.needsNotice()) {
      return true;
    }
    if (!mounted) {
      return false;
    }
    final bool? ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) => AlertDialog(
        key: const Key('audio-notice'),
        title: const Text('For personal use'),
        content: const Text(VideoLinkDownloader.personalUseNotice),
        actions: <Widget>[
          TextButton(
            key: const Key('audio-notice-cancel'),
            style: TextButton.styleFrom(minimumSize: const Size(64, 48)),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('audio-notice-ok'),
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
    await _d.video.noticeSeen();
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
      _status = 'Looking for the audio…';
      _audio = null;
      _choice = null;
    });
    try {
      final AudioLink a = await _d.resolve(_link.text);
      if (!mounted) {
        return;
      }
      setState(() {
        _audio = a;
        _choice = a.best;
        _status = a.duration == null ? null : 'Length ${formatClock(a.duration!)}';
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

  TrimRange? _range() {
    if (!_trim) {
      return const TrimRange();
    }
    try {
      final TrimRange r = TrimRange(start: parseClock(_start.text), end: parseClock(_end.text));
      final String? p = r.problem(_audio?.duration);
      if (p != null) {
        setState(() => _status = p);
        return null;
      }
      return r;
    } on FormatException catch (e) {
      setState(() => _status = e.message);
      return null;
    }
  }

  Future<void> _download() async {
    final AudioLink? a = _audio;
    final AudioFormat? f = _choice;
    final TrimRange? trim = _range();
    if (a == null || f == null || trim == null || _busy) {
      return;
    }
    setState(() {
      _busy = true;
      _saved = null;
    });
    try {
      final DownloadTask t = await _d.start(_q, a, f, trim);
      if (mounted) {
        setState(() {
          _task = t;
          _status = 'Downloading…';
        });
      }
      final DownloadTask done = await AudioLinkDownloader.whenDone(_q, t);
      if (f.fromVideo || !trim.isEmpty) {
        if (mounted) {
          setState(() => _status = 'Copying the sound out…');
        }
        _q.remove(done.id);
      }
      final String path = await _d.finish(done, a, f, trim);
      if (mounted) {
        setState(() {
          _saved = path;
          _status = 'Saved ${path.split('/').last}';
        });
      }
    } on VideoLinkError catch (e) {
      if (mounted) {
        setState(() => _status = e.message);
      }
    } on DownloadLinkError catch (e) {
      if (mounted) {
        setState(() => _status = e.message);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
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
        _status = 'Audio goes to $picked';
      });
    }
  }

  Future<void> _share() async {
    final ShareEngine s = widget.share ?? ShareEngine.instance;
    final String? p = _saved;
    if (p != null) {
      await s.shareFiles(<String>[p]);
      return;
    }
    final AudioLink? a = _audio;
    if (a == null) {
      setState(() => _status = 'Find the audio first');
      return;
    }
    await s.shareText(a.page.toString(), subject: a.title);
  }

  Future<void> _undo() async {
    final String? p = _saved;
    final DownloadTask? t = _task;
    if (p == null && t == null) {
      unawaited(Navigator.of(context).maybePop());
      return;
    }
    if (t != null) {
      _q.remove(t.id);
    }
    if (p != null) {
      try {
        await File(p).delete();
      } catch (_) {
        // Already gone.
      }
    }
    if (mounted) {
      setState(() {
        _task = null;
        _saved = null;
        _status = p == null ? 'Download cancelled' : 'Removed ${p.split('/').last}';
      });
    }
  }

  Widget _options(AudioLink a) {
    final AudioFormat? f = _choice;
    final bool canTrim = f != null && f.canTrim;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(a.title, key: const Key('audio-title'), style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        const Text('Sound'),
        RadioGroup<AudioFormat>(
          groupValue: _choice,
          onChanged: (AudioFormat? v) => setState(() => _choice = v),
          child: Column(children: <Widget>[
            for (int i = 0; i < a.formats.length; i++)
              RadioListTile<AudioFormat>(
                key: Key('audio-format-$i'),
                contentPadding: EdgeInsets.zero,
                value: a.formats[i],
                title: Text(a.formats[i].label),
              ),
          ]),
        ),
        SwitchListTile(
          key: const Key('audio-trim'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Trim before saving'),
          subtitle: Text(canTrim ? 'Keep only the part between a start and an end' : 'Not available for this sound file'),
          value: _trim && canTrim,
          onChanged: canTrim ? (bool v) => setState(() => _trim = v) : null,
        ),
        if (_trim && canTrim)
          Row(children: <Widget>[
            Expanded(
              child: TextField(
                key: const Key('audio-start'),
                controller: _start,
                keyboardType: TextInputType.datetime,
                decoration: const InputDecoration(labelText: 'Start (m:ss)', hintText: '0:00'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                key: const Key('audio-end'),
                controller: _end,
                keyboardType: TextInputType.datetime,
                decoration: InputDecoration(
                  labelText: 'End (m:ss)',
                  hintText: a.duration == null ? 'end' : formatClock(a.duration!),
                ),
              ),
            ),
          ]),
        const SizedBox(height: 8),
        FilledButton.icon(
          key: const Key('audio-download'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          onPressed: _busy ? null : _download,
          icon: const Icon(Icons.download),
          label: const Text('Save audio'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final AudioLink? a = _audio;
    return Scaffold(
      appBar: AppBar(title: const Text('Audio from a link')),
      body: ListenableBuilder(
        listenable: _q,
        builder: (BuildContext context, Widget? _) {
          final DownloadTask? t = _task == null ? null : _q.byId(_task!.id);
          final double? frac = t?.fraction;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              const Text('Paste or share a link to a video or a sound file. The app saves only the sound, as M4A, '
                  'or the site\'s own sound file. Public posts only; nothing of yours is uploaded.'),
              const SizedBox(height: 12),
              Row(children: <Widget>[
                Expanded(
                  child: TextField(
                    key: const Key('audio-link'),
                    controller: _link,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(labelText: 'Link'),
                    onSubmitted: (_) => _find(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  key: const Key('audio-find'),
                  style: FilledButton.styleFrom(minimumSize: const Size(64, 48)),
                  onPressed: _busy ? null : _find,
                  child: const Text('Find'),
                ),
              ]),
              ListTile(
                key: const Key('audio-folder'),
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.folder_outlined, semanticLabel: 'Folder'),
                title: const Text('Save to'),
                subtitle: Text(_folder),
                trailing: TextButton(
                  key: const Key('audio-change-folder'),
                  style: TextButton.styleFrom(minimumSize: const Size(64, 48)),
                  onPressed: _chooseFolder,
                  child: const Text('Change'),
                ),
              ),
              if (_busy) LinearProgressIndicator(
                value: t != null && t.state == DownloadState.running ? frac : null,
                semanticsLabel: 'Working',
              ),
              if (a != null) _options(a),
              if (t != null && t.state != DownloadState.done)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(t.statusLine, key: const Key('audio-task-status')),
                ),
              if (_status != null)
                ListTile(
                  key: const Key('audio-note'),
                  leading: const Icon(Icons.info_outline, semanticLabel: 'Note'),
                  title: Text(_status!),
                ),
            ],
          );
        },
      ),
      bottomNavigationBar: ResultBar(
        onShare: _share,
        onSave: _chooseFolder,
        onUndo: () => unawaited(_undo()),
        saveLabel: 'Save to…',
      ),
    );
  }
}
