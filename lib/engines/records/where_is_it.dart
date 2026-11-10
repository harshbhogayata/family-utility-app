import 'package:flutter/foundation.dart';

import '../family/family_space.dart';
import '../family/family_store.dart';
import '../platform/one_search.dart';

/// Feature 099 — Where-is-it notes.
///
/// Where the spare key, the warranty card or the wedding album is kept.
/// Each note is private to this phone unless the person shares it with the
/// family; shared notes ride the family store to the other phones. A photo
/// stays in this phone's app folder. Notes are found by any word from One
/// search (114) as well as here. Nothing is uploaded.

class WhereNote {
  const WhereNote({
    required this.id,
    required this.item,
    required this.place,
    this.detail = '',
    this.photo,
    this.shared = false,
    this.updated,
  });

  final String id;

  /// What it is: "Spare car key".
  final String item;

  /// Where it is: "Bedroom cupboard, top shelf, blue box".
  final String place;
  final String detail;

  /// A photo in this phone's app folder.
  final String? photo;

  /// On the family store, so the family sees it.
  final bool shared;
  final DateTime? updated;

  Map<String, Object?> toFields() => <String, Object?>{
        'item': item,
        'place': place,
        if (detail.isNotEmpty) 'detail': detail,
        if (photo != null) 'photo': photo,
        if (updated != null) 'updated': updated!.toIso8601String(),
      };

  static WhereNote fromRecord(FamilyRecord r, {required bool shared}) {
    final Map<String, Object?> f = r.fields;
    final Object? p = f['photo'];
    return WhereNote(
      id: r.id,
      item: '${f['item'] ?? ''}',
      place: '${f['place'] ?? ''}',
      detail: '${f['detail'] ?? ''}',
      photo: p is String && p.isNotEmpty ? p : null,
      shared: shared,
      updated: DateTime.tryParse('${f['updated'] ?? ''}'),
    );
  }

  WhereNote copyWith({String? item, String? place, String? detail, String? photo, bool clearPhoto = false, bool? shared, DateTime? updated}) => WhereNote(
        id: id,
        item: item ?? this.item,
        place: place ?? this.place,
        detail: detail ?? this.detail,
        photo: clearPhoto ? null : (photo ?? this.photo),
        shared: shared ?? this.shared,
        updated: updated ?? this.updated,
      );
}

class WhereIsIt extends ChangeNotifier implements SearchSource {
  WhereIsIt({FamilySpace? space, FamilyStore? privateStore, DateTime Function()? now})
      : _space = space,
        _private = privateStore ?? FamilyStore(deviceId: 'this-phone'),
        _now = now ?? DateTime.now;

  static const String collection = 'where_is_it';

  /// One search refs start with this, so a hit opens these notes.
  static const String refPrefix = 'where:';

  final FamilySpace? _space;
  final FamilyStore _private;
  final DateTime Function() _now;
  int _seq = 0;

  FamilySpace get space => _space ?? FamilySpace.instance;

  /// Sharing needs a family to share with.
  bool get canShare => space.inFamily;

  FamilyStore get privateStore => _private;
  FamilyStore? get familyStore => canShare ? space.store : null;

  /// Everything a screen should listen to.
  Listenable get listenable => Listenable.merge(<Listenable>[this, _private, space.store]);

  FamilyStore _storeFor(bool shared) => shared && canShare ? space.store : _private;

  /// Newest first.
  List<WhereNote> get all {
    final List<WhereNote> out = <WhereNote>[
      for (final FamilyRecord r in _private.list(collection)) WhereNote.fromRecord(r, shared: false),
      if (canShare)
        for (final FamilyRecord r in space.store.list(collection)) WhereNote.fromRecord(r, shared: true),
    ];
    out.sort((WhereNote a, WhereNote b) {
      final DateTime da = a.updated ?? DateTime(2000), db = b.updated ?? DateTime(2000);
      final int c = db.compareTo(da);
      return c != 0 ? c : a.item.toLowerCase().compareTo(b.item.toLowerCase());
    });
    return out;
  }

  WhereNote? byId(String id) {
    for (final WhereNote n in all) {
      if (n.id == id) {
        return n;
      }
    }
    return null;
  }

  SearchDoc _doc(WhereNote n) => SearchDoc(
        kind: SearchKind.record,
        ref: '$refPrefix${n.id}',
        title: n.item,
        subtitle: n.place,
        body: n.detail,
      );

