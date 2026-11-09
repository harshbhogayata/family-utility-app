import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../app/theme.dart';
import '../../app/widgets/result_bar.dart';
import '../../engines/convert/pdf_to_word.dart' show PdfTextPiece, PdfTextSource;
import '../../engines/pdf/pdf_text_search.dart';
import '../../engines/platform/action_history.dart' show baseName;
import '../../engines/platform/file_manager.dart';
import '../../engines/share/share_engine.dart';
import '../../platform/pdfrx_text_source.dart';
import '../pdf_viewer/pdf_viewer_screen.dart' show PdfChooser, SystemPdfChooser;

/// Reads a file's bytes. Behind a typedef for tests.
typedef PdfBytesReader = Future<Uint8List> Function(String path);

Future<Uint8List> readPdfBytes(String path) => File(path).readAsBytes();

/// Writes the hit list somewhere the person keeps (the Save action).
typedef PdfSearchSaver = Future<String> Function(String text);

Future<String> savePdfSearchToAppFolder(String text) async {
  final Directory base = await getApplicationDocumentsDirectory();
  final File f = File('${base.path}/pdf-search-results.txt');
  await f.writeAsString(text, flush: true);
  return f.path;
}

/// Every PDF under the file manager's roots, for the library indexer.
Future<List<PdfOnDisk>> listPdfsInFileRoots({FileManager? files, int maxFiles = 5000}) async {
  final FileManager fm = files ?? FileManager.instance;
  final List<PdfOnDisk> out = <PdfOnDisk>[];
  final Set<String> seen = <String>{};
  for (final FileRoot root in fm.roots) {
    final List<String> todo = <String>[root.path];
    while (todo.isNotEmpty && out.length < maxFiles) {
      final String dir = todo.removeAt(0);
      final List<FileNode> nodes;
      try {
        nodes = await fm.source.list(dir);
      } catch (_) {
        continue;
      }
      for (final FileNode n in nodes) {
        if (n.isDir) {
          if (!n.name.startsWith('.')) {
            todo.add(n.path);
          }
        } else if (n.extension == 'pdf' && seen.add(n.path)) {
          out.add(PdfOnDisk(n.path, n.modified.millisecondsSinceEpoch));
        }
      }
    }
  }
  return out;
}

enum PdfSearchScope { file, library }

/// Feature 016 — Search inside PDFs: one file, or every saved PDF.
class PdfSearchScreen extends StatefulWidget {
  const PdfSearchScreen({
    super.key,
    this.path,
    this.chooser = const SystemPdfChooser(),
    this.readBytes = readPdfBytes,
    this.textSource = const PdfrxTextSource(),
    this.index,
    this.indexer,
    this.saver = savePdfSearchToAppFolder,
    this.share,
    this.initialScope = PdfSearchScope.file,
  });

  final String? path;
  final PdfChooser chooser;
  final PdfBytesReader readBytes;
  final PdfTextSource textSource;
  final PdfLibraryIndex? index;
  final PdfLibraryIndexer? indexer;
  final PdfSearchSaver saver;
  final ShareEngine? share;
  final PdfSearchScope initialScope;

  @override
  State<PdfSearchScreen> createState() => _PdfSearchScreenState();
}

class _PdfSearchScreenState extends State<PdfSearchScreen> {
  final TextEditingController _box = TextEditingController();
  final List<String> _past = <String>[];
  late PdfSearchScope _scope = widget.initialScope;

  String? _path;
  PdfFileSearch? _file;
  bool _opening = false;
  List<PdfHit> _hits = const <PdfHit>[];
  PdfHit? _selected;

  LibraryOutcome? _library;
  bool _indexing = false;
  String? _indexStatus;
  String _lastQuery = '';

  PdfLibraryIndex get _index => widget.index ?? PdfLibraryIndex.instance;

  late final PdfLibraryIndexer _indexer = widget.indexer ??
      PdfLibraryIndexer(
        index: _index,
        list: listPdfsInFileRoots,
        pageTexts: (String p) async => pageTextsOf(await widget.textSource.read(await widget.readBytes(p))),
      );

