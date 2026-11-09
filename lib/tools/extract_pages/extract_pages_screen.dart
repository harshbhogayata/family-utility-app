import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import '../../app/widgets/result_bar.dart';
import '../../engines/pdf/page_extractor.dart';
import '../../engines/pdf/pdf_splitter.dart';
import '../../engines/pdf/pdf_to_images.dart';
import '../../engines/share/share_engine.dart';
import '../../platform/pdf_rasterizer_platform.dart';

/// The PDF the person picked.
class ExtractSource {
  const ExtractSource(this.name, this.bytes);
  final String name;
  final Uint8List bytes;
}

/// Picks the PDF and keeps the result. Behind an interface for tests.
abstract class ExtractFiles {
  Future<ExtractSource?> pick();
  Future<String> write(String name, Uint8List bytes);
  Future<void> remove(String path);
}

class SystemExtractFiles implements ExtractFiles {
  const SystemExtractFiles();

  @override
  Future<ExtractSource?> pick() async {
    final FilePickerResult? r = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: <String>['pdf'],
    );
    final PlatformFile? f = r?.files.isEmpty ?? true ? null : r!.files.first;
    final String? p = f?.path;
    if (f == null || p == null) {
      return null;
    }
    return ExtractSource(f.name, await File(p).readAsBytes());
  }

  @override
  Future<String> write(String name, Uint8List bytes) async {
    final Directory base = await getApplicationDocumentsDirectory();
    final Directory dir = Directory('${base.path}/extracted');
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
}

typedef ExtractRunner = Future<ExtractResult> Function(ExtractRequest request);

Future<ExtractResult> extractInIsolate(ExtractRequest request) => compute(PageExtractor.run, request);

/// Feature 004 — Extract pages.
class ExtractPagesScreen extends StatefulWidget {
  const ExtractPagesScreen({
    super.key,
    this.files = const SystemExtractFiles(),
    this.rasterizer = const PdfrxRasterizer(),
    this.runner = extractInIsolate,
    this.share,
  });

  final ExtractFiles files;
  final PdfRasterizer rasterizer;
  final ExtractRunner runner;
  final ShareEngine? share;

  @override
  State<ExtractPagesScreen> createState() => _ExtractPagesScreenState();
}

class _ExtractPagesScreenState extends State<ExtractPagesScreen> {
  /// Thumbnails are drawn small: enough to recognise a page.
  static const int thumbDpi = 24;

  final PageSelection _selection = PageSelection();
  ExtractSource? _pdf;
  int _pages = 0;
  final Map<int, Uint8List> _thumbs = <int, Uint8List>{};
  ExtractResult? _result;
  String? _path;
  String? _status;
  bool _working = false;

  /// What Undo puts back when it clears a selection.
  List<int>? _clearedSelection;

