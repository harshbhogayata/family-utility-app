import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../security/secure_notes.dart';
import 'action_history.dart';
import 'file_manager.dart';

/// Feature 114 — One search.
///
/// One box across tools, files, history and records. Every source hands the
/// index plain documents; the index is an in-memory inverted index with
/// prefix lookup, built and queried on the phone. Nothing is uploaded.

/// What a hit points at. Ordered as results are grouped on screen.
enum SearchKind {
  tool('Tools'),
  file('Files'),
  text('Text in files'),
  history('History'),
  record('Records');

  const SearchKind(this.label);
  final String label;
}

/// One searchable thing.
@immutable
class SearchDoc {
  const SearchDoc({
    required this.kind,
    required this.ref,
    required this.title,
    this.subtitle = '',
    this.body = '',
  });

  final SearchKind kind;

  /// What opening the hit needs: a tool id, a file path, a history id or a
  /// record id.
  final String ref;
  final String title;
  final String subtitle;

  /// Extra words that match but are not the title (fields, OCR text, inputs).
  final String body;

  String get key => '${kind.name}:$ref';
}

/// A ranked hit.
@immutable
class SearchResult {
  const SearchResult(this.doc, {required this.score, this.snippet});

  final SearchDoc doc;
  final double score;

  /// The words around the match when it was found in the body.
  final String? snippet;
}

/// Splits text into lower-case words (letters, marks and digits, any script).
List<String> tokenize(String text) {
  return text
      .toLowerCase()
      .split(RegExp(r'[^\p{L}\p{M}\p{N}]+', unicode: true))
      .where((String t) => t.isNotEmpty)
      .toList();
}

/// An immutable index over a set of documents.
class SearchIndex {
  SearchIndex(List<SearchDoc> docs)
      : docs = List<SearchDoc>.unmodifiable(docs),
        _lowTitles = docs.map((SearchDoc d) => d.title.toLowerCase()).toList(growable: false) {
    final Map<String, Set<int>> titleMap = <String, Set<int>>{};
    final Map<String, Set<int>> bodyMap = <String, Set<int>>{};
    for (int i = 0; i < this.docs.length; i++) {
      final SearchDoc d = this.docs[i];
      for (final String t in tokenize('${d.title} ${d.subtitle}')) {
        (titleMap[t] ??= <int>{}).add(i);
      }
      for (final String t in tokenize(d.body)) {
        (bodyMap[t] ??= <int>{}).add(i);
      }
    }
    _title = titleMap;
    _body = bodyMap;
    _titleTerms = titleMap.keys.toList()..sort();
    _bodyTerms = bodyMap.keys.toList()..sort();
  }

  final List<SearchDoc> docs;
  final List<String> _lowTitles;
  late final Map<String, Set<int>> _title;
  late final Map<String, Set<int>> _body;
  late final List<String> _titleTerms;
  late final List<String> _bodyTerms;

  int get size => docs.length;

  int get termCount => _titleTerms.length + _bodyTerms.length;

  /// Every query word must match a word in the document, as a prefix.
  /// Title matches outrank body matches; exact words outrank prefixes.
  List<SearchResult> query(String q, {int limit = 50}) {
    final List<String> words = tokenize(q);
    if (words.isEmpty) {
      return const <SearchResult>[];
    }
    Map<int, double>? scores;
    for (final String w in words) {
      final Map<int, double> forWord = <int, double>{};
      _collect(w, _titleTerms, _title, 3, forWord);
      _collect(w, _bodyTerms, _body, 1, forWord);
      if (scores == null) {
        scores = forWord;
      } else {
        final Map<int, double> next = <int, double>{};
        scores.forEach((int i, double s) {
          final double? add = forWord[i];
          if (add != null) {
            next[i] = s + add;
          }
        });
        scores = next;
      }
      if (scores.isEmpty) {
        return const <SearchResult>[];
      }
    }
    final String phrase = words.join(' ');
    final String whole = q.trim().toLowerCase();
    final List<MapEntry<int, double>> ranked = scores!.entries.map((MapEntry<int, double> e) {
      final SearchDoc d = docs[e.key];
      double s = e.value;
      final String title = _lowTitles[e.key];
      if (title == whole) {
        s += 10;
      } else if (title.startsWith(phrase)) {
        s += 4;
      }
      // Tools first on ties: they are the shortest path to doing something.
      s += (SearchKind.values.length - d.kind.index) * 0.01;
      return MapEntry<int, double>(e.key, s);
    }).toList()
      ..sort((MapEntry<int, double> a, MapEntry<int, double> b) {
        final int c = b.value.compareTo(a.value);
        return c != 0 ? c : _lowTitles[a.key].compareTo(_lowTitles[b.key]);
      });
    return ranked.take(limit).map((MapEntry<int, double> e) {
      final SearchDoc d = docs[e.key];
      return SearchResult(d, score: e.value, snippet: _snippet(d, words));
    }).toList();
  }