  @override
  void initState() {
    super.initState();
    final String? p = widget.path;
    if (p != null) {
      _open(p);
    }
  }

  @override
  void dispose() {
    _box.dispose();
    super.dispose();
  }

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
      await _open(p);
    }
  }

  Future<void> _open(String p) async {
    setState(() {
      _opening = true;
      _path = p;
      _file = null;
      _hits = const <PdfHit>[];
      _selected = null;
    });
    try {
      final List<List<PdfTextPiece>> pieces = await widget.textSource.read(await widget.readBytes(p));
      final PdfFileSearch f = PdfFileSearch(<PdfPageText>[
        for (int i = 0; i < pieces.length; i++) PdfPageText(i + 1, pieces[i]),
      ]);
      // Opening a file also keeps the library index current for it.
      if (f.hasText) {
        _index.put(IndexedPdf(path: p, pages: <String>[for (final PdfPageText t in f.pages) t.text]));
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _file = f;
        _opening = false;
      });
      if (!f.hasText) {
        _toast('No text in this PDF. Scan it with the document scanner to read the words.');
      }
      _run(_box.text, remember: false);
    } catch (_) {
      if (mounted) {
        setState(() => _opening = false);
        _toast('Could not read this PDF');
      }
    }
  }

  void _run(String q, {bool remember = true}) {
    if (remember) {
      if (_lastQuery.trim().isNotEmpty && _lastQuery != q) {
        _past.add(_lastQuery);
      }
      _lastQuery = q;
    }
    setState(() {
      if (_scope == PdfSearchScope.file) {
        final PdfFileSearch? f = _file;
        _hits = f == null ? const <PdfHit>[] : f.find(q);
        _selected = _hits.isEmpty ? null : _hits.first;
      } else {
        _library = q.trim().isEmpty ? null : _index.search(q);
      }
    });
  }

  Future<void> _refreshIndex() async {
    setState(() {
      _indexing = true;
      _indexStatus = 'Reading PDFs on this phone…';
    });
    try {
      final int n = await _indexer.refresh(progress: (int done, int total) {
        if (mounted) {
          setState(() => _indexStatus = 'Reading $done of $total…');
        }
      });
      if (!mounted) {
        return;
      }
      setState(() {
        _indexing = false;
        _indexStatus = n == 0 ? 'Index is up to date' : 'Read $n ${n == 1 ? 'file' : 'files'}';
      });
      _run(_box.text, remember: false);
    } catch (_) {
      if (mounted) {
        setState(() {
          _indexing = false;
          _indexStatus = 'Could not update the index';
        });
      }
    }
  }

  void _setScope(PdfSearchScope s) {
    setState(() => _scope = s);
    _run(_box.text, remember: false);
  }

  String? _resultText() {
    final String q = _box.text.trim();
    if (q.isEmpty) {
      return null;
    }
    if (_scope == PdfSearchScope.file) {
      final String? p = _path;
      if (p == null || _hits.isEmpty) {
        return null;
      }
      return PdfFileSearch.asText(baseName(p), q, _hits);
    }
    final LibraryOutcome? o = _library;
    return o == null || o.hits.isEmpty ? null : o.asText();
  }

  Future<void> _share() async {
    final String? t = _resultText();
    if (t == null) {
      _toast('Nothing to share yet');
      return;
    }
    await (widget.share ?? ShareEngine.instance).shareText(t, subject: 'Search: ${_box.text.trim()}');
  }

  Future<void> _save() async {
    final String? t = _resultText();
    if (t == null) {
      _toast('Nothing to save yet');
      return;
    }
    final String where = await widget.saver(t);
    _toast('Saved ${baseName(where)}');
  }

  void _undo() {
    if (_past.isEmpty) {
      if (_box.text.isEmpty) {
        Navigator.of(context).maybePop();
        return;
      }
      _box.clear();
      _lastQuery = '';
      _run('', remember: false);
      return;
    }
    final String q = _past.removeLast();
    _lastQuery = q;
    _box.value = TextEditingValue(text: q, selection: TextSelection.collapsed(offset: q.length));
    _run(q, remember: false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Search inside PDFs')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: SegmentedButton<PdfSearchScope>(
              key: const Key('pdf-search-scope'),
              segments: const <ButtonSegment<PdfSearchScope>>[
                ButtonSegment<PdfSearchScope>(
                  value: PdfSearchScope.file,
                  label: Text('This PDF'),
                  icon: Icon(Icons.description_outlined),
                ),
                ButtonSegment<PdfSearchScope>(
                  value: PdfSearchScope.library,
                  label: Text('All PDFs'),
                  icon: Icon(Icons.library_books_outlined),
                ),
              ],
              selected: <PdfSearchScope>{_scope},
              onSelectionChanged: (Set<PdfSearchScope> s) => _setScope(s.first),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              key: const Key('pdf-search-box'),
              controller: _box,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                labelText: _scope == PdfSearchScope.file ? 'Find in this PDF' : 'Find in every saved PDF',
                prefixIcon: const Icon(Icons.search),
              ),
              onSubmitted: (String q) => _run(q),
              onChanged: (String q) => _run(q, remember: false),
            ),
          ),
          Expanded(child: _scope == PdfSearchScope.file ? _fileBody(context) : _libraryBody(context)),
        ],
      ),
      bottomNavigationBar: ResultBar(onShare: _share, onSave: _save, onUndo: _undo),
    );
  }

  Widget _fileBody(BuildContext context) {
    final String? p = _path;
    final PdfFileSearch? f = _file;
    if (p == null) {
      return Center(
        child: FilledButton.icon(
          key: const Key('pdf-search-open'),
          onPressed: _pick,
          icon: const Icon(Icons.picture_as_pdf_outlined),
          label: const Text('Open a PDF'),
        ),
      );
    }
    if (_opening || f == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final TextTheme text = Theme.of(context).textTheme;
    final List<int> pages = PdfFileSearch.pagesWithHits(_hits);
    final PdfHit? sel = _selected;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  _box.text.trim().isEmpty
                      ? '${baseName(p)} · ${f.pageCount} ${f.pageCount == 1 ? 'page' : 'pages'}'
                      : '${_hits.length} ${_hits.length == 1 ? 'hit' : 'hits'} on ${pages.length} '
                          '${pages.length == 1 ? 'page' : 'pages'}',
                  key: const Key('pdf-search-count'),
                  style: text.bodyMedium,
                ),
              ),
              TextButton(
                key: const Key('pdf-search-change'),
                onPressed: _pick,
                child: const Text('Other PDF'),
              ),
            ],
          ),
        ),
        if (sel != null) _pagePanel(context, f, sel),
        Expanded(
          child: ListView.builder(
            key: const Key('pdf-search-hits'),
            itemCount: _hits.length,
            itemBuilder: (BuildContext ctx, int i) {
              final PdfHit h = _hits[i];
              return Semantics(
                button: true,
                selected: identical(h, sel),
                label: 'Page ${h.page}: ${h.snippet}',
                excludeSemantics: true,
                child: ListTile(
                  key: ValueKey<String>('pdf-hit-$i'),
                  minTileHeight: 48,
                  selected: identical(h, sel),
                  leading: CircleAvatar(radius: 18, child: Text('${h.page}')),
                  title: Text.rich(
                    highlighted(h.snippet, <(int, int)>[(h.snippetStart, h.snippetEnd)], text.bodyMedium),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => setState(() => _selected = h),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// The selected hit's page text with every match on it highlighted.
  Widget _pagePanel(BuildContext context, PdfFileSearch f, PdfHit sel) {
    final PdfPageText page = f.pages[sel.page - 1];
    final List<(int, int)> ranges = <(int, int)>[
      for (final PdfHit h in _hits)
        if (h.page == sel.page) (h.start, h.end),
    ];
    return Container(
      key: const Key('pdf-search-page'),
      constraints: const BoxConstraints(maxHeight: 180),
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(12),
      ),
      child: SingleChildScrollView(
        child: Semantics(
          label: 'Page ${sel.page} text, ${ranges.length} ${ranges.length == 1 ? 'match' : 'matches'} highlighted',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('Page ${sel.page}', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              Text.rich(highlighted(page.text, ranges, Theme.of(context).textTheme.bodySmall)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _libraryBody(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final LibraryOutcome? o = _library;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  o == null
                      ? (_indexStatus ?? '${_index.fileCount} ${_index.fileCount == 1 ? 'file' : 'files'} indexed')
                      : '${o.hits.length} of ${o.filesSearched} files · ${o.elapsed.inMilliseconds} ms',
                  key: const Key('pdf-library-status'),
                  style: text.bodyMedium,
                ),
              ),
              TextButton.icon(
                key: const Key('pdf-library-refresh'),
                onPressed: _indexing ? null : _refreshIndex,
                icon: _indexing
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.refresh),
                label: const Text('Update index'),
              ),
            ],
          ),
        ),
        Expanded(
          child: o == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Type a word to search every PDF and scan on this phone. '
                      'The text is read and searched here; nothing is uploaded.',
                      textAlign: TextAlign.center,
                      style: text.bodyMedium?.copyWith(color: AppColors.muted),
                    ),
                  ),
                )
              : ListView.builder(
                  key: const Key('pdf-library-hits'),
                  itemCount: o.hits.length,
                  itemBuilder: (BuildContext ctx, int i) {
                    final LibraryHit h = o.hits[i];
                    final String where = h.ocr
                        ? 'Scanned text'
                        : (h.pages.length == 1 ? 'Page ${h.pages.first}' : 'Pages ${_pageList(h.pages)}');
                    return Semantics(
                      button: true,
                      label: '${h.name}, $where: ${h.snippet}',
                      excludeSemantics: true,
                      child: ListTile(
                        key: ValueKey<String>('pdf-library-hit-$i'),
                        minTileHeight: 48,
                        leading: Icon(h.ocr ? Icons.document_scanner_outlined : Icons.picture_as_pdf_outlined),
                        title: Text(h.name, overflow: TextOverflow.ellipsis),
                        subtitle: Text.rich(
                          TextSpan(children: <InlineSpan>[
                            TextSpan(text: '$where · '),
                            highlighted(h.snippet, <(int, int)>[(h.snippetStart, h.snippetEnd)], null),
                          ]),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: h.ocr || !h.path.toLowerCase().endsWith('.pdf') ? null : () => _openFromLibrary(h.path),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Future<void> _openFromLibrary(String path) async {
    setState(() => _scope = PdfSearchScope.file);
    await _open(path);
  }

  static String _pageList(List<int> pages) {
    if (pages.length <= 6) {
      return pages.join(', ');
    }
    return '${pages.take(5).join(', ')} +${pages.length - 5}';
  }
}

/// [text] with [ranges] drawn as highlights (marker colour, bold).
TextSpan highlighted(String text, List<(int, int)> ranges, TextStyle? base) {
  final List<(int, int)> sorted = ranges.where(((int, int) r) => r.$1 >= 0 && r.$2 <= text.length && r.$2 > r.$1).toList()
    ..sort(((int, int) a, (int, int) b) => a.$1.compareTo(b.$1));
  final List<InlineSpan> spans = <InlineSpan>[];
  int at = 0;
  for (final (int s, int e) in sorted) {
    if (s < at) {
      continue;
    }
    if (s > at) {
      spans.add(TextSpan(text: text.substring(at, s)));
    }
    spans.add(TextSpan(
      text: text.substring(s, e),
      style: const TextStyle(backgroundColor: Color(0xFFFFE58A), fontWeight: FontWeight.w700, color: AppColors.ink),
    ));
    at = e;
  }
  if (at < text.length) {
    spans.add(TextSpan(text: text.substring(at)));
  }
  return TextSpan(style: base, children: spans);
}
