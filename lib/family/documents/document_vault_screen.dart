import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../app/theme.dart';
import '../../app/widgets/result_bar.dart';
import '../../engines/family/document_vault.dart';
import '../../engines/family/family_store.dart';
import '../../engines/family/family_space.dart';
import '../../engines/image/redact.dart';
import '../../engines/pdf/images_to_pdf.dart';
import '../../engines/share/share_engine.dart';
import '../../platform/document_vault_platform.dart';
import '../../platform/face_platform.dart';
import '../../platform/mlkit_text_platform.dart';

/// Picks the document file; null on cancel.
typedef DocumentFilePick = Future<Uint8List?> Function();

/// Picks an expiry day; null on cancel.
typedef DocumentDatePick = Future<DateTime?> Function(BuildContext context, DateTime initial);

/// Sends a file (name, bytes) out of the app.
typedef DocumentSend = Future<void> Function(String name, Uint8List bytes);

typedef DocumentTextAction = Future<String?> Function(String text);

/// Feature 074 — the family's ID papers per member, encrypted on the
/// phone, with expiry reminders and quick "send as PDF" / "send masked".
class DocumentVaultScreen extends StatefulWidget {
  const DocumentVaultScreen({
    super.key,
    this.vault,
    this.pickFile,
    this.pickDate,
    this.send,
    this.share,
    this.save,
    this.masker,
    this.toPdf,
  });

  final DocumentVault? vault;
  final DocumentFilePick? pickFile;
  final DocumentDatePick? pickDate;
  final DocumentSend? send;
  final DocumentTextAction? share;
  final DocumentTextAction? save;
  final DocumentMasker? masker;
  final DocumentPdfMaker? toPdf;

  @override
  State<DocumentVaultScreen> createState() => _DocumentVaultScreenState();
}

class _DocumentVaultScreenState extends State<DocumentVaultScreen> {
  bool _busy = false;

  DocumentVault get _vault => widget.vault ?? DocumentVault.instance!;