  static void _collect(
    String word,
    List<String> terms,
    Map<String, Set<int>> postings,
    double weight,
    Map<int, double> into,
  ) {
    int i = _lowerBound(terms, word);
    while (i < terms.length && terms[i].startsWith(word)) {
      final double w = terms[i] == word ? weight : weight * 0.6;
      for (final int d in postings[terms[i]]!) {
        final double? had = into[d];
        if (had == null || had < w) {
          into[d] = w;
        }
      }
      i++;
    }
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

  static String? _snippet(SearchDoc d, List<String> words) {
    if (d.body.isEmpty) {
      return null;
    }
    final String lowTitle = '${d.title} ${d.subtitle}'.toLowerCase();
    if (words.every((String w) => lowTitle.contains(w))) {
      return null;
    }
    final String lower = d.body.toLowerCase();
    for (final String w in words) {
      final int at = lower.indexOf(w);
      if (at >= 0) {
        final int from = at - 30 < 0 ? 0 : at - 30;
        final int to = at + w.length + 40 > d.body.length ? d.body.length : at + w.length + 40;
        final String s = d.body.substring(from, to).replaceAll(RegExp(r'\s+'), ' ').trim();
        return '${from > 0 ? '…' : ''}$s${to < d.body.length ? '…' : ''}';
      }
    }
    return null;
  }
}

/// Hands documents to the index. One per kind of thing searched.
abstract class SearchSource {
  Future<List<SearchDoc>> collect();
}

/// A tool as the search needs it, kept free of Flutter widgets.
@immutable
class ToolInfo {
  const ToolInfo({required this.id, required this.name, this.section = ''});

  final String id;
  final String name;
  final String section;
}

class ToolSearchSource implements SearchSource {
  ToolSearchSource(this.tools);

  final List<ToolInfo> Function() tools;

  @override
  Future<List<SearchDoc>> collect() async => <SearchDoc>[
        for (final ToolInfo t in tools())
          SearchDoc(kind: SearchKind.tool, ref: t.id, title: t.name, subtitle: t.section),
      ];
}

/// File names under the roots, and the start of text files.
class FileSearchSource implements SearchSource {
  FileSearchSource(this.files, {this.maxFiles = 5000, this.textBytes = 16 * 1024});

  final FileManager files;
  final int maxFiles;
  final int textBytes;

  @override
  Future<List<SearchDoc>> collect() async {
    final List<SearchDoc> out = <SearchDoc>[];
    final Set<String> seen = <String>{};
    for (final FileRoot root in files.roots) {
      final List<String> todo = <String>[root.path];
      while (todo.isNotEmpty && out.length < maxFiles) {
        final String dir = todo.removeAt(0);
        final List<FileNode> nodes;
        try {
          nodes = await files.source.list(dir);
        } catch (_) {
          continue;
        }
        for (final FileNode n in nodes) {
          if (out.length >= maxFiles) {
            break;
          }
          if (n.isDir) {
            if (!n.name.startsWith('.')) {
              todo.add(n.path);
            }
            continue;
          }
          if (!seen.add(n.path)) {
            continue;
          }
          String body = '';
          if (FileManager.textExtensions.contains(n.extension)) {
            body = await files.source.readText(n.path, textBytes) ?? '';
          }
          out.add(SearchDoc(
            kind: SearchKind.file,
            ref: n.path,
            title: n.name,
            subtitle: '${root.label} · ${_relative(root.path, parentOf(n.path))}',
            body: body,
          ));
        }
      }
    }
    return out;
  }

  static String _relative(String root, String dir) {
    if (dir == root) {
      return '/';
    }
    return dir.startsWith(root) ? dir.substring(root.length) : dir;
  }
}

class HistorySearchSource implements SearchSource {
  HistorySearchSource(this.history);

  final ActionHistory history;

  @override
  Future<List<SearchDoc>> collect() async => <SearchDoc>[
        for (final HistoryEntry e in history.entries)
          SearchDoc(
            kind: SearchKind.history,
            ref: e.id,
            title: e.toolName,
            subtitle: <String>[...e.inputs, ...e.outputs].map(baseName).join(', '),
          ),
      ];
}

/// Records: titles, field labels and the fields that are not secret.
/// Secret values are never put in the index.
class RecordSearchSource implements SearchSource {
  RecordSearchSource(this.notes);

  final SecureNotes notes;

  @override
  Future<List<SearchDoc>> collect() async => <SearchDoc>[
        for (final SecureNote n in notes.notes)
          SearchDoc(
            kind: SearchKind.record,
            ref: n.id,
            title: n.title,
            subtitle: n.fields.map((NoteField f) => f.label).where((String l) => l.isNotEmpty).join(', '),
            body: <String>[
              for (final NoteField f in n.fields)
                if (!f.secret) '${f.label} ${f.value}',
              n.note,
            ].join('\n'),
          ),
      ];
}

/// Text read out of scans and photos (on-device OCR). OCR tools put their
/// text here, keyed by file path; the search finds the file by its words.
abstract class OcrTextStoreBackend {
  Future<String?> read();

