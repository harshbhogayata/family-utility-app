import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import '../../app/widgets/result_bar.dart';
import '../../engines/pdf/page_reorder.dart';
import '../../engines/pdf/pdf_splitter.dart';
import '../../engines/pdf/pdf_to_images.dart';
import '../../engines/share/share_engine.dart';
import '../../platform/pdf_rasterizer_platform.dart';

/// The PDF the person picked.
class ReorderSource {
  const ReorderSource(this.name, this.bytes);
  final String name;
  final Uint8List bytes;
}

/// Picks the PDF and keeps the result. Behind an interface for tests.
abstract class ReorderFiles {
  Future<ReorderSource?> pick();
  Future<String> write(String name, Uint8List bytes);
  Future<void> remove(String path);
}

class SystemReorderFiles implements ReorderFiles {
  const SystemReorderFiles();

  @override
  Future<ReorderSource?> pick() async {
    final FilePickerResult? r = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: <String>['pdf'],
    );
    final PlatformFile? f = r?.files.isEmpty ?? true ? null : r!.files.first;
    final String? p = f?.path;
    if (f == null || p == null) {
      return null;
    }
    return ReorderSource(f.name, await File(p).readAsBytes());
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

typedef ReorderRunner = Future<ReorderResult> Function(ReorderRequest request);

Future<ReorderResult> reorderInIsolate(ReorderRequest request) => compute(PageReorderer.run, request);

enum _TileAction { earlier, later, blankBefore, blankAfter, removeBlank }

/// Feature 006 — Reorder pages.
class ReorderPagesScreen extends StatefulWidget {
  const ReorderPagesScreen({
    super.key,
    this.files = const SystemReorderFiles(),
    this.rasterizer = const PdfrxRasterizer(),
    this.runner = reorderInIsolate,
    this.share,
  });

  final ReorderFiles files;
  final PdfRasterizer rasterizer;
  final ReorderRunner runner;
  final ShareEngine? share;

  @override
  State<ReorderPagesScreen> createState() => _ReorderPagesScreenState();
}

class _ReorderPagesScreenState extends State<ReorderPagesScreen> {
  static const int thumbDpi = 24;

  ReorderSource? _pdf;
  PageLayout _layout = PageLayout(0);

  /// Earlier layouts, for Undo.
  final List<List<int>> _past = <List<int>>[];
  final Map<int, Uint8List> _thumbs = <int, Uint8List>{};
  ReorderResult? _result;
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
    final ReorderSource? p = await widget.files.pick();
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
      _layout = PageLayout(pages);
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

  void _change(void Function(PageLayout l) edit, String said) {
    final List<int> before = _layout.slots;
    edit(_layout);
    if (_listEquals(before, _layout.slots)) {
      return;
    }
    setState(() {
      _past.add(before);
      _result = null;
      _path = null;
      _status = said;
    });
  }

  static bool _listEquals(List<int> a, List<int> b) {
    if (a.length != b.length) {
      return false;
    }
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }

  String _labelAt(int i) => _layout.isBlank(i) ? 'Blank page' : 'Page ${_layout[i]}';

  void _act(int i, _TileAction a) {
    switch (a) {
      case _TileAction.earlier:
        _change((PageLayout l) => l.move(i, i - 1), '${_labelAt(i)} moved to place $i');
      case _TileAction.later:
        _change((PageLayout l) => l.move(i, i + 1), '${_labelAt(i)} moved to place ${i + 2}');
      case _TileAction.blankBefore:
        _change((PageLayout l) => l.insertBlank(i), 'Blank page added at place ${i + 1}');
      case _TileAction.blankAfter:
        _change((PageLayout l) => l.insertBlank(i + 1), 'Blank page added at place ${i + 2}');
      case _TileAction.removeBlank:
        _change((PageLayout l) => l.removeBlank(i), 'Blank page taken out');
    }
  }

  Future<void> _save() async {
    final ReorderSource? pdf = _pdf;
    if (pdf == null || _working) {
      _toast('Choose a PDF first');
      return;
    }
    if (_path != null) {
      _toast('Saved in Files › edited');
      return;
    }
    if (_layout.isOriginal) {
      _toast('Drag a page or add a blank page first');
      return;
    }
    setState(() => _working = true);
    try {
      final ReorderResult r = await widget.runner(ReorderRequest(bytes: pdf.bytes, name: pdf.name, slots: _layout.slots));
      final String path = await widget.files.write(r.name, r.bytes);
      setState(() {
        _result = r;
        _path = path;
        _status = 'Saved ${r.slots.length} pages in the new order in Files › edited. Your original is unchanged.';
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
        _status = 'Removed the saved PDF; the new order is still here';
      });
      return;
    }
    if (_past.isNotEmpty) {
      setState(() {
        _layout = PageLayout.of(_past.removeLast());
        _status = 'Undid the last change';
      });
      return;
    }
    if (mounted) {
      await Navigator.of(context).maybePop();
    }
  }

