import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../app/widgets/result_bar.dart';
import '../../engines/pdf/pdf_reader.dart';
import '../../engines/platform/action_history.dart' show baseName;
import '../../engines/platform/file_manager.dart';
import '../../engines/share/share_engine.dart';
import '../../platform/pdf_surface.dart';

/// Picks a PDF. Behind an interface for tests.
abstract class PdfChooser {
  Future<String?> pick();
}

class SystemPdfChooser implements PdfChooser {
  const SystemPdfChooser();

  @override
  Future<String?> pick() async {
    final FilePickerResult? r = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: <String>['pdf'],
    );
    return r?.files.single.path;
  }
}

/// Feature 001 — PDF viewer.
class PdfViewerScreen extends StatefulWidget {
  const PdfViewerScreen({
    super.key,
    this.path,
    this.surface = const PdfrxSurface(),
    this.chooser = const SystemPdfChooser(),
    this.store,
    this.share,
  });

  final String? path;
  final PdfSurface surface;
  final PdfChooser chooser;
  final LastPageStore? store;
  final ShareEngine? share;

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  String? _path;
  PdfReader? _reader;
  bool _thumbs = true;
  late final LastPageStore _store = widget.store ?? const PrefsLastPageStore();

  @override
  void initState() {
    super.initState();
    final String? p = widget.path;
    if (p != null) {
      _load(p);
    }
  }

  void _load(String p) {
    _reader?.removeListener(_changed);
    _reader?.dispose();
    final PdfReader r = PdfReader(fileKey: p, store: _store)..addListener(_changed);
    setState(() {
      _path = p;
      _reader = r;
    });
    FileManager.instance.touch(p);
  }

  @override
  void dispose() {
    _reader?.removeListener(_changed);
    _reader?.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) {
      setState(() {});
    }
  }

  void _toast(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(m)));
    }
  }

  Future<void> _pick() async {
    final String? p = await widget.chooser.pick();
    if (p != null && mounted) {
      _load(p);
    }
  }

  Future<void> _jumpDialog() async {
    final PdfReader? r = _reader;
    if (r == null || r.pageCount == 0) {
      return;
    }
    final TextEditingController c = TextEditingController();
    final String? typed = await showDialog<String>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Go to page'),
        content: TextField(
          key: const Key('pdf-jump-field'),
          controller: c,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: 'Page (1–${r.pageCount})'),
          onSubmitted: (String v) => Navigator.of(ctx).pop(v),
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          FilledButton(
            key: const Key('pdf-jump-go'),
            onPressed: () => Navigator.of(ctx).pop(c.text),
            child: const Text('Go'),
          ),
        ],
      ),
    );
    if (typed == null) {
      return;
    }
    final int? n = parsePageJump(typed, r.pageCount);
    if (n == null) {
      _toast('Type a page from 1 to ${r.pageCount}');
      return;
    }
    r.goTo(n);
  }

  Future<void> _share() async {
    final String? p = _path;
    if (p == null) {
      _toast('Open a PDF first');
      return;
    }
    await (widget.share ?? ShareEngine.instance).shareFiles(<String>[p]);
  }

  Future<void> _save() async {
    final PdfReader? r = _reader;
    if (r == null) {
      _toast('Open a PDF first');
      return;
    }
    await r.savePlace();
    _toast('Saved your place: page ${r.page}');
  }

  void _undo() {
    final PdfReader? r = _reader;
    if (r != null && r.undoJump()) {
      _toast('Back to page ${r.page}');
      return;
    }
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final PdfReader? r = _reader;
    final String? p = _path;
    return Scaffold(
      appBar: AppBar(
        title: Text(p == null ? 'PDF viewer' : baseName(p), overflow: TextOverflow.ellipsis),
        actions: <Widget>[
          if (r != null) ...<Widget>[
            IconButton(
              key: const Key('pdf-jump'),
              tooltip: 'Go to page',
              onPressed: _jumpDialog,
              icon: const Icon(Icons.find_in_page_outlined),
            ),
            IconButton(
              key: const Key('pdf-night'),
              tooltip: r.night ? 'Night mode off' : 'Night mode on',
              onPressed: r.toggleNight,
              icon: Icon(r.night ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
            ),
            IconButton(
              key: const Key('pdf-layout'),
              tooltip: r.layout == PdfLayout.continuous ? 'One page at a time' : 'Continuous scroll',
              onPressed: () => r.setLayout(
                r.layout == PdfLayout.continuous ? PdfLayout.single : PdfLayout.continuous,
              ),
              icon: Icon(r.layout == PdfLayout.continuous ? Icons.view_carousel_outlined : Icons.view_day_outlined),
            ),
            IconButton(
              key: const Key('pdf-thumbs'),
              tooltip: _thumbs ? 'Hide thumbnails' : 'Show thumbnails',
              onPressed: () => setState(() => _thumbs = !_thumbs),
              icon: const Icon(Icons.view_module_outlined),
            ),
          ],
        ],
      ),
      body: r == null || p == null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: FilledButton.icon(
                  key: const Key('pdf-open'),
                  onPressed: _pick,
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: const Text('Open a PDF'),
                ),
              ),
            )
          : Column(
              children: <Widget>[
                Expanded(
                  child: ColorFiltered(
                    colorFilter: r.night
                        ? const ColorFilter.matrix(NightMode.matrix)
                        : const ColorFilter.mode(Colors.transparent, BlendMode.dst),
                    child: widget.surface.viewer(context, p, r),
                  ),
                ),
                if (_thumbs && r.pageCount > 0)
                  SizedBox(
                    height: 96,
                    child: ListView.builder(
                      key: const Key('pdf-thumb-strip'),
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      itemCount: r.pageCount,
                      itemBuilder: (BuildContext ctx, int i) {
                        final int n = i + 1;
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Semantics(
                            button: true,
                            selected: n == r.page,
                            label: 'Page $n',
                            child: InkWell(
                              key: ValueKey<String>('pdf-thumb-$n'),
                              onTap: () => r.goTo(n),
                              child: Container(
                                width: 60,
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: n == r.page ? Theme.of(ctx).colorScheme.primary : Colors.black12,
                                    width: n == r.page ? 2 : 1,
                                  ),
                                ),
                                child: ExcludeSemantics(child: widget.surface.thumbnail(ctx, p, n)),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    r.pageCount == 0 ? 'Opening…' : 'Page ${r.page} of ${r.pageCount}',
                    key: const Key('pdf-page-label'),
                  ),
                ),
              ],
            ),
      bottomNavigationBar: ResultBar(onShare: _share, onSave: _save, onUndo: _undo),
    );
  }
}
