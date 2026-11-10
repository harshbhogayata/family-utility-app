import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../../app/widgets/result_bar.dart';
import '../../engines/records/where_is_it.dart';
import '../../engines/share/share_engine.dart';

/// Feature 099 — where the spare key, warranty card or album is kept.
class WhereIsItScreen extends StatefulWidget {
  const WhereIsItScreen({super.key, this.notes, this.takePhoto, this.share, this.save, this.initialQuery = ''});

  final WhereIsIt? notes;

  /// Takes a photo and returns its path in the app folder; defaults to the camera.
  final Future<String?> Function()? takePhoto;
  final Future<void> Function(String text)? share;
  final Future<String?> Function(String text, String name)? save;
  final String initialQuery;

  @override
  State<WhereIsItScreen> createState() => _WhereIsItScreenState();
}

class _WhereIsItScreenState extends State<WhereIsItScreen> {
  WhereIsIt get _w => widget.notes ?? WhereIsIt.instance;
  late final TextEditingController _q = TextEditingController(text: widget.initialQuery);

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  void _snack(String s) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
    }
  }

  static Future<String?> _camera() async {
    final XFile? x = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 70, maxWidth: 1600);
    if (x == null) {
      return null;
    }
    final Directory base = await getApplicationDocumentsDirectory();
    final Directory dir = Directory('${base.path}/where_is_it');
    await dir.create(recursive: true);
    final String path = '${dir.path}/place_${DateTime.now().millisecondsSinceEpoch}.jpg';
    await File(x.path).copy(path);
    return path;
  }

  Future<String?> _photo() async {
    try {
      return await (widget.takePhoto ?? _camera)();
    } catch (_) {
      _snack('Could not take a photo');
      return null;
    }
  }

  Future<void> _shareText(String text) async {
    final Future<void> Function(String)? s = widget.share;
    if (s != null) {
      await s(text);
      return;
    }
    await ShareEngine.instance.shareText(text);
  }

  static Future<String?> _saveToDocuments(String text, String name) async {
    final Directory dir = await getApplicationDocumentsDirectory();
    final File f = File('${dir.path}/$name');
    await f.writeAsString(text);
    return f.path;
  }

  Future<void> _save() async {
    String? where;
    try {
      where = await (widget.save ?? _saveToDocuments)(_w.toText(_w.search(_q.text)), 'Where is it.txt');
    } catch (_) {
      where = null;
    }
    _snack(where == null ? 'Could not save' : 'Saved to $where');
  }

  /// Adds a note, or edits [existing].
  Future<void> _edit([WhereNote? existing]) async {
    final TextEditingController item = TextEditingController(text: existing?.item ?? '');
    final TextEditingController place = TextEditingController(text: existing?.place ?? '');
    final TextEditingController detail = TextEditingController(text: existing?.detail ?? '');
    String? photo = existing?.photo;
    bool shared = existing?.shared ?? false;
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setInner) => AlertDialog(
          title: Text(existing == null ? 'Where is it kept?' : 'Moved it?'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                TextField(
                  key: const Key('wi-item'),
                  controller: item,
                  decoration: const InputDecoration(labelText: 'What', hintText: 'Spare car key'),
                ),
                TextField(
                  key: const Key('wi-place'),
                  controller: place,
                  decoration: const InputDecoration(labelText: 'Where', hintText: 'Bedroom cupboard, top shelf'),
                ),
                TextField(
                  key: const Key('wi-detail'),
                  controller: detail,
                  decoration: const InputDecoration(labelText: 'More (optional)', hintText: 'In the blue box'),
                ),
                const SizedBox(height: 8),
                Row(
                  children: <Widget>[
                    TextButton.icon(
                      key: const Key('wi-photo'),
                      style: TextButton.styleFrom(minimumSize: const Size(88, 48)),
                      onPressed: () async {
                        final String? p = await _photo();
                        if (p != null) {
                          setInner(() => photo = p);
                        }
                      },
                      icon: const Icon(Icons.photo_camera_outlined),
                      label: Text(photo == null ? 'Add a photo' : 'Retake photo'),
                    ),
                    if (photo != null)
                      IconButton(
                        tooltip: 'Remove photo',
                        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                        onPressed: () => setInner(() => photo = null),
                        icon: const Icon(Icons.close),
                      ),
                  ],
                ),
                if (existing == null)
                  SwitchListTile(
                    key: const Key('wi-shared'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Share with the family'),
                    subtitle: Text(_w.canShare ? 'Everyone in the family sees it' : 'Join a family to share'),
                    value: shared && _w.canShare,
                    onChanged: _w.canShare ? (bool v) => setInner(() => shared = v) : null,
                  ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(key: const Key('wi-save'), onPressed: () => Navigator.pop(context, true), child: Text(existing == null ? 'Add' : 'Save')),
          ],
        ),
      ),
    );
    if (ok != true) {
      return;
    }
    if (existing == null) {
      final WhereNote? n = _w.add(item: item.text, place: place.text, detail: detail.text, photo: photo, shared: shared);
      _snack(n == null ? 'Type what it is and where it is kept' : 'Noted where ${n.item} is');
    } else {
      final bool done = _w.edit(existing.id, item: item.text, place: place.text, detail: detail.text, photo: photo, clearPhoto: photo == null);
      _snack(done ? 'Updated' : 'Type what it is and where it is kept');
    }
  }

  void _toggleShare(WhereNote n) {
    if (!n.shared && !_w.canShare) {
      _snack('Join a family to share notes');
      return;
    }
    _w.setShared(n.id, !n.shared);
    _snack(n.shared ? 'Now only on this phone' : 'Shared with the family');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Where is it?')),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('wi-add'),
        onPressed: () => unawaited(_edit()),
        icon: const Icon(Icons.add_location_alt_outlined),
        label: const Text('Note a place'),
      ),
      bottomNavigationBar: ResultBar(
        onShare: () => unawaited(_shareText(_w.toText(_w.search(_q.text)))),
        onSave: () => unawaited(_save()),
        onUndo: () => _snack(_w.undo() ? 'Undone' : 'Nothing to undo'),
      ),
      body: ListenableBuilder(listenable: _w.listenable, builder: (BuildContext context, Widget? _) => _body(context)),
    );
  }

  Widget _body(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final List<WhereNote> list = _w.search(_q.text);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: <Widget>[
        TextField(
          key: const Key('wi-search'),
          controller: _q,
          decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Key, passport, album…'),
          onChanged: (String _) => setState(() {}),
        ),
        const SizedBox(height: 8),
        if (_w.all.isEmpty)
          Text('Nothing noted yet. Write down where the spare key or the warranty card is kept, with a photo if it helps.', style: text.bodyMedium)
        else if (list.isEmpty)
          Text('Nothing matches "${_q.text.trim()}".', style: text.bodyMedium),
        for (final WhereNote n in list) _card(context, n),
      ],
    );
  }

  Widget _card(BuildContext context, WhereNote n) {
    final TextTheme text = Theme.of(context).textTheme;
    final String? photo = n.photo;
    final bool hasPhoto = photo != null && File(photo).existsSync();
    return Card(
      key: Key('wi-${n.id}'),
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(child: Text(n.item, style: text.titleMedium)),
                if (n.shared)
                  Semantics(
                    label: 'Shared with the family',
                    child: const ExcludeSemantics(child: Icon(Icons.family_restroom, size: 20)),
                  ),
              ],
            ),
            Text(n.place, key: Key('wi-place-${n.id}'), style: text.bodyLarge),
            if (n.detail.isNotEmpty) Text(n.detail, style: text.bodySmall),
            if (hasPhoto)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(
                    File(photo!),
                    height: 140,
                    fit: BoxFit.cover,
                    semanticLabel: 'Photo of where ${n.item} is kept',
                  ),
                ),
              )
            else if (photo != null)
              Text('Photo is on the phone that took it', style: text.bodySmall),
            Wrap(
              spacing: 8,
              children: <Widget>[
                TextButton.icon(
                  key: Key('wi-edit-${n.id}'),
                  style: TextButton.styleFrom(minimumSize: const Size(88, 48)),
                  onPressed: () => unawaited(_edit(n)),
                  icon: const Icon(Icons.edit_location_alt_outlined),
                  label: const Text('Moved it'),
                ),
                TextButton.icon(
                  key: Key('wi-share-${n.id}'),
                  style: TextButton.styleFrom(minimumSize: const Size(88, 48)),
                  onPressed: () => _toggleShare(n),
                  icon: Icon(n.shared ? Icons.lock_outline : Icons.family_restroom),
                  label: Text(n.shared ? 'Keep on this phone' : 'Share with family'),
                ),
                TextButton.icon(
                  key: Key('wi-delete-${n.id}'),
                  style: TextButton.styleFrom(minimumSize: const Size(88, 48)),
                  onPressed: () {
                    _w.remove(n.id);
                    _snack('Deleted. Undo brings it back.');
                  },
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Delete'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
