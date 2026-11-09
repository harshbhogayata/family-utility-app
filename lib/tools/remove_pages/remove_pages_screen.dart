import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import '../../app/widgets/result_bar.dart';
import '../../engines/pdf/page_remover.dart';
import '../../engines/pdf/pdf_splitter.dart';
import '../../engines/pdf/pdf_to_images.dart';
import '../../engines/platform/versions.dart';
import '../../engines/share/share_engine.dart';
import '../../platform/pdf_rasterizer_platform.dart';

/// The PDF the person picked; [path] is where it lives, when known.
class RemoveSource {
  const RemoveSource(this.name, this.bytes, {this.path});
  final String name;
  final Uint8List bytes;
  final String? path;
}

/// Picks the PDF, writes the result and keeps versions. Behind an interface
/// for tests.
abstract class RemoveFiles {
  Future<RemoveSource?> pick();

  /// A new file in Files › edited; returns its path.
  Future<String> writeCopy(String name, Uint8List bytes);

  /// Replaces the file at [path].
  Future<void> overwrite(String path, Uint8List bytes);

  Future<void> remove(String path);

  /// Keeps the current file at [path] in its version list (108) first.
  Future<void> keepVersion(String path);
}

class SystemRemoveFiles implements RemoveFiles {
  const SystemRemoveFiles();

  @override
  Future<RemoveSource?> pick() async {
    final FilePickerResult? r = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: <String>['pdf'],
    );
    final PlatformFile? f = r?.files.isEmpty ?? true ? null : r!.files.first;
    final String? p = f?.path;
    if (f == null || p == null) {
      return null;
    }
    return RemoveSource(f.name, await File(p).readAsBytes(), path: p);
  }

  @override
  Future<String> writeCopy(String name, Uint8List bytes) async {
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
  Future<void> overwrite(String path, Uint8List bytes) => File(path).writeAsBytes(bytes, flush: true);

  @override
  Future<void> remove(String path) async {
    final File f = File(path);
    if (f.existsSync()) {
      await f.delete();
    }
  }

  @override
  Future<void> keepVersion(String path) async {
    await Versions.instance.keep(path, path, 'Before removing pages');
  }
}

typedef RemoveRunner = Future<RemoveResult> Function(RemoveRequest request);

Future<RemoveResult> removeInIsolate(RemoveRequest request) => compute(PageRemover.run, request);

/// Feature 005 — Remove pages.
class RemovePagesScreen extends StatefulWidget {
  const RemovePagesScreen({
    super.key,
    this.files = const SystemRemoveFiles(),
    this.rasterizer = const PdfrxRasterizer(),
    this.runner = removeInIsolate,
    this.share,
  });

  final RemoveFiles files;
  final PdfRasterizer rasterizer;
  final RemoveRunner runner;
  final ShareEngine? share;

  @override
  State<RemovePagesScreen> createState() => _RemovePagesScreenState();
}

class _RemovePagesScreenState extends State<RemovePagesScreen> {
  static const int thumbDpi = 24;

  final Set<int> _marked = <int>{};
  RemoveSource? _pdf;
  int _pages = 0;
  final Map<int, Uint8List> _thumbs = <int, Uint8List>{};
  bool _overwrite = false;
  RemoveResult? _result;

  /// Where the result went, and whether that replaced the original.
  String? _path;
  bool _replaced = false;
  String? _status;
  bool _working = false;
  Set<int>? _clearedMarks;