  Future<void> write(String json);
}

class MemoryOcrBackend implements OcrTextStoreBackend {
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String json) async => value = json;
}

class FileOcrBackend implements OcrTextStoreBackend {
  FileOcrBackend(this.folder);

  final Future<Directory> Function() folder;

  Future<File> _file() async => File('${(await folder()).path}/ocr-text.json');

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

class OcrTextStore extends ChangeNotifier implements SearchSource {
  OcrTextStore(this.backend);

  final OcrTextStoreBackend backend;
  Map<String, String> _text = <String, String>{};

  Map<String, String> get all => Map<String, String>.unmodifiable(_text);

  Future<void> load() async {
    try {
      final String? raw = await backend.read();
      if (raw != null && raw.isNotEmpty) {
        _text = (jsonDecode(raw) as Map<String, Object?>).map(
          (String k, Object? v) => MapEntry<String, String>(k, v is String ? v : ''),
        );
      }
    } catch (_) {
      _text = <String, String>{};
    }
    notifyListeners();
  }

  Future<void> put(String path, String text) async {
    _text = <String, String>{..._text, path: text};
    await _save();
  }

  Future<void> remove(String path) async {
    if (_text.remove(path) != null) {
      await _save();
    }
  }

  Future<void> _save() async {
    try {
      await backend.write(jsonEncode(_text));
    } catch (_) {
      // Kept in memory for this launch.
    }
    notifyListeners();
  }

  @override
  Future<List<SearchDoc>> collect() async => <SearchDoc>[
        for (final MapEntry<String, String> e in _text.entries)
          SearchDoc(kind: SearchKind.text, ref: e.key, title: baseName(e.key), subtitle: 'Scanned text', body: e.value),
      ];

  static OcrTextStore instance = OcrTextStore(MemoryOcrBackend());

  static void install(OcrTextStore store) {
    instance = store;
  }
}

/// The answer to one query, with how long it took.
@immutable
class SearchOutcome {
  const SearchOutcome(this.query, this.results, this.elapsed);

  final String query;
  final List<SearchResult> results;
  final Duration elapsed;

  Map<SearchKind, List<SearchResult>> get grouped {
    final Map<SearchKind, List<SearchResult>> g = <SearchKind, List<SearchResult>>{};
    for (final SearchKind k in SearchKind.values) {
      final List<SearchResult> of = results.where((SearchResult r) => r.doc.kind == k).toList();
      if (of.isNotEmpty) {
        g[k] = of;
      }
    }
    return g;
  }

  /// Plain text for Share and Save.
  String asText() {
    final StringBuffer b = StringBuffer('Search: $query\n');
    grouped.forEach((SearchKind k, List<SearchResult> rs) {
      b.writeln('\n${k.label}');
      for (final SearchResult r in rs) {
        b.writeln('- ${r.doc.title}${r.doc.subtitle.isEmpty ? '' : ' (${r.doc.subtitle})'}');
      }
    });
    return b.toString();
  }
}

/// Owns the sources and the current index. Rebuild when the app's data
/// changes; queries run against the last built index.
class OneSearch extends ChangeNotifier {
  OneSearch(this.sources);

  final List<SearchSource> sources;
  SearchIndex _index = SearchIndex(const <SearchDoc>[]);
  bool _stale = true;
  Future<void>? _building;

  SearchIndex get index => _index;

  bool get isStale => _stale;

  /// Mark the index out of date; the next search rebuilds it.
  void invalidate() {
    _stale = true;
  }

  Future<void> rebuild() {
    return _building ??= _rebuild().whenComplete(() => _building = null);
  }

  Future<void> _rebuild() async {
    final List<SearchDoc> docs = <SearchDoc>[];
    final Set<String> keys = <String>{};
    for (final SearchSource s in sources) {
      final List<SearchDoc> got;
      try {
        got = await s.collect();
      } catch (_) {
        continue;
      }
      for (final SearchDoc d in got) {
        if (keys.add(d.key)) {
          docs.add(d);
        }
      }
    }
    _index = SearchIndex(docs);
    _stale = false;
    notifyListeners();
  }

  /// Runs the query on the index, rebuilding it first when stale.
  Future<SearchOutcome> search(String q, {int limit = 50}) async {
    if (_stale) {
      await rebuild();
    }
    final Stopwatch w = Stopwatch()..start();
    final List<SearchResult> r = _index.query(q, limit: limit);
    w.stop();
    return SearchOutcome(q, r, w.elapsed);
  }

  static OneSearch instance = OneSearch(<SearchSource>[]);

  static void install(OneSearch s) {
    instance = s;
  }
}
