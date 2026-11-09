import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../app/widgets/result_bar.dart';
import '../../engines/share/message_history.dart';
import '../../engines/share/share_engine.dart';

/// Writes an exported history into Files › message history; returns the path.
typedef TextSaver = Future<String> Function(String name, String text);

Future<Directory> _historyRoot() async {
  final Directory docs = await getApplicationDocumentsDirectory();
  return Directory('${docs.path}/message_history');
}

Future<String> _saveToFiles(String name, String text) async {
  final Directory docs = await getApplicationDocumentsDirectory();
  final Directory dir = Directory('${docs.path}/message history');
  await dir.create(recursive: true);
  final File f = File('${dir.path}/$name');
  await f.writeAsString(text, flush: true);
  return f.path;
}

/// Feature 129 — Recover deleted messages.
class DeletedMessagesScreen extends StatefulWidget {
  const DeletedMessagesScreen({
    super.key,
    this.history,
    this.media,
    this.platform = const PhoneListenerPlatform(),
    this.share,
    this.saveText,
    this.now,
  });

  final MessageHistory? history;
  final MediaRescue? media;
  final ListenerPlatform platform;
  final ShareEngine? share;
  final TextSaver? saveText;
  final DateTime Function()? now;

  @override
  State<DeletedMessagesScreen> createState() => _DeletedMessagesScreenState();
}

enum _View { messages, media }

class _DeletedMessagesScreenState extends State<DeletedMessagesScreen> {
  MessageHistory? _history;
  ListenerAccess? _access;
  bool _on = false;
  bool _mediaOn = false;
  bool _loading = true;
  bool _onlyDeleted = true;
  _View _view = _View.messages;
  List<HistoryMessage> _messages = <HistoryMessage>[];
  List<RescuedMedia> _files = <RescuedMedia>[];
  String? _status;

  /// What Undo puts back: the last saved file, or messages just removed.
  String? _savedPath;
  List<HistoryMessage>? _beforeClear;