  static const List<String> _months = <String>[
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec', //
  ];
  static String _day(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

  void _snack(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _run(Future<void> Function() job) async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      await job();
    } on DocumentVaultException catch (e) {
      if (mounted) {
        _snack(e.message);
      }
    } catch (e) {
      if (mounted) {
        _snack('That did not work: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  static Future<Uint8List?> _pickFromPhone() async {
    final FilePickerResult? r = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: <String>['jpg', 'jpeg', 'png', 'heic', 'webp', 'pdf'],
      withData: true,
    );
    return r?.files.single.bytes;
  }

  Future<DateTime?> _date(DateTime initial) {
    final DocumentDatePick pick = widget.pickDate ??
        (BuildContext c, DateTime i) => showDatePicker(
              context: c,
              initialDate: i,
              firstDate: DateTime(2000),
              lastDate: DateTime(2100),
            );
    return pick(context, initial);
  }

  Future<void> _add() async {
    final Uint8List? bytes = await (widget.pickFile ?? _pickFromPhone)();
    if (bytes == null || !mounted) {
      return;
    }
    final _NewDoc? d = await showDialog<_NewDoc>(
      context: context,
      builder: (BuildContext c) => _AddDocumentDialog(vault: _vault, pickDate: _date),
    );
    if (d == null) {
      return;
    }
    await _run(() async {
      final FamilyDocument doc =
          await _vault.add(member: d.member, type: d.type, bytes: bytes, title: d.title, expiry: d.expiry);
      if (mounted) {
        _snack('${doc.title} added, encrypted on this phone');
      }
    });
  }

  Future<Uint8List> _pdf(Uint8List image) =>
      (widget.toPdf ?? (Uint8List b) => ImagesToPdf().build(<Uint8List>[b], const ImagesToPdfOptions()))(image);

  Future<void> _send(String name, Uint8List bytes) async {
    final DocumentSend? s = widget.send;
    if (s != null) {
      await s(name, bytes);
      return;
    }
    final Directory tmp = await getTemporaryDirectory();
    final File f = File('${tmp.path}/$name');
    await f.writeAsBytes(bytes, flush: true);
    await ShareEngine.instance.shareFiles(<String>[f.path]);
  }

  static String _fileName(FamilyDocument d, String suffix) =>
      '${d.title.replaceAll(RegExp(r'[^A-Za-z0-9 ._-]'), '').trim()}$suffix.pdf';

  void _sendPdf(FamilyDocument d) => unawaited(_run(() async {
        await _send(_fileName(d, ''), await _vault.asPdf(d, _pdf));
      }));

  void _sendMasked(FamilyDocument d) => unawaited(_run(() async {
        final DocumentMasker masker =
            widget.masker ?? const RedactorDocumentMasker(Redactor(faces: MlKitFaceFinder(), text: MlKitTextRecognizer()));
        await _send(_fileName(d, ' (masked)'), await _vault.maskedPdf(d, masker, _pdf));
      }));

  Future<void> _changeExpiry(FamilyDocument d) async {
    final DateTime? e = await _date(d.expiry ?? DateTime.now());
    if (e != null) {
      _vault.setExpiry(d.id, e);
    }
  }

  Future<void> _share() async {
    final String text = _vault.toText();
    final DocumentTextAction? s = widget.share;
    if (s != null) {
      await s(text);
    } else {
      await ShareEngine.instance.shareText(text, subject: 'Family documents');
    }
  }

  Future<void> _save() async {
    final String text = _vault.toText();
    final DocumentTextAction s = widget.save ?? _saveToDocuments;
    String? where;
    try {
      where = await s(text);
    } catch (_) {
      where = null;
    }
    if (mounted) {
      _snack(where == null ? 'Could not save the list' : 'Saved to $where');
    }
  }

  static Future<String?> _saveToDocuments(String text) async {
    final Directory dir = await getApplicationDocumentsDirectory();
    final File f = File('${dir.path}/Family documents.txt');
    await f.writeAsString(text);
    return f.path;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Family documents')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy ? null : () => unawaited(_add()),
        icon: const Icon(Icons.add),
        label: const Text('Add document'),
      ),
      bottomNavigationBar: ResultBar(
        onShare: () => unawaited(_share()),
        onSave: () => unawaited(_save()),
        onUndo: () => _snack(_vault.undo() ? 'Undone' : 'Nothing to undo'),
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge(<Listenable>[_vault, _vault.store]),
        builder: (BuildContext context, Widget? _) => _body(context),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final List<MapEntry<String, List<FamilyDocument>>> groups = _vault.byMember();
    final DateTime today = DateTime.now();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: <Widget>[
        if (_busy) const LinearProgressIndicator(),
        Text(
          'Files are encrypted on the phone that added them. The family sees '
          'each card\'s name and expiry, and gets reminders 30, 7 and 1 day before.',
          style: text.bodySmall,
        ),
        if (groups.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text('No documents yet. Add an Aadhaar, PAN, passport, vehicle papers or insurance.',
                style: text.bodyMedium),
          ),
        for (final MapEntry<String, List<FamilyDocument>> g in groups) ...<Widget>[
          Padding(
            padding: const EdgeInsets.only(top: 16, bottom: 4),
            child: Semantics(header: true, child: Text(_vault.memberName(g.key), style: text.titleSmall)),
          ),
          for (final FamilyDocument d in g.value) _tile(d, today),
        ],
      ],
    );
  }

  Widget _tile(FamilyDocument d, DateTime today) {
    final int? left = d.daysLeft(today);
    String sub = d.type.label;
    if (d.expiry != null) {
      sub += left! < 0 ? ' · Expired ${_day(d.expiry!)}' : ' · Expires ${_day(d.expiry!)} · $left days left';
    } else {
      sub += ' · No expiry';
    }
    final bool urgent = left != null && left <= 30;
    return ListTile(
      key: Key('doc-${d.id}'),
      contentPadding: EdgeInsets.zero,
      minTileHeight: 48,
      leading: Icon(urgent ? Icons.warning_amber_rounded : Icons.badge_outlined,
          color: urgent ? Theme.of(context).colorScheme.error : AppColors.accent,
          semanticLabel: urgent ? 'Expiring soon' : null),
      title: Text(d.title),
      subtitle: Text(sub, style: urgent ? TextStyle(color: Theme.of(context).colorScheme.error) : null),
      trailing: PopupMenuButton<String>(
        tooltip: 'Actions for ${d.title}',
        onSelected: (String v) {
          switch (v) {
            case 'pdf':
              _sendPdf(d);
            case 'masked':
              _sendMasked(d);
            case 'expiry':
              unawaited(_changeExpiry(d));
            case 'remove':
              _vault.remove(d.id);
          }
        },
        itemBuilder: (BuildContext c) => const <PopupMenuEntry<String>>[
          PopupMenuItem<String>(value: 'pdf', child: Text('Send as PDF')),
          PopupMenuItem<String>(value: 'masked', child: Text('Send masked')),
          PopupMenuItem<String>(value: 'expiry', child: Text('Change expiry date')),
          PopupMenuItem<String>(value: 'remove', child: Text('Remove')),
        ],
      ),
    );
  }
}

class _NewDoc {
  const _NewDoc(this.member, this.type, this.title, this.expiry);
  final String member;
  final FamilyDocType type;
  final String title;
  final DateTime? expiry;
}

class _AddDocumentDialog extends StatefulWidget {
  const _AddDocumentDialog({required this.vault, required this.pickDate});

