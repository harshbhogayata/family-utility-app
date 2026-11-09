import 'package:flutter/material.dart';

import '../app/widgets/result_bar.dart';
import '../engines/platform/action_history.dart';
import '../engines/platform/file_manager.dart';
import '../engines/share/share_engine.dart';

enum _Kind { rename, move, delete }

class _LastAction {
  const _LastAction(this.kind, this.before, this.after, {this.trashId});

  final _Kind kind;
  final String before;
  final String after;
  final String? trashId;
}

/// Files tab: recents, favourites, folders and search (feature 117).
class FilesScreen extends StatefulWidget {
  const FilesScreen({super.key, this.manager, this.share});

  /// Injected in tests; otherwise the app-wide file manager.
  final FileManager? manager;
  final ShareEngine? share;

  @override
  State<FilesScreen> createState() => _FilesScreenState();
}

class _FilesScreenState extends State<FilesScreen> {
  late final FileManager _fm = widget.manager ?? FileManager.instance;
  final TextEditingController _query = TextEditingController();

  String? _cwd;
  List<FileNode> _nodes = <FileNode>[];
  List<SearchHit>? _hits;
  bool _inContent = true;
  SortBy _sort = SortBy.name;
  bool _ascending = true;
  String? _error;
  String? _selected;
  _LastAction? _last;

  ShareEngine get _share => widget.share ?? ShareEngine.instance;

  @override
  void initState() {
    super.initState();
    _fm.addListener(_changed);
  }

