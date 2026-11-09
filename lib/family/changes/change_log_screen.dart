import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../app/widgets/result_bar.dart';
import '../../engines/family/change_log.dart';
import '../../engines/family/family_space.dart';
import '../../engines/family/family_store.dart';
import '../../engines/share/share_engine.dart';

typedef ChangeLogTextAction = Future<String?> Function(String text);

/// Feature 078 — who changed what across the family's shared records, newest
/// first, each with an Undo that puts the record back the way it was.
class ChangeLogScreen extends StatefulWidget {
  const ChangeLogScreen({super.key, this.store, this.share, this.save});

  final FamilyStore? store;
  final ChangeLogTextAction? share;
  final ChangeLogTextAction? save;

  @override
  State<ChangeLogScreen> createState() => _ChangeLogScreenState();
}

class _ChangeLogScreenState extends State<ChangeLogScreen> {
  FamilyStore get _store => widget.store ?? FamilySpace.instance.store;

  ChangeLog get _log => ChangeLog(_store);

  void _snack(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  void _undo(ChangeLogEntry e) {
    final bool done = _log.undo(e);
    _snack(done ? 'Put back: ${e.label}' : 'Already that way');
  }

  /// The bar's Undo takes back the newest change in the log.
  void _undoNewest() {
    final List<ChangeLogEntry> all = _log.all(limit: 1);
    if (all.isEmpty) {
      _snack('Nothing to undo');
      return;
    }
    _undo(all.first);
  }

  static Future<String?> _saveToDocuments(String text) async {
    final Directory dir = await getApplicationDocumentsDirectory();
    final File f = File('${dir.path}/Family change log.txt');
    await f.writeAsString(text);
    return f.path;
  }

  Future<void> _share() async {
    final ChangeLogTextAction? s = widget.share;
    if (s != null) {
      await s(_log.describe());
    } else {
      await ShareEngine.instance.shareText(_log.describe(), subject: 'Family change log');
    }
  }

  Future<void> _save() async {
    String? where;
    try {
      where = await (widget.save ?? _saveToDocuments)(_log.describe());
    } catch (_) {
      where = null;
    }
    if (mounted) {
      _snack(where == null ? 'Could not save the log' : 'Saved to $where');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _store,
      builder: (BuildContext context, Widget? _) {
        final List<ChangeLogEntry> entries = _log.all();
        final TextTheme text = Theme.of(context).textTheme;
        return Scaffold(
          appBar: AppBar(title: const Text('Change log')),
          bottomNavigationBar: ResultBar(
            onShare: () => unawaited(_share()),
            onSave: () => unawaited(_save()),
            onUndo: _undoNewest,
          ),
          body: entries.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('No changes yet. Edits to shared lists, events and notes show up here.'),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: entries.length + 1,
                  itemBuilder: (BuildContext context, int i) {
                    if (i == 0) {
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                        child: Text(
                          'Each shared item keeps its last ${FamilyRecord.keepChanges} changes. '
                          'Undo puts it back for everyone.',
                          style: text.bodyMedium,
                        ),
                      );
                    }
                    final ChangeLogEntry e = entries[i - 1];
                    final String when = ChangeLog.stamp(e.at);
                    return KeyedSubtree(
                      key: ValueKey<String>('change-${i - 1}'),
                      child: ListTile(
                        minVerticalPadding: 12,
                        leading: Icon(switch (e.kind) {
                          ChangeKind.added => Icons.add_circle_outline,
                          ChangeKind.changed => Icons.edit_outlined,
                          ChangeKind.removed => Icons.remove_circle_outline,
                        }),
                        title: Text(e.line),
                        subtitle: Text(when),
                        trailing: IconButton(
                          key: Key('undo-change-${i - 1}'),
                          tooltip: 'Undo: ${e.author} ${e.kind.verb} ${e.label}',
                          icon: const Icon(Icons.undo),
                          onPressed: () => _undo(e),
                        ),
                      ),
                    );
                  },
                ),
        );
      },
    );
  }
}
