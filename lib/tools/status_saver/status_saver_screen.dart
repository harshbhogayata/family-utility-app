import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../app/widgets/result_bar.dart';
import '../../engines/share/share_engine.dart';
import '../../engines/share/status_saver.dart';

class FolderStatusSink implements StatusSink {
  const FolderStatusSink();

  @override
  Future<String> write(String name, Uint8List bytes) async {
    final Directory base = await getApplicationDocumentsDirectory();
    final Directory dir = Directory('${base.path}/statuses');
    await dir.create(recursive: true);
    final File f = File('${dir.path}/$name');
    await f.writeAsBytes(bytes, flush: true);
    return f.path;
  }

  @override
  Future<void> remove(String path) async {
    final File f = File(path);
    if (f.existsSync()) {
      await f.delete();
    }
  }
}

/// Feature 125 — WhatsApp status saver.
class StatusSaverScreen extends StatefulWidget {
  const StatusSaverScreen({
    super.key,
    this.source = const PhoneStatusSource(),
    this.sink = const FolderStatusSink(),
    this.share,
  });

  final StatusSource source;
  final StatusSink sink;
  final ShareEngine? share;

  @override
  State<StatusSaverScreen> createState() => _StatusSaverScreenState();
}

class _StatusSaverScreenState extends State<StatusSaverScreen> {
  late final StatusSaver _saver = StatusSaver(widget.source, widget.sink);
  StatusAccess? _access;
  List<StatusItem> _items = <StatusItem>[];
  final Map<String, Uint8List> _thumbs = <String, Uint8List>{};
  final Set<String> _selected = <String>{};
  final List<String> _saved = <String>[];
  String? _status;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool ask = false}) async {
    setState(() => _loading = true);
    final StatusAccess a = ask ? await widget.source.requestAccess() : await widget.source.access();
    List<StatusItem> items = <StatusItem>[];
    if (a == StatusAccess.granted) {
      items = await _saver.list();
      for (final StatusItem s in items.where((StatusItem s) => s.isPhoto)) {
        try {
          _thumbs[s.id] = await widget.source.read(s);
        } catch (_) {
          // Expired between listing and reading; it shows as a plain tile.
        }
      }
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _access = a;
      _items = items;
      _loading = false;
      _selected.removeWhere((String id) => !items.any((StatusItem s) => s.id == id));
    });
  }

  void _toast(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(m)));
    }
  }

  List<StatusItem> get _chosen => _items.where((StatusItem s) => _selected.contains(s.id)).toList();

  Future<void> _save() async {
    final List<StatusItem> chosen = _chosen;
    if (chosen.isEmpty) {
      _toast('Tap the statuses to keep first');
      return;
    }
    int ok = 0;
    for (final StatusItem s in chosen) {
      try {
        _saved.add(await _saver.save(s));
        ok++;
      } on FileSystemException {
        // Expired.
      }
    }
    setState(() {
      _status = ok == chosen.length
          ? 'Kept $ok status${ok == 1 ? '' : 'es'} in Files › statuses'
          : 'Kept $ok of ${chosen.length}; the others have expired';
      _selected.clear();
    });
  }

  Future<void> _share() async {
    if (_saved.isEmpty) {
      await _save();
    }
    if (_saved.isEmpty) {
      return;
    }
    await (widget.share ?? ShareEngine.instance).shareFiles(List<String>.of(_saved));
  }

  Future<void> _undo() async {
    if (_saved.isEmpty) {
      if (_selected.isNotEmpty) {
        setState(_selected.clear);
        return;
      }
      Navigator.of(context).maybePop();
      return;
    }
    final List<String> gone = List<String>.of(_saved);
    _saved.clear();
    for (final String p in gone) {
      await widget.sink.remove(p);
    }
    setState(() => _status = 'Removed ${gone.length} kept status${gone.length == 1 ? '' : 'es'}');
  }

  Widget _message(String text, {Widget? action}) => ListView(
        padding: const EdgeInsets.all(24),
        children: <Widget>[
          Text(text, key: const Key('status-message'), style: Theme.of(context).textTheme.bodyLarge),
          if (action != null) ...<Widget>[const SizedBox(height: 16), action],
        ],
      );

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    switch (_access) {
      case StatusAccess.unsupported:
        return _message('WhatsApp does not let other apps read statuses on this phone.');
      case StatusAccess.noWhatsApp:
        return _message('No WhatsApp statuses folder was found. Open a few statuses in WhatsApp first.');
      case StatusAccess.needsGrant:
      case null:
        return _message(
          'Statuses you have viewed stay on this phone for about a day. Allow the app to read the '
          'WhatsApp statuses folder to keep them. Nothing is uploaded.',
          action: FilledButton.icon(
            key: const Key('status-allow'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: () => _load(ask: true),
            icon: const Icon(Icons.folder_open_outlined),
            label: const Text('Allow access to statuses'),
          ),
        );
      case StatusAccess.granted:
        if (_items.isEmpty) {
          return _message('No statuses right now. Watch some in WhatsApp, then come back.');
        }
        return Column(
          children: <Widget>[
            if (_status != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Semantics(liveRegion: true, child: Text(_status!, key: const Key('status-status'))),
              ),
            Expanded(
              child: GridView.count(
                crossAxisCount: 3,
                padding: const EdgeInsets.all(8),
                mainAxisSpacing: 6,
                crossAxisSpacing: 6,
                children: <Widget>[
                  for (final StatusItem s in _items) _tile(s),
                ],
              ),
            ),
          ],
        );
    }
  }

  Widget _tile(StatusItem s) {
    final bool on = _selected.contains(s.id);
    final Uint8List? thumb = _thumbs[s.id];
    return Semantics(
      button: true,
      selected: on,
      label: '${s.isVideo ? 'Video' : 'Photo'} status${on ? ', selected' : ''}',
      child: InkWell(
        key: Key('status-${s.name}'),
        onTap: () => setState(() => on ? _selected.remove(s.id) : _selected.add(s.id)),
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: thumb != null
                  ? Image.memory(thumb, fit: BoxFit.cover, excludeFromSemantics: true,
                      errorBuilder: (BuildContext c, Object e, StackTrace? t) => const ColoredBox(color: Colors.black12))
                  : ColoredBox(
                      color: Colors.black87,
                      child: Icon(s.isVideo ? Icons.play_circle_outline : Icons.image_outlined,
                          color: Colors.white, size: 36),
                    ),
            ),
            if (on)
              const Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.check_circle, color: Colors.white),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Status saver'),
        actions: <Widget>[
          IconButton(
            key: const Key('status-refresh'),
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
