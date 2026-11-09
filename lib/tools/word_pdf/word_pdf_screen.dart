import 'package:flutter/material.dart';

import '../../app/widgets/result_bar.dart';
import '../../engines/convert/convert_registry.dart';
import '../../engines/convert/file_kind.dart';
import '../../engines/share/share_engine.dart';
import '../convert_anything/convert_anything_screen.dart';

/// Feature 018 — Word to PDF and back. Pick a Word file to get a PDF, or a
/// PDF to get an editable Word file. Everything runs on the phone.
class WordPdfScreen extends StatefulWidget {
  const WordPdfScreen({
    super.key,
    this.chooser = const SystemConvertFileChooser(),
    this.sink = const FolderConvertSink(),
    this.registry,
    this.share,
  });

  final ConvertFileChooser chooser;
  final ConvertSink sink;
  final ConvertRegistry? registry;
  final ShareEngine? share;

  @override
  State<WordPdfScreen> createState() => _WordPdfScreenState();
}

class _WordPdfScreenState extends State<WordPdfScreen> {
  ConvertRegistry get _registry => widget.registry ?? ConvertRegistry.instance;

  final List<String> _written = <String>[];
  String? _status;
  bool _busy = false;

  void _toast(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(m)));
    }
  }

  Future<void> _pickAndConvert() async {
    final ConvertInput? input = await widget.chooser.pick();
    if (input == null || !mounted) {
      return;
    }
    final FileKind kind = sniffFileKind(input.bytes);
    final String? id = switch (kind) {
      FileKind.docx => 'docx-to-pdf',
      FileKind.doc => 'doc-to-pdf',
      FileKind.pdf => 'pdf-to-docx',
      _ => null,
    };
    if (id == null) {
      setState(() => _status = 'Pick a Word (.docx) file or a PDF. This one is ${kind.label}.');
      return;
    }
    setState(() {
      _busy = true;
      _status = 'Converting ${input.name}…';
    });
    try {
      final ConvertOutput out = await _registry.convert(input, id);
      final String path = await widget.sink.write(out);
      _written.add(path);
      setState(() => _status = 'Made ${out.name} in Files › converted');
    } on ConvertException catch (e) {
      setState(() => _status = e.message);
    } on FormatException {
      setState(() => _status = 'This file could not be read. It may be damaged.');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _share() async {
    if (_written.isEmpty) {
      _toast('Convert something first');
      return;
    }
    await (widget.share ?? ShareEngine.instance).shareFiles(<String>[_written.last]);
  }

  void _save() {
    if (_written.isEmpty) {
      _toast('Nothing to save yet');
      return;
    }
    _toast('Saved in Files › converted');
  }

  Future<void> _undo() async {
    if (_written.isEmpty) {
      Navigator.of(context).maybePop();
      return;
    }
    final String last = _written.removeLast();
    await widget.sink.remove(last);
    setState(() => _status = 'Removed ${last.substring(last.lastIndexOf('/') + 1)}');
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Word to PDF and back')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text('Word ↔ PDF', style: text.titleMedium),
                  const SizedBox(height: 6),
                  Text(
                    'A Word file becomes a PDF with its fonts, tables and pictures. '
                    'A PDF becomes a Word file you can edit. The file never leaves this phone.',
                    style: text.bodyMedium,
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    key: const Key('word-pdf-pick'),
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                    onPressed: _busy ? null : _pickAndConvert,
                    icon: _busy
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.file_open_outlined),
                    label: const Text('Choose a Word file or PDF'),
                  ),
                ],
              ),
            ),
          ),
          if (_status != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Semantics(
                liveRegion: true,
                child: Text(_status!, key: const Key('word-pdf-status'), style: text.bodyMedium),
              ),
            ),
        ],
      ),
      bottomNavigationBar: ResultBar(onShare: _share, onSave: _save, onUndo: _undo),
    );
  }
}
