import 'dart:typed_data';

import '../archive/zip_codec.dart';
import 'pdf_compressor.dart';

/// Feature 003 — Split PDF: by page ranges, every N pages, or into parts
/// that each stay under a file size.
///
/// Pure Dart on the phone. Each part keeps its pages' size, rotation and
/// resources (inherited attributes are copied onto the page); only the
/// objects a part's pages use are written into it. The parts are named in
/// order with zero-padded numbers and can be bundled as one ZIP.

enum SplitMode { ranges, everyN, bySize }

class SplitError implements Exception {
  const SplitError(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Pages [first] to [last], counted from 1, both included.
class PageRange {
  const PageRange(this.first, this.last);
  final int first;
  final int last;

  int get length => last - first + 1;

  List<int> get pages => <int>[for (int p = first; p <= last; p++) p];

  String get label => first == last ? 'p$first' : 'p$first-$last';

  @override
  bool operator ==(Object other) => other is PageRange && other.first == first && other.last == last;

  @override
  int get hashCode => Object.hash(first, last);

  @override
  String toString() => '$first-$last';
}

abstract final class PageRanges {
  /// Reads forms like `1-3, 5, 8-10`. Each comma-separated item becomes one
  /// part. `8-` runs to the last page; en and em dashes, `to` and `;` are
  /// accepted too. Throws [SplitError] with a plain message otherwise.
  static List<PageRange> parse(String input, int pageCount) {
    final String text = input
        .replaceAll('–', '-')
        .replaceAll('—', '-')
        .replaceAll(RegExp(r'\s*to\s*', caseSensitive: false), '-')
        .replaceAll(';', ',');
    final List<String> items = text.split(',').map((String s) => s.trim()).where((String s) => s.isNotEmpty).toList();
    if (items.isEmpty) {
      throw const SplitError('Type the pages, like 1-3, 5, 8-10.');
    }
    final List<PageRange> out = <PageRange>[];
    final RegExp single = RegExp(r'^(\d+)$');
    final RegExp span = RegExp(r'^(\d+)\s*-\s*(\d*)$');
    for (final String item in items) {
      int first;
      int last;
      final RegExpMatch? s = single.firstMatch(item);
      final RegExpMatch? r = span.firstMatch(item);
      if (s != null) {
        first = int.parse(s.group(1)!);
        last = first;
      } else if (r != null) {
        first = int.parse(r.group(1)!);
        final String end = r.group(2)!;
        last = end.isEmpty ? pageCount : int.parse(end);
      } else {
        throw SplitError('"$item" is not a page or a range like 8-10.');
      }
      if (first < 1 || last < 1) {
        throw const SplitError('Pages start at 1.');
      }
      if (first > pageCount || last > pageCount) {
        throw SplitError('"$item" goes past the last page ($pageCount).');
      }
      if (last < first) {
        throw SplitError('"$item" runs backwards; write it as $last-$first.');
      }
      out.add(PageRange(first, last));
    }
    return out;
  }
}

/// One file the split made.
class SplitPart {
  const SplitPart({required this.number, required this.range, required this.name, required this.bytes, this.overLimit = false});

  /// 1, 2, 3… in the order the parts were made.
  final int number;
  final PageRange range;
  final String name;
  final Uint8List bytes;

  /// By size: a single page that alone is bigger than the limit.
  final bool overLimit;
}

class PdfSplitResult {
  const PdfSplitResult(this.parts, this.pageCount);
  final List<SplitPart> parts;
  final int pageCount;

  int get overLimit => parts.where((SplitPart p) => p.overLimit).length;
}

/// Everything a split needs, sendable to an isolate.
class SplitRequest {
  const SplitRequest({required this.bytes, required this.name, required this.mode, required this.value});
  final Uint8List bytes;
  final String name;
  final SplitMode mode;

  /// The ranges text, N, or the size limit in bytes, as typed or computed.
  final String value;
}

class _Page {
  _Page(this.num, this.gen, this.inherited);
  final int num;
  final int gen;
  final Map<String, Object> inherited;
}

/// A parsed PDF ready to be cut into parts.
class PdfSplitSource {
  PdfSplitSource._(this._doc, this._pages, this._drop, this._next);

  static const List<String> _inheritable = <String>['Resources', 'MediaBox', 'CropBox', 'Rotate'];

  final PdfDocumentModel _doc;
  final List<_Page> _pages;

  /// Old catalog, page tree nodes and pages: never copied wholesale.
  final Set<int> _drop;
  final int _next;

  int get pageCount => _pages.length;

  factory PdfSplitSource.parse(Uint8List bytes) {
    final PdfDocumentModel doc = PdfDocumentModel.parse(bytes);
    final List<_Page> pages = <_Page>[];
    final Set<int> drop = <int>{};
    final Set<int> seen = <int>{};
    final Object? rootRef = doc.trailer['Root'];
    if (rootRef is PdfRef) {
      drop.add(rootRef.num);
    }
    final Object? root = doc.resolve(rootRef);

    void walk(Object? node, Map<String, Object> inherit, int depth) {
      if (node is! PdfRef || depth > 64 || !seen.add(node.num)) {
        return;
      }
      final PdfObject? o = doc.objects[node.num];
      final Object? v = o?.value;
      if (o == null || v is! PdfDict) {
        return;
      }
      final Map<String, Object> here = Map<String, Object>.of(inherit);
      for (final String key in _inheritable) {
        final Object? a = v[key];
        if (a != null) {
          here[key] = a;
        }
      }
      final Object? kids = doc.resolve(v['Kids']);
      if (v.name('Type') == 'Pages' || kids is PdfArray) {
        drop.add(node.num);
        if (kids is PdfArray) {
          for (final Object k in kids.items) {
            walk(k, here, depth + 1);
          }
        }
        return;
      }
      drop.add(node.num);
      pages.add(_Page(node.num, o.gen, here));
    }

    walk(root is PdfDict ? root['Pages'] : null, <String, Object>{}, 0);
    if (pages.isEmpty) {
      throw const SplitError('This PDF has no pages to split.');
    }
    int max = 0;
    for (final int n in doc.objects.keys) {
      if (n > max) {
        max = n;
      }
    }
    return PdfSplitSource._(doc, pages, drop, max + 1);
  }

  /// A new PDF holding pages [range] (counted from 1).
  Uint8List build(PageRange range) {
    final Map<int, PdfObject> out = <int, PdfObject>{};
    for (final MapEntry<int, PdfObject> e in _doc.objects.entries) {
      if (!_drop.contains(e.key)) {
        out[e.key] = e.value;
      }
    }
    final int pagesNum = _next;
    final int catalogNum = _next + 1;
    final List<Object> kids = <Object>[];
    for (int p = range.first; p <= range.last; p++) {
      final _Page page = _pages[p - 1];
      final PdfObject src = _doc.objects[page.num]!;
      final PdfDict d = PdfDict(Map<String, Object>.of((src.value as PdfDict).entries));
      for (final MapEntry<String, Object> e in page.inherited.entries) {
        d.entries.putIfAbsent(e.key, () => e.value);
      }
      d.entries['Parent'] = PdfRef(pagesNum, 0);
      out[page.num] = PdfObject(page.num, page.gen, d, stream: src.stream);
      kids.add(PdfRef(page.num, page.gen));
    }
    out[pagesNum] = PdfObject(pagesNum, 0, PdfDict(<String, Object>{
      'Type': const PdfName('Pages'),
      'Kids': PdfArray(kids),
      'Count': PdfNum('${kids.length}'),
    }));
    out[catalogNum] = PdfObject(catalogNum, 0, PdfDict(<String, Object>{
      'Type': const PdfName('Catalog'),
      'Pages': PdfRef(pagesNum, 0),
    }));
    final PdfDocumentModel part = PdfDocumentModel.build(out, PdfDict(<String, Object>{'Root': PdfRef(catalogNum, 0)}));
    final Set<int> live = part.reachable();
    out.removeWhere((int n, PdfObject _) => !live.contains(n));
    return part.write();
  }
}

abstract final class PdfSplitter {
  /// The name stem parts are named after: "report.pdf" → "report".
  static String stem(String name) {
    final String base = name.split('/').last;
    return base.toLowerCase().endsWith('.pdf') ? base.substring(0, base.length - 4) : base;
  }

  /// "report part 02 (p4-6).pdf", padded so the parts sort in order.
  static String partName(String name, int number, int total, PageRange range) {
    final int width = '$total'.length < 2 ? 2 : '$total'.length;
    return '${stem(name)} part ${'$number'.padLeft(width, '0')} (${range.label}).pdf';
  }

  static PdfSplitResult byRanges(Uint8List bytes, String name, String ranges) {
    final PdfSplitSource src = _open(bytes);
    return _parts(src, name, PageRanges.parse(ranges, src.pageCount));
  }

  static PdfSplitResult everyN(Uint8List bytes, String name, int n) {
    if (n < 1) {
      throw const SplitError('Pick at least 1 page per part.');
    }
    final PdfSplitSource src = _open(bytes);
    final List<PageRange> ranges = <PageRange>[
      for (int first = 1; first <= src.pageCount; first += n)
        PageRange(first, first + n - 1 > src.pageCount ? src.pageCount : first + n - 1),
    ];
    return _parts(src, name, ranges);
  }

  /// Greedy: each part takes as many following pages as fit under
  /// [maxBytes]. A page too big on its own becomes a part by itself,
  /// marked [SplitPart.overLimit].
  static PdfSplitResult bySize(Uint8List bytes, String name, int maxBytes) {
    if (maxBytes < 1024) {
      throw const SplitError('Pick a size of at least 1 KB.');
    }
    final PdfSplitSource src = _open(bytes);
    final List<(PageRange, Uint8List)> made = <(PageRange, Uint8List)>[];
    int first = 1;
    while (first <= src.pageCount) {
      PageRange range = PageRange(first, first);
      Uint8List data = src.build(range);
      while (range.last < src.pageCount) {
        final PageRange wider = PageRange(first, range.last + 1);
        final Uint8List more = src.build(wider);
        if (more.length > maxBytes) {
          break;
        }
        range = wider;
        data = more;
      }
      made.add((range, data));
      first = range.last + 1;
    }
    return PdfSplitResult(<SplitPart>[
      for (int i = 0; i < made.length; i++)
        SplitPart(
          number: i + 1,
          range: made[i].$1,
          name: partName(name, i + 1, made.length, made[i].$1),
          bytes: made[i].$2,
          overLimit: made[i].$2.length > maxBytes,
        ),
    ], src.pageCount);
  }

  /// Runs [r]; top level so it can go to an isolate.
  static PdfSplitResult run(SplitRequest r) {
    switch (r.mode) {
      case SplitMode.ranges:
        return byRanges(r.bytes, r.name, r.value);
      case SplitMode.everyN:
        final int? n = int.tryParse(r.value.trim());
        if (n == null) {
          throw const SplitError('Type how many pages go in each part.');
        }
        return everyN(r.bytes, r.name, n);
      case SplitMode.bySize:
        final int? max = int.tryParse(r.value.trim());
        if (max == null) {
          throw const SplitError('Type the largest size a part may be.');
        }
        return bySize(r.bytes, r.name, max);
    }
  }

  /// All parts as one ZIP, in order.
  static Uint8List zip(PdfSplitResult r, {DateTime? now}) =>
      ZipWriter().build(<ZipInput>[for (final SplitPart p in r.parts) ZipInput(p.name, p.bytes)], now: now);

  static String zipName(String name) => '${stem(name)} parts.zip';

  /// "5", "2.5" or "0.5" megabytes as bytes; null when it is not a size.
  static int? megabytes(String typed) {
    final double? mb = double.tryParse(typed.trim().replaceAll(',', '.'));
    if (mb == null || mb <= 0) {
      return null;
    }
    return (mb * 1024 * 1024).round();
  }

  static PdfSplitSource _open(Uint8List bytes) {
    try {
      return PdfSplitSource.parse(bytes);
    } on PdfCompressError catch (e) {
      throw SplitError(e.message);
    }
  }

  static PdfSplitResult _parts(PdfSplitSource src, String name, List<PageRange> ranges) {
    return PdfSplitResult(<SplitPart>[
      for (int i = 0; i < ranges.length; i++)
        SplitPart(
          number: i + 1,
          range: ranges[i],
          name: partName(name, i + 1, ranges.length, ranges[i]),
          bytes: src.build(ranges[i]),
        ),
    ], src.pageCount);
  }
}
