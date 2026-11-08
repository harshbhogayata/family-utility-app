import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../engines/security/app_lock.dart';
import '../../engines/security/secure_notes.dart';
import 'note_edit_screen.dart';

/// Feature 057 — the list of secure notes. Each field can be copied from
/// here without opening the note; secret values stay masked.
class SecureNotesScreen extends StatefulWidget {
  const SecureNotesScreen({super.key, SecureNotes? notes}) : _notes = notes;

  final SecureNotes? _notes;

  @override
  State<SecureNotesScreen> createState() => _SecureNotesScreenState();
}

class _SecureNotesScreenState extends State<SecureNotesScreen> {
  SecureNotes get notes => widget._notes ?? SecureNotes.instance;

  @override
  void initState() {
    super.initState();
    if (!notes.isLoaded) {
      notes.load();
    }
  }

  @override
  void dispose() {
    notes.clearClipboardNow();
    super.dispose();
  }

  Future<void> _copy(NoteField f) async {
    await notes.copy(f.value);
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('${f.label} copied. The clipboard clears in ${notes.clearClipboardAfter.inSeconds} s.'),
      ));
  }

  Future<void> _open(SecureNote? note) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext _) => NoteEditScreen(notes: notes, existing: note),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final bool lockOn = AppLock.instance.isEnabled;
    return Scaffold(
      appBar: AppBar(title: const Text('Secure notes')),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('new-note'),
        onPressed: () => _open(null),
        icon: const Icon(Icons.add),
        label: const Text('New note'),
      ),
      body: ListenableBuilder(
        listenable: notes,
        builder: (BuildContext context, Widget? _) {
          final List<SecureNote> all = notes.notes;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: <Widget>[
              if (!lockOn)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: <Widget>[
                      const Icon(Icons.lock_open_outlined, size: 18, color: AppColors.muted),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Notes are encrypted on this phone. Set a PIN in App lock to ask for it before they open.',
                          style: text.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
              if (notes.loadError != null)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(notes.loadError!, style: text.bodyMedium),
                  ),
                ),
              if (notes.isLoaded && all.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Column(
                    children: <Widget>[
                      const Icon(Icons.sticky_note_2_outlined, size: 40, color: AppColors.accent),
                      const SizedBox(height: 12),
                      Text('No notes yet', style: text.titleMedium),
                      const SizedBox(height: 4),
                      Text(
                        'Keep ID numbers, Wi-Fi keys and card last-fours here. Encrypted, never uploaded.',
                        style: text.bodyMedium,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              for (final SecureNote n in all) ...<Widget>[
                _NoteCard(note: n, onOpen: () => _open(n), onCopy: _copy),
                const SizedBox(height: AppRadius.gridGap),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({required this.note, required this.onOpen, required this.onCopy});

  final SecureNote note;
  final VoidCallback onOpen;
  final void Function(NoteField) onCopy;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          InkWell(
            onTap: onOpen,
            child: Semantics(
              button: true,
              label: 'Open note ${note.title}',
              child: ExcludeSemantics(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
                  child: Row(
                    children: <Widget>[
                      const Icon(Icons.lock_outline, size: 18, color: AppColors.accent),
                      const SizedBox(width: 8),
                      Expanded(child: Text(note.title.isEmpty ? 'Untitled' : note.title, style: text.titleMedium)),
                      const Icon(Icons.chevron_right, color: AppColors.muted),
                    ],
                  ),
                ),
              ),
            ),
          ),
          for (final NoteField f in note.fields)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 4, 0),
              child: Row(
                children: <Widget>[
                  SizedBox(width: 96, child: Text(f.label, style: text.bodyMedium)),
                  Expanded(
                    child: Text(
                      f.secret ? '•' * f.value.length.clamp(4, 12).toInt() : f.value,
                      style: text.bodyLarge,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    key: ValueKey<String>('copy-${note.id}-${f.label}'),
                    tooltip: 'Copy ${f.label}',
                    onPressed: f.value.isEmpty ? null : () => onCopy(f),
                    icon: const Icon(Icons.copy_outlined),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 6),
        ],
      ),
    );
  }
}
