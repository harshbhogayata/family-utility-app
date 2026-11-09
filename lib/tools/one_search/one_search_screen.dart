import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../app/theme.dart';
import '../../app/tool_registry.dart';
import '../../app/widgets/result_bar.dart';
import '../../engines/platform/action_history.dart';
import '../../engines/platform/file_manager.dart';
import '../../engines/platform/one_search.dart';
import '../../engines/security/app_lock.dart';
import '../../engines/share/share_engine.dart';
import '../app_lock/lock_screen.dart';
import '../history/history_screen.dart';
import '../secure_notes/secure_notes_screen.dart';

/// Opens a hit. Behind a typedef so tests can see what was opened.
typedef SearchOpener = Future<void> Function(BuildContext context, SearchDoc doc);

Future<void> openSearchHit(BuildContext context, SearchDoc doc) async {
  switch (doc.kind) {
    case SearchKind.tool:
      final ToolEntry? tool = ToolRegistry.byId(doc.ref);
      if (tool == null) {
        return;
      }
      final bool ok = await ensureUnlockedFor(context, tool.id);
      if (!ok || !context.mounted) {
        return;
      }
      await Navigator.of(context).push<void>(MaterialPageRoute<void>(builder: tool.builder));
    case SearchKind.file:
    case SearchKind.text:
      await FileManager.instance.touch(doc.ref);
      await ShareEngine.instance.shareFiles(<String>[doc.ref]);
    case SearchKind.history:
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(builder: (BuildContext _) => const HistoryScreen()),
      );
    case SearchKind.record:
      final bool ok = await ensureUnlockedFor(context, LockableIds.secureNotes);
      if (!ok || !context.mounted) {
        return;
      }
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(builder: (BuildContext _) => const SecureNotesScreen()),
      );
  }
}

/// Writes the result list somewhere the person keeps (the Save action).
typedef SearchSaver = Future<String> Function(String text);

Future<String> saveSearchToAppFolder(String text) async {
  final Directory base = await getApplicationDocumentsDirectory();
  final File f = File('${base.path}/search-results.txt');
  await f.writeAsString(text, flush: true);
  return f.path;
}

IconData iconFor(SearchKind k) => switch (k) {
      SearchKind.tool => Icons.apps_outlined,
      SearchKind.file => Icons.insert_drive_file_outlined,
      SearchKind.text => Icons.document_scanner_outlined,
      SearchKind.history => Icons.history,
      SearchKind.record => Icons.sticky_note_2_outlined,
    };

/// Feature 114 — One search: one box across tools, files, history and records.
class OneSearchScreen extends StatefulWidget {
  const OneSearchScreen({
    super.key,
    this.search,
    this.opener = openSearchHit,
    this.saver = saveSearchToAppFolder,
    this.share,
  });

  final OneSearch? search;
  final SearchOpener opener;
  final SearchSaver saver;
  final ShareEngine? share;

  @override
  State<OneSearchScreen> createState() => _OneSearchScreenState();
}

class _OneSearchScreenState extends State<OneSearchScreen> {
  final TextEditingController _box = TextEditingController();
  final List<String> _past = <String>[];
  SearchOutcome? _outcome;
  int _seq = 0;
  bool _restoring = false;

  OneSearch get _s => widget.search ?? OneSearch.instance;

  @override
  void initState() {
    super.initState();
    // Fresh data every time the box opens; queries wait for it if needed.
    _s.invalidate();
    _s.rebuild();
  }

  @override
  void dispose() {
    _box.dispose();
    super.dispose();
  }

  Future<void> _run(String q) async {
    final int mine = ++_seq;
    if (q.trim().isEmpty) {
      setState(() => _outcome = null);
      return;
    }
    final SearchOutcome out = await _s.search(q);
    if (!mounted || mine != _seq) {
      return;
    }
    setState(() => _outcome = out);
  }

  void _changed(String q) {
    if (!_restoring) {
      final String prev = _outcome?.query ?? '';
      if (prev.isNotEmpty && (_past.isEmpty || _past.last != prev)) {
        _past.add(prev);
      }
    }
    _run(q);
  }

  void _toast(String m) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _share() async {
    final SearchOutcome? o = _outcome;
    if (o == null || o.results.isEmpty) {
      _toast('Nothing to share yet');
      return;
    }
    await (widget.share ?? ShareEngine.instance).shareText(o.asText(), subject: 'Search: ${o.query}');
  }

  Future<void> _save() async {
    final SearchOutcome? o = _outcome;
    if (o == null || o.results.isEmpty) {
      _toast('Nothing to save yet');
      return;
    }
    final String where = await widget.saver(o.asText());
    _toast('Saved ${baseName(where)} in Files');
  }

  Future<void> _undo() async {
    if (_past.isEmpty) {
      if (_box.text.isEmpty) {
        Navigator.of(context).maybePop();
        return;
      }
      _box.clear();
      await _run('');
      return;
    }
    final String q = _past.removeLast();
    _restoring = true;
    _box.value = TextEditingValue(text: q, selection: TextSelection.collapsed(offset: q.length));
    _restoring = false;
    await _run(q);
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final SearchOutcome? o = _outcome;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
            key: const Key('one-search-box'),
            controller: _box,
            autofocus: true,
            textInputAction: TextInputAction.search,
            onChanged: _changed,
            onSubmitted: _run,
            decoration: InputDecoration(
              hintText: 'Search tools, files, history, records',
              border: InputBorder.none,
              suffixIcon: IconButton(
                key: const Key('one-search-clear'),
                tooltip: 'Clear',
                icon: const Icon(Icons.close),
                onPressed: () {
                  _changed('');
                  _box.clear();
                },
              ),
            ),
          ),
      ),
      body: _body(text, o),
      bottomNavigationBar: ResultBar(onShare: _share, onSave: _save, onUndo: _undo),
    );
  }

  Widget _body(TextTheme text, SearchOutcome? o) {
    if (o == null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'Type to find a tool, a file, words inside a scan, something you did, or a record. '
          'The search runs on this phone.',
          style: text.bodyMedium,
          textAlign: TextAlign.center,
        ),
      );
    }
    if (o.results.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'Nothing matches "${o.query}".',
          key: const Key('one-search-empty'),
          style: text.bodyMedium,
          textAlign: TextAlign.center,
        ),
      );
    }
    final List<Widget> rows = <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Text(
          '${o.results.length} found in ${o.elapsed.inMilliseconds} ms',
          key: const Key('one-search-count'),
          style: text.labelSmall,
        ),
      ),
    ];
    o.grouped.forEach((SearchKind k, List<SearchResult> rs) {
      rows.add(Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Semantics(header: true, child: Text(k.label, style: text.titleSmall)),
      ));
      for (final SearchResult r in rs) {
        final SearchDoc d = r.doc;
        final String sub = r.snippet ?? d.subtitle;
        rows.add(Semantics(
          button: true,
          label: '${k.label}: ${d.title}${sub.isEmpty ? '' : ', $sub'}',
          excludeSemantics: true,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: ListTile(
              key: ValueKey<String>('hit-${d.key}'),
              leading: Icon(iconFor(k), color: AppColors.accent),
              title: Text(d.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: sub.isEmpty ? null : Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis),
              onTap: () => widget.opener(context, d),
            ),
          ),
        ));
      }
    });
    return ListView(children: rows);
  }
}
