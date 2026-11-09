import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../app/tool_registry.dart';
import '../../app/widgets/result_bar.dart';
import '../../engines/platform/action_history.dart';
import '../../engines/share/share_engine.dart';

/// Picks the new file for a re-run. Behind an interface for tests.
abstract class RerunChooser {
  Future<List<String>> pick();
}

class SystemRerunChooser implements RerunChooser {
  const SystemRerunChooser();

  @override
  Future<List<String>> pick() async {
    final FilePickerResult? r = await FilePicker.platform.pickFiles(allowMultiple: true);
    return r == null ? <String>[] : r.files.map((PlatformFile f) => f.path).whereType<String>().toList();
  }
}

/// Opens the tool for a re-run. Default: the tool's screen from the registry.
typedef RerunLauncher = Future<void> Function(BuildContext context, RerunRequest request);

Future<void> openToolForRerun(BuildContext context, RerunRequest request) async {
  final ToolEntry? tool = ToolRegistry.byId(request.toolId);
  if (tool == null) {
    return;
  }
  await Navigator.of(context).push(MaterialPageRoute<void>(
    builder: tool.builder,
    settings: RouteSettings(name: tool.id, arguments: request),
  ));
}

/// Writes the history log somewhere the person keeps (the Save action).
typedef LogSaver = Future<String> Function(String text);

Future<String> saveLogToAppFolder(String text) async {
  final Directory base = await getApplicationDocumentsDirectory();
  final File f = File('${base.path}/action-history.txt');
  await f.writeAsString(text, flush: true);
  return f.path;
}

/// Feature 118 — Action history and trash.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({
    super.key,
    this.history,
    this.chooser = const SystemRerunChooser(),
    this.launcher = openToolForRerun,
    this.saveLog = saveLogToAppFolder,
    this.share,
  });

  final ActionHistory? history;
  final RerunChooser chooser;
  final RerunLauncher launcher;
  final LogSaver saveLog;
  final ShareEngine? share;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  late final ActionHistory _h = widget.history ?? ActionHistory.instance;

  /// Files restored on this screen, so Undo can put them back in the trash.
  final List<String> _restoredPaths = <String>[];

  @override
  void initState() {
    super.initState();
    _h.addListener(_changed);
  }

  @override
  void dispose() {
    _h.removeListener(_changed);
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

  Future<void> _undoEntry(HistoryEntry e) async {
    final bool ok = await _h.undo(e.id);
    _toast(ok ? 'Undone. The result is in Recently deleted for 30 days.' : 'Already undone');
  }

  Future<void> _rerun(HistoryEntry e) async {
    final List<String> picked = await widget.chooser.pick();
    if (picked.isEmpty || !mounted) {
      return;
    }
    await widget.launcher(context, _h.rerun(e.id, picked));
  }

  Future<void> _restore(TrashItem t) async {
    final String? back = await _h.restore(t.id);
    if (back != null) {
      _restoredPaths.add(back);
      _toast('Restored ${baseName(back)}');
    }
  }

  Future<void> _share() async {
    await (widget.share ?? ShareEngine.instance).shareText(_h.asText(), subject: 'Action history');
  }

  Future<void> _save() async {
    final String where = await widget.saveLog(_h.asText());
    _toast('Saved ${baseName(where)} in Files');
  }

  Future<void> _undo() async {
    if (_restoredPaths.isNotEmpty) {
      final String p = _restoredPaths.removeLast();
      await _h.delete(p);
      _toast('Back in Recently deleted');
      return;
    }
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final DateTime now = _h.now;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('History and trash'),
          bottom: const TabBar(
            tabs: <Widget>[
              Tab(key: Key('tab-history'), text: 'History'),
              Tab(key: Key('tab-trash'), text: 'Recently deleted'),
            ],
          ),
        ),
        body: TabBarView(
          children: <Widget>[
            if (_h.entries.isEmpty)
              _empty(text, 'Tool runs show up here, with Undo and Re-run.')
            else
              ListView(
                padding: const EdgeInsets.all(16),
                children: <Widget>[
                  for (final HistoryEntry e in _h.entries)
                    Card(
                      key: ValueKey<String>('history-${e.id}'),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(e.toolName + (e.undone ? ' · undone' : ''), style: text.titleMedium),
                            const SizedBox(height: 2),
                            Text(ActionHistory.formatWhen(e.at), style: text.bodySmall),
                            const SizedBox(height: 6),
                            Text('In: ${e.inputs.map(baseName).join(', ')}', style: text.bodyMedium),
                            Text('Out: ${e.outputs.map(baseName).join(', ')}', style: text.bodyMedium),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: <Widget>[
                                TextButton.icon(
                                  key: ValueKey<String>('history-undo-${e.id}'),
                                  onPressed: e.undone ? null : () => _undoEntry(e),
                                  icon: const Icon(Icons.undo),
                                  label: Text('Undo', semanticsLabel: 'Undo ${e.toolName}'),
                                ),
                                TextButton.icon(
                                  key: ValueKey<String>('history-rerun-${e.id}'),
                                  onPressed: () => _rerun(e),
                                  icon: const Icon(Icons.replay),
                                  label: Text('Re-run', semanticsLabel: 'Re-run ${e.toolName} on a new file'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            if (_h.trash.isEmpty)
              _empty(text, 'Deleted files wait here for 30 days before they go for good.')
            else
              ListView(
                padding: const EdgeInsets.all(16),
                children: <Widget>[
                  for (final TrashItem t in _h.trash)
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.delete_outline),
                        title: Text(t.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                          'Deleted ${ActionHistory.formatWhen(t.deletedAt)} · '
                          '${t.daysLeft(now)} ${t.daysLeft(now) == 1 ? 'day' : 'days'} left',
                        ),
                        trailing: TextButton(
                          key: ValueKey<String>('trash-restore-${t.id}'),
                          onPressed: () => _restore(t),
                          child: Text('Restore', semanticsLabel: 'Restore ${t.name}'),
                        ),
                      ),
                    ),
                ],
              ),
          ],
        ),
        bottomNavigationBar: ResultBar(onShare: _share, onSave: _save, onUndo: _undo),
      ),
    );
  }

  Widget _empty(TextTheme text, String message) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Text(message, style: text.bodyMedium, textAlign: TextAlign.center),
    );
  }
}
