import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../app/theme.dart';
import '../../app/widgets/result_bar.dart';
import '../../engines/pdf/pdf_clean_scan.dart';
import '../../engines/pdf/pdf_ocr.dart';
import '../../engines/pdf/pdf_to_images.dart';
import '../../engines/platform/action_history.dart' show baseName;
import '../../engines/share/share_engine.dart';
import '../../platform/mlkit_text_platform.dart';
import '../../platform/pdf_rasterizer_platform.dart';
import '../pdf_search/pdf_search_screen.dart' show PdfBytesReader, readPdfBytes;
import '../pdf_viewer/pdf_viewer_screen.dart' show PdfChooser, SystemPdfChooser;

/// Writes the cleaned PDF and returns its path.
typedef CleanPdfWriter = Future<String> Function(String name, Uint8List bytes);

Future<String> writeCleanPdfToAppFolder(String name, Uint8List bytes) async {
  final Directory base = await getApplicationDocumentsDirectory();
  final File f = File('${base.path}/$name');
  await f.writeAsBytes(bytes, flush: true);
  return f.path;
}

/// The cleaned file's name: "scan.pdf" becomes "scan-clean.pdf".
String cleanName(String path) {
  final String name = baseName(path);
  final int dot = name.toLowerCase().lastIndexOf('.pdf');
  final String stem = dot > 0 ? name.substring(0, dot) : name;
  return '$stem-clean.pdf';
}

/// Feature 015 — Remove blank pages and straighten.
class CleanScanScreen extends StatefulWidget {
  const CleanScanScreen({
    super.key,
    this.chooser = const SystemPdfChooser(),
    this.readBytes = readPdfBytes,
    this.rasterizer = const PdfrxRasterizer(),
    this.recognizer = const MlKitTextRecognizer(),
    this.writer = writeCleanPdfToAppFolder,
    this.share,
  });

  final PdfChooser chooser;
  final PdfBytesReader readBytes;
  final PdfRasterizer rasterizer;
  final TextRecognizerEngine recognizer;
  final CleanPdfWriter writer;
  final ShareEngine? share;

  @override
  State<CleanScanScreen> createState() => _CleanScanScreenState();
}

class _CleanScanScreenState extends State<CleanScanScreen> {
  String? _source;
  bool _deskew = true;
  bool _autoRotate = true;
  OcrScript _script = OcrScript.latin;
  double _threshold = defaultBlankInk;
  bool _running = false;
  String _progress = '';
  List<CleanPage>? _pages;
  CleanScanResult? _result;
  String? _savedPath;

