import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../convert/pdf_to_word.dart' show PdfTextPiece;
import '../platform/action_history.dart' show baseName;
import '../platform/one_search.dart';

/// Feature 016 — Search inside PDFs.
///
/// Two halves, both plain Dart and offline:
/// * [PdfFileSearch]: find a word or phrase in one file's page text, with a
///   hit list, snippets and the ranges to highlight.
/// * [PdfLibraryIndex]: an inverted index over the text of every saved PDF
///   (and text read out of scans by on-device OCR), queried in milliseconds.
/// Reading the text out of a PDF is the job of a [PdfTextSource] (PDFium on
/// the phone). Nothing is uploaded.

/// One page's text, built from its positioned pieces so a hit can be mapped
/// back to the boxes on the page.
@immutable
class PdfPageText {
  PdfPageText(this.page, List<PdfTextPiece> pieces) : pieces = List<PdfTextPiece>.unmodifiable(pieces) {
    final StringBuffer b = StringBuffer();
    final List<int> starts = <int>[];
    for (int i = 0; i < pieces.length; i++) {
      if (i > 0) {
        b.write(' ');
      }
      starts.add(b.length);
      b.write(pieces[i].text);
    }
    text = b.toString();
    _starts = starts;
  }

  /// A page with text but no positions (an OCR'd scan, a test).
  PdfPageText.plain(this.page, String value) : pieces = const <PdfTextPiece>[] {
    text = value;
    _starts = const <int>[];
  }

  /// 1-based page number.
  final int page;
  final List<PdfTextPiece> pieces;
  late final String text;
  late final List<int> _starts;

  /// The pieces a range of [text] touches: the boxes to highlight on the page.
  List<PdfTextPiece> boxesFor(int start, int end) {
    final List<PdfTextPiece> out = <PdfTextPiece>[];
    for (int i = 0; i < pieces.length; i++) {
      final int s = _starts[i];
      final int e = s + pieces[i].text.length;
      if (s < end && e > start) {
        out.add(pieces[i]);
      }
    }
    return out;
  }
}

/// One place the query was found.
@immutable
class PdfHit {
  const PdfHit({
    required this.page,
    required this.start,
    required this.end,
    required this.snippet,
    required this.snippetStart,
    required this.snippetEnd,
    this.boxes = const <PdfTextPiece>[],
  });

  final int page;

  /// The match in the page text.
  final int start;
  final int end;

  /// The words around the match, and where the match sits inside it.
  final String snippet;
  final int snippetStart;
  final int snippetEnd;

  /// The text pieces on the page to highlight.
  final List<PdfTextPiece> boxes;
}

/// The query as a pattern: case-insensitive, any run of spaces in the query
/// matches any run of white space (lines break mid-phrase in PDFs).
RegExp? queryPattern(String query) {
  final List<String> parts = query.trim().split(RegExp(r'\s+')).where((String s) => s.isNotEmpty).toList();
  if (parts.isEmpty) {
    return null;
  }
  return RegExp(parts.map(RegExp.escape).join(r'\s+'), caseSensitive: false);
}

/// Every match of [pattern] in [text], as (start, end) pairs.
List<(int, int)> matchRanges(String text, RegExp? pattern) {
  if (pattern == null) {
    return const <(int, int)>[];
  }
  return <(int, int)>[
    for (final RegExpMatch m in pattern.allMatches(text))
      if (m.end > m.start) (m.start, m.end),
  ];
}

(String, int, int) snippetAround(String text, int start, int end, {int before = 40, int after = 60}) {
  int from = start - before < 0 ? 0 : start - before;
  int to = end + after > text.length ? text.length : end + after;
  // Start and end on word boundaries where there is one nearby.
  if (from > 0) {
    final int sp = text.indexOf(' ', from);
    if (sp >= 0 && sp < start) {
      from = sp + 1;
    }
  }
  if (to < text.length) {
    final int sp = text.lastIndexOf(' ', to);
    if (sp > end) {
      to = sp;
    }
  }
  final String lead = from > 0 ? '…' : '';
  final String tail = to < text.length ? '…' : '';
  final String raw = text.substring(from, to).replaceAll('\n', ' ');
  return ('$lead$raw$tail', lead.length + start - from, lead.length + end - from);
}

/// Search in one open file.
class PdfFileSearch {
  PdfFileSearch(List<PdfPageText> pages) : pages = List<PdfPageText>.unmodifiable(pages);

  final List<PdfPageText> pages;

  int get pageCount => pages.length;

  bool get hasText => pages.any((PdfPageText p) => p.text.trim().isNotEmpty);