  void _toast(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(m)));
    }
  }

  Future<void> _pick() async {
    final RemoveSource? p = await widget.files.pick();
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
      _replaced = false;
      _overwrite = false;
      _thumbs.clear();
      _marked.clear();
      _clearedMarks = null;
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

  Future<void> _run() async {
    final RemoveSource? pdf = _pdf;
    if (pdf == null || _working || _result != null) {
      return;
    }
    setState(() => _working = true);
    try {
      final RemoveResult r = await widget.runner(RemoveRequest(bytes: pdf.bytes, name: pdf.name, pages: _marked.toList()));
      final String? original = pdf.path;
      final String path;
      final bool replaced;
      if (_overwrite && original != null) {
        await widget.files.keepVersion(original);
        await widget.files.overwrite(original, r.bytes);
        path = original;
        replaced = true;
      } else {
        path = await widget.files.writeCopy(r.name, r.bytes);
        replaced = false;
      }
      setState(() {
        _result = r;
        _path = path;
        _replaced = replaced;
        _status = 'Removed ${r.removed.length} of ${r.sourcePages} pages; ${r.kept.length} left. '
            '${replaced ? 'The original was replaced (an older version is kept).' : 'Your original is unchanged.'}';
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
      _toast('Remove the pages first');
      return;
    }
    await (widget.share ?? ShareEngine.instance).shareFiles(<String>[path]);
  }

  void _save() => _toast(_path == null
      ? 'Nothing to save yet'
      : _replaced
          ? 'Saved over the original'
          : 'Saved in Files › edited');

  Future<void> _undo() async {
    final String? path = _path;
    final RemoveSource? pdf = _pdf;
    if (path != null && pdf != null) {
      if (_replaced) {
        await widget.files.overwrite(path, pdf.bytes);
      } else {
        await widget.files.remove(path);
      }
      setState(() {
        _status = _replaced ? 'Put the original back' : 'Removed the new PDF';
        _result = null;
        _path = null;
        _replaced = false;
      });
      return;
    }
    final Set<int>? cleared = _clearedMarks;
    if (cleared != null) {
      setState(() {
        _marked.addAll(cleared);
        _clearedMarks = null;
        _status = null;
      });
      return;
    }
    if (_marked.isNotEmpty) {
      setState(() {
        _clearedMarks = Set<int>.of(_marked);
        _marked.clear();
        _status = 'Unmarked the pages';
      });
      return;
    }
    if (mounted) {
      await Navigator.of(context).maybePop();
    }
  }

  Widget _tile(int page) {
    final bool marked = _marked.contains(page);
    final Uint8List? thumb = _thumbs[page];
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: marked,
      label: 'Page $page${marked ? ', marked for removal' : ''}',
      excludeSemantics: true,
      child: InkWell(
        key: Key('remove-page-$page'),
        borderRadius: BorderRadius.circular(8),
        onTap: _result != null
            ? null
            : () => setState(() {
                  marked ? _marked.remove(page) : _marked.add(page);
                  _clearedMarks = null;
                }),
        child: Container(
          constraints: const BoxConstraints(minHeight: 96, minWidth: 64),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: marked ? colors.error : colors.outlineVariant, width: marked ? 3 : 1),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              ClipRRect(
                borderRadius: BorderRadius.circular(7),
                child: Opacity(
                  opacity: marked ? 0.35 : 1,
                  child: thumb != null
                      ? Image.memory(thumb, fit: BoxFit.contain, excludeFromSemantics: true,
                          errorBuilder: (BuildContext c, Object e, StackTrace? t) => const SizedBox())
                      : ColoredBox(color: colors.surfaceContainerHighest),
                ),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Text('$page', style: Theme.of(context).textTheme.labelMedium),
                ),
              ),
              if (marked)
                Align(
                  alignment: Alignment.topRight,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(Icons.delete, color: colors.error, size: 22),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final RemoveSource? pdf = _pdf;
    final RemoveResult? r = _result;
    final int n = _marked.length;
    return Scaffold(
      appBar: AppBar(title: const Text('Remove pages')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          OutlinedButton.icon(
            key: const Key('remove-pick'),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: _working ? null : _pick,
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: Text(pdf == null ? 'Choose a PDF' : 'Choose another PDF'),
          ),
          if (pdf != null && _pages > 0) ...<Widget>[
            const SizedBox(height: 12),
            Text('Tap the pages to remove. Tap again to keep one.', style: text.bodyMedium),
            const SizedBox(height: 8),
            Text('$n of $_pages marked', key: const Key('remove-count'), style: text.titleSmall),
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
            const SizedBox(height: 8),
            SwitchListTile(
              key: const Key('remove-overwrite'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Replace the original'),
              subtitle: Text(pdf.path == null
                  ? 'This file can only be saved as a copy'
                  : 'Off keeps your original and saves a copy. On keeps the old one in Versions.'),
              value: _overwrite,
              onChanged: pdf.path == null || r != null ? null : (bool v) => setState(() => _overwrite = v),
            ),
            const SizedBox(height: 8),
            FilledButton(
              key: const Key('remove-run'),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              onPressed: _working || n == 0 || r != null ? null : _run,
              child: Text(_working ? 'Removing…' : 'Remove $n ${n == 1 ? 'page' : 'pages'}'),
            ),
          ],
          if (_status != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Semantics(liveRegion: true, child: Text(_status!, key: const Key('remove-status'), style: text.bodyMedium)),
            ),
          if (r != null)
            ListTile(
              key: const Key('remove-result'),
              leading: const Icon(Icons.description_outlined),
              title: Text(_replaced ? pdf?.name ?? r.name : r.name),
              subtitle: Text('${r.kept.length} ${r.kept.length == 1 ? 'page' : 'pages'}'),
            ),
        ],
      ),
      bottomNavigationBar: ResultBar(onShare: _share, onSave: _save, onUndo: _undo),
    );
  }
}
