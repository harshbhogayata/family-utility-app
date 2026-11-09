import 'package:flutter/material.dart';

import '../../app/widgets/result_bar.dart';
import '../../engines/convert/convert_registry.dart';
import '../../engines/convert/file_kind.dart';
import '../../engines/share/share_engine.dart';
import '../convert_anything/convert_anything_screen.dart';

/// Feature 019 — Excel to PDF and back. Pick a workbook to get a PDF, or a
/// PDF to get its tables as a workbook. Everything runs on the phone.
class ExcelPdfScreen extends StatefulWidget {
  const ExcelPdfScreen({
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
  State<ExcelPdfScreen> createState() => _ExcelPdfScreenState();
}

class _ExcelPdfScreenState extends State<ExcelPdfScreen> {
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
      FileKind.xlsx => 'xlsx-to-pdf',
      FileKind.xls => 'xls-to-pdf',
      FileKind.pdf => 'pdf-to-xlsx',
      _ => null,
    };
    if (id == null) {
      setState(() => _status = 'Pick an Excel (.xlsx) file or a PDF. This one is ${kind.label}.');
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
      appBar: AppBar(title: const Text('Excel to PDF and back')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text('Excel ↔ PDF', style: text.titleMedium),
                  const SizedBox(height: 6),
                  Text(
                    'Every sheet of a workbook becomes landscape PDF pages; long sheets run on and wide ones '
                    'print in column blocks. A PDF\'s tables become sheets, one cell per cell. The file never leaves this phone.',
                    style: text.bodyMedium,
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    key: const Key('excel-pdf-pick'),
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                    onPressed: _busy ? null : _pickAndConvert,
                    icon: _busy
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.file_open_outlined),
                    label: const Text('Choose an Excel file or PDF'),
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
                child: Text(_status!, key: const Key('excel-pdf-status'), style: text.bodyMedium),
              ),
            ),
        ],
      ),
      bottomNavigationBar: ResultBar(onShare: _share, onSave: _save, onUndo: _undo),
    );
  }
}