  /// Every hit, in page order then position.
  List<PdfHit> find(String query, {int limit = 1000}) {
    final RegExp? pattern = queryPattern(query);
    final List<PdfHit> out = <PdfHit>[];
    for (final PdfPageText p in pages) {
      for (final (int s, int e) in matchRanges(p.text, pattern)) {
        final (String snip, int ss, int se) = snippetAround(p.text, s, e);
        out.add(PdfHit(
          page: p.page,
          start: s,
          end: e,
          snippet: snip,
          snippetStart: ss,
          snippetEnd: se,
          boxes: p.boxesFor(s, e),
        ));
        if (out.length >= limit) {
          return out;
        }
      }
    }
    return out;
  }

  /// Pages with at least one hit, for the page strip.
  static List<int> pagesWithHits(List<PdfHit> hits) {
    final List<int> out = <int>[];
    for (final PdfHit h in hits) {
      if (out.isEmpty || out.last != h.page) {
        out.add(h.page);
      }
    }
    return out;
  }

  /// Plain text of a hit list, for Share and Save.
  static String asText(String fileName, String query, List<PdfHit> hits) {
    final StringBuffer b = StringBuffer('"$query" in $fileName: ${hits.length} ${hits.length == 1 ? 'hit' : 'hits'}\n');
    for (final PdfHit h in hits) {
      b.writeln('- Page ${h.page}: ${h.snippet}');
    }
    return b.toString();
  }
}

/// One file in the library index.
@immutable
class IndexedPdf {
  const IndexedPdf({required this.path, required this.pages, this.modified = 0, this.ocr = false});

  final String path;

  /// Page texts, index 0 is page 1.
  final List<String> pages;

  /// Last-modified time (ms) when the text was read, to skip unchanged files.
  final int modified;

  /// The text came from on-device OCR of a scan.
  final bool ocr;

  Map<String, Object?> toJson() => <String, Object?>{'m': modified, 'o': ocr, 'p': pages};

  static IndexedPdf fromJson(String path, Map<String, Object?> j) => IndexedPdf(
        path: path,
        modified: (j['m'] as num?)?.toInt() ?? 0,
        ocr: j['o'] == true,
        pages: <String>[for (final Object? p in (j['p'] as List<Object?>? ?? const <Object?>[])) p is String ? p : ''],
      );
}

/// A file that matched a library search.
@immutable
class LibraryHit {
  const LibraryHit({
    required this.path,
    required this.pages,
    required this.score,
    required this.snippet,
    required this.snippetStart,
    required this.snippetEnd,
    required this.ocr,
  });

  final String path;

  /// Pages (1-based) where a query word appears.
  final List<int> pages;
  final double score;
  final String snippet;
  final int snippetStart;
  final int snippetEnd;
  final bool ocr;

  String get name => baseName(path);
}

/// The answer to one library query, with how long it took.
@immutable
class LibraryOutcome {
  const LibraryOutcome(this.query, this.hits, this.elapsed, this.filesSearched);

  final String query;
  final List<LibraryHit> hits;
  final Duration elapsed;
  final int filesSearched;

  String asText() {
    final StringBuffer b = StringBuffer('"$query" in ${hits.length} of $filesSearched files\n');
    for (final LibraryHit h in hits) {
      b.writeln('- ${h.name} (page ${h.pages.join(', ')}): ${h.snippet}');
    }
    return b.toString();
  }
}

/// Where the library index is kept between launches.
abstract class PdfIndexBackend {
  Future<String?> read();

  Future<void> write(String json);
}

class MemoryPdfIndexBackend implements PdfIndexBackend {
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String json) async => value = json;
}

class FilePdfIndexBackend implements PdfIndexBackend {
  FilePdfIndexBackend(this.folder);

  final Future<Directory> Function() folder;

  Future<File> _file() async => File('${(await folder()).path}/pdf-text-index.json');

  @override
  Future<String?> read() async {
    final File f = await _file();
    return f.existsSync() ? f.readAsString() : null;
  }

  @override
  Future<void> write(String json) async {
    final File f = await _file();
    await f.parent.create(recursive: true);
    await f.writeAsString(json, flush: true);
  }
}

/// Text of every saved PDF and every OCR'd scan, with an inverted index:
/// word -> file -> pages. Every query word must match (as a word prefix)
/// somewhere in a file; an exact phrase on one page ranks first.
class PdfLibraryIndex extends ChangeNotifier implements SearchSource {
  PdfLibraryIndex(this.backend);

  final PdfIndexBackend backend;

  final Map<String, IndexedPdf> _files = <String, IndexedPdf>{};
  List<IndexedPdf>? _list;
  Map<String, Map<int, List<int>>>? _postings;
  List<String>? _terms;

  int get fileCount => _files.length;

  Iterable<String> get paths => _files.keys;

  IndexedPdf? operator [](String path) => _files[path];