  void _toast(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(m)));
    }
  }

  Future<void> _pick() async {
    final ExtractSource? p = await widget.files.pick();
    if (!mounted || p == null) {
      return;
    }
    int pages = 0;
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
      _path = null;
      _thumbs.clear();
      _selection.clear();
      _clearedSelection = null;
    });
    await _drawThumbs(p, pages);
  }

  Future<void> _drawThumbs(ExtractSource p, int pages) async {
    for (int i = 0; i < pages; i++) {
      try {
        final img.Image page = await widget.rasterizer.render(p.bytes, i, thumbDpi);
        final Uint8List jpg = img.encodeJpg(page, quality: 70);
        if (!mounted || _pdf != p) {
          return;
        }
        setState(() => _thumbs[i + 1] = jpg);
      } catch (_) {
        // The page shows its number only.
      }
    }
  }

  void _toggle(int page) {
    setState(() {
      _selection.toggle(page);
      _clearedSelection = null;
    });
  }

  Future<void> _extract() async {
    final ExtractSource? pdf = _pdf;
    if (pdf == null || _working) {
      return;
    }
    if (_selection.isEmpty) {
      setState(() => _status = 'Tap the pages to take first.');
      return;
    }
    setState(() => _working = true);
    try {
      final ExtractResult r = await widget.runner(ExtractRequest(bytes: pdf.bytes, name: pdf.name, pages: _selection.order));
      final String path = await widget.files.write(r.name, r.bytes);
      setState(() {
        _result = r;
        _path = path;
        _status = 'Took ${r.pages.length} of ${r.sourcePages} pages, in the order you tapped: ${r.pages.join(', ')}';
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
    final String? path = _path;
    if (path == null) {
      _toast('Extract the pages first');
      return;
    }
    await (widget.share ?? ShareEngine.instance).shareFiles(<String>[path]);
  }

  void _save() => _toast(_path == null ? 'Nothing to save yet' : 'Saved in Files › extracted');

  Future<void> _undo() async {
    final String? path = _path;
    if (path != null) {
      await widget.files.remove(path);
      setState(() {
        _result = null;
        _path = null;
        _status = 'Removed the new PDF; your pages are still chosen';
      });
      return;
    }
    final List<int>? cleared = _clearedSelection;
    if (cleared != null) {
      setState(() {
        _selection.restore(cleared);
        _clearedSelection = null;
        _status = null;
      });
      return;
    }
    if (!_selection.isEmpty) {
      setState(() {
        _clearedSelection = _selection.order;
        _selection.clear();
        _status = 'Cleared the chosen pages';
      });
      return;
    }
    if (_pdf != null) {
      setState(() {
        _pdf = null;
        _pages = 0;
        _thumbs.clear();
        _status = null;
      });
      return;
    }
    if (mounted) {
      await Navigator.of(context).maybePop();
    }
  }

  Widget _tile(int page) {
    final int? place = _selection.placeOf(page);
    final Uint8List? thumb = _thumbs[page];
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: place != null,
      label: 'Page $page${place == null ? '' : ', chosen ${_ordinal(place)}'}',
      excludeSemantics: true,
      child: InkWell(
        key: Key('extract-page-$page'),
        borderRadius: BorderRadius.circular(8),
        onTap: () => _toggle(page),
        child: Container(
          constraints: const BoxConstraints(minHeight: 96, minWidth: 64),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: place != null ? colors.primary : colors.outlineVariant, width: place != null ? 3 : 1),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              ClipRRect(
                borderRadius: BorderRadius.circular(7),
                child: thumb != null
                    ? Image.memory(thumb, fit: BoxFit.contain, excludeFromSemantics: true,
                        errorBuilder: (BuildContext c, Object e, StackTrace? t) => const SizedBox())
                    : ColoredBox(color: colors.surfaceContainerHighest),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Text('$page', style: Theme.of(context).textTheme.labelMedium),
                ),
              ),
              if (place != null)
                Align(
                  alignment: Alignment.topRight,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: CircleAvatar(
                      radius: 13,
                      backgroundColor: colors.primary,
                      child: Text('$place', key: Key('extract-place-$page'),
                          style: TextStyle(color: colors.onPrimary, fontSize: 12)),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  static String _ordinal(int n) {
    final int mod100 = n % 100;
    if (mod100 >= 11 && mod100 <= 13) {
      return '${n}th';
    }
    switch (n % 10) {
      case 1:
        return '${n}st';
      case 2:
        return '${n}nd';
      case 3:
        return '${n}rd';
      default:
        return '${n}th';
    }
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ExtractSource? pdf = _pdf;
    final ExtractResult? r = _result;
    return Scaffold(
      appBar: AppBar(title: const Text('Extract pages')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          OutlinedButton.icon(
            key: const Key('extract-pick'),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: _working ? null : _pick,
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: Text(pdf == null ? 'Choose a PDF' : 'Choose another PDF'),
          ),
          if (pdf != null && _pages > 0) ...<Widget>[
            const SizedBox(height: 12),
            Text('Tap pages in the order you want them. Tap again to drop one.', style: text.bodyMedium),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                Expanded(
                  child: Text('${_selection.length} of $_pages chosen', key: const Key('extract-count'), style: text.titleSmall),
                ),
                TextButton(
                  key: const Key('extract-all'),
                  style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                  onPressed: () => setState(() => _selection.selectAll(_pages)),
                  child: const Text('Choose all'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 0.72,
              children: <Widget>[for (int p = 1; p <= _pages; p++) _tile(p)],
            ),
            const SizedBox(height: 12),
            FilledButton(
              key: const Key('extract-run'),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              onPressed: _working || _selection.isEmpty ? null : _extract,
              child: Text(_working ? 'Extracting…' : 'Extract ${_selection.length} ${_selection.length == 1 ? 'page' : 'pages'}'),
            ),
          ],
          if (_status != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Semantics(liveRegion: true, child: Text(_status!, key: const Key('extract-status'), style: text.bodyMedium)),
            ),
          if (r != null)
            ListTile(
              key: const Key('extract-result'),
              leading: const Icon(Icons.description_outlined),
              title: Text(r.name),
              subtitle: Text('${r.pages.length} ${r.pages.length == 1 ? 'page' : 'pages'}'),
            ),
        ],
      ),
      bottomNavigationBar: ResultBar(onShare: _share, onSave: _save, onUndo: _undo),
    );
  }
}
