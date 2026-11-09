import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../app/theme.dart';
import '../../app/tool_registry.dart';
import '../../app/widgets/result_bar.dart';
import '../../engines/family/member_profiles.dart';
import '../../engines/platform/home_layout.dart';
import '../../engines/share/share_engine.dart';

typedef HomeTextAction = Future<String?> Function(String text);

/// Feature 116 — Custom home: drag tools into order, hide the ones a member
/// never uses, pin favourites to the top, and reset to the default grid.
/// Each family member keeps their own layout; it never leaves the phone.
class CustomHomeScreen extends StatefulWidget {
  const CustomHomeScreen({super.key, this.profiles, this.share, this.save});

  final MemberProfiles? profiles;
  final HomeTextAction? share;
  final HomeTextAction? save;

  @override
  State<CustomHomeScreen> createState() => _CustomHomeScreenState();
}

class _CustomHomeScreenState extends State<CustomHomeScreen> {
  MemberProfiles get _p => widget.profiles ?? MemberProfiles.instance;

  /// Layouts before each change, newest last, for Undo.
  final List<HomeLayout> _undo = <HomeLayout>[];

  List<String> get _all => ToolRegistry.all.map((ToolEntry t) => t.id).toList();

  String _nameOf(String id) => ToolRegistry.byId(id)?.name ?? id;

  Future<void> _apply(HomeLayout next, {String? message}) async {
    final HomeLayout before = _p.layout;
    if (next == before) {
      return;
    }
    _undo.add(before);
    await _p.setLayout(next);
    if (message != null && mounted) {
      _snack(message);
    }
  }

  void _snack(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  String _describe() => _p.layout.describe(
        memberName: _p.active.name,
        all: _all,
        nameOf: _nameOf,
        recents: _p.active.recents,
      );

  static Future<String?> _saveToDocuments(String text) async {
    final Directory dir = await getApplicationDocumentsDirectory();
    final File f = File('${dir.path}/Home layout.txt');
    await f.writeAsString(text);
    return f.path;
  }

  Future<void> _share() async {
    final HomeTextAction? s = widget.share;
    if (s != null) {
      await s(_describe());
    } else {
      await ShareEngine.instance.shareText(_describe(), subject: 'Home layout');
    }
  }

  Future<void> _save() async {
    String? where;
    try {
      where = await (widget.save ?? _saveToDocuments)(_describe());
    } catch (_) {
      where = null;
    }
    if (mounted) {
      _snack(where == null ? 'Could not save the layout' : 'Saved to $where');
    }
  }

  Future<void> _undoLast() async {
    if (_undo.isEmpty) {
      _snack('Nothing to undo');
      return;
    }
    await _p.setLayout(_undo.removeLast());
    if (mounted) {
      _snack('Undone');
    }
  }

  Future<void> _reset() => _apply(_p.layout.reset(), message: 'Home is back to the default order');

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _p,
      builder: (BuildContext context, Widget? _) {
        final HomeLayout layout = _p.layout;
        final List<String> order = _p.fullToolOrder(_all);
        final TextTheme text = Theme.of(context).textTheme;
        return Scaffold(
          appBar: AppBar(
            title: Text('Home for ${_p.active.name}'),
            actions: <Widget>[
              TextButton.icon(
                key: const Key('home-reset'),
                onPressed: layout.isDefault ? null : () => unawaited(_reset()),
                icon: const Icon(Icons.restart_alt),
                label: const Text('Reset'),
              ),
            ],
          ),
          bottomNavigationBar: ResultBar(
            onShare: () => unawaited(_share()),
            onSave: () => unawaited(_save()),
            onUndo: () => unawaited(_undoLast()),
          ),
          body: order.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('Tools appear here as they are built.'),
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: Text(
                        'Drag the handle to reorder. Hidden tools stay in search. '
                        'Pinned tools always sit at the top.',
                        style: text.bodyMedium,
                      ),
                    ),
                    Expanded(
                      child: ReorderableListView.builder(
                        key: const Key('home-arrange-list'),
                        buildDefaultDragHandles: false,
                        padding: const EdgeInsets.only(bottom: 8),
                        itemCount: order.length,
                        onReorder: (int from, int to) => unawaited(_apply(layout.reorder(order, from, to))),
                        itemBuilder: (BuildContext context, int i) =>
                            _row(context, layout, order, i),
                      ),
                    ),
                  ],
                ),
        );
      },
    );
  }

  Widget _row(BuildContext context, HomeLayout layout, List<String> order, int i) {
    final String id = order[i];
    final ToolEntry? t = ToolRegistry.byId(id);
    final String name = t?.name ?? id;
    final bool hidden = layout.isHidden(id);
    final bool pinned = layout.isPinned(id);
    final String state = hidden ? 'hidden' : (pinned ? 'pinned' : 'shown');
    return Semantics(
      key: ValueKey<String>('arrange-$id'),
      container: true,
      label: '$name, position ${i + 1} of ${order.length}, $state',
      customSemanticsActions: <CustomSemanticsAction, VoidCallback>{
        if (i > 0)
          CustomSemanticsAction(label: 'Move $name up'): () =>
              unawaited(_apply(layout.step(order, id, -1))),
        if (i < order.length - 1)
          CustomSemanticsAction(label: 'Move $name down'): () =>
              unawaited(_apply(layout.step(order, id, 1))),
      },
      child: Opacity(
        opacity: hidden ? 0.5 : 1,
        child: ListTile(
          minVerticalPadding: 12,
          leading: ReorderableDragStartListener(
            index: i,
            child: SizedBox(
              key: Key('drag-$id'),
              width: 44,
              height: 44,
              child: Tooltip(
                message: 'Drag to move $name',
                child: const Icon(Icons.drag_handle),
              ),
            ),
          ),
          title: Row(
            children: <Widget>[
              Icon(t?.icon ?? Icons.apps, size: 20, color: hidden ? AppColors.muted : AppColors.accent),
              const SizedBox(width: 8),
              Expanded(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis)),
            ],
          ),
          subtitle: Text(hidden ? 'Hidden from home' : (pinned ? 'Pinned to the top' : 'On home')),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              IconButton(
                key: Key('pin-toggle-$id'),
                tooltip: pinned ? 'Unpin $name' : 'Pin $name',
                isSelected: pinned,
                icon: const Icon(Icons.push_pin_outlined),
                selectedIcon: const Icon(Icons.push_pin),
                onPressed: () => unawaited(_apply(layout.togglePinned(id))),
              ),
              IconButton(
                key: Key('hide-toggle-$id'),
                tooltip: hidden ? 'Show $name on home' : 'Hide $name from home',
                icon: Icon(hidden ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                onPressed: () => unawaited(_apply(
                  layout.toggleHidden(id),
                  message: hidden ? '$name is back on home' : '$name hidden. Find it in search.',
                )),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