  final DocumentVault vault;
  final Future<DateTime?> Function(DateTime initial) pickDate;

  @override
  State<_AddDocumentDialog> createState() => _AddDocumentDialogState();
}

class _AddDocumentDialogState extends State<_AddDocumentDialog> {
  final TextEditingController _title = TextEditingController();
  late String _member = widget.vault.me;
  FamilyDocType _type = FamilyDocType.aadhaar;
  DateTime? _expiry;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final List<FamilyRecord> members = widget.vault.store.list(FamilySpace.members);
    final List<MapEntry<String, String>> choices = <MapEntry<String, String>>[
      for (final FamilyRecord r in members) MapEntry<String, String>(r.id, '${r.fields['name'] ?? 'Member'}'),
      if (members.every((FamilyRecord r) => r.id != widget.vault.me)) MapEntry<String, String>(widget.vault.me, 'Me'),
    ];
    return AlertDialog(
      title: const Text('Add document'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
          Semantics(
            label: 'Whose document',
            child: DropdownButton<String>(
              key: const Key('doc-member'),
              value: _member,
              isExpanded: true,
              items: <DropdownMenuItem<String>>[
                for (final MapEntry<String, String> m in choices)
                  DropdownMenuItem<String>(value: m.key, child: Text('For ${m.value}')),
              ],
              onChanged: (String? v) => setState(() => _member = v ?? _member),
            ),
          ),
          Semantics(
            label: 'Kind of document',
            child: DropdownButton<FamilyDocType>(
              key: const Key('doc-type'),
              value: _type,
              isExpanded: true,
              items: <DropdownMenuItem<FamilyDocType>>[
                for (final FamilyDocType t in FamilyDocType.values)
                  DropdownMenuItem<FamilyDocType>(value: t, child: Text(t.label)),
              ],
              onChanged: (FamilyDocType? v) => setState(() => _type = v ?? _type),
            ),
          ),
          TextField(
            controller: _title,
            decoration: const InputDecoration(labelText: 'Name (optional)'),
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 48,
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () async {
                final DateTime? d = await widget.pickDate(_expiry ?? DateTime.now());
                if (d != null && mounted) {
                  setState(() => _expiry = d);
                }
              },
              icon: const Icon(Icons.event_outlined),
              label: Text(_expiry == null
                  ? 'Expiry date (optional)'
                  : 'Expires ${_expiry!.day} ${_DocumentVaultScreenState._months[_expiry!.month - 1]} ${_expiry!.year}'),
            ),
          ),
        ]),
      ),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_NewDoc(_member, _type, _title.text, _expiry)),
          child: const Text('Add'),
        ),
      ],
    );
  }
}
