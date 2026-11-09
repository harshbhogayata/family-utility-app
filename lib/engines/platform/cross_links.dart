import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Feature 122 — Cross-links.
///
/// Any record points at any other by id: a receipt at its warranty and its
/// appliance, a doctor's visit at its prescription. Links are two-way and
/// kept on this phone. Each record kind registers how to name and open its
/// records, so the related-items strip works for every kind, and a link to a
/// record that was deleted simply stops showing.

@immutable
class RecordRef implements Comparable<RecordRef> {
  const RecordRef(this.kind, this.id);

  /// "receipt", "warranty", "appliance", "visit", "prescription"...
  final String kind;
  final String id;

  String get key => '$kind/$id';

  static RecordRef? parse(String key) {
    final int slash = key.indexOf('/');
    if (slash <= 0 || slash == key.length - 1) {
      return null;
    }
    return RecordRef(key.substring(0, slash), key.substring(slash + 1));
  }

  @override
  bool operator ==(Object other) => other is RecordRef && other.kind == kind && other.id == id;

  @override
  int get hashCode => Object.hash(kind, id);

  @override
  int compareTo(RecordRef other) => key.compareTo(other.key);

  @override
  String toString() => key;
}

/// How one kind of record is named and opened.
abstract class RecordKindInfo {
  String get kind;

  /// "Warranty", "Prescription".
  String get noun;

  /// The record's title, or null when it no longer exists.
  String? title(String id);
}

/// Simple [RecordKindInfo] from a function, for kinds and tests.
class SimpleRecordKind implements RecordKindInfo {
  SimpleRecordKind(this.kind, this.noun, this._title);

  @override
  final String kind;
  @override
  final String noun;
  final String? Function(String id) _title;

  @override
  String? title(String id) => _title(id);
}

/// One related item, ready for the strip.
@immutable
class RelatedItem {
  const RelatedItem({required this.ref, required this.noun, required this.title});
  final RecordRef ref;
  final String noun;
  final String title;
}

abstract class CrossLinkStorage {
  Future<List<List<String>>> load();
  Future<void> save(List<List<String>> pairs);
}

class MemoryCrossLinkStorage implements CrossLinkStorage {
  List<List<String>> saved = <List<String>>[];

  @override
  Future<List<List<String>>> load() async => List<List<String>>.of(saved);

  @override
  Future<void> save(List<List<String>> pairs) async => saved = List<List<String>>.of(pairs);
}

/// A JSON file in the app's private folder.
class FileCrossLinkStorage implements CrossLinkStorage {
  FileCrossLinkStorage(this.folder);

  final Future<Directory> Function() folder;

  Future<File> _file() async => File('${(await folder()).path}/cross_links.json');

  @override
  Future<List<List<String>>> load() async {
    final File f = await _file();
    if (!f.existsSync()) {
      return <List<String>>[];
    }
    final Object? j = jsonDecode(await f.readAsString());
    if (j is! List) {
      return <List<String>>[];
    }
    return <List<String>>[
      for (final Object? p in j)
        if (p is List && p.length == 2) <String>['${p[0]}', '${p[1]}'],
    ];
  }

  @override
  Future<void> save(List<List<String>> pairs) async {
    final File f = await _file();
    await f.parent.create(recursive: true);
    final File tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode(pairs));
    await tmp.rename(f.path);
  }
}

class CrossLinks extends ChangeNotifier {
  CrossLinks({CrossLinkStorage? storage}) : _storage = storage ?? MemoryCrossLinkStorage();

  final CrossLinkStorage _storage;
  final Map<RecordRef, Set<RecordRef>> _links = <RecordRef, Set<RecordRef>>{};
  final Map<String, RecordKindInfo> _kinds = <String, RecordKindInfo>{};
  List<List<RecordRef>>? _undoAdd;
  List<List<RecordRef>>? _undoRemove;

  void registerKind(RecordKindInfo info) {
    _kinds[info.kind] = info;
    notifyListeners();
  }

  RecordKindInfo? kindInfo(String kind) => _kinds[kind];

