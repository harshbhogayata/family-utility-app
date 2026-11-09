import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/gestures.dart' show PointerDownEvent, PointerMoveEvent, PointerUpEvent;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../app/theme.dart';
import '../../app/widgets/result_bar.dart';
import '../../engines/convert/pdf_to_word.dart' show PdfTextPiece, PdfTextSource;
import '../../engines/pdf/pdf_redactor.dart';
import '../../engines/share/share_engine.dart';
import '../../platform/pdf_surface.dart';
import '../../platform/pdfrx_text_source.dart';

class RedactInput {
  const RedactInput(this.name, this.path, this.bytes);
  final String name;
  final String path;
  final Uint8List bytes;
}

/// Picks the PDF and keeps the redacted copy. Behind an interface for tests.
abstract class RedactPdfFiles {
  Future<RedactInput?> pick();
  Future<String> write(String name, Uint8List bytes);
  Future<void> remove(String path);
}

class SystemRedactPdfFiles implements RedactPdfFiles {
  const SystemRedactPdfFiles();

  @override
  Future<RedactInput?> pick() async {
    final FilePickerResult? r = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: <String>['pdf'],
    );
    final List<PlatformFile> files = r?.files ?? const <PlatformFile>[];
    final String? p = files.isEmpty ? null : files.first.path;
    if (p == null) {
      return null;
    }
    return RedactInput(files.first.name, p, await File(p).readAsBytes());
  }

  @override
  Future<String> write(String name, Uint8List bytes) async {
    final Directory base = await getApplicationDocumentsDirectory();
    final Directory dir = Directory('${base.path}/redacted');
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

/// Everything a redaction needs, sendable to an isolate.
class RedactJob {
  const RedactJob(this.bytes, this.boxes, this.words);
  final Uint8List bytes;
  final List<RedactBox> boxes;
  final List<String> words;
}

class RedactOutcome {
  const RedactOutcome(this.result, this.check);
  final PdfRedactResult result;
  final RedactCheck check;
}

RedactOutcome _redact(RedactJob job) {
  final PdfRedactResult r = PdfRedactor.redact(job.bytes, job.boxes);
  return RedactOutcome(r, PdfRedactor.verify(r.bytes, job.boxes, words: job.words));
}

typedef RedactRunner = Future<RedactOutcome> Function(RedactJob job);

Future<RedactOutcome> redactInIsolate(RedactJob job) => compute(_redact, job);

typedef RedactPageView = Widget Function(BuildContext context, String path, int pageNumber);

Widget _pdfrxPage(BuildContext context, String path, int pageNumber) =>
    const PdfrxSurface().thumbnail(context, path, pageNumber);

/// Boxes around every place [query] appears inside the text pieces of a
/// page, cut to the letters of the match where a piece holds more words.
List<RedactBox> boxesForQuery(List<List<PdfTextPiece>> pages, List<RedactPageBox> sizes, String query) {
  final String q = query.trim();
  if (q.isEmpty) {
    return const <RedactBox>[];
  }
  final RegExp pattern =
      RegExp(q.split(RegExp(r'\s+')).map(RegExp.escape).join(r'\s+'), caseSensitive: false);
  final List<RedactBox> out = <RedactBox>[];
  for (int p = 0; p < pages.length && p < sizes.length; p++) {
    for (final PdfTextPiece piece in pages[p]) {
      final int len = piece.text.length;
      if (len == 0) {
        continue;
      }
      for (final RegExpMatch m in pattern.allMatches(piece.text)) {
        final double span = piece.right - piece.left;
        out.add(sizes[p].boxFor(
          p,
          piece.left + span * m.start / len,
          piece.bottom,
          piece.left + span * m.end / len,
          piece.top,
        ));
      }
    }
  }
  return out;
}

/// Feature 013 — Redact.
class RedactPdfScreen extends StatefulWidget {
  const RedactPdfScreen({
    super.key,
    this.files = const SystemRedactPdfFiles(),
    this.runner = redactInIsolate,
    this.textSource = const PdfrxTextSource(),
    this.pageView = _pdfrxPage,
    this.share,
  });

  final RedactPdfFiles files;
  final RedactRunner runner;
  final PdfTextSource textSource;
  final RedactPageView pageView;
  final ShareEngine? share;

  @override
  State<RedactPdfScreen> createState() => _RedactPdfScreenState();
}

class _RedactPdfScreenState extends State<RedactPdfScreen> {
  final TextEditingController _query = TextEditingController();
  RedactInput? _input;
  List<RedactPageBox> _sizes = const <RedactPageBox>[];
  List<List<PdfTextPiece>>? _text;
  final List<RedactBox> _boxes = <RedactBox>[];
  final List<String> _words = <String>[];
  int _page = 0;
  Offset? _dragStart;
  Rect? _drag;
  bool _working = false;
  String? _saved;
  String? _status;
  bool _failed = false;

  @override
  void dispose() {
    _query.dispose();
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
    final RedactInput? p = await widget.files.pick();
    if (!mounted || p == null) {
      return;
    }
    try {
      final List<RedactPageBox> sizes = PdfRedactor.pageBoxes(p.bytes);
      setState(() {
        _input = p;
        _sizes = sizes;
        _text = null;
        _boxes.clear();
        _words.clear();
        _page = 0;
        _saved = null;
        _failed = false;
        _status = 'Drag over the page to mark an area, or find words to black out.';
      });
    } on RedactError catch (e) {
      setState(() {
        _failed = true;
        _status = e.message;
      });
    }
  }

  Future<void> _find() async {
    final RedactInput? input = _input;
    final String q = _query.text.trim();
    if (input == null || q.isEmpty) {
      return;
    }
    final List<List<PdfTextPiece>> text = _text ?? await widget.textSource.read(input.bytes);
    _text = text;
    final List<RedactBox> found = boxesForQuery(text, _sizes, q);
    if (!mounted) {
      return;
    }
    setState(() {
      if (found.isEmpty) {
        _status = 'No "$q" in this PDF. Mark it by hand if it is part of a picture.';
      } else {
        _boxes.addAll(found);
        if (!_words.contains(q)) {
          _words.add(q);
        }
        final int pages = found.map((RedactBox b) => b.page).toSet().length;
        _status = 'Marked "$q" ${found.length} ${found.length == 1 ? 'time' : 'times'} on '
            '$pages ${pages == 1 ? 'page' : 'pages'}.';
        _page = found.first.page;
      }
      _query.clear();
    });
  }

  Future<void> _run() async {
    final RedactInput? input = _input;
    if (input == null || _boxes.isEmpty || _working) {
      return;
    }
    setState(() => _working = true);
    try {
      final RedactOutcome out = await widget.runner(RedactJob(input.bytes, List<RedactBox>.of(_boxes), List<String>.of(_words)));
      if (!out.check.passed) {
        setState(() {
          _failed = true;
          _status = 'The check found text still under a box, so nothing was saved. '
              'Try a larger box, or turn the page into an image first.';
        });
        return;
      }
      final String stem = input.name.toLowerCase().endsWith('.pdf') ? input.name.substring(0, input.name.length - 4) : input.name;
      final String path = await widget.files.write('$stem redacted.pdf', out.result.bytes);
      final PdfRedactResult r = out.result;
      final String searched = _words.isEmpty ? '' : ' Searching for ${_words.map((String w) => '"$w"').join(', ')} finds nothing.';
      setState(() {
        _saved = path;
        _failed = false;
        _status = 'Blacked out ${_boxes.length} ${_boxes.length == 1 ? 'area' : 'areas'}: removed '
            '${r.glyphsRemoved} ${r.glyphsRemoved == 1 ? 'letter' : 'letters'}, '
            '${r.imagesChanged} ${r.imagesChanged == 1 ? 'picture' : 'pictures'} and '
            '${r.annotationsRemoved} ${r.annotationsRemoved == 1 ? 'note' : 'notes'}. '
            'Checked: no text is left under the boxes.$searched';
      });
    } on RedactError catch (e) {
      setState(() {
        _failed = true;
        _status = e.message;
      });
    } finally {
      if (mounted) {
        setState(() => _working = false);
      }
    }
  }

  Future<void> _share() async {
    final String? p = _saved;
    if (p == null) {
      _toast('Redact a PDF first');
      return;
    }
    await (widget.share ?? ShareEngine.instance).shareFiles(<String>[p]);
  }

  void _save() => _toast(_saved == null ? 'Nothing to save yet' : 'Saved in Files › redacted');

  Future<void> _undo() async {
    final String? p = _saved;
    if (p != null) {
      await widget.files.remove(p);
      setState(() {
        _saved = null;
        _status = 'Removed the redacted copy. Your boxes are still marked.';
      });
      return;
    }
    if (_boxes.isNotEmpty) {
      setState(() {
        _boxes.removeLast();
        _status = 'Removed the last box.';
      });
      return;
    }
    if (mounted) {
      await Navigator.of(context).maybePop();
    }
  }

  void _down(PointerDownEvent e, Size size) {
    _dragStart = Offset(e.localPosition.dx / size.width, e.localPosition.dy / size.height);
  }

  void _move(PointerMoveEvent e, Size size) {
    final Offset? s = _dragStart;
    if (s == null) {
      return;
    }
    final Offset now = Offset(
      (e.localPosition.dx / size.width).clamp(0.0, 1.0).toDouble(),
      (e.localPosition.dy / size.height).clamp(0.0, 1.0).toDouble(),
    );
    setState(() => _drag = Rect.fromPoints(s, now));
  }

  void _up(PointerUpEvent e) {
    final Rect? r = _drag;
    _dragStart = null;
    _drag = null;
    if (r == null) {
      setState(() {});
      return;
    }
    final RedactBox box = RedactBox(page: _page, left: r.left, top: r.top, width: r.width, height: r.height);
    setState(() {
      if (box.isUsable) {
        _boxes.add(box);
        _saved = null;
      }
    });
  }

  /// Adds a box from outside the gesture (tests, screen readers).
  void _addCentreBox() {
    setState(() => _boxes.add(RedactBox(page: _page, left: 0.25, top: 0.4, width: 0.5, height: 0.1)));
  }

  Widget _canvas(BuildContext context) {
    final RedactPageBox size = _sizes[_page];
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 520),
      child: Center(
        child: AspectRatio(
          aspectRatio: size.width / size.height,
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints c) {
              final Size s = Size(c.maxWidth, c.maxHeight);
              final Rect? drag = _drag;
              return Semantics(
                label: 'Page ${_page + 1}. Drag to mark an area to black out.',
                child: Listener(
                  key: const Key('redact-pdf-canvas'),
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: (PointerDownEvent e) => _down(e, s),
                  onPointerMove: (PointerMoveEvent e) => _move(e, s),
                  onPointerUp: _up,
                  child: Stack(
                    children: <Widget>[
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(color: Colors.white, border: Border.all(color: AppColors.line)),
                          child: widget.pageView(context, _input!.path, _page + 1),
                        ),
                      ),
                      for (final RedactBox b in _boxes)
                        if (b.page == _page)
                          Positioned(
                            left: b.left * s.width,
                            top: b.top * s.height,
                            width: b.width * s.width,
                            height: b.height * s.height,
                            child: const ColoredBox(color: Colors.black87),
                          ),
                      if (drag != null)
                        Positioned(
                          left: drag.left * s.width,
                          top: drag.top * s.height,
                          width: drag.width * s.width,
                          height: drag.height * s.height,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: Colors.black38,
                              border: Border.all(color: Colors.black),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final RedactInput? input = _input;
    final int onPage = _boxes.where((RedactBox b) => b.page == _page).length;
    return Scaffold(
      appBar: AppBar(title: const Text('Redact PDF')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          OutlinedButton.icon(
            key: const Key('redact-pdf-pick'),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: _working ? null : _pick,
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: Text(input == null ? 'Choose a PDF' : input.name),
          ),
          if (input != null) ...<Widget>[
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    key: const Key('redact-pdf-query'),
                    controller: _query,
                    onSubmitted: (_) => _find(),
                    decoration: const InputDecoration(
                      labelText: 'Words to black out',
                      helperText: 'A name, an account or Aadhaar number…',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 56,
                  child: FilledButton.tonal(
                    key: const Key('redact-pdf-find'),
                    onPressed: _working ? null : _find,
                    child: const Text('Find'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                IconButton(
                  key: const Key('redact-pdf-prev'),
                  tooltip: 'Previous page',
                  onPressed: _page > 0 ? () => setState(() => _page--) : null,
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: Text(
                    'Page ${_page + 1} of ${_sizes.length} · $onPage ${onPage == 1 ? 'box' : 'boxes'}',
                    textAlign: TextAlign.center,
                  ),
                ),
                IconButton(
                  key: const Key('redact-pdf-next'),
                  tooltip: 'Next page',
                  onPressed: _page < _sizes.length - 1 ? () => setState(() => _page++) : null,
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
            _canvas(context),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton.icon(
                    key: const Key('redact-pdf-add-box'),
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                    onPressed: _addCentreBox,
                    icon: const Icon(Icons.crop_square),
                    label: const Text('Add a box'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    key: const Key('redact-pdf-clear'),
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                    onPressed: onPage == 0 ? null : () => setState(() => _boxes.removeWhere((RedactBox b) => b.page == _page)),
                    icon: const Icon(Icons.layers_clear_outlined),
                    label: const Text('Clear page'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const Key('redact-pdf-run'),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              onPressed: _boxes.isEmpty || _working ? null : _run,
              icon: const Icon(Icons.format_color_fill),
              label: Text(_working
                  ? 'Removing…'
                  : (_boxes.isEmpty ? 'Mark something first' : 'Black out ${_boxes.length} for good')),
            ),
          ],
          if (_status != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Semantics(
                liveRegion: true,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    if (_saved != null)
                      const Padding(
                        padding: EdgeInsets.only(right: 8),
                        child: Icon(Icons.verified_outlined, semanticLabel: 'Checked'),
                      ),
                    Expanded(
                      child: Text(
                        _status!,
                        key: const Key('redact-pdf-status'),
                        style: _failed ? TextStyle(color: scheme.error) : null,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 12),
          const Text('The text and pictures under each box are deleted from the file, not just covered, '
              'and the copy is checked before it is saved. Everything happens on this phone; '
              'your original is not changed.'),
        ],
      ),
      bottomNavigationBar: ResultBar(onShare: _share, onSave: _save, onUndo: _undo),
    );
  }
}
