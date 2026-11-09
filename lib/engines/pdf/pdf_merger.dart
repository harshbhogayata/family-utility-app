import 'dart:convert';
import 'dart:typed_data';

import 'pdf_compressor.dart';

/// Feature 002 — Merge PDF: several PDFs, in the chosen order, into one.
///
/// Pure Dart on the phone. Every page keeps its own size and rotation
/// (inherited attributes are copied onto the page), and each file's
/// bookmarks are kept under one bookmark named after that file.

class MergeInput {
  const MergeInput(this.name, this.bytes);
  final String name;
  final Uint8List bytes;
}

class PdfMergeResult {
  const PdfMergeResult(this.bytes, this.pageCount);
  final Uint8List bytes;
  final int pageCount;
}

abstract final class PdfMerger {
  static const List<String> _inherited = <String>['Resources', 'MediaBox', 'CropBox', 'Rotate'];

  static PdfMergeResult merge(List<MergeInput> inputs) {
    if (inputs.length < 2) {
      throw const PdfCompressError('Pick at least two PDFs to merge.');
    }
    final Map<int, PdfObject> out = <int, PdfObject>{};
    // 1 catalog, 2 pages, 3 outlines; inputs follow.
    const int catalogNum = 1;
    const int pagesNum = 2;
    const int outlinesNum = 3;
    int next = 4;
    final List<PdfRef> kids = <PdfRef>[];
    final List<int> fileItems = <int>[];
    final Map<int, (int, int)> fileChildren = <int, (int, int)>{};

    for (final MergeInput input in inputs) {
      final PdfDocumentModel doc;
      try {
        doc = PdfDocumentModel.parse(input.bytes);
      } on PdfCompressError catch (e) {
        throw PdfCompressError('${input.name}: ${e.message}');
      }
      final int base = next;
      int maxNum = 0;
      Object renum(Object v) {
        if (v is PdfRef) {
          return PdfRef(v.num + base, 0);
        }
        if (v is PdfArray) {
          return PdfArray(<Object>[for (final Object i in v.items) renum(i)]);
        }
        if (v is PdfDict) {
          return PdfDict(<String, Object>{for (final MapEntry<String, Object> e in v.entries.entries) e.key: renum(e.value)});
        }
        return v;
      }

      for (final int n in doc.reachable()) {
        final PdfObject? o = doc.objects[n];
        if (o == null) {
          continue;
        }
        out[n + base] = PdfObject(n + base, 0, renum(o.value), stream: o.stream);
        if (n > maxNum) {
          maxNum = n;
        }
      }
      next = base + maxNum + 1;

      // Pages, in order, with inherited attributes made explicit.
      final Object? root = doc.resolve(doc.trailer['Root']);
      final Object? pagesRoot = root is PdfDict ? root['Pages'] : null;
      final int before = kids.length;
      void walk(Object? node, Map<String, Object> inherit, int depth) {
        if (node is! PdfRef || depth > 64) {
          return;
        }
        final PdfObject? o = out[node.num + base];
        final Object? v = o?.value;
        if (o == null || v is! PdfDict) {
          return;
        }
        final Map<String, Object> here = Map<String, Object>.of(inherit);
        for (final String key in _inherited) {
          final Object? a = v[key];
          if (a != null) {
            here[key] = a;
          }
        }
        final Object? k = v['Kids'];
        final Object? kidsValue = k is PdfRef ? out[k.num]?.value : k;
        if (v.name('Type') == 'Pages' || kidsValue is PdfArray) {
          if (kidsValue is PdfArray) {
            for (final Object kid in kidsValue.items) {
              // Kids were renumbered; walk by the original number.
              walk(kid is PdfRef ? PdfRef(kid.num - base, 0) : kid, here, depth + 1);
            }
          }
          return;
        }
        for (final MapEntry<String, Object> e in here.entries) {
          v.entries.putIfAbsent(e.key, () => e.value);
        }
        v.entries['Parent'] = const PdfRef(pagesNum, 0);
        kids.add(PdfRef(o.num, 0));
      }

      walk(pagesRoot, <String, Object>{}, 0);
      if (kids.length == before) {
        throw PdfCompressError('${input.name} has no pages.');
      }

      // Bookmarks: one per file, holding that file's own bookmarks.
      final int item = next++;
      fileItems.add(item);
      final Object? outlines = root is PdfDict ? doc.resolve(root['Outlines']) : null;
      if (outlines is PdfDict && outlines['First'] is PdfRef && outlines['Last'] is PdfRef) {
        final int first = (outlines['First']! as PdfRef).num + base;
        final int last = (outlines['Last']! as PdfRef).num + base;
        fileChildren[item] = (first, last);
        int? cur = first;
        int guard = 0;
        while (cur != null && guard++ < 10000) {
          final Object? v = out[cur]?.value;
          if (v is! PdfDict) {
            break;
          }
          v.entries['Parent'] = PdfRef(item, 0);
          final Object? n = v['Next'];
          cur = n is PdfRef ? n.num : null;
        }
      }
      out[item] = PdfObject(item, 0, PdfDict(<String, Object>{
        'Title': textString(input.name),
        'Parent': const PdfRef(outlinesNum, 0),
        'Dest': PdfArray(<Object>[kids[before], const PdfName('Fit')]),
      }));
    }

    for (int i = 0; i < fileItems.length; i++) {
      final PdfDict d = out[fileItems[i]]!.value as PdfDict;
      if (i > 0) {
        d.entries['Prev'] = PdfRef(fileItems[i - 1], 0);
      }
      if (i < fileItems.length - 1) {
        d.entries['Next'] = PdfRef(fileItems[i + 1], 0);
      }
      final (int, int)? c = fileChildren[fileItems[i]];
      if (c != null) {
        d.entries['First'] = PdfRef(c.$1, 0);
        d.entries['Last'] = PdfRef(c.$2, 0);
      }
    }
    out[outlinesNum] = PdfObject(outlinesNum, 0, PdfDict(<String, Object>{
      'Type': const PdfName('Outlines'),
      'First': PdfRef(fileItems.first, 0),
      'Last': PdfRef(fileItems.last, 0),
      'Count': PdfNum('${fileItems.length}'),
    }));
    out[pagesNum] = PdfObject(pagesNum, 0, PdfDict(<String, Object>{
      'Type': const PdfName('Pages'),
      'Kids': PdfArray(kids),
      'Count': PdfNum('${kids.length}'),
    }));
    out[catalogNum] = PdfObject(catalogNum, 0, PdfDict(<String, Object>{
      'Type': const PdfName('Catalog'),
      'Pages': const PdfRef(pagesNum, 0),
      'Outlines': const PdfRef(outlinesNum, 0),
      'PageMode': const PdfName('UseOutlines'),
    }));

    final PdfDocumentModel merged =
        PdfDocumentModel.build(out, PdfDict(<String, Object>{'Root': const PdfRef(catalogNum, 0)}));
    // Drop the old catalogs and page trees nothing points at any more.
    final Set<int> live = merged.reachable();
    out.removeWhere((int n, PdfObject _) => !live.contains(n));
    return PdfMergeResult(merged.write(), kids.length);
  }

  /// A PDF text string: plain when ASCII, UTF-16 with a BOM otherwise.
  static PdfString textString(String s) {
    if (s.codeUnits.every((int c) => c >= 32 && c < 127)) {
      final String esc = s.replaceAll(r'\', r'\\').replaceAll('(', r'\(').replaceAll(')', r'\)');
      return PdfString(Uint8List.fromList(latin1.encode('($esc)')));
    }
    final StringBuffer b = StringBuffer('<FEFF');
    for (final int u in s.codeUnits) {
      b.write(u.toRadixString(16).padLeft(4, '0'));
    }
    b.write('>');
    return PdfString(Uint8List.fromList(latin1.encode(b.toString())));
  }
}
