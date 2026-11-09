import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../app/theme.dart';
import '../../app/widgets/result_bar.dart';
import '../../engines/family/family_board.dart';
import '../../engines/share/share_engine.dart';

typedef BoardTextAction = Future<String?> Function(String text);

/// Picks a due day; null on cancel.
typedef BoardDatePick = Future<DateTime?> Function(BuildContext context, DateTime initial);

/// Feature 073 — shared to-do and notice board: tasks with an owner, a
/// due date and a done state, and notes pinned to the Family screen.
class FamilyBoardScreen extends StatefulWidget {
  const FamilyBoardScreen({super.key, this.board, this.share, this.save, this.pickDate});

  final FamilyBoard? board;
  final BoardTextAction? share;

  /// Saves the board as text; returns where it went, or null.
  final BoardTextAction? save;
  final BoardDatePick? pickDate;

  @override
  State<FamilyBoardScreen> createState() => _FamilyBoardScreenState();
}

class _FamilyBoardScreenState extends State<FamilyBoardScreen> {
  final TextEditingController _task = TextEditingController();
  final TextEditingController _note = TextEditingController();
  String? _owner;
  DateTime? _due;

  FamilyBoard get _board => widget.board ?? FamilyBoard.instance;

  @override
  void dispose() {
    _task.dispose();
    _note.dispose();
    super.dispose();
  }

  static String _day(DateTime d) => '${d.day} ${_months[d.month - 1]}';
  static const List<String> _months = <String>[
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec', //
  ];