  PdfCleanScan get _engine => PdfCleanScan(rasterizer: widget.rasterizer, recognizer: widget.recognizer);

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
        _pages = null;
        _result = null;
        _savedPath = null;
      });
    }
  }

  Future<void> _analyze() async {
    final String? src = _source;
    if (src == null) {
      return;
    }
    setState(() {
      _running = true;
      _progress = 'Checking page 1…';
      _pages = null;
      _result = null;
      _savedPath = null;
    });
    try {
      final List<CleanPage> pages = await _engine.analyze(
        await widget.readBytes(src),
        CleanScanOptions(deskew: _deskew, autoRotate: _autoRotate, script: _script),
        progress: (int done, int total) {
          if (mounted && done < total) {
            setState(() => _progress = 'Checking page ${done + 1} of $total…');
          }
        },
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _pages = pages;
        _running = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _running = false);
        _toast(e is PdfOcrError ? e.message : 'Could not read this PDF');
      }
    }
  }

  Future<void> _apply() async {
    final List<CleanPage>? pages = _pages;
    final String? src = _source;
    if (pages == null || src == null) {
      return;
    }
    try {
      final CleanScanResult r = _engine.build(pages, _threshold);
      final String out = await widget.writer(cleanName(src), r.pdf);
      if (!mounted) {
        return;
      }
      setState(() {
        _result = r;
        _savedPath = out;
      });
    } catch (e) {
      _toast(e is PdfOcrError ? e.message : 'Could not write the PDF');
    }
  }

  Future<void> _share() async {
    final String? p = _savedPath;
    if (p == null) {
      _toast('Make the clean PDF first');
      return;
    }
    await (widget.share ?? ShareEngine.instance).shareFiles(<String>[p]);
  }

  void _save() {
    final String? p = _savedPath;
    if (p == null) {
      _toast('Make the clean PDF first');
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
    _toast('Removed the clean copy; your original is untouched');
  }

  void _toggle(CleanPage p) {
    if (_result != null) {
      return;
    }
    setState(() {
      final bool now = p.keep(_threshold);
      final bool byThreshold = !p.isBlank(_threshold);
      // Back to following the threshold when the choice matches it.
      p.keepOverride = !now == byThreshold ? null : !now;
    });
  }

  String _describe(CleanPage p) {
    final List<String> bits = <String>[
      p.keep(_threshold) ? 'kept' : 'removed',
      if (p.isBlank(_threshold)) 'blank',
      if (p.skewDegrees != 0) 'straightened ${p.skewDegrees.abs().toStringAsFixed(1)}°',
      if (p.upsideDown) 'turned upright',
    ];
    return bits.join(', ');
  }

  Widget _tile(CleanPage p) {
    final bool keep = p.keep(_threshold);
    final String desc = _describe(p);
    return Semantics(
      button: true,
      label: 'Page ${p.index + 1}: $desc. Double tap to ${keep ? 'remove' : 'keep'}.',
      excludeSemantics: true,
      child: InkWell(
        key: Key('clean-page-${p.index}'),
        onTap: () => _toggle(p),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: keep ? AppColors.surface : AppColors.line,
            border: Border.all(color: keep ? AppColors.line : AppColors.muted, width: keep ? 1 : 2),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Opacity(
                opacity: keep ? 1 : 0.35,
                child: Image.memory(p.thumbnail, height: 110, fit: BoxFit.contain, gaplessPlayback: true),
              ),
              const SizedBox(height: 4),
              Text('Page ${p.index + 1}', style: Theme.of(context).textTheme.labelLarge),
              Text(desc, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall, maxLines: 2),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final String? src = _source;
    final List<CleanPage>? pages = _pages;
    final CleanScanResult? r = _result;
    final int removing = pages == null ? 0 : pages.where((CleanPage p) => !p.keep(_threshold)).length;
    return Scaffold(
      appBar: AppBar(title: const Text('Remove blank pages and straighten')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Text(
            'Finds blank pages, straightens crooked scans and turns upside-down pages the right way up, '
            'all on this phone. You see every page before anything is removed; your original stays as it is.',
            style: text.bodyMedium,
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            key: const Key('clean-pick'),
            onPressed: _running ? null : _pick,
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: Text(src == null ? 'Choose a scanned PDF' : baseName(src), overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            key: const Key('clean-deskew'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Straighten crooked pages'),
            subtitle: const Text('Up to 15° either way'),
            value: _deskew,
            onChanged: _running ? null : (bool v) => setState(() => _deskew = v),
          ),
          SwitchListTile(
            key: const Key('clean-rotate'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Turn upside-down pages'),
            subtitle: const Text('Reads each page both ways on the phone'),
            value: _autoRotate,
            onChanged: _running ? null : (bool v) => setState(() => _autoRotate = v),
          ),
          if (_autoRotate)
            Semantics(
              label: 'Script of the text',
              child: SegmentedButton<OcrScript>(
                key: const Key('clean-script'),
                segments: const <ButtonSegment<OcrScript>>[
                  ButtonSegment<OcrScript>(value: OcrScript.latin, label: Text('Latin')),
                  ButtonSegment<OcrScript>(value: OcrScript.devanagari, label: Text('देवनागरी')),
                ],
                selected: <OcrScript>{_script},
                onSelectionChanged: _running ? null : (Set<OcrScript> s) => setState(() => _script = s.first),
              ),
            ),
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const Key('clean-analyze'),
            onPressed: src == null || _running ? null : _analyze,
            icon: const Icon(Icons.auto_fix_high_outlined),
            label: const Text('Check pages'),
          ),
          if (_running) ...<Widget>[
            const SizedBox(height: 16),
            const LinearProgressIndicator(),
            const SizedBox(height: 8),
            Text(_progress, key: const Key('clean-progress')),
          ],
          if (pages != null) ...<Widget>[
            const SizedBox(height: 24),
            Text('Blank if less than ${(_threshold * 100).toStringAsFixed(1)} % of the page has ink',
                key: const Key('clean-threshold-label'), style: text.titleSmall),
            Slider(
              key: const Key('clean-threshold'),
              min: minBlankInk,
              max: maxBlankInk,
              value: _threshold,
              semanticFormatterCallback: (double v) => '${(v * 100).toStringAsFixed(1)} percent ink',
              onChanged: r != null ? null : (double v) => setState(() => _threshold = v),
            ),
            Text(
              removing == 0
                  ? 'No pages will be removed. Tap a page to remove it.'
                  : '$removing of ${pages.length} ${pages.length == 1 ? 'page' : 'pages'} will be removed. Tap a page to change.',
              key: const Key('clean-plan'),
              style: text.bodyMedium,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[for (final CleanPage p in pages) SizedBox(width: 150, child: _tile(p))],
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const Key('clean-apply'),
              onPressed: r != null ? null : _apply,
              icon: const Icon(Icons.check),
              label: const Text('Make clean PDF'),
            ),
          ],
          if (r != null) ...<Widget>[
            const SizedBox(height: 24),
            Semantics(
              header: true,
              child: Text(
                '${r.kept} ${r.kept == 1 ? 'page' : 'pages'} kept, ${r.removed} removed, '
                '${r.straightened} straightened, ${r.turned} turned',
                key: const Key('clean-summary'),
                style: text.titleMedium,
              ),
            ),
            if (_savedPath != null)
              Text('Saved as ${baseName(_savedPath!)}', key: const Key('clean-saved'), style: text.bodySmall),
          ],
        ],
      ),
      bottomNavigationBar: ResultBar(onShare: _share, onSave: _save, onUndo: _undo),
    );
  }
}