  Future<void> load() async {
    try {
      for (final List<String> p in await _storage.load()) {
        final RecordRef? a = RecordRef.parse(p[0]);
        final RecordRef? b = RecordRef.parse(p[1]);
        if (a != null && b != null && a != b) {
          _add(a, b);
        }
      }
    } catch (_) {
      // A damaged file starts with no links.
    }
    notifyListeners();
  }

  bool areLinked(RecordRef a, RecordRef b) => _links[a]?.contains(b) ?? false;

  /// Links two records both ways. False when already linked or the same.
  bool link(RecordRef a, RecordRef b) {
    if (a == b || areLinked(a, b)) {
      return false;
    }
    _add(a, b);
    _undoAdd = <List<RecordRef>>[<RecordRef>[a, b]];
    _undoRemove = null;
    _changed();
    return true;
  }

  bool unlink(RecordRef a, RecordRef b) {
    if (!areLinked(a, b)) {
      return false;
    }
    _remove(a, b);
    _undoRemove = <List<RecordRef>>[<RecordRef>[a, b]];
    _undoAdd = null;
    _changed();
    return true;
  }

  /// Drops every link of a deleted record. Returns how many went.
  int forget(RecordRef r) {
    final List<RecordRef> others = (_links[r] ?? <RecordRef>{}).toList();
    for (final RecordRef o in others) {
      _remove(r, o);
    }
    if (others.isNotEmpty) {
      _undoRemove = <List<RecordRef>>[for (final RecordRef o in others) <RecordRef>[r, o]];
      _undoAdd = null;
      _changed();
    }
    return others.length;
  }

  bool undo() {
    final List<List<RecordRef>>? add = _undoAdd;
    final List<List<RecordRef>>? rem = _undoRemove;
    _undoAdd = null;
    _undoRemove = null;
    if (add != null) {
      for (final List<RecordRef> p in add) {
        _remove(p[0], p[1]);
      }
    } else if (rem != null) {
      for (final List<RecordRef> p in rem) {
        _add(p[0], p[1]);
      }
    } else {
      return false;
    }
    _changed();
    return true;
  }

  /// Every record linked to [r], ids only (dangling ones included).
  List<RecordRef> linkedTo(RecordRef r) => (_links[r]?.toList() ?? <RecordRef>[])..sort();

  /// What the strip shows: linked records that still exist, grouped by
  /// kind in registration order, then by title.
  List<RelatedItem> related(RecordRef r) {
    final List<String> order = _kinds.keys.toList();
    final List<RelatedItem> out = <RelatedItem>[];
    for (final RecordRef o in linkedTo(r)) {
      final RecordKindInfo? k = _kinds[o.kind];
      final String? title = k?.title(o.id);
      if (k == null || title == null) {
        continue;
      }
      out.add(RelatedItem(ref: o, noun: k.noun, title: title));
    }
    out.sort((RelatedItem a, RelatedItem b) {
      final int c = order.indexOf(a.ref.kind).compareTo(order.indexOf(b.ref.kind));
      return c != 0 ? c : a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });
    return out;
  }

  void _add(RecordRef a, RecordRef b) {
    _links.putIfAbsent(a, () => <RecordRef>{}).add(b);
    _links.putIfAbsent(b, () => <RecordRef>{}).add(a);
  }

  void _remove(RecordRef a, RecordRef b) {
    _links[a]?.remove(b);
    _links[b]?.remove(a);
    if (_links[a]?.isEmpty ?? false) {
      _links.remove(a);
    }
    if (_links[b]?.isEmpty ?? false) {
      _links.remove(b);
    }
  }

  List<List<String>> get pairs {
    final List<List<String>> out = <List<String>>[];
    for (final MapEntry<RecordRef, Set<RecordRef>> e in _links.entries) {
      for (final RecordRef o in e.value) {
        if (e.key.compareTo(o) < 0) {
          out.add(<String>[e.key.key, o.key]);
        }
      }
    }
    out.sort((List<String> a, List<String> b) => '${a[0]} ${a[1]}'.compareTo('${b[0]} ${b[1]}'));
    return out;
  }

  void _changed() {
    notifyListeners();
    _storage.save(pairs).catchError((Object _) {});
  }

  static CrossLinks instance = CrossLinks();
  static void install(CrossLinks c) => instance = c;
}