  Future<void> load() async {
    try {
      final String? raw = await backend.read();
      if (raw != null && raw.isNotEmpty) {
        final Map<String, Object?> j = jsonDecode(raw) as Map<String, Object?>;
        _files.clear();
        j.forEach((String k, Object? v) {
          if (v is Map<String, Object?>) {
            _files[k] = IndexedPdf.fromJson(k, v);
          }
        });
      }
    } catch (_) {
      _files.clear();
    }
    _dirty();
  }

  /// Adds or replaces a file's text. Call [save] after a batch.
  void put(IndexedPdf file) {
    _files[file.path] = file;
    _dirty();
  }

  bool remove(String path) {
    final bool had = _files.remove(path) != null;
    if (had) {
      _dirty();
    }
    return had;
  }

  /// Mirrors the OCR text store: scans OCR'd on the phone become one-page
  /// entries, and entries for scans whose text was removed go.
  void syncOcr(Map<String, String> ocrText) {
    _files.removeWhere((String k, IndexedPdf v) => v.ocr && !ocrText.containsKey(k));
    ocrText.forEach((String path, String text) {
      final IndexedPdf? had = _files[path];
      // A PDF that has its own text keeps it; OCR fills scans with none.
      if (had != null && !had.ocr && had.pages.any((String p) => p.trim().isNotEmpty)) {
        return;
      }
      _files[path] = IndexedPdf(path: path, pages: <String>[text], ocr: true);
    });
    _dirty();
  }

  Future<void> save() async {
    try {
      await backend.write(jsonEncode(<String, Object?>{
        for (final IndexedPdf f in _files.values) f.path: f.toJson(),
      }));
    } catch (_) {
      // Kept in memory for this launch.
    }
  }

  void _dirty() {
    _list = null;
    _postings = null;
    _terms = null;
    notifyListeners();
  }

  void _build() {
    if (_postings != null) {
      return;
    }
    final List<IndexedPdf> list = _files.values.toList(growable: false);
    final Map<String, Map<int, List<int>>> postings = <String, Map<int, List<int>>>{};
    for (int d = 0; d < list.length; d++) {
      final List<String> pages = list[d].pages;
      for (int p = 0; p < pages.length; p++) {
        for (final String t in tokenize(pages[p]).toSet()) {
          ((postings[t] ??= <int, List<int>>{})[d] ??= <int>[]).add(p + 1);
        }
      }
    }
    _list = list;
    _postings = postings;
    _terms = postings.keys.toList()..sort();
  }

  /// Builds the word index now (otherwise the first query does).
  void warm() => _build();

