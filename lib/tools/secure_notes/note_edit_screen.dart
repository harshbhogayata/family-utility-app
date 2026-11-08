import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../app/widgets/result_bar.dart';
import '../../engines/security/secure_notes.dart';
import '../../engines/share/share_engine.dart';

/// Edit or create one secure note. Ends in Share / Save / Undo: Save writes
/// the encrypted blob, Undo returns to the last saved version.
class NoteEditScreen extends StatefulWidget {
  const NoteEditScreen({super.key, required this.notes, this.existing});

  final SecureNotes notes;
  final SecureNote? existing;

  @override
  State<NoteEditScreen> createState() => _NoteEditScreenState();
}

class _FieldRow {
  _FieldRow(NoteField f)
      : label = TextEditingController(text: f.label),
        value = TextEditingController(text: f.value),
        secret = f.secret;

  final TextEditingController label;
  final TextEditingController value;
  bool secret;
  bool reveal = false;

  NoteField toField() => NoteField(label: label.text.trim(), value: value.text, secret: secret);

  void dispose() {
    label.dispose();
    value.dispose();
  }
}

class _NoteEditScreenState extends State<NoteEditScreen> {
  late SecureNote _saved;
  late final TextEditingController _title;
  late final TextEditingController _note;
  final List<_FieldRow> _rows = <_FieldRow>[];

  /// Controllers taken out of the tree; disposed with the screen so a
  /// TextField being rebuilt never touches a disposed controller.
  final List<_FieldRow> _retired = <_FieldRow>[];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _saved = widget.existing ??
        SecureNote(id: SecureNotes.newId(), title: '', updatedAt: DateTime.now());
    _title = TextEditingController(text: _saved.title);
    _note = TextEditingController(text: _saved.note);
    _loadRows(_saved);
  }

  void _loadRows(SecureNote from) {
    _retired.addAll(_rows);
    _rows
      ..clear()
      ..addAll(from.fields.map(_FieldRow.new));
  }

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    for (final _FieldRow r in _rows) {
      r.dispose();
    }
    for (final _FieldRow r in _retired) {
      r.dispose();
    }
    super.dispose();
  }

  SecureNote _draft() => _saved.copyWith(
        title: _title.text.trim(),
        fields: _rows.map((_FieldRow r) => r.toField()).where((NoteField f) => f.label.isNotEmpty || f.value.isNotEmpty).toList(),
        note: _note.text,
      );

  bool get _dirty {
    final SecureNote d = _draft();
    return d.title != _saved.title || d.note != _saved.note || !_sameFields(d.fields, _saved.fields);
  }

  static bool _sameFields(List<NoteField> a, List<NoteField> b) {
    if (a.length != b.length) {
      return false;
    }
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }

  void _toast(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(m)));
    }
  }

  Future<void> _save() async {
    if (_busy) {
      return;
    }
    final SecureNote d = _draft();
    if (d.title.isEmpty && d.fields.isEmpty && d.note.trim().isEmpty) {
      _toast('Nothing to save yet');
      return;
    }
    setState(() => _busy = true);
    try {
      _saved = await widget.notes.save(d);
      _toast('Saved, encrypted on this phone');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _undo() {
    if (!_dirty) {
      Navigator.of(context).maybePop();
      return;
    }
    setState(() {
      _title.text = _saved.title;
      _note.text = _saved.note;
      _loadRows(_saved);
    });
    _toast('Back to the saved version');
  }

  Future<void> _share() async {
    await ShareEngine.instance.shareText(_draft().toPlainText(), subject: _draft().title);
  }

  Future<void> _delete() async {
    final bool? sure = await showDialog<bool>(
      context: context,
      builder: (BuildContext d) => AlertDialog(
        title: const Text('Delete this note?'),
        content: const Text('It cannot be recovered.'),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.of(d).pop(false), child: const Text('Keep')),
          TextButton(onPressed: () => Navigator.of(d).pop(true), child: const Text('Delete')),
        ],
      ),
    );
    if (sure ?? false) {
      await widget.notes.delete(_saved.id);
      if (mounted) {
        Navigator.of(context).maybePop();
      }
    }
  }

  void _addField([String label = '']) {
    setState(() => _rows.add(_FieldRow(NoteField(label: label, value: ''))));
  }

  void _applyTemplate(String name) {
    setState(() {
      if (_title.text.trim().isEmpty) {
        _title.text = name;
      }
      for (final String label in NoteTemplates.fields[name] ?? const <String>[]) {
        if (!_rows.any((_FieldRow r) => r.label.text.trim() == label)) {
          _rows.add(_FieldRow(NoteField(label: label, value: '')));
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? 'New note' : 'Edit note'),
        actions: <Widget>[
          if (widget.existing != null)
            IconButton(
              key: const Key('delete-note'),
              tooltip: 'Delete note',
              onPressed: _delete,
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          TextField(
            key: const Key('note-title'),
            controller: _title,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Title'),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: <Widget>[
              for (final String name in NoteTemplates.fields.keys)
                ActionChip(
                  key: ValueKey<String>('template-$name'),
                  label: Text(name),
                  onPressed: () => _applyTemplate(name),
                ),
            ],
          ),
          const SizedBox(height: 16),
          for (int i = 0; i < _rows.length; i++) _fieldEditor(i),
          OutlinedButton.icon(
            key: const Key('add-field'),
            onPressed: () => _addField(),
            icon: const Icon(Icons.add),
            label: const Text('Add field'),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('note-text'),
            controller: _note,
            minLines: 3,
            maxLines: 8,
            decoration: const InputDecoration(labelText: 'Notes'),
          ),
          const SizedBox(height: 12),
          Text(
            'Encrypted on this phone with a key in its secure storage. Never uploaded.',
            style: text.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
      bottomNavigationBar: ResultBar(
        onShare: _share,
        onSave: _save,
        onUndo: _undo,
      ),
    );
  }

  Widget _fieldEditor(int i) {
    final _FieldRow r = _rows[i];
    return Padding(
      padding: const EdgeInsets.only(bottom: AppRadius.gridGap),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          SizedBox(
            width: 110,
            child: TextField(
              key: ValueKey<String>('field-label-$i'),
              controller: r.label,
              decoration: const InputDecoration(labelText: 'Label', isDense: true),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              key: ValueKey<String>('field-value-$i'),
              controller: r.value,
              obscureText: r.secret && !r.reveal,
              decoration: InputDecoration(
                labelText: 'Value',
                isDense: true,
                suffixIcon: IconButton(
                  tooltip: r.reveal ? 'Hide value' : 'Show value',
                  onPressed: () => setState(() => r.reveal = !r.reveal),
                  icon: Icon(r.reveal ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                ),
              ),
            ),
          ),
          IconButton(
            key: ValueKey<String>('field-remove-$i'),
            tooltip: 'Remove field',
            onPressed: () => setState(() => _retired.add(_rows.removeAt(i))),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }
}
