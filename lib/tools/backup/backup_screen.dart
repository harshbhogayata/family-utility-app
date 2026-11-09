import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../app/widgets/result_bar.dart';
import '../../engines/family/family_space.dart';
import '../../engines/platform/backup_export.dart';
import '../../engines/share/share_engine.dart';

typedef PickBackupFolder = Future<String?> Function();
typedef PickBackupFile = Future<Uint8List?> Function();
typedef ShareBackupFile = Future<void> Function(String path);

/// Feature 120 — Backup and export.
class BackupScreen extends StatefulWidget {
  const BackupScreen({
    super.key,
    this.engine,
    this.pickFolder,
    this.pickFile,
    this.shareFile,
    this.defaultFolder,
  });

  final BackupExport? engine;
  final PickBackupFolder? pickFolder;
  final PickBackupFile? pickFile;
  final ShareBackupFile? shareFile;

  /// Where a backup goes when no folder was picked: the family's own sync
  /// folder if there is one, else the app's Documents/Backups.
  final Future<String> Function()? defaultFolder;

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  final TextEditingController _pw = TextEditingController();
  final TextEditingController _confirm = TextEditingController();
  bool _busy = false;
  String? _problem;
  String? _result;

  BackupExport get _b => widget.engine ?? BackupExport.instance;