  LibraryOutcome search(String query, {int limit = 100}) {
    final Stopwatch w = Stopwatch()..start();
    final List<String> words = tokenize(query);
    if (words.isEmpty) {
      return LibraryOutcome(query, const <LibraryHit>[], w.elapsed, _files.length);
    }
    _build();
    final List<IndexedPdf> list = _list!;
    final Map<String, Map<int, List<int>>> postings = _postings!;
    final List<String> terms = _terms!;

    Map<int, double>? scores;
    final Map<int, Set<int>> pagesOf = <int, Set<int>>{};
    for (final String word in words) {
      final Map<int, double> forWord = <int, double>{};
      int i = _lowerBound(terms, word);
      while (i < terms.length && terms[i].startsWith(word)) {
        final double weight = terms[i] == word ? 1 : 0.6;
        postings[terms[i]]!.forEach((int doc, List<int> pages) {
          final double s = weight + (pages.length > 5 ? 0.5 : pages.length * 0.1);
          final double? had = forWord[doc];
          if (had == null || had < s) {
            forWord[doc] = s;
          }
          (pagesOf[doc] ??= <int>{}).addAll(pages);
        });
        i++;
      }
      if (scores == null) {
        scores = forWord;
      } else {
        final Map<int, double> next = <int, double>{};
        scores.forEach((int doc, double s) {
          final double? add = forWord[doc];
          if (add != null) {
            next[doc] = s + add;
          }
        });
        scores = next;
      }
      if (scores.isEmpty) {
        break;
      }
    }

    final RegExp? phrase = queryPattern(query);
    final List<LibraryHit> hits = <LibraryHit>[];
    final List<MapEntry<int, double>> ranked = (scores ?? const <int, double>{}).entries.toList()
      ..sort((MapEntry<int, double> a, MapEntry<int, double> b) => b.value.compareTo(a.value));
    for (final MapEntry<int, double> e in ranked) {
      final IndexedPdf f = list[e.key];
      final List<int> pages = (pagesOf[e.key] ?? <int>{}).toList()..sort();
      double score = e.value;
      String snippet = '';
      int ss = 0;
      int se = 0;
      // The exact phrase on one of the pages ranks first and gives the snippet.
      for (final int p in pages) {
        final RegExpMatch? m = phrase?.firstMatch(f.pages[p - 1]);
        if (m != null) {
          score += 2;
          (snippet, ss, se) = snippetAround(f.pages[p - 1], m.start, m.end);
          break;
        }
      }
      if (snippet.isEmpty && pages.isNotEmpty) {
        final String text = f.pages[pages.first - 1];
        final int at = text.toLowerCase().indexOf(words.first);
        if (at >= 0) {
          (snippet, ss, se) = snippetAround(text, at, at + words.first.length);
        }
      }
      hits.add(LibraryHit(
        path: f.path,
        pages: pages,
        score: score,
        snippet: snippet,
        snippetStart: ss,
        snippetEnd: se,
        ocr: f.ocr,
      ));
    }
    hits.sort((LibraryHit a, LibraryHit b) {
      final int c = b.score.compareTo(a.score);
      return c != 0 ? c : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    w.stop();
    return LibraryOutcome(query, hits.take(limit).toList(growable: false), w.elapsed, _files.length);
  }

  static int _lowerBound(List<String> sorted, String value) {
    int lo = 0;
    int hi = sorted.length;
    while (lo < hi) {
      final int mid = (lo + hi) >> 1;
      if (sorted[mid].compareTo(value) < 0) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  /// One search: PDF text is found by its words. OCR'd scans already come
  /// from the OCR store, so only PDFs with their own text are handed over.
  @override
  Future<List<SearchDoc>> collect() async => <SearchDoc>[
        for (final IndexedPdf f in _files.values)
          if (!f.ocr)
            SearchDoc(
              kind: SearchKind.text,
              ref: f.path,
              title: baseName(f.path),
              subtitle: 'PDF text · ${f.pages.length} ${f.pages.length == 1 ? 'page' : 'pages'}',
              body: _capped(f.pages.join('\n')),
            ),
      ];

  static String _capped(String s) => s.length > 20000 ? s.substring(0, 20000) : s;

  static PdfLibraryIndex instance = PdfLibraryIndex(MemoryPdfIndexBackend());

  static void install(PdfLibraryIndex index) {
    instance = index;
  }
}

/// A PDF found on disk, as the indexer needs it.
@immutable
class PdfOnDisk {
  const PdfOnDisk(this.path, this.modified);

  final String path;
  final int modified;
}

/// Brings the library index up to date: reads the text of new and changed
/// PDFs, drops files that are gone. Text extraction runs on the phone.
class PdfLibraryIndexer {
  PdfLibraryIndexer({required this.index, required this.list, required this.pageTexts});

  final PdfLibraryIndex index;

  /// Every PDF the person keeps (the file manager's roots).
  final Future<List<PdfOnDisk>> Function() list;

  /// Each page's text for one file.
  final Future<List<String>> Function(String path) pageTexts;

  bool _running = false;

  bool get running => _running;

  /// Returns how many files were (re)read.
  Future<int> refresh({void Function(int done, int total)? progress}) async {
    if (_running) {
      return 0;
    }
    _running = true;
    int read = 0;
    try {
      final List<PdfOnDisk> found = await list();
      final Set<String> present = found.map((PdfOnDisk f) => f.path).toSet();
      for (final String p in index.paths.toList()) {
        final IndexedPdf? had = index[p];
        if (had != null && !had.ocr && !present.contains(p)) {
          index.remove(p);
        }
      }
      final List<PdfOnDisk> todo = found.where((PdfOnDisk f) {
        final IndexedPdf? had = index[f.path];
        return had == null || had.ocr || had.modified != f.modified;
      }).toList();
      for (int i = 0; i < todo.length; i++) {
        final PdfOnDisk f = todo[i];
        try {
          final List<String> pages = await pageTexts(f.path);
          final IndexedPdf? had = index[f.path];
          if (had != null && had.ocr && pages.every((String t) => t.trim().isEmpty)) {
            // A scan with no text layer keeps its OCR text.
          } else {
            index.put(IndexedPdf(path: f.path, pages: pages, modified: f.modified));
          }
          read++;
        } catch (_) {
          // Damaged or locked: skipped until it changes.
          index.put(IndexedPdf(path: f.path, pages: const <String>[], modified: f.modified));
        }
        progress?.call(i + 1, todo.length);
      }
      await index.save();
    } finally {
      _running = false;
    }
    return read;
  }
}

/// Page texts from positioned pieces (what a [PdfTextSource] returns).
List<String> pageTextsOf(List<List<PdfTextPiece>> pages) =>
    <String>[for (int i = 0; i < pages.length; i++) PdfPageText(i + 1, pages[i]).text];
