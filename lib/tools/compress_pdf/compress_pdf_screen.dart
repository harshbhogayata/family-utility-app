import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../app/widgets/result_bar.dart';
import '../../engines/pdf/pdf_compressor.dart';
import '../../engines/share/share_engine.dart';

/// Reads the picked PDF and writes the smaller copy. Behind an interface so
/// tests need neither the picker nor the disk.
abstract class PdfFiles {
  Future<String?> pick();

  Future<Uint8List> read(String path);

  Future<String> write(String name, Uint8List bytes);

  Future<void> remove(String path);
}

class SystemPdfFiles implements PdfFiles {
  const SystemPdfFiles();

  @override
  Future<String?> pick() async {
    final FilePickerResult? r = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: <String>['pdf'],
    );
    return r?.files.single.path;
  }

  @override
  Future<Uint8List> read(String path) => File(path).readAsBytes();

  @override
  Future<String> write(String name, Uint8List bytes) async {
    final Directory base = await getApplicationDocumentsDirectory();
    final Directory dir = Directory('${base.path}/compressed');
    await dir.create(recursive: true);
    String path = '${dir.path}/$name';
    int i = 2;
    while (File(path).existsSync()) {
      path = '${dir.path}/${name.substring(0, name.length - 4)} ($i).pdf';
      i++;
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

typedef PdfAnalyzer = Future<PdfAnalysis> Function(Uint8List input);
typedef PdfRunner = Future<PdfCompressResult> Function(Uint8List input, PdfPreset preset);

Future<PdfAnalysis> analyzeInIsolate(Uint8List input) => compute(PdfCompressor.analyze, input);

Future<PdfCompressResult> compressPdfInIsolate(Uint8List input, PdfPreset preset) =>
    compute(_run, (input, preset));

PdfCompressResult _run((Uint8List, PdfPreset) job) => PdfCompressor.compress(job.$1, job.$2);

String formatBytes(int n) {
  if (n >= 1024 * 1024) {
    return '${(n / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  if (n >= 1024) {
    return '${(n / 1024).round()} KB';
  }
  return '$n B';
}

/// Feature 032 — Compress PDF: low, medium and high presets, the size
/// estimated before the run and the real size after.
class CompressPdfScreen extends StatefulWidget {
  const CompressPdfScreen({
    super.key,
    this.files = const SystemPdfFiles(),
    this.analyzer = analyzeInIsolate,
    this.runner = compressPdfInIsolate,
    this.share,
  });

  final PdfFiles files;
  final PdfAnalyzer analyzer;
  final PdfRunner runner;
  final ShareEngine? share;

  @override
  State<CompressPdfScreen> createState() => _CompressPdfScreenState();
}

class _CompressPdfScreenState extends State<CompressPdfScreen> {
  String? _path;
  Uint8List? _input;
  PdfAnalysis? _analysis;
  PdfPreset _preset = PdfPreset.medium;
  PdfCompressResult? _result;
  String? _savedPath;
  String? _error;
  bool _working = false;

  String get _name => _path == null ? 'document.pdf' : _path!.split('/').last;

  String get _outName {
    final String n = _name.toLowerCase().endsWith('.pdf') ? _name.substring(0, _name.length - 4) : _name;
    return '$n-compressed.pdf';
  }

  void _toast(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(m)));
    }
  }

  Future<void> _pick() async {
    final String? path = await widget.files.pick();
    if (path == null) {
      return;
    }
    setState(() {
      _working = true;
      _error = null;
      _result = null;
      _savedPath = null;
    });
    try {
      final Uint8List bytes = await widget.files.read(path);
      final PdfAnalysis a = await widget.analyzer(bytes);
      if (!mounted) {
        return;
      }
      setState(() {
        _path = path;
        _input = bytes;
        _analysis = a;
      });
    } on PdfCompressError catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'This file could not be read as a PDF.');
    } finally {
      if (mounted) {
        setState(() => _working = false);
      }
    }
  }

  Future<void> _compress() async {
    final Uint8List? input = _input;
    if (input == null) {
      return;
    }
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final PdfCompressResult r = await widget.runner(input, _preset);
      if (mounted) {
        setState(() => _result = r);
      }
    } on PdfCompressError catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Something in this PDF could not be compressed. The original is untouched.');
    } finally {
      if (mounted) {
        setState(() => _working = false);
      }
    }
  }

  Future<void> _save() async {
    final PdfCompressResult? r = _result;
    if (r == null) {
      _toast('Compress a PDF first');
      return;
    }
    if (!r.smaller) {
      _toast('Already as small as it gets. Nothing saved.');
      return;
    }
    if (_savedPath != null) {
      _toast('Already saved');
      return;
    }
    final String where = await widget.files.write(_outName, r.bytes);
    setState(() => _savedPath = where);
    _toast('Saved ${where.split('/').last} in Files');
  }

  Future<void> _share() async {
    final PdfCompressResult? r = _result;
    if (r == null || !r.smaller) {
      _toast('Nothing smaller to share yet');
      return;
    }
    final String path = _savedPath ?? await widget.files.write(_outName, r.bytes);
    if (mounted) {
      setState(() => _savedPath = path);
    }
    await (widget.share ?? ShareEngine.instance).shareFiles(<String>[path]);
  }

  Future<void> _undo() async {
    final String? saved = _savedPath;
    if (saved != null) {
      await widget.files.remove(saved);
      setState(() => _savedPath = null);
      _toast('Saved copy removed. The original is untouched.');
      return;
    }
    if (_result != null) {
      setState(() => _result = null);
      return;
    }
    if (mounted) {
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final PdfAnalysis? a = _analysis;
    final PdfCompressResult? r = _result;
    return Scaffold(
      appBar: AppBar(title: const Text('Compress PDF')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          SizedBox(
            height: 48,
            child: FilledButton.tonalIcon(
              key: const Key('pdf-pick'),
              onPressed: _working ? null : _pick,
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: Text(a == null ? 'Pick a PDF' : 'Pick another PDF'),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_error!, key: const Key('pdf-error'), style: text.bodyMedium?.copyWith(color: Colors.red[800])),
            ),
          if (a != null) ...<Widget>[
            const SizedBox(height: 16),
            Text(_name, style: text.titleMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
            Text(
              '${formatBytes(a.size)} · ${a.pages} ${a.pages == 1 ? 'page' : 'pages'} · ${a.images.length} '
              '${a.images.length == 1 ? 'photo' : 'photos'}',
              style: text.bodyMedium,
            ),
            const SizedBox(height: 16),
            Semantics(
              label: 'Compression level',
              child: SegmentedButton<PdfPreset>(
                key: const Key('pdf-preset'),
                segments: <ButtonSegment<PdfPreset>>[
                  for (final PdfPreset p in PdfPreset.values)
                    ButtonSegment<PdfPreset>(value: p, label: Text(p.label, key: Key('preset-${p.name}'))),
                ],
                selected: <PdfPreset>{_preset},
                onSelectionChanged: _working
                    ? null
                    : (Set<PdfPreset> s) => setState(() {
                          _preset = s.first;
                          _result = null;
                        }),
              ),
            ),
            const SizedBox(height: 8),
            Text(_preset.hint, style: text.bodySmall),
            const SizedBox(height: 12),
            Text(
              'Estimated: about ${formatBytes(a.estimate(_preset))}',
              key: const Key('pdf-estimate'),
              style: text.titleSmall,
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 48,
              child: FilledButton(
                key: const Key('pdf-run'),
                onPressed: _working ? null : _compress,
                child: const Text('Compress'),
              ),
            ),
          ],
          if (_working)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator(semanticsLabel: 'Working')),
            ),
          if (r != null) ...<Widget>[
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Semantics(
                  liveRegion: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        r.smaller
                            ? '${formatBytes(r.before)} → ${formatBytes(r.after)}'
                            : 'Already compact: ${formatBytes(r.before)}',
                        key: const Key('pdf-actual'),
                        style: text.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        r.smaller
                            ? '${r.savedPercent}% smaller. ${r.imagesChanged} photos resized, text still selectable.'
                            : 'This PDF could not be made smaller. The original is untouched.',
                        style: text.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
      bottomNavigationBar: ResultBar(
        onShare: _share,
        onSave: _save,
        onUndo: _undo,
        saveLabel: _savedPath == null ? 'Save' : 'Saved',
      ),
    );
  }
}