  @override
  void dispose() {
    _pw.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<String> _folder() async {
    final Future<String> Function()? d = widget.defaultFolder;
    if (d != null) {
      return d();
    }
    final String? sync = FamilySpace.instance.identity?.syncFolder;
    if (sync != null) {
      return '$sync/backups';
    }
    return '${(await getApplicationDocumentsDirectory()).path}/Backups';
  }

  Future<String?> _pickFolder() async {
    final PickBackupFolder? p = widget.pickFolder;
    if (p != null) {
      return p();
    }
    return FilePicker.platform.getDirectoryPath(dialogTitle: 'Back up to this folder');
  }

  Future<Uint8List?> _pickFile() async {
    final PickBackupFile? p = widget.pickFile;
    if (p != null) {
      return p();
    }
    final FilePickerResult? r = await FilePicker.platform.pickFiles(withData: true);
    if (r == null || r.files.isEmpty) {
      return null;
    }
    final PlatformFile f = r.files.first;
    return f.bytes ?? (f.path == null ? null : await File(f.path!).readAsBytes());
  }

  void _snack(String s) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
    }
  }

  Future<void> _run(Future<String> Function() job) async {
    setState(() => _busy = true);
    try {
      final String r = await job();
      if (mounted) {
        setState(() => _result = r);
      }
    } on BackupError catch (e) {
      _snack(e.message);
    } catch (_) {
      _snack('That folder could not be written');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _backup({bool pick = false}) async {
    final String? problem = BackupExport.passwordProblem(_pw.text, _confirm.text);
    setState(() => _problem = problem);
    if (problem != null) {
      return;
    }
    final String? folder = pick ? await _pickFolder() : await _folder();
    if (folder == null) {
      return;
    }
    await _run(() async => 'Backup saved to ${await _b.backupTo(folder, _pw.text)}');
  }

  Future<void> _restore() async {
    final Uint8List? bytes = await _pickFile();
    if (bytes == null || !mounted) {
      return;
    }
    if (!BackupExport.isBackup(bytes)) {
      _snack('This is not a backup made by this app.');
      return;
    }
    final String? pw = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => const _PasswordDialog(),
    );
    if (pw == null) {
      return;
    }
    await _run(() async {
      final int n = await _b.restore(bytes, pw);
      return 'Restored · $n ${n == 1 ? 'item' : 'items'} brought back';
    });
  }

  Future<void> _export(ExportSection s, {required bool csv}) async {
    final String folder = '${await _folder()}/Exports';
    await _run(() async => 'Exported to ${await _b.exportTo(folder, s, csv: csv)}');
  }

  Future<void> _schedule(BackupFrequency f) async {
    if (f != BackupFrequency.off) {
      final String? problem = BackupExport.passwordProblem(_pw.text, _confirm.text);
      setState(() => _problem = problem);
      if (problem != null) {
        _snack('Type a backup password first');
        return;
      }
    }
    final String folder = _b.settings.folder ?? await _folder();
    await _b.setSchedule(f, folderPath: folder, password: f == BackupFrequency.off ? null : _pw.text);
    _snack(f == BackupFrequency.off ? 'Automatic backup off' : '${f.label} to $folder');
  }

  Future<void> _share() async {
    final String? path = _b.lastWritten;
    if (path == null) {
      _snack('Back up or export first');
      return;
    }
    final ShareBackupFile? s = widget.shareFile;
    if (s != null) {
      await s(path);
    } else {
      await ShareEngine.instance.shareFiles(<String>[path], subject: 'Family utility backup');
    }
  }

  Future<void> _undo() async {
    final bool ok = await _b.undo();
    if (mounted) {
      setState(() => _result = ok ? null : _result);
    }
    _snack(ok ? 'Undone' : 'Nothing to undo');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Backup and export')),
      bottomNavigationBar: ResultBar(
        onShare: () => unawaited(_share()),
        onSave: () => unawaited(_backup(pick: true)),
        onUndo: () => unawaited(_undo()),
      ),
      body: ListenableBuilder(listenable: _b, builder: (BuildContext context, Widget? _) => _body(context)),
    );
  }

  Widget _body(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final BackupSettings s = _b.settings;
    final DateTime? last = s.lastAt;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Text(
          'One locked file holds the whole app: family data and settings. '
          'Keep it in your own Drive or iCloud folder and restore it on a new phone with the password. '
          'The app never uploads it anywhere.',
          style: text.bodyMedium,
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('backup-password'),
          controller: _pw,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Backup password', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 8),
        TextField(
          key: const Key('backup-confirm'),
          controller: _confirm,
          obscureText: true,
          decoration: InputDecoration(
            labelText: 'Type it again',
            border: const OutlineInputBorder(),
            errorText: _problem,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: <Widget>[
            Expanded(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size(44, 48)),
                onPressed: _busy ? null : () => unawaited(_backup()),
                icon: const Icon(Icons.backup_outlined),
                label: const Text('Back up now'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size(44, 48)),
                onPressed: _busy ? null : () => unawaited(_restore()),
                icon: const Icon(Icons.restore),
                label: const Text('Restore'),
              ),
            ),
          ],
        ),
        if (_busy) const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator()),
        if (_result != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Semantics(liveRegion: true, child: Text(_result!, style: text.bodySmall)),
          ),
        const SizedBox(height: 16),
        Text('Automatic backup', style: text.titleMedium),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          children: <Widget>[
            for (final BackupFrequency f in BackupFrequency.values)
              ChoiceChip(
                label: Text(f.label),
                selected: s.frequency == f,
                materialTapTargetSize: MaterialTapTargetSize.padded,
                onSelected: (_) => unawaited(_schedule(f)),
              ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            <String>[
              if (s.folder != null) 'Folder: ${s.folder}',
              if (last != null) 'Last backup: ${last.year}-${_two(last.month)}-${_two(last.day)} ${_two(last.hour)}:${_two(last.minute)}',
              if (_b.lastError != null) _b.lastError!,
            ].join('\n'),
            style: text.bodySmall,
          ),
        ),
        const SizedBox(height: 16),
        Text('Export a section', style: text.titleMedium),
        for (final ExportSection sec in _b.sections())
          ListTile(
            contentPadding: EdgeInsets.zero,
            minTileHeight: 48,
            title: Text(sec.label),
            subtitle: Text('${sec.rows().length} rows'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                TextButton(
                  style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                  onPressed: _busy ? null : () => unawaited(_export(sec, csv: true)),
                  child: Text('CSV', semanticsLabel: 'Export ${sec.label} as CSV'),
                ),
                TextButton(
                  style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                  onPressed: _busy ? null : () => unawaited(_export(sec, csv: false)),
                  child: Text('JSON', semanticsLabel: 'Export ${sec.label} as JSON'),
                ),
              ],
            ),
          ),
      ],
    );
  }

  static String _two(int n) => n.toString().padLeft(2, '0');
}

class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog();

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final TextEditingController _c = TextEditingController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Backup password'),
      content: TextField(
        key: const Key('restore-password'),
        controller: _c,
        obscureText: true,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Password'),
      ),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.of(context).pop(_c.text), child: const Text('Restore')),
      ],
    );
  }
}