  Widget _face(int i, {bool dragging = false}) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final bool blank = _layout.isBlank(i);
    final Uint8List? thumb = blank ? null : _thumbs[_layout[i]];
    return Container(
      constraints: const BoxConstraints(minHeight: 96, minWidth: 64),
      decoration: BoxDecoration(
        color: blank ? Colors.white : null,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: dragging ? colors.primary : colors.outlineVariant, width: dragging ? 3 : 1),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          if (!blank)
            ClipRRect(
              borderRadius: BorderRadius.circular(7),
              child: thumb != null
                  ? Image.memory(thumb, fit: BoxFit.contain, excludeFromSemantics: true,
                      errorBuilder: (BuildContext c, Object e, StackTrace? t) => const SizedBox())
                  : ColoredBox(color: colors.surfaceContainerHighest),
            ),
          Align(
            alignment: Alignment.bottomLeft,
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Text(blank ? 'Blank' : '${_layout[i]}', style: Theme.of(context).textTheme.labelMedium),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tile(int i) {
    final bool blank = _layout.isBlank(i);
    final int last = _layout.length - 1;
    final String label = '${_labelAt(i)}, place ${i + 1} of ${_layout.length}';
    return DragTarget<int>(
      onWillAcceptWithDetails: (DragTargetDetails<int> d) => d.data != i,
      onAcceptWithDetails: (DragTargetDetails<int> d) =>
          _change((PageLayout l) => l.move(d.data, i), '${_labelAt(d.data)} moved to place ${i + 1}'),
      builder: (BuildContext context, List<int?> over, List<dynamic> rejected) => Semantics(
        label: label,
        customSemanticsActions: <CustomSemanticsAction, VoidCallback>{
          if (i > 0) const CustomSemanticsAction(label: 'Move earlier'): () => _act(i, _TileAction.earlier),
          if (i < last) const CustomSemanticsAction(label: 'Move later'): () => _act(i, _TileAction.later),
          const CustomSemanticsAction(label: 'Add blank page before'): () => _act(i, _TileAction.blankBefore),
          const CustomSemanticsAction(label: 'Add blank page after'): () => _act(i, _TileAction.blankAfter),
        },
        child: LongPressDraggable<int>(
          key: Key('reorder-tile-$i'),
          data: i,
          feedback: SizedBox(width: 96, height: 132, child: Material(elevation: 6, child: _face(i, dragging: true))),
          childWhenDragging: Opacity(opacity: 0.3, child: _face(i)),
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              _face(i, dragging: over.isNotEmpty),
              Align(
                alignment: Alignment.topRight,
                child: PopupMenuButton<_TileAction>(
                  key: Key('reorder-menu-$i'),
                  tooltip: 'Options for ${_labelAt(i)}',
                  onSelected: (_TileAction a) => _act(i, a),
                  itemBuilder: (BuildContext c) => <PopupMenuEntry<_TileAction>>[
                    if (i > 0) const PopupMenuItem<_TileAction>(value: _TileAction.earlier, child: Text('Move earlier')),
                    if (i < last) const PopupMenuItem<_TileAction>(value: _TileAction.later, child: Text('Move later')),
                    const PopupMenuItem<_TileAction>(value: _TileAction.blankBefore, child: Text('Add blank page before')),
                    const PopupMenuItem<_TileAction>(value: _TileAction.blankAfter, child: Text('Add blank page after')),
                    if (blank)
                      const PopupMenuItem<_TileAction>(value: _TileAction.removeBlank, child: Text('Take out this blank page')),
                  ],
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
    final ReorderSource? pdf = _pdf;
    final ReorderResult? r = _result;
    return Scaffold(
      appBar: AppBar(title: const Text('Reorder pages')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          OutlinedButton.icon(
            key: const Key('reorder-pick'),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: _working ? null : _pick,
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: Text(pdf == null ? 'Choose a PDF' : 'Choose another PDF'),
          ),
          if (pdf != null && _layout.length > 0) ...<Widget>[
            const SizedBox(height: 12),
            Text('Hold a page and drag it to a new place. Use ⋮ on a page to move it or add a blank page.',
                style: text.bodyMedium),
            const SizedBox(height: 8),
            Text(
              '${_layout.length} pages${_layout.blanks == 0 ? '' : ' · ${_layout.blanks} blank'}',
              key: const Key('reorder-count'),
              style: text.titleSmall,
            ),
            const SizedBox(height: 8),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 0.72,
              children: <Widget>[for (int i = 0; i < _layout.length; i++) _tile(i)],
            ),
          ],
          if (_status != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Semantics(liveRegion: true, child: Text(_status!, key: const Key('reorder-status'), style: text.bodyMedium)),
            ),
          if (r != null)
            ListTile(
              key: const Key('reorder-result'),
              leading: const Icon(Icons.description_outlined),
              title: Text(r.name),
              subtitle: Text('${r.slots.length} pages'),
            ),
        ],
      ),
      bottomNavigationBar: ResultBar(onShare: _share, onSave: _save, onUndo: _undo),
    );
  }
}
