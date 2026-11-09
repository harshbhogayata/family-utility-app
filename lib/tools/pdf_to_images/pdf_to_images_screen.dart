import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../app/widgets/result_bar.dart';
import '../../engines/pdf/pdf_to_images.dart';
import '../../engines/share/share_engine.dart';
import '../../platform/pdf_rasterizer_platform.dart';

/// Picking the PDF and saving the pictures, behind one interface for tests.
abstract class PdfImagesIo {
  /// Path of the picked PDF, or null.
  Future<String?> pick();
  Future<Uint8List> read(String path);

  /// [name] includes the extension. Returns the saved path.
  Future<String> write(String name, Uint8List bytes);
  Future<void> remove(String path);
}

class SystemPdfImagesIo implements PdfImagesIo {
  const SystemPdfImagesIo();

  @override
  Future<String?> pick() async {
    final FilePickerResult? r =
        await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: <String>['pdf']);
    return r == null || r.files.isEmpty ? null : r.files.first.path;
  }

  @override
  Future<Uint8List> read(String path) => File(path).readAsBytes();

  @override
  Future<String> write(String name, Uint8List bytes) async {
    final Directory base = await getApplicationDocumentsDirectory();
    final Directory dir = Directory('${base.path}/images');
    await dir.create(recursive: true);
    String path = '${dir.path}/$name';
    int n = 2;
    while (File(path).existsSync()) {
      final int dot = name.lastIndexOf('.');
      path = '${dir.path}/${name.substring(0, dot)} ($n)${name.substring(dot)}';
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
}

/// Feature 022 — PDF to images.
class PdfToImagesScreen extends StatefulWidget {
  const PdfToImagesScreen({
    super.key,
    this.io = const SystemPdfImagesIo(),
    this.rasterizer = const PdfrxRasterizer(),
    this.share,
  });

  final PdfImagesIo io;
  final PdfRasterizer rasterizer;
  final ShareEngine? share;

  @override
  State<PdfToImagesScreen> createState() => _PdfToImagesScreenState();
}

class _PdfToImagesScreenState extends State<PdfToImagesScreen> {
  String? _path;
  PdfImageFormat _format = PdfImageFormat.jpg;
  int _dpi = 150;
  bool _long = false;
  final TextEditingController _range = TextEditingController();
  final List<String> _saved = <String>[];
  String? _status;
  bool _working = false;

  @override
  void dispose() {
    _range.dispose();
    super.dispose();
  }

  void _toast(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(m)));
    }
  }

  Future<void> _pick() async {
    final String? p = await widget.io.pick();
    if (!mounted || p == null) {
      return;
    }
    setState(() {
      _path = p;
      _status = null;
    });
  }

  Future<void> _run() async {
    final String? path = _path;
    if (path == null || _working) {
      return;
    }
    setState(() => _working = true);
    try {
      final Uint8List pdf = await widget.io.read(path);
      final String name = path.split('/').last;
      final String stem = name.toLowerCase().endsWith('.pdf') ? name.substring(0, name.length - 4) : name;
      final PdfToImages engine = PdfToImages(widget.rasterizer);
      final List<PdfImageOut> outs = _long
          ? <PdfImageOut>[await engine.longImage(pdf, stem, range: _range.text, dpi: _dpi, format: _format)]
          : await engine.perPage(pdf, stem, range: _range.text, dpi: _dpi, format: _format);
      final List<String> saved = <String>[for (final PdfImageOut o in outs) await widget.io.write(o.name, o.bytes)];
      setState(() {
        _saved
          ..clear()
          ..addAll(saved);
        _status = _long
            ? 'One long ${_format.label}: ${outs.single.width} × ${outs.single.height} px'
            : '${outs.length} ${_format.label} ${outs.length == 1 ? 'image' : 'images'} at $_dpi dpi';
      });
    } on PdfToImagesError catch (e) {
      setState(() => _status = e.message);
    } catch (_) {
      setState(() => _status = 'This PDF could not be opened');
    } finally {
      if (mounted) {
        setState(() => _working = false);
      }
    }
  }

  Future<void> _share() async {
    if (_saved.isEmpty) {
      _toast('Make the images first');
      return;
    }
    await (widget.share ?? ShareEngine.instance).shareFiles(List<String>.of(_saved));
  }

  void _save() => _toast(_saved.isEmpty ? 'Nothing to save yet' : 'Saved in Files › images');

  Future<void> _undo() async {
    if (_saved.isEmpty) {
      Navigator.of(context).maybePop();
      return;
    }
    for (final String p in _saved) {
      await widget.io.remove(p);
    }
    setState(() {
      _saved.clear();
      _status = 'Removed the images';
    });
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('PDF to images')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          OutlinedButton.icon(
            key: const Key('p2i-pick'),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: _working ? null : _pick,
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: Text(_path == null ? 'Choose a PDF' : _path!.split('/').last),
          ),
          const SizedBox(height: 16),
          Text('Format', style: text.titleSmall),
          Wrap(spacing: 8, children: <Widget>[
            for (final PdfImageFormat f in PdfImageFormat.values)
              ChoiceChip(
                key: Key('p2i-${f.extension}'),
                materialTapTargetSize: MaterialTapTargetSize.padded,
                label: Text(f.label),
                selected: _format == f,
                onSelected: (_) => setState(() => _format = f),
              ),
          ]),
          Text('Sharpness', style: text.titleSmall),
          Wrap(spacing: 8, children: <Widget>[
            for (final int d in pdfImageDpis)
              ChoiceChip(
                key: Key('p2i-dpi-$d'),
                materialTapTargetSize: MaterialTapTargetSize.padded,
                label: Text('$d dpi'),
                selected: _dpi == d,
                onSelected: (_) => setState(() => _dpi = d),
              ),
          ]),
          TextField(
            key: const Key('p2i-range'),
            controller: _range,
            decoration: const InputDecoration(labelText: 'Pages, e.g. 1-3, 5 (empty for all)'),
          ),
          SwitchListTile(
            key: const Key('p2i-long'),
            value: _long,
            onChanged: (bool v) => setState(() => _long = v),
            title: const Text('One long image'),
            subtitle: const Text('All chosen pages top to bottom, for sharing in chat'),
          ),
          const SizedBox(height: 8),
          FilledButton(
            key: const Key('p2i-run'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: _path == null || _working ? null : _run,
            child: const Text('Make images'),
          ),
          if (_status != null)
            ListTile(
              key: const Key('p2i-status'),
              leading: Icon(_saved.isEmpty ? Icons.info_outline : Icons.check_circle,
                  semanticLabel: _saved.isEmpty ? 'Note' : 'Done'),
              title: Text(_status!),
            ),
        ],
      ),
      bottomNavigationBar: ResultBar(onShare: _share, onSave: _save, onUndo: _undo),
    );
  }
}