  void _snack(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  void _addTask() {
    final FamilyTask? t = _board.addTask(_task.text, owner: _owner, due: _due);
    if (t == null) {
      _snack('Type the task first');
      return;
    }
    _task.clear();
    setState(() => _due = null);
  }

  void _addNote() {
    final FamilyNote? n = _board.addNote(_note.text);
    if (n == null) {
      _snack('Type the note first');
      return;
    }
    _note.clear();
  }

  Future<void> _chooseDue() async {
    final DateTime now = DateTime.now();
    final BoardDatePick pick = widget.pickDate ??
        (BuildContext c, DateTime initial) => showDatePicker(
              context: c,
              initialDate: initial,
              firstDate: DateTime(now.year - 1),
              lastDate: DateTime(now.year + 5),
            );
    final DateTime? d = await pick(context, _due ?? now);
    if (mounted) {
      setState(() => _due = d);
    }
  }

  Future<void> _share() async {
    final String text = _board.toText();
    final BoardTextAction? s = widget.share;
    if (s != null) {
      await s(text);
    } else {
      await ShareEngine.instance.shareText(text, subject: 'Family board');
    }
  }

  Future<void> _save() async {
    final String text = _board.toText();
    final BoardTextAction s = widget.save ?? _saveToDocuments;
    String? where;
    try {
      where = await s(text);
    } catch (_) {
      where = null;
    }
    if (mounted) {
      _snack(where == null ? 'Could not save the board' : 'Saved to $where');
    }
  }

  static Future<String?> _saveToDocuments(String text) async {
    final Directory dir = await getApplicationDocumentsDirectory();
    final File f = File('${dir.path}/Family board.txt');
    await f.writeAsString(text);
    return f.path;
  }

  void _undo() => _snack(_board.undo() ? 'Undone' : 'Nothing to undo');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('To-do and notices'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Clear done tasks',
            icon: const Icon(Icons.playlist_remove),
            onPressed: () {
              final int n = _board.clearDone();
              _snack(n == 0 ? 'Nothing done yet' : 'Cleared $n done');
            },
          ),
        ],
      ),
      bottomNavigationBar: ResultBar(
        onShare: () => unawaited(_share()),
        onSave: () => unawaited(_save()),
        onUndo: _undo,
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge(<Listenable>[_board, _board.store]),
        builder: (BuildContext context, Widget? _) => _body(context),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final List<MapEntry<String, String>> members = _board.memberChoices;
    final String owner =
        members.any((MapEntry<String, String> e) => e.key == _owner) ? _owner! : members.first.key;
    final List<FamilyNote> notes = _board.notes;
    final List<FamilyTask> tasks = _board.tasks;
    final DateTime today = DateTime.now();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      children: <Widget>[
        Semantics(header: true, child: Text('Notice board', style: text.titleMedium)),
        const SizedBox(height: 4),
        Row(children: <Widget>[
          Expanded(
            child: TextField(
              controller: _note,
              decoration: const InputDecoration(labelText: 'Pin a note'),
              textCapitalization: TextCapitalization.sentences,
              onSubmitted: (_) => _addNote(),
            ),
          ),
          const SizedBox(width: 4),
          IconButton.filled(
            tooltip: 'Pin note',
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            onPressed: _addNote,
            icon: const Icon(Icons.push_pin_outlined),
          ),
        ]),
        if (notes.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text('No notes yet. Pinned notes show on the Family screen.',
                style: text.bodyMedium?.copyWith(color: AppColors.muted)),
          ),
        for (final FamilyNote n in notes) _noteTile(n),
        const SizedBox(height: 20),
        Semantics(header: true, child: Text('To do', style: text.titleMedium)),
        const SizedBox(height: 4),
        TextField(
          controller: _task,
          decoration: const InputDecoration(labelText: 'Add a task'),
          textCapitalization: TextCapitalization.sentences,
          onSubmitted: (_) => _addTask(),
        ),
        const SizedBox(height: 8),
        Row(children: <Widget>[
          Expanded(
            child: Semantics(
              label: 'Owner',
              child: DropdownButton<String>(
                key: const Key('task-owner'),
                value: owner,
                isExpanded: true,
                items: <DropdownMenuItem<String>>[
                  for (final MapEntry<String, String> m in members)
                    DropdownMenuItem<String>(value: m.key, child: Text('Owner: ${m.value}')),
                ],
                onChanged: (String? v) => setState(() => _owner = v),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 48,
            child: OutlinedButton.icon(
              onPressed: () => unawaited(_chooseDue()),
              icon: const Icon(Icons.event_outlined),
              label: Text(_due == null ? 'Due date' : 'Due ${_day(_due!)}'),
            ),
          ),
          const SizedBox(width: 4),
          IconButton.filled(
            tooltip: 'Add task',
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            onPressed: _addTask,
            icon: const Icon(Icons.add),
          ),
        ]),
        if (tasks.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text('No tasks yet. Give each one an owner and, if it matters, a due date.',
                style: text.bodyMedium?.copyWith(color: AppColors.muted)),
          ),
        for (final FamilyTask t in tasks) _taskTile(t, today),
      ],
    );
  }

  Widget _noteTile(FamilyNote n) {
    return ListTile(
      key: Key('note-${n.id}'),
      contentPadding: EdgeInsets.zero,
      minTileHeight: 48,
      leading: Icon(n.pinned ? Icons.push_pin : Icons.sticky_note_2_outlined,
          color: n.pinned ? AppColors.accent : AppColors.muted, semanticLabel: n.pinned ? 'Pinned' : 'Not pinned'),
      title: Text(n.text),
      subtitle: Text('By ${_board.memberName(n.addedBy)}'),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
        IconButton(
          tooltip: n.pinned ? 'Unpin note' : 'Pin note to Family screen',
          icon: Icon(n.pinned ? Icons.push_pin_outlined : Icons.push_pin),
          onPressed: () => _board.setPinned(n.id, !n.pinned),
        ),
        IconButton(
          tooltip: 'Remove note',
          icon: const Icon(Icons.close),
          onPressed: () => _board.removeNote(n.id),
        ),
      ]),
    );
  }

  Widget _taskTile(FamilyTask t, DateTime today) {
    final List<String> bits = <String>[_board.memberName(t.owner)];
    if (t.due != null) {
      bits.add('${t.overdueOn(today) ? 'Overdue' : 'Due'} ${_day(t.due!)}');
    }
    if (t.done) {
      bits.add('Done by ${_board.memberName(t.doneBy!)}');
    }
    return MergeSemantics(
      child: CheckboxListTile(
        key: Key('task-${t.id}'),
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        value: t.done,
        onChanged: (bool? v) => _board.setDone(t.id, v ?? false),
        title: Text(
          t.title,
          style: t.done ? const TextStyle(decoration: TextDecoration.lineThrough, color: AppColors.muted) : null,
        ),
        subtitle: Text(bits.join(' · '),
            style: t.overdueOn(today) ? TextStyle(color: Theme.of(context).colorScheme.error) : null),
        secondary: IconButton(
          tooltip: 'Remove ${t.title}',
          icon: const Icon(Icons.close),
          onPressed: () => _board.removeTask(t.id),
        ),
      ),
    );
  }
}
