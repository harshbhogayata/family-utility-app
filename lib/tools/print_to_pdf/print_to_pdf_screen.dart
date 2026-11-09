import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../app/theme.dart';
import '../../app/widgets/result_bar.dart';
import '../../engines/pdf/print_to_pdf.dart';
import '../../engines/share/share_engine.dart';

String _size(int n) {
  if (n < 1024) {
    return '$n B';
  }
  if (n < 1024 * 1024) {
    return '${(n / 1024).toStringAsFixed(0)} KB';
  }
  return '${(n / (1024 * 1024)).toStringAsFixed(1)} MB';
}

String _when(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
}

/// The real folders: `<documents>/printed` and `<documents>/Saved`.
PrintedPdfs systemPrintedPdfs() {
  Future<Directory> under(String name) async {
    final Directory base = await getApplicationDocumentsDirectory();
    return Directory('${base.path}/$name');
  }

  return PrintedPdfs(
    folder: () => under(PrintToPdfNames.folder),
    savedFolder: () => under('Saved'),
  );
}

/// iOS `Documents/Inbox`, where shared PDFs land; null elsewhere.
Future<String?> systemInboxDir() async {
  if (!Platform.isIOS) {
    return null;
  }
  final Directory base = await getApplicationDocumentsDirectory();
  return '${base.path}/Inbox';
}

/// Feature 017 — Print to PDF: every app's Print (Android) or Share (iOS)
/// becomes a PDF in the app's files. This screen says how, lists what came
/// in, and ends in Share, Save and Undo.
class PrintToPdfScreen extends StatefulWidget {
  const PrintToPdfScreen({
    super.key,
    this.pdfs,
    this.platform = const ChannelPrintToPdfPlatform(),
    this.inboxDir = systemInboxDir,
    this.share,
    this.isIos,
  });

  final PrintedPdfs? pdfs;
  final PrintToPdfPlatform platform;
  final Future<String?> Function() inboxDir;
  final ShareEngine? share;

  /// Overrides the platform check (tests).
  final bool? isIos;

  @override
  State<PrintToPdfScreen> createState() => _PrintToPdfScreenState();
}

class _PrintToPdfScreenState extends State<PrintToPdfScreen> {
  late final PrintedPdfs _pdfs = widget.pdfs ?? systemPrintedPdfs();
  AppLifecycleListener? _life;
  PrintedPdf? _selected;
  bool _loading = true;

  bool get _ios => widget.isIos ?? Platform.isIOS;

  @override
  void initState() {
    super.initState();
    _pdfs.addListener(_changed);
    _life = AppLifecycleListener(onResume: () => unawaited(_refresh()));
    unawaited(_refresh());
  }

  @override
  void dispose() {
    _life?.dispose();
    _pdfs.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (!mounted) {
      return;
    }
    setState(() {
      final PrintedPdf? s = _selected;
      if (s != null && !_pdfs.items.contains(s)) {
        _selected = null;
      }
      _selected ??= _pdfs.items.isEmpty ? null : _pdfs.items.first;
    });
  }

  Future<void> _refresh() async {
    try {
      final String? inbox = await widget.inboxDir();
      if (inbox != null) {
        await _pdfs.adoptInbox(inbox);
      }
      await _pdfs.refresh();
    } catch (_) {
      // Unreadable folder: show what there is.
    }
    if (mounted) {
      setState(() => _loading = false);
    }
  }

  void _toast(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(m)));
    }
  }

  Future<void> _openSettings() async {
    final bool ok = await widget.platform.openPrintSettings();
    if (!ok) {
      _toast('Open Settings > Connected devices > Printing and turn on ${PrintToPdfNames.printerName}.');
    }
  }

  Future<void> _share() async {
    final PrintedPdf? p = _selected;
    if (p == null) {
      _toast('Nothing printed yet');
      return;
    }
    await (widget.share ?? ShareEngine.instance).shareFiles(<String>[p.path]);
  }

  Future<void> _save() async {
    final PrintedPdf? p = _selected;
    if (p == null) {
      _toast('Nothing printed yet');
      return;
    }
    final String where = await _pdfs.keep(p);
    _toast('Saved ${where.split('/').last} in Files');
  }

  Future<void> _remove(PrintedPdf p) async {
    await _pdfs.remove(p);
    _toast('Removed ${p.name}. Undo puts it back.');
  }

  Future<void> _undo() async {
    final String? what = await _pdfs.undo();
    if (what != null) {
      _toast(what);
      return;
    }
    if (mounted) {
      Navigator.of(context).maybePop();
    }
  }

  List<Widget> _howTo(TextTheme text) {
    if (_ios) {
      return <Widget>[
        Text('In any app, tap Print, then Share in the print preview, and pick this app. '
            'The PDF appears here.', style: text.bodyLarge),
      ];
    }
    return <Widget>[
      Text('In any app, tap Print or Share > Print and choose "${PrintToPdfNames.printerName}" as the printer. '
          'The PDF appears here.', style: text.bodyLarge),
      const SizedBox(height: 8),
      Text('First time: turn the printer on once in the phone\'s printing settings.', style: text.bodyMedium),
      const SizedBox(height: 12),
      SizedBox(
        height: 48,
        child: OutlinedButton.icon(
          key: const Key('print-settings'),
          onPressed: _openSettings,
          icon: const Icon(Icons.settings_outlined),
          label: const Text('Open printing settings'),
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final List<PrintedPdf> items = _pdfs.items;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Print to PDF'),
        actions: <Widget>[
          IconButton(
            key: const Key('print-refresh'),
            tooltip: 'Look for new PDFs',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          ..._howTo(text),
          const SizedBox(height: 24),
          Text('Printed PDFs', style: text.titleMedium),
          const SizedBox(height: 8),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator(semanticsLabel: 'Looking for PDFs')),
            )
          else if (items.isEmpty)
            Text('Nothing printed yet.', key: const Key('print-empty'), style: text.bodyMedium)
          else
            for (final PrintedPdf p in items)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                color: p == _selected ? AppColors.accentTint : null,
                child: ListTile(
                  key: Key('printed-${p.name}'),
                  minVerticalPadding: 12,
                  leading: const Icon(Icons.picture_as_pdf_outlined, semanticLabel: 'PDF'),
                  title: Text(p.name),
                  subtitle: Text('${_size(p.size)} · ${_when(p.received)}'),
                  selected: p == _selected,
                  onTap: () => setState(() => _selected = p),
                  trailing: IconButton(
                    key: Key('printed-remove-${p.name}'),
                    tooltip: 'Remove ${p.name}',
                    constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                    onPressed: () => _remove(p),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ),
              ),
          const SizedBox(height: 8),
          Text('Printed PDFs stay on this phone. Nothing is uploaded.', style: text.bodySmall),
        ],
      ),
      bottomNavigationBar: ResultBar(
        onShare: _share,
        onSave: _save,
        onUndo: _undo,
      ),
    );
  }
}
