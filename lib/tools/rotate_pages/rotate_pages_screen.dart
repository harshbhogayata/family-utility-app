import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import '../../app/widgets/result_bar.dart';
import '../../engines/pdf/page_rotate.dart';
import '../../engines/pdf/pdf_splitter.dart';
import '../../engines/pdf/pdf_to_images.dart';
import '../../engines/share/share_engine.dart';
import '../../platform/pdf_rasterizer_platform.dart';

/// The PDF the person picked.
class RotateSource {
  const RotateSource(this.name, this.bytes);
  final String name;
  final Uint8List bytes;
}

/// Picks the PDF and keeps the result. Behind an interface for tests.
abstract class RotateFiles {
  Future<RotateSource?> pick();
  Future<String> write(String name, Uint8List bytes);
  Future<void> remove(String path);
}

class SystemRotateFiles implements RotateFiles {
  const SystemRotateFiles();

  @override
  Future<RotateSource?> pick() async {
    final FilePickerResult? r = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: <String>['pdf'],
    );
    final PlatformFile? f = r?.files.isEmpty ?? true ? null : r!.files.first;
    final String? p = f?.path;
    if (f == null || p == null) {
      return null;
    }
    return RotateSource(f.name, await File(p).readAsBytes());
  }

  @override
  Future<String> write(String name, Uint8List bytes) async {
    final Directory base = await getApplicationDocumentsDirectory();
    final Directory dir = Directory('${base.path}/edited');
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

typedef RotateRunner = Future<RotateResult> Function(RotateRequest request);

Future<RotateResult> rotateInIsolate(RotateRequest request) => compute(PageRotator.run, request);

/// Feature 007 — Rotate pages.
class RotatePagesScreen extends StatefulWidget {
  const RotatePagesScreen({
    super.key,
    this.files = const SystemRotateFiles(),
    this.rasterizer = const PdfrxRasterizer(),
    this.runner = rotateInIsolate,
    this.share,
  });

  final RotateFiles files;
  final PdfRasterizer rasterizer;
  final RotateRunner runner;
  final ShareEngine? share;

  @override
  State<RotatePagesScreen> createState() => _RotatePagesScreenState();
}

class _RotatePagesScreenState extends State<RotatePagesScreen> {
  static const int thumbDpi = 24;

  RotateSource? _pdf;
  PageTurns _turns = PageTurns(0);

  /// Earlier turns, for Undo.
  final List<List<int>> _past = <List<int>>[];
  final Map<int, Uint8List> _thumbs = <int, Uint8List>{};
  RotateResult? _result;
  String? _path;
  String? _status;
  bool _working = false;

  void _toast(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(m)));
    }
  }

  Future<void> _pick() async {
    final RotateSource? p = await widget.files.pick();
    if (!mounted || p == null) {
      return;
    }
    int pages = 0;
    String? status;
    try {
      pages = PageRotator.open(p.bytes).pageCount;
    } on SplitError catch (e) {
      status = e.message;
    }
    setState(() {
      _pdf = p;
      _turns = PageTurns(pages);
      _past.clear();
      _status = status;
      _result = null;
      _path = null;
      _thumbs.clear();
    });
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

  void _change(void Function(PageTurns t) edit, String said) {
    final List<int> before = _turns.turns;
    edit(_turns);
    setState(() {
      _past.add(before);
      _result = null;
      _path = null;
      _status = said;
    });
  }

  static String _way(bool clockwise) => clockwise ? 'right' : 'left';

  void _rotate(int page, bool clockwise) => _change(
        (PageTurns t) => t.rotate(page, clockwise: clockwise),
        'Page $page turned ${_way(clockwise)}; now ${_turnLabel(page)}',
      );

  void _rotateAll(bool clockwise) => _change(
        (PageTurns t) => t.rotateAll(clockwise: clockwise),
        'All ${_turns.length} pages turned ${_way(clockwise)}',
      );

  String _turnLabel(int page) {
    final int deg = _turns.degreesOf(page);
    return deg == 0 ? 'upright as in the file' : 'turned $deg° clockwise';
  }

  Future<void> _save() async {
    final RotateSource? pdf = _pdf;
    if (pdf == null || _working) {
      _toast('Choose a PDF first');
      return;
    }
    if (_path != null) {
      _toast('Saved in Files › edited');
      return;
    }
    if (_turns.isOriginal) {
      _toast('Turn a page first');
      return;
    }
    setState(() => _working = true);
    try {
      final RotateResult r = await widget.runner(RotateRequest(bytes: pdf.bytes, name: pdf.name, turns: _turns.turns));
      final String path = await widget.files.write(r.name, r.bytes);
      setState(() {
        _result = r;
        _path = path;
        _status = 'Saved with ${r.turned} of ${r.pageCount} pages turned in Files › edited. Your original is unchanged.';
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
        _status = 'Removed the saved PDF; your turns are still here';
      });
      return;
    }
    if (_past.isNotEmpty) {
      setState(() {
        _turns = PageTurns.of(_past.removeLast());
        _status = 'Undid the last turn';
      });
      return;
    }
    if (mounted) {
      await Navigator.of(context).maybePop();
    }
  }

  Widget _tile(int page) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final Uint8List? thumb = _thumbs[page];
    final int quarter = _turns.of(page);
    return Semantics(
      key: Key('rotate-tile-$page'),
      container: true,
      label: 'Page $page, ${_turnLabel(page)}',
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: quarter == 0 ? colors.outlineVariant : colors.primary, width: quarter == 0 ? 1 : 2),
        ),
        child: Column(
          children: <Widget>[
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: RotatedBox(
                  quarterTurns: quarter,
                  child: thumb != null
                      ? Image.memory(thumb, fit: BoxFit.contain, excludeFromSemantics: true,
                          errorBuilder: (BuildContext c, Object e, StackTrace? t) => const SizedBox())
                      : AspectRatio(
                          aspectRatio: 0.72,
                          child: ColoredBox(
                            color: colors.surfaceContainerHighest,
                            child: const Align(alignment: Alignment.topCenter, child: Icon(Icons.arrow_upward, size: 16)),
                          ),
                        ),
                ),
              ),
            ),
            Row(
              children: <Widget>[
                IconButton(
                  key: Key('rotate-left-$page'),
                  tooltip: 'Turn page $page left',
                  constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                  onPressed: _working ? null : () => _rotate(page, false),
                  icon: const Icon(Icons.rotate_left),
                ),
                Expanded(
                  child: ExcludeSemantics(
                    child: Text(
                      quarter == 0 ? '$page' : '$page · ${quarter * 90}°',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ),
                ),
                IconButton(
                  key: Key('rotate-right-$page'),
                  tooltip: 'Turn page $page right',
                  constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                  onPressed: _working ? null : () => _rotate(page, true),
                  icon: const Icon(Icons.rotate_right),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final RotateSource? pdf = _pdf;
    final RotateResult? r = _result;
    return Scaffold(
      appBar: AppBar(title: const Text('Rotate pages')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          OutlinedButton.icon(
            key: const Key('rotate-pick'),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: _working ? null : _pick,
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: Text(pdf == null ? 'Choose a PDF' : 'Choose another PDF'),
          ),
          if (pdf != null && _turns.length > 0) ...<Widget>[
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: FilledButton.tonalIcon(
                    key: const Key('rotate-all-left'),
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                    onPressed: _working ? null : () => _rotateAll(false),
                    icon: const Icon(Icons.rotate_left),
                    label: const Text('All left'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.tonalIcon(
                    key: const Key('rotate-all-right'),
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                    onPressed: _working ? null : () => _rotateAll(true),
                    icon: const Icon(Icons.rotate_right),
                    label: const Text('All right'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${_turns.length} pages · ${_turns.turned} turned',
              key: const Key('rotate-count'),
              style: text.titleSmall,
            ),
            const SizedBox(height: 8),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 0.8,
              children: <Widget>[for (int p = 1; p <= _turns.length; p++) _tile(p)],
            ),
          ],
          if (_status != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Semantics(liveRegion: true, child: Text(_status!, key: const Key('rotate-status'), style: text.bodyMedium)),
            ),
          if (r != null)
            ListTile(
              key: const Key('rotate-result'),
              leading: const Icon(Icons.description_outlined),
              title: Text(r.name),
              subtitle: Text('${r.turned} of ${r.pageCount} pages turned'),
            ),
        ],
      ),
      bottomNavigationBar: ResultBar(onShare: _share, onSave: _save, onUndo: _undo),
    );
  }
}