  /// Every word must match the start of a word in the item, place or detail.
  List<WhereNote> search(String q) {
    if (q.trim().isEmpty) {
      return all;
    }
    final List<WhereNote> list = all;
    final Map<String, WhereNote> byRef = <String, WhereNote>{for (final WhereNote n in list) '$refPrefix${n.id}': n};
    return SearchIndex(list.map(_doc).toList()).query(q).map((SearchResult r) => byRef[r.doc.ref]).whereType<WhereNote>().toList();
  }

  /// For One search (114).
  @override
  Future<List<SearchDoc>> collect() async => all.map(_doc).toList();

  // Undo keeps what each touched record looked like before, per store.
  final List<(FamilyStore, String, Map<String, Object?>?)> _undo = <(FamilyStore, String, Map<String, Object?>?)>[];

  void _remember(List<(FamilyStore, String)> touched) {
    _undo
      ..clear()
      ..addAll(touched.map(((FamilyStore, String) t) => (t.$1, t.$2, t.$1.get(collection, t.$2)?.fields)));
  }

  /// Null when the item or the place is empty.
  WhereNote? add({required String item, required String place, String detail = '', String? photo, bool shared = false}) {
    if (item.trim().isEmpty || place.trim().isEmpty) {
      return null;
    }
    final WhereNote n = WhereNote(
      id: 'wi${_now().microsecondsSinceEpoch}-${_seq++}',
      item: item.trim(),
      place: place.trim(),
      detail: detail.trim(),
      photo: photo,
      shared: shared && canShare,
      updated: _now(),
    );
    final FamilyStore s = _storeFor(n.shared);
    _remember(<(FamilyStore, String)>[(s, n.id)]);
    s.put(collection, n.id, n.toFields());
    notifyListeners();
    return n;
  }

  /// Moved it? Change where it is kept.
  bool edit(String id, {String? item, String? place, String? detail, String? photo, bool clearPhoto = false}) {
    final WhereNote? n = byId(id);
    if (n == null || (item != null && item.trim().isEmpty) || (place != null && place.trim().isEmpty)) {
      return false;
    }
    final WhereNote next = n.copyWith(item: item?.trim(), place: place?.trim(), detail: detail?.trim(), photo: photo, clearPhoto: clearPhoto, updated: _now());
    final FamilyStore s = _storeFor(n.shared);
    _remember(<(FamilyStore, String)>[(s, id)]);
    s.put(collection, id, next.toFields());
    notifyListeners();
    return true;
  }

  /// Moves a note between this phone and the family. False without a family.
  bool setShared(String id, bool shared) {
    final WhereNote? n = byId(id);
    if (n == null || (shared && !canShare) || n.shared == shared) {
      return false;
    }
    final FamilyStore from = _storeFor(n.shared), to = _storeFor(shared);
    _remember(<(FamilyStore, String)>[(from, id), (to, id)]);
    from.delete(collection, id);
    to.put(collection, id, n.copyWith(shared: shared).toFields());
    notifyListeners();
    return true;
  }

  bool remove(String id) {
    final WhereNote? n = byId(id);
    if (n == null) {
      return false;
    }
    final FamilyStore s = _storeFor(n.shared);
    _remember(<(FamilyStore, String)>[(s, id)]);
    s.delete(collection, id);
    notifyListeners();
    return true;
  }

  bool undo() {
    if (_undo.isEmpty) {
      return false;
    }
    for (final (FamilyStore, String, Map<String, Object?>?) u in _undo.reversed) {
      if (u.$3 == null) {
        u.$1.delete(collection, u.$2);
      } else {
        u.$1.put(collection, u.$2, u.$3!);
      }
    }
    _undo.clear();
    notifyListeners();
    return true;
  }

  static String noteText(WhereNote n) => '${n.item}: ${n.place}${n.detail.isEmpty ? '' : ' (${n.detail})'}';

  String toText([List<WhereNote>? list]) {
    final StringBuffer b = StringBuffer('Where is it\n');
    for (final WhereNote n in list ?? all) {
      b.write('- ${noteText(n)}${n.shared ? ' · shared' : ''}\n');
    }
    return b.toString();
  }

  static WhereIsIt instance = WhereIsIt();
  static void install(WhereIsIt w) => instance = w;
}
