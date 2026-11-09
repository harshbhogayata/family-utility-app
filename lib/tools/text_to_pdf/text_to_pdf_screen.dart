import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../../app/widgets/result_bar.dart';
import '../../engines/pdf/images_to_pdf.dart' show PdfPageSize;
import '../../engines/pdf/text_to_pdf.dart';
import '../../engines/share/share_engine.dart';

/// Keeps the made PDF. Behind an interface for tests.
abstract class TextPdfFiles {
  Future<String> write(String name, Uint8List bytes);
  Future<void> remove(String path);
  Future<String?> paste();
}

class SystemTextPdfFiles implements TextPdfFiles {
  const SystemTextPdfFiles();

  @override
  Future<String> write(String name, Uint8List bytes) async {
    final Directory base = await getApplicationDocumentsDirectory();
    final Directory dir = Directory('${base.path}/converted');
    await dir.create(recursive: true);
    String path = '${dir.path}/$name';
    int n = 2;
    while (File(path).existsSync()) {
      path = '${dir.path}/${name.substring(0, name.length - 4)} ($n).pdf';
      n++;
    }
    await File(path).writeAsBytes(bytes, flush: true);
    return path;
  }

  @override
  Future<void> remove(String path) async {
    final File f = File(path);
    if (f.existsSync()) {
      await f.delete();
    }
  }

  @override
  Future<String?> paste() async => (await Clipboard.getData(Clipboard.kTextPlain))?.text;
}

/// Feature 024 — Text to PDF.
class TextToPdfScreen extends StatefulWidget {
  const TextToPdfScreen({
    super.key,
    this.files = const SystemTextPdfFiles(),
    this.maker = const TextPdfMaker(),
    this.share,
  });

  final TextPdfFiles files;
  final TextPdfMaker maker;
  final ShareEngine? share;

  @override
  State<TextToPdfScreen> createState() => _TextToPdfScreenState();
}

class _TextToPdfScreenState extends State<TextToPdfScreen> {
  final TextEditingController _text = TextEditingController();
  TextPdfOptions _options = const TextPdfOptions();
  TextPdfResult? _result;
  String? _path;
  String? _status;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _text.addListener(_edited);
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _edited() {
    if (_path != null || _result != null) {
      setState(() {
        _result = null;
        _path = null;
        _status = null;
      });
    }
  }

  void _set(TextPdfOptions o) => setState(() {
        _options = o;
        _result = null;
        _path = null;
      });

  void _toast(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(m)));
    }
  }

  Future<void> _paste() async {
    final String? t = await widget.files.paste();
    if (!mounted) {
      return;
    }
    if (t == null || t.isEmpty) {
      _toast('Nothing to paste');
      return;
    }
    _text.text = t;
    setState(() => _status = 'Pasted ${t.characters.length} characters');
  }

  Future<void> _save() async {
    if (_working) {
      return;
    }
    if (_path != null) {
      _toast('Saved in Files › converted');
      return;
    }
    if (_text.text.trim().isEmpty) {
      _toast('Paste or type some text first');
      return;
    }
    setState(() {
      _working = true;
      _status = 'Making the PDF…';
    });
    try {
      final TextPdfResult r = await widget.maker.make(_text.text, _options);
      final String path = await widget.files.write(r.name, r.bytes);
      if (!mounted) {
        return;
      }
      setState(() {
        _result = r;
        _path = path;
        _status = 'Saved ${r.pages} ${r.pages == 1 ? 'page' : 'pages'} in Files › converted. Made on this phone.';
      });
    } on TextPdfError catch (e) {
      setState(() => _status = e.message);
    } finally {
      if (mounted) {
        setState(() => _working = false);
      }
    }
  }

  Future<void> _share() async {
    if (_path == null) {
      await _save();
    }
    final String? path = _path;
    if (path == null) {
      return;
    }
    await (widget.share ?? ShareEngine.instance).shareFiles(<String>[path]);
  }

  Future<void> _undo() async {
    final String? path = _path;
    if (path != null) {
      await widget.files.remove(path);
      setState(() {
        _result = null;
        _path = null;
        _status = 'Removed the PDF; your text is still here';
      });
      return;
    }
    if (_text.text.isNotEmpty) {
      _text.clear();
      setState(() => _status = 'Cleared the text');
      return;
    }
    if (mounted) {
      await Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final TextPdfResult? r = _result;
    return Scaffold(
      appBar: AppBar(title: const Text('Text to PDF')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          TextField(
            key: const Key('text-pdf-input'),
            controller: _text,
            minLines: 6,
            maxLines: 14,
            keyboardType: TextInputType.multiline,
            style: TextStyle(fontFamily: _options.font.family),
            decoration: const InputDecoration(
              labelText: 'Text',
              hintText: 'Paste or type here. Hindi, Tamil, Bengali and other scripts work.',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const Key('text-pdf-paste'),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: _working ? null : _paste,
            icon: const Icon(Icons.content_paste),
            label: const Text('Paste'),
          ),
          const SizedBox(height: 16),
          Text('Font', style: text.titleSmall),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: <Widget>[
              for (final TextPdfFont f in TextPdfFont.values)
                ChoiceChip(
                  key: Key('text-pdf-font-${f.name}'),
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                  label: Text(f.label),
                  selected: _options.font == f,
                  onSelected: (bool _) => _set(_options.copyWith(font: f)),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text('Size: ${_options.fontSize.round()} pt', key: const Key('text-pdf-size-label'), style: text.titleSmall),
          Slider(
            key: const Key('text-pdf-size'),
            min: TextPdfOptions.minSize,
            max: TextPdfOptions.maxSize,
            divisions: (TextPdfOptions.maxSize - TextPdfOptions.minSize).round(),
            value: _options.fontSize,
            label: '${_options.fontSize.round()} pt',
            semanticFormatterCallback: (double v) => 'Font size ${v.round()} points',
            onChanged: (double v) => _set(_options.copyWith(fontSize: v.roundToDouble())),
          ),
          Text('Page', style: text.titleSmall),
          const SizedBox(height: 4),
          SegmentedButton<PdfPageSize>(
            key: const Key('text-pdf-page'),
            style: SegmentedButton.styleFrom(minimumSize: const Size(0, 48)),
            segments: const <ButtonSegment<PdfPageSize>>[
              ButtonSegment<PdfPageSize>(value: PdfPageSize.a4, label: Text('A4')),
              ButtonSegment<PdfPageSize>(value: PdfPageSize.letter, label: Text('Letter')),
            ],
            selected: <PdfPageSize>{_options.pageSize},
            onSelectionChanged: (Set<PdfPageSize> s) => _set(_options.copyWith(pageSize: s.first)),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const Key('text-pdf-make'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: _working ? null : _save,
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: const Text('Make PDF'),
          ),
          if (_status != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Semantics(liveRegion: true, child: Text(_status!, key: const Key('text-pdf-status'), style: text.bodyMedium)),
            ),
          if (r != null)
            ListTile(
              key: const Key('text-pdf-result'),
              leading: const Icon(Icons.description_outlined),
              title: Text(r.name),
              subtitle: Text('${r.pages} ${r.pages == 1 ? 'page' : 'pages'}'),
            ),
        ],
      ),
      bottomNavigationBar: ResultBar(onShare: _share, onSave: _save, onUndo: _undo),
    );
  }
}