  @override
  void dispose() {
    _fm.removeListener(_changed);
    _query.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) {
      setState(() {});
    }
  }

  void _toast(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(m)));
    }
  }

  Future<void> _open(String dir) async {
    try {
      final List<FileNode> nodes = await _fm.list(dir, by: _sort, ascending: _ascending);
      if (!mounted) {
        return;
      }
      setState(() {
        _cwd = dir;
        _nodes = nodes;
        _error = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Could not open this folder. Allow file access in Settings and try again.');
      }
    }
  }

  Future<void> _refresh() async {
    final String? d = _cwd;
    if (d != null) {
      await _open(d);
    }
  }

  void _up() {
    final String? d = _cwd;
    if (d == null) {
      return;
    }
    final bool atRoot = _fm.roots.any((FileRoot r) => r.path == d);
    if (atRoot) {
      setState(() {
        _cwd = null;
        _nodes = <FileNode>[];
      });
    } else {
      _open(parentOf(d));
    }
  }

  Future<void> _search(String q) async {
    if (q.trim().isEmpty) {
      setState(() => _hits = null);
      return;
    }
    final List<String> where = _cwd != null ? <String>[_cwd!] : _fm.roots.map((FileRoot r) => r.path).toList();
    final List<SearchHit> all = <SearchHit>[];
    for (final String root in where) {
      all.addAll(await _fm.search(root, q, inContent: _inContent));
    }
    if (mounted) {
      setState(() => _hits = all);
    }
  }

  Future<void> _openFile(String path) async {
    _selected = path;
    await _fm.touch(path);
    await _share.shareFiles(<String>[path]);
  }

  Future<void> _rename(String path) async {
    final TextEditingController c = TextEditingController(text: baseName(path));
    final String? name = await showDialog<String>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Rename'),
        content: TextField(
          key: const Key('rename-field'),
          controller: c,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'New name'),
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          FilledButton(
            key: const Key('rename-ok'),
            onPressed: () => Navigator.of(ctx).pop(c.text),
            child: const Text('Rename'),
          ),
        ],
      ),
    );
    // The controller is left to the GC: the dialog may still be animating out.
    if (name == null) {
      return;
    }
    try {
      final String to = await _fm.rename(path, name);
      _selected = to;
      _last = _LastAction(_Kind.rename, path, to);
      _toast('Renamed to ${baseName(to)}');
      await _refresh();
    } on ArgumentError catch (e) {
      _toast('${e.message}');
    } on StateError catch (e) {
      _toast(e.message);
    }
  }

  Future<void> _move(String path) async {
    final String here = parentOf(path);
    final List<String> targets = <String>[
      if (_fm.roots.every((FileRoot r) => r.path != here)) parentOf(here),
      ..._nodes.where((FileNode n) => n.isDir && n.path != path).map((FileNode n) => n.path),
      ..._fm.roots.map((FileRoot r) => r.path).where((String p) => p != here),
    ];
    if (targets.isEmpty) {
      _toast('No other folder here. Make one with New folder first.');
      return;
    }
    final String? to = await showDialog<String>(
      context: context,
      builder: (BuildContext ctx) => SimpleDialog(
        title: const Text('Move to'),
        children: <Widget>[
          for (final String t in targets.toSet())
            SimpleDialogOption(
              key: ValueKey<String>('move-to-${baseName(t)}'),
              onPressed: () => Navigator.of(ctx).pop(t),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(t == parentOf(here) ? 'Up: ${baseName(t)}' : baseName(t)),
              ),
            ),
        ],
      ),
    );
    if (to == null) {
      return;
    }
    final String moved = await _fm.moveTo(path, to);
    _selected = moved;
    _last = _LastAction(_Kind.move, path, moved);
    _toast('Moved to ${baseName(to)}');
    await _refresh();
  }

  Future<void> _delete(String path) async {
    final TrashItem? t = await _fm.delete(path);
    if (t == null) {
      _toast('Already gone');
    } else {
      _last = _LastAction(_Kind.delete, path, t.trashedPath, trashId: t.id);
      _toast('Moved to Recently deleted for 30 days');
    }
    if (_selected == path) {
      _selected = null;
    }
    await _refresh();
  }

  Future<void> _newFolder() async {
    final String? d = _cwd;
    if (d == null) {
      return;
    }
    await _fm.createFolder(d, 'New folder');
    await _refresh();
  }

  Future<void> _shareSelected() async {
    final String? s = _selected;
    if (s == null) {
      _toast('Open or pick a file first');
      return;
    }
    await _share.shareFiles(<String>[s]);
  }

  Future<void> _saveSelected() async {
    final String? s = _selected;
    if (s == null) {
      _toast('Open or pick a file first');
      return;
    }
    if (!_fm.favourites.contains(s)) {
      await _fm.toggleFavourite(s);
    }
    _toast('${baseName(s)} is in Favourites');
  }

  Future<void> _undo() async {
    final _LastAction? a = _last;
    if (a == null) {
      _toast('Nothing to undo');
      return;
    }
    _last = null;
    switch (a.kind) {
      case _Kind.rename:
        await _fm.rename(a.after, baseName(a.before));
      case _Kind.move:
        await _fm.moveTo(a.after, parentOf(a.before));
      case _Kind.delete:
        await _fm.history.restore(a.trashId!);
    }
    _selected = a.before;
    _toast('Undone');
    await _refresh();
  }

  Future<void> _menu(FileNode n, String action) async {
    switch (action) {
      case 'open':
        await _openFile(n.path);
      case 'fav':
        final bool on = await _fm.toggleFavourite(n.path);
        _toast(on ? 'Added to Favourites' : 'Removed from Favourites');
      case 'rename':
        await _rename(n.path);
      case 'move':
        await _move(n.path);
      case 'delete':
        await _delete(n.path);
    }
  }

  Widget _tile(FileNode n, {String? subtitle}) {
    final bool fav = _fm.favourites.contains(n.path);
    return ListTile(
      key: ValueKey<String>('file-${n.name}'),
      minVerticalPadding: 8,
      leading: Icon(
        n.isDir ? Icons.folder_outlined : Icons.insert_drive_file_outlined,
        semanticLabel: n.isDir ? 'Folder' : 'File',
      ),
      title: Text(n.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: subtitle == null ? null : Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
      onTap: () => n.isDir ? _open(n.path) : _openFile(n.path),
      onLongPress: () => setState(() => _selected = n.path),
      selected: _selected == n.path,
      trailing: PopupMenuButton<String>(
        key: ValueKey<String>('file-menu-${n.name}'),
        tooltip: 'Actions for ${n.name}',
        onSelected: (String a) => _menu(n, a),
        itemBuilder: (BuildContext _) => <PopupMenuEntry<String>>[
          if (!n.isDir) const PopupMenuItem<String>(value: 'open', child: Text('Open with…')),
          PopupMenuItem<String>(value: 'fav', child: Text(fav ? 'Remove favourite' : 'Favourite')),
          const PopupMenuItem<String>(value: 'rename', child: Text('Rename')),
          const PopupMenuItem<String>(value: 'move', child: Text('Move')),
          const PopupMenuItem<String>(value: 'delete', child: Text('Delete')),
        ],
      ),
    );
  }

  Widget _pathTile(String path) {
    return ListTile(
      key: ValueKey<String>('path-$path'),
      leading: const Icon(Icons.insert_drive_file_outlined, semanticLabel: 'File'),
      title: Text(baseName(path), maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(parentOf(path), maxLines: 1, overflow: TextOverflow.ellipsis),
      onTap: () => _openFile(path),
    );
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final List<Widget> body = <Widget>[];
    final List<SearchHit>? hits = _hits;
    final String? cwd = _cwd;

    if (hits != null) {
      body.add(Text('${hits.length} found', style: text.titleMedium));
      for (final SearchHit h in hits) {
        body.add(_tile(h.node, subtitle: h.inName ? parentOf(h.node.path) : h.snippet));
      }
    } else if (cwd != null) {
      body.add(Row(
        children: <Widget>[
          IconButton(
            key: const Key('files-up'),
            tooltip: 'Up one folder',
            onPressed: _up,
            icon: const Icon(Icons.arrow_upward),
          ),
          Expanded(child: Text(baseName(cwd), style: text.titleMedium, overflow: TextOverflow.ellipsis)),
          PopupMenuButton<SortBy>(
            key: const Key('files-sort'),
            tooltip: 'Sort',
            icon: const Icon(Icons.sort),
            onSelected: (SortBy s) {
              setState(() {
                _ascending = s == _sort ? !_ascending : s == SortBy.name || s == SortBy.type;
                _sort = s;
              });
              _refresh();
            },
            itemBuilder: (BuildContext _) => const <PopupMenuEntry<SortBy>>[
              PopupMenuItem<SortBy>(value: SortBy.name, child: Text('Name')),
              PopupMenuItem<SortBy>(value: SortBy.date, child: Text('Date')),
              PopupMenuItem<SortBy>(value: SortBy.size, child: Text('Size')),
              PopupMenuItem<SortBy>(value: SortBy.type, child: Text('Type')),
            ],
          ),
          IconButton(
            key: const Key('files-new-folder'),
            tooltip: 'New folder',
            onPressed: _newFolder,
            icon: const Icon(Icons.create_new_folder_outlined),
          ),
        ],
      ));
      if (_nodes.isEmpty) {
        body.add(Padding(
          padding: const EdgeInsets.all(16),
          child: Text('This folder is empty.', style: text.bodyMedium),
        ));
      }
      for (final FileNode n in _nodes) {
        body.add(_tile(n));
      }
    } else {
      if (_fm.favourites.isNotEmpty) {
        body.add(Text('Favourites', style: text.titleMedium));
        body.addAll(_fm.favourites.map(_pathTile));
        body.add(const SizedBox(height: 12));
      }
      if (_fm.recents.isNotEmpty) {
        body.add(Text('Recents', style: text.titleMedium));
        body.addAll(_fm.recents.take(10).map(_pathTile));
        body.add(const SizedBox(height: 12));
      }
      body.add(Text('Folders', style: text.titleMedium));
      for (final FileRoot r in _fm.roots) {
        body.add(ListTile(
          key: ValueKey<String>('root-${r.label}'),
          leading: const Icon(Icons.folder_open_outlined, semanticLabel: 'Folder'),
          title: Text(r.label),
          onTap: () => _open(r.path),
        ));
      }
    }

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            Text('Files', style: text.titleLarge),
            const SizedBox(height: 8),
            Text('Recents, favourites and folders.', style: text.bodyMedium),
            const SizedBox(height: 12),
            TextField(
              key: const Key('files-search'),
              controller: _query,
              textInputAction: TextInputAction.search,
              onSubmitted: _search,
              decoration: InputDecoration(
                labelText: 'Search by name or content',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _hits == null
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        onPressed: () {
                          _query.clear();
                          setState(() => _hits = null);
                        },
                        icon: const Icon(Icons.close),
                      ),
              ),
            ),
            Row(
              children: <Widget>[
                Expanded(child: Text('Look inside text files', style: text.bodyMedium)),
                Switch(
                  key: const Key('files-in-content'),
                  value: _inContent,
                  onChanged: (bool v) => setState(() => _inContent = v),
                ),
              ],
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(_error!, style: text.bodyMedium?.copyWith(color: const Color(0xFFB45309))),
              ),
            ...body,
          ],
        ),
      ),
      bottomNavigationBar: ResultBar(onShare: _shareSelected, onSave: _saveSelected, onUndo: _undo),
    );
  }
}
