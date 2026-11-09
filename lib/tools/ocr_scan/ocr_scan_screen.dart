import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../app/theme.dart';
import '../../app/widgets/result_bar.dart';
import '../../engines/pdf/pdf_ocr.dart';
import '../../engines/pdf/pdf_text_search.dart';
import '../../engines/pdf/pdf_to_images.dart';
import '../../engines/platform/action_history.dart' show baseName;
import '../../engines/share/share_engine.dart';
import '../../platform/mlkit_text_platform.dart';
import '../../platform/pdf_rasterizer_platform.dart';
import '../pdf_search/pdf_search_screen.dart' show PdfBytesReader, readPdfBytes;
import '../pdf_viewer/pdf_viewer_screen.dart' show PdfChooser, SystemPdfChooser;

/// Writes the searchable PDF and returns its path.
typedef OcrPdfWriter = Future<String> Function(String name, Uint8List bytes);

Future<String> writeOcrPdfToAppFolder(String name, Uint8List bytes) async {
  final Directory base = await getApplicationDocumentsDirectory();
  final File f = File('${base.path}/$name');
  await f.writeAsBytes(bytes, flush: true);
  return f.path;
}

/// The searchable file's name: "scan.pdf" becomes "scan-searchable.pdf".
String searchableName(String path) {
  final String name = baseName(path);
  final int dot = name.toLowerCase().lastIndexOf('.pdf');
  final String stem = dot > 0 ? name.substring(0, dot) : name;
  return '$stem-searchable.pdf';
}

/// Feature 008 — OCR a scan: make a scanned PDF searchable on the phone.
class OcrScanScreen extends StatefulWidget {
  const OcrScanScreen({
    super.key,
    this.chooser = const SystemPdfChooser(),
    this.readBytes = readPdfBytes,
    this.rasterizer = const PdfrxRasterizer(),
    this.recognizer = const MlKitTextRecognizer(),
    this.writer = writeOcrPdfToAppFolder,
    this.index,
    this.share,
  });

  final PdfChooser chooser;
  final PdfBytesReader readBytes;
  final PdfRasterizer rasterizer;
  final TextRecognizerEngine recognizer;
  final OcrPdfWriter writer;
  final PdfLibraryIndex? index;
  final ShareEngine? share;

  @override
  State<OcrScanScreen> createState() => _OcrScanScreenState();
}

class _OcrScanScreenState extends State<OcrScanScreen> {
  String? _source;
  OcrScript _script = OcrScript.latin;
  bool _running = false;
  String _progress = '';
  OcrResult? _result;
  String? _savedPath;

  PdfLibraryIndex get _index => widget.index ?? PdfLibraryIndex.instance;

  void _toast(String m) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _pick() async {
    final String? p = await widget.chooser.pick();
    if (p != null && mounted) {
      setState(() {
        _source = p;
        _result = null;
        _savedPath = null;
      });
    }
  }

  Future<void> _run() async {
    final String? src = _source;
    if (src == null) {
      return;
    }
    setState(() {
      _running = true;
      _progress = 'Reading page 1…';
    });
    try {
      final OcrResult r = await PdfOcr(rasterizer: widget.rasterizer, recognizer: widget.recognizer).run(
        await widget.readBytes(src),
        _script,
        progress: (int done, int total) {
          if (mounted && done < total) {
            setState(() => _progress = 'Reading page ${done + 1} of $total…');
          }
        },
      );
      final String out = await widget.writer(searchableName(src), r.pdf);
      // The searchable copy goes straight into Search inside PDFs.
      _index.put(IndexedPdf(path: out, pages: r.pageTexts));
      await _index.save();
      if (!mounted) {
        return;
      }
      setState(() {
        _result = r;
        _savedPath = out;
        _running = false;
      });
      if (r.wordCount == 0) {
        _toast('No words found. Try the other script or a sharper scan.');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _running = false);
        _toast(e is PdfOcrError ? e.message : 'Could not read this PDF');
      }
    }
  }

  Future<void> _share() async {
    final String? p = _savedPath;
    if (p == null) {
      _toast('Make a searchable PDF first');
      return;
    }
    await (widget.share ?? ShareEngine.instance).shareFiles(<String>[p]);
  }

  void _save() {
    final String? p = _savedPath;
    if (p == null) {
      _toast('Make a searchable PDF first');
      return;
    }
    _toast('Saved ${baseName(p)} in Files');
  }

  Future<void> _undo() async {
    final String? p = _savedPath;
    if (p == null) {
      Navigator.of(context).maybePop();
      return;
    }
    _index.remove(p);
    await _index.save();
    try {
      final File f = File(p);
      if (f.existsSync()) {
        await f.delete();
      }
    } catch (_) {
      // Already gone.
    }
    setState(() {
      _result = null;
      _savedPath = null;
    });
    _toast('Removed the searchable copy');
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final OcrResult? r = _result;
    final String? src = _source;
    return Scaffold(
      appBar: AppBar(title: const Text('OCR a scan')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Text(
            'Reads the words in a scanned PDF on this phone and adds them as an invisible layer, '
            'so you can search and select text. The pages look the same; nothing is uploaded.',
            style: text.bodyMedium,
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            key: const Key('ocr-pick'),
            onPressed: _running ? null : _pick,
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: Text(src == null ? 'Choose a scanned PDF' : baseName(src), overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(height: 16),
          Semantics(
            label: 'Script of the text',
            child: SegmentedButton<OcrScript>(
              key: const Key('ocr-script'),
              segments: const <ButtonSegment<OcrScript>>[
                ButtonSegment<OcrScript>(value: OcrScript.latin, label: Text('Latin')),
                ButtonSegment<OcrScript>(value: OcrScript.devanagari, label: Text('देवनागरी')),
              ],
              selected: <OcrScript>{_script},
              onSelectionChanged: _running ? null : (Set<OcrScript> s) => setState(() => _script = s.first),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(_script.label, style: text.bodySmall),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const Key('ocr-run'),
            onPressed: src == null || _running ? null : _run,
            icon: const Icon(Icons.document_scanner_outlined),
            label: const Text('Make searchable'),
          ),
          if (_running) ...<Widget>[
            const SizedBox(height: 16),
            const LinearProgressIndicator(),
            const SizedBox(height: 8),
            Text(_progress, key: const Key('ocr-progress')),
          ],
          if (r != null) ...<Widget>[
            const SizedBox(height: 24),
            Semantics(
              header: true,
              child: Text(
                '${r.wordCount} ${r.wordCount == 1 ? 'word' : 'words'} on ${r.pages.length} '
                '${r.pages.length == 1 ? 'page' : 'pages'}',
                key: const Key('ocr-summary'),
                style: text.titleMedium,
              ),
            ),
            if (_savedPath != null)
              Text('Saved as ${baseName(_savedPath!)}', key: const Key('ocr-saved'), style: text.bodySmall),
            const SizedBox(height: 8),
            Container(
              key: const Key('ocr-text'),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surface,
                border: Border.all(color: AppColors.line),
                borderRadius: BorderRadius.circular(12),
              ),
              child: SelectableText(
                r.pageTexts.asMap().entries.map((MapEntry<int, String> e) => 'Page ${e.key + 1}\n${e.value}').join('\n\n'),
              ),
            ),
          ],
        ],
      ),
      bottomNavigationBar: ResultBar(onShare: _share, onSave: _save, onUndo: _undo),
    );
  }
}