  DateTime get _now => (widget.now ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    MessageHistory h = widget.history ?? MessageHistory(MemoryHistoryStore());
    MediaRescue? m = widget.media;
    if (widget.history == null || m == null) {
      try {
        final Directory root = await _historyRoot();
        if (widget.history == null) {
          h = MessageHistory(FolderHistoryStore(root));
        }
        m ??= MediaRescue(PhoneMediaFolders(root));
      } catch (_) {
        // No app folder (tests without a platform): an empty history.
      }
    }
    _history = h;
    final ListenerAccess a = await widget.platform.access();
    final bool on = await h.isOn();
    final bool mediaOn = await h.mediaOn();
    List<HistoryMessage> msgs = <HistoryMessage>[];
    List<RescuedMedia> files = <RescuedMedia>[];
    if (a != ListenerAccess.unsupported) {
      msgs = await h.refresh(now: _now);
      if (m != null) {
        if (on && mediaOn) {
          await m.rescueNew(now: _now);
        }
        files = await m.list();
      }
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _access = a;
      _on = on;
      _mediaOn = mediaOn;
      _messages = msgs;
      _files = files;
      _loading = false;
    });
  }

  void _toast(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(m)));
    }
  }

  Future<void> _setOn(bool on) async {
    await _history?.setOn(on);
    if (on && _access == ListenerAccess.needsGrant) {
      await widget.platform.openSettings();
    }
    await _load();
    if (!mounted) {
      return;
    }
    setState(() => _status = on ? 'Message history is on. New WhatsApp messages are kept on this phone.' : 'Message history is off. Nothing new is kept.');
  }

  Future<void> _setMediaOn(bool on) async {
    await _history?.setMediaOn(on);
    await _load();
  }

  List<HistoryMessage> get _shown =>
      _onlyDeleted ? _messages.where((HistoryMessage m) => m.deleted).toList() : _messages;

  String _fileName() {
    final DateTime t = _now;
    String two(int v) => v.toString().padLeft(2, '0');
    return 'Messages ${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}.${two(t.minute)}.txt';
  }

  Future<String?> _save() async {
    if (_view == _View.media) {
      _toast('Kept media is already in Files › message_history › media');
      return null;
    }
    final List<HistoryMessage> shown = _shown;
    if (shown.isEmpty) {
      _toast('No messages to save yet');
      return null;
    }
    final String path = await (widget.saveText ?? _saveToFiles)(_fileName(), exportText(shown));
    setState(() {
      _savedPath = path;
      _beforeClear = null;
      _status = 'Saved ${shown.length} message${shown.length == 1 ? '' : 's'} to Files › message history';
    });
    return path;
  }

  Future<void> _share() async {
    final ShareEngine share = widget.share ?? ShareEngine.instance;
    if (_view == _View.media) {
      final List<String> paths = <String>[
        for (final RescuedMedia r in _files)
          if (!_onlyDeleted || r.originalGone) r.file.path,
      ];
      if (paths.isEmpty) {
        _toast('No kept media to share');
        return;
      }
      await share.shareFiles(paths);
      return;
    }
    final String? path = _savedPath ?? await _save();
    if (path != null) {
      await share.shareFiles(<String>[path]);
    }
  }

  Future<void> _clear() async {
    final List<HistoryMessage> before = List<HistoryMessage>.of(_messages);
    final List<HistoryMessage> after = _onlyDeleted ? _messages.where((HistoryMessage m) => !m.deleted).toList() : <HistoryMessage>[];
    await _history?.replaceAll(after);
    setState(() {
      _beforeClear = before;
      _savedPath = null;
      _messages = after;
      _status = 'Removed ${before.length - after.length} message${before.length - after.length == 1 ? '' : 's'}';
    });
  }

  Future<void> _undo() async {
    final List<HistoryMessage>? before = _beforeClear;
    if (before != null) {
      await _history?.replaceAll(before);
      setState(() {
        _beforeClear = null;
        _messages = before;
        _status = 'Messages put back';
      });
      return;
    }
    final String? saved = _savedPath;
    if (saved != null) {
      final File f = File(saved);
      if (f.existsSync()) {
        await f.delete();
      }
      setState(() {
        _savedPath = null;
        _status = 'Removed the saved file';
      });
      return;
    }
    if (mounted) {
      await Navigator.of(context).maybePop();
    }
  }

  Widget _message(String text, {Widget? action}) => ListView(
        padding: const EdgeInsets.all(24),
        children: <Widget>[
          Text(text, key: const Key('history-message'), style: Theme.of(context).textTheme.bodyLarge),
          if (action != null) ...<Widget>[const SizedBox(height: 16), action],
        ],
      );

  Widget _switches() {
    return Column(
      children: <Widget>[
        SwitchListTile(
          key: const Key('history-on'),
          title: const Text('Keep WhatsApp messages'),
          subtitle: const Text('Reads message notifications and keeps them on this phone'),
          value: _on,
          onChanged: _setOn,
        ),
        SwitchListTile(
          key: const Key('history-media'),
          title: const Text('Also keep photos, videos and voice notes'),
          subtitle: const Text('Copies new WhatsApp media into the app as it arrives'),
          value: _mediaOn,
          onChanged: _on ? _setMediaOn : null,
        ),
        if (_on && _access == ListenerAccess.needsGrant)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: FilledButton.icon(
              key: const Key('history-allow'),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              onPressed: () async {
                await widget.platform.openSettings();
                await _load();
              },
              icon: const Icon(Icons.notifications_active_outlined),
              label: const Text('Allow notification access'),
            ),
          ),
      ],
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_access == ListenerAccess.unsupported) {
      return _message('This phone does not let apps read other apps’ notifications, so deleted messages '
          'cannot be kept here. On Android it works once you turn it on.');
    }
    if (!_on && _messages.isEmpty && _files.isEmpty) {
      return ListView(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
            child: Text(
              'Off until you turn it on. When it is on, the app keeps a copy of WhatsApp message '
              'notifications, so a message the sender deletes can still be read here. Everything stays '
              'on this phone and is removed after 30 days. Lock this tool from App lock to keep it private.',
              key: const Key('history-message'),
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
          _switches(),
        ],
      );
    }
    final List<Widget> rows = <Widget>[
      _switches(),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            SegmentedButton<_View>(
              segments: const <ButtonSegment<_View>>[
                ButtonSegment<_View>(value: _View.messages, label: Text('Messages'), icon: Icon(Icons.chat_outlined)),
                ButtonSegment<_View>(value: _View.media, label: Text('Media'), icon: Icon(Icons.perm_media_outlined)),
              ],
              selected: <_View>{_view},
              onSelectionChanged: (Set<_View> s) => setState(() => _view = s.first),
            ),
            FilterChip(
              key: const Key('history-only-deleted'),
              label: const Text('Only deleted'),
              selected: _onlyDeleted,
              onSelected: (bool v) => setState(() => _onlyDeleted = v),
            ),
          ],
        ),
      ),
      if (_status != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Semantics(liveRegion: true, child: Text(_status!, key: const Key('history-status'))),
        ),
    ];
    if (_view == _View.messages) {
      final List<HistoryMessage> shown = _shown;
      if (shown.isEmpty) {
        rows.add(Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _onlyDeleted ? 'No deleted messages yet.' : 'No messages kept yet.',
            key: const Key('history-empty'),
          ),
        ));
      } else {
        rows.add(Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            key: const Key('history-clear'),
            style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
            onPressed: _clear,
            icon: const Icon(Icons.delete_outline),
            label: Text(_onlyDeleted ? 'Remove deleted' : 'Remove all'),
          ),
        ));
        for (final HistoryMessage m in shown) {
          rows.add(_messageTile(m));
        }
      }
    } else {
      final List<RescuedMedia> shown = <RescuedMedia>[
        for (final RescuedMedia r in _files)
          if (!_onlyDeleted || r.originalGone) r,
      ];
      if (shown.isEmpty) {
        rows.add(Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _mediaOn ? 'No media kept yet.' : 'Turn on media keeping above to copy new WhatsApp media.',
            key: const Key('history-empty'),
          ),
        ));
      }
      for (final RescuedMedia r in shown) {
        rows.add(ListTile(
          minVerticalPadding: 12,
          leading: const Icon(Icons.insert_drive_file_outlined),
          title: Text(r.file.name),
          subtitle: Text(r.originalGone ? 'Deleted in WhatsApp, kept here' : 'Still in WhatsApp'),
        ));
      }
    }
    return ListView(padding: const EdgeInsets.only(bottom: 16), children: rows);
  }

  Widget _messageTile(HistoryMessage m) {
    String two(int v) => v.toString().padLeft(2, '0');
    final String when = '${two(m.at.day)}/${two(m.at.month)} ${two(m.at.hour)}:${two(m.at.minute)}';
    final String who = m.chat == m.sender ? m.sender : '${m.chat} › ${m.sender}';
    return Semantics(
      label: '${m.deleted ? 'Deleted message' : 'Message'} from $who at $when: ${m.text}',
      excludeSemantics: true,
      child: ListTile(
        key: Key('history-${m.key}'),
        minVerticalPadding: 12,
        leading: Icon(m.deleted ? Icons.restore_from_trash_outlined : Icons.chat_bubble_outline),
        title: Text(who),
        subtitle: Text(m.text),
        trailing: Text(when, style: Theme.of(context).textTheme.bodySmall),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recover deleted messages'),
        actions: <Widget>[
          IconButton(
            key: const Key('history-refresh'),
            tooltip: 'Refresh',
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _body(),
      bottomNavigationBar: ResultBar(onShare: _share, onSave: _save, onUndo: _undo),
    );
  }
}
