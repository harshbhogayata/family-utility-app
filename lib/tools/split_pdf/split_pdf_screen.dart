import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../app/widgets/result_bar.dart';
import '../../engines/pdf/pdf_splitter.dart';
import '../../engines/share/share_engine.dart';

/// The PDF the person picked.
class PickedPdf {
  const PickedPdf(this.name, this.bytes);
  final String name;
  final Uint8List bytes;
}

/// Picks the PDF and keeps the parts. Behind an interface for tests.
abstract class SplitFiles {
  Future<PickedPdf?> pick();

  /// Writes [bytes] as [name] inside the folder for this split ([set]);
  /// returns the path.
  Future<String> write(String set, String name, Uint8List bytes);
  Future<void> remove(String path);
}

class SystemSplitFiles implements SplitFiles {
  const SystemSplitFiles();

  @override
  Future<PickedPdf?> pick() async {
    final FilePickerResult? r = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: <String>['pdf'],
    );
    final PlatformFile? f = r?.files.isEmpty ?? true ? null : r!.files.first;
    final String? p = f?.path;
    if (f == null || p == null) {
      return null;
    }
    return PickedPdf(f.name, await File(p).readAsBytes());
  }

  @override
  Future<String> write(String set, String name, Uint8List bytes) async {
    final Directory base = await getApplicationDocumentsDirectory();
    final Directory dir = Directory('${base.path}/split/$set');
    await dir.create(recursive: true);
    final String path = '${dir.path}/$name';
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

typedef SplitRunner = Future<PdfSplitResult> Function(SplitRequest request);

Future<PdfSplitResult> splitInIsolate(SplitRequest request) => compute(PdfSplitter.run, request);

/// Feature 003 — Split PDF.
class SplitPdfScreen extends StatefulWidget {
  const SplitPdfScreen({
    super.key,
    this.files = const SystemSplitFiles(),
    this.runner = splitInIsolate,
    this.share,
    this.clock,
  });

  final SplitFiles files;
  final SplitRunner runner;
  final ShareEngine? share;

  /// Names each split's folder; tests pass a fixed time.
  final DateTime Function()? clock;

  @override
  State<SplitPdfScreen> createState() => _SplitPdfScreenState();
}

class _SplitPdfScreenState extends State<SplitPdfScreen> {
  final TextEditingController _value = TextEditingController();
  PickedPdf? _pdf;
  int? _pages;
  SplitMode _mode = SplitMode.ranges;
  PdfSplitResult? _result;
  List<String> _partPaths = <String>[];
  String? _zipPath;
  String? _status;
  bool _working = false;

  @override
  void dispose() {
    _value.dispose();
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
    final PickedPdf? p = await widget.files.pick();
    if (!mounted || p == null) {
      return;
    }
    int? pages;
    String? status;
    try {
      pages = PdfSplitSource.parse(p.bytes).pageCount;
    } on SplitError catch (e) {
      status = e.message;
    } catch (_) {
      status = 'This file could not be read as a PDF.';
    }
    setState(() {
      _pdf = p;
      _pages = pages;
      _status = status;
      _result = null;
    });
  }

  String get _hint {
    switch (_mode) {
      case SplitMode.ranges:
        return 'Pages, like 1-3, 5, 8-10';
      case SplitMode.everyN:
        return 'Pages in each part, like 2';
      case SplitMode.bySize:
        return 'Largest part in MB, like 5';
    }
  }

  String get _helper {
    switch (_mode) {
      case SplitMode.ranges:
        return 'Each item becomes one part. 8- runs to the end.';
      case SplitMode.everyN:
        return 'The last part takes whatever pages are left.';
      case SplitMode.bySize:
        return 'Handy for email limits. A single page bigger than this gets its own part.';
    }
  }

  Future<void> _split() async {
    final PickedPdf? pdf = _pdf;
    if (pdf == null || _working) {
      return;
    }
    String value = _value.text;
    if (_mode == SplitMode.bySize) {
      final int? bytes = PdfSplitter.megabytes(value);
      if (bytes == null) {
        setState(() => _status = 'Type a size in MB, like 5 or 2.5.');
        return;
      }
      value = '$bytes';
    }
    setState(() => _working = true);
    try {
      final PdfSplitResult r = await widget.runner(SplitRequest(bytes: pdf.bytes, name: pdf.name, mode: _mode, value: value));
      final DateTime now = (widget.clock ?? DateTime.now)();
      final String set = '${PdfSplitter.stem(pdf.name)} ${now.millisecondsSinceEpoch}';
      final List<String> paths = <String>[];
      for (final SplitPart p in r.parts) {
        paths.add(await widget.files.write(set, p.name, p.bytes));
      }
      final String zip = await widget.files.write(set, PdfSplitter.zipName(pdf.name), PdfSplitter.zip(r, now: now));
      final int over = r.overLimit;
      setState(() {
        _result = r;
        _partPaths = paths;
        _zipPath = zip;
        _status = 'Split ${r.pageCount} pages into ${r.parts.length} ${r.parts.length == 1 ? 'part' : 'parts'}'
            '${over == 0 ? '' : ' · $over over the size (one page each)'}';
      });
    } on SplitError catch (e) {
      setState(() => _status = e.message);
    } finally {
      if (mounted) {
        setState(() => _working = false);
      }
    }
  }

  Future<void> _share() async {
    final String? zip = _zipPath;
    if (zip == null) {
      _toast('Split first');
      return;
    }
    await (widget.share ?? ShareEngine.instance).shareFiles(<String>[zip]);
  }

  Future<void> _shareParts() async {
    if (_partPaths.isEmpty) {
      return;
    }
    await (widget.share ?? ShareEngine.instance).shareFiles(List<String>.of(_partPaths));
  }

  void _save() => _toast(_result == null ? 'Nothing to save yet' : 'Saved in Files › split, with a ZIP of all parts');

  Future<void> _undo() async {
    if (_result != null) {
      for (final String p in <String>[..._partPaths, if (_zipPath != null) _zipPath!]) {
        await widget.files.remove(p);
      }
      setState(() {
        _result = null;
        _partPaths = <String>[];
        _zipPath = null;
        _status = 'Removed the parts';
      });
      return;
    }
    if (_pdf != null) {
      setState(() {
        _pdf = null;
        _pages = null;
        _status = null;
      });
      return;
    }
    if (mounted) {
      await Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final PickedPdf? pdf = _pdf;
    final PdfSplitResult? r = _result;
    return Scaffold(
      appBar: AppBar(title: const Text('Split PDF')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          OutlinedButton.icon(
            key: const Key('split-pick'),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: _working ? null : _pick,
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: Text(pdf == null ? 'Choose a PDF' : 'Choose another PDF'),
          ),
          if (pdf != null)
            ListTile(
              key: const Key('split-file'),
              leading: const Icon(Icons.description_outlined),
              title: Text(pdf.name),
              subtitle: Text(_pages == null ? 'Could not read the pages' : '$_pages pages'),
            ),
          const SizedBox(height: 8),
          SegmentedButton<SplitMode>(
            key: const Key('split-mode'),
            segments: const <ButtonSegment<SplitMode>>[
              ButtonSegment<SplitMode>(value: SplitMode.ranges, label: Text('Ranges'), icon: Icon(Icons.format_list_numbered)),
              ButtonSegment<SplitMode>(value: SplitMode.everyN, label: Text('Every N'), icon: Icon(Icons.view_agenda_outlined)),
              ButtonSegment<SplitMode>(value: SplitMode.bySize, label: Text('By size'), icon: Icon(Icons.straighten)),
            ],
            selected: <SplitMode>{_mode},
            onSelectionChanged: (Set<SplitMode> s) => setState(() {
              _mode = s.first;
              _value.clear();
            }),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('split-value'),
            controller: _value,
            keyboardType: _mode == SplitMode.ranges
                ? TextInputType.text
                : const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: _hint,
              helperText: _helper,
              helperMaxLines: 2,
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (_) => _split(),
          ),
          const SizedBox(height: 12),
          FilledButton(
            key: const Key('split-run'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: pdf == null || _pages == null || _working ? null : _split,
            child: Text(_working ? 'Splitting…' : 'Split'),
          ),
          if (_status != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Semantics(liveRegion: true, child: Text(_status!, key: const Key('split-status'), style: text.bodyMedium)),
            ),
          if (r != null) ...<Widget>[
            const SizedBox(height: 8),
            for (final SplitPart p in r.parts)
              ListTile(
                key: Key('split-part-${p.number}'),
                leading: CircleAvatar(child: Text('${p.number}')),
                title: Text(p.name),
                subtitle: Text('${p.range.length} ${p.range.length == 1 ? 'page' : 'pages'} · ${_size(p.bytes.length)}'
                    '${p.overLimit ? ' · over the size' : ''}'),
              ),
            TextButton.icon(
              key: const Key('split-share-parts'),
              style: TextButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              onPressed: _shareParts,
              icon: const Icon(Icons.share_outlined),
              label: const Text('Share the parts as separate PDFs', semanticsLabel: 'Share the parts as separate PDFs'),
            ),
          ],
        ],
      ),
      bottomNavigationBar: ResultBar(onShare: _share, onSave: _save, onUndo: _undo),
    );
  }

  static String _size(int bytes) {
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(bytes < 10 * 1024 ? 1 : 0)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
