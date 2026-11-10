import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../app/widgets/result_bar.dart';
import '../../engines/records/contacts_backup.dart';
import '../../engines/share/share_engine.dart';
import '../../platform/contacts_platform.dart';

/// Feature 103 — Contacts backup: every contact to one .vcf with photos,
/// and a restore that merges without making duplicates.
class ContactsBackupScreen extends StatefulWidget {
  const ContactsBackupScreen({super.key, this.source, this.pickVcf, this.share, this.save, this.now});

  final ContactsSource? source;

  /// Returns the text of a chosen .vcf; defaults to the system picker.
  final Future<String?> Function()? pickVcf;

  /// Shares the .vcf; defaults to the share sheet.
  final Future<void> Function(String vcf, String name)? share;

  /// Saves the .vcf and returns where; defaults to the app's documents.
  final Future<String?> Function(String vcf, String name)? save;
  final DateTime Function()? now;

  @override
  State<ContactsBackupScreen> createState() => _ContactsBackupScreenState();
}

class _ContactsBackupScreenState extends State<ContactsBackupScreen> {
  ContactsSource get _source => widget.source ?? const PhoneContactsSource();
  DateTime _now() => (widget.now ?? DateTime.now)();

  String? _vcf;
  int _count = 0;
  int _photos = 0;
  RestorePlan? _plan;
  String _status = '';
  bool _busy = false;

  void _snack(String s) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
    }
  }

  Future<void> _backup() async {
    setState(() => _busy = true);
    try {
      if (!await _source.allowed(write: false)) {
        setState(() => _status = 'Contacts permission is off. Turn it on in Settings to back up.');
        return;
      }
      final List<BackupContact> all = await _source.readAll();
      setState(() {
        _vcf = ContactsBackup.toVcf(all);
        _count = all.length;
        _photos = all.where((BackupContact c) => c.photo != null && c.photo!.isNotEmpty).length;
        _plan = null;
        _status = 'Backed up $_count contacts ($_photos with photos). Share or save the file.';
      });
    } catch (e) {
      setState(() => _status = 'Could not read contacts: $e');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  static Future<String?> _pickSystem() async {
    final FilePickerResult? r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: <String>['vcf'], withData: true);
    final PlatformFile? f = r == null || r.files.isEmpty ? null : r.files.first;
    if (f == null) {
      return null;
    }
    final List<int>? data = f.bytes ?? (f.path == null ? null : await File(f.path!).readAsBytes());
    return data == null ? null : utf8.decode(data, allowMalformed: true);
  }

  Future<void> _chooseRestore() async {
    final String? text = await (widget.pickVcf ?? _pickSystem)();
    if (text == null) {
      return;
    }
    final List<BackupContact> incoming = ContactsBackup.parse(text);
    if (incoming.isEmpty) {
      setState(() => _status = 'No contacts found in that file.');
      return;
    }
    setState(() => _busy = true);
    try {
      if (!await _source.allowed(write: true)) {
        setState(() => _status = 'Contacts permission is off. Turn it on in Settings to restore.');
        return;
      }
      final RestorePlan p = ContactsBackup.plan(await _source.readAll(), incoming);
      setState(() {
        _plan = p;
        _status = p.isEmpty
            ? 'All ${incoming.length} contacts are already on this phone.'
            : 'Restore adds ${p.add.length}, adds details to ${p.update.length}, skips ${p.same} already here.';
      });
    } catch (e) {
      setState(() => _status = 'Could not read contacts: $e');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _restore() async {
    final RestorePlan? p = _plan;
    if (p == null || p.isEmpty) {
      return;
    }
    setState(() => _busy = true);
    try {
      final ({int added, int updated}) r = await ContactsBackup.apply(_source, p);
      setState(() {
        _plan = null;
        _status = 'Restored: ${r.added} added, ${r.updated} updated, no duplicates.';
      });
    } catch (e) {
      setState(() => _status = 'Restore stopped: $e');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  String get _name => ContactsBackup.fileName(_now());

  Future<void> _share() async {
    final String? v = _vcf;
    if (v == null) {
      _snack('Back up first');
      return;
    }
    final Future<void> Function(String, String)? s = widget.share;
    if (s != null) {
      await s(v, _name);
      return;
    }
    final Directory dir = await getTemporaryDirectory();
    final File f = File('${dir.path}/$_name');
    await f.writeAsString(v);
    await ShareEngine.instance.shareFiles(<String>[f.path]);
  }

  static Future<String?> _saveToDocuments(String vcf, String name) async {
    final Directory dir = await getApplicationDocumentsDirectory();
    final File f = File('${dir.path}/$name');
    await f.writeAsString(vcf);
    return f.path;
  }

  Future<void> _save() async {
    final String? v = _vcf;
    if (v == null) {
      _snack('Back up first');
      return;
    }
    String? where;
    try {
      where = await (widget.save ?? _saveToDocuments)(v, _name);
    } catch (_) {
      where = null;
    }
    _snack(where == null ? 'Could not save the file' : 'Saved to $where');
  }

  void _undo() {
    if (_vcf == null && _plan == null) {
      _snack('Nothing to undo');
      return;
    }
    setState(() {
      _vcf = null;
      _plan = null;
      _status = '';
    });
    _snack('Undone');
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final RestorePlan? p = _plan;
    return Scaffold(
      appBar: AppBar(title: const Text('Contacts backup')),
      bottomNavigationBar: ResultBar(
        onShare: () => unawaited(_share()),
        onSave: () => unawaited(_save()),
        onUndo: _undo,
        saveLabel: 'Save .vcf',
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: <Widget>[
          Text('Every contact with photos in one .vcf file. Restore it on a new phone; contacts already there are not duplicated. Nothing is uploaded.',
              style: text.bodyMedium),
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const Key('contacts-backup'),
            style: FilledButton.styleFrom(minimumSize: const Size(88, 48)),
            onPressed: _busy ? null : () => unawaited(_backup()),
            icon: const Icon(Icons.backup_outlined),
            label: const Text('Back up all contacts'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            key: const Key('contacts-restore-pick'),
            style: OutlinedButton.styleFrom(minimumSize: const Size(88, 48)),
            onPressed: _busy ? null : () => unawaited(_chooseRestore()),
            icon: const Icon(Icons.restore_outlined),
            label: const Text('Restore from a .vcf file'),
          ),
          const SizedBox(height: 16),
          if (_busy) const LinearProgressIndicator(),
          if (_status.isNotEmpty)
            Semantics(
              liveRegion: true,
              child: Text(_status, key: const Key('contacts-status'), style: text.bodyLarge),
            ),
          if (p != null && !p.isEmpty) ...<Widget>[
            const SizedBox(height: 12),
            for (final BackupContact c in p.add.take(20))
              ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.person_add_alt_outlined), title: Text(c.name.isNotEmpty ? c.name : (c.phones.isNotEmpty ? c.phones.first : c.emails.first))),
            for (final BackupContact c in p.update.take(20))
              ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.merge_outlined), title: Text(c.name), subtitle: const Text('Adds missing details')),
            const SizedBox(height: 8),
            FilledButton(
              key: const Key('contacts-restore'),
              style: FilledButton.styleFrom(minimumSize: const Size(88, 48)),
              onPressed: _busy ? null : () => unawaited(_restore()),
              child: const Text('Restore'),
            ),
          ],
        ],
      ),
    );
  }
}
