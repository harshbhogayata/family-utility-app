import 'package:flutter/foundation.dart';

import 'family_space.dart';
import 'family_store.dart';

/// Feature 072 — Shared shopping list.
///
/// Items live in the family store's `shopping` collection, so a tick made
/// at the shop shows on every family phone (Wi-Fi or own folder), with who
/// added and who ticked it. Nothing leaves the family's phones.

@immutable
class ShoppingItem {
  const ShoppingItem({
    required this.id,
    required this.name,
    required this.quantity,
    required this.aisle,
    required this.addedBy,
    required this.addedAt,
    this.tickedBy,
    this.tickedAt,
  });

  final String id;
  final String name;
  final String quantity;
  final String aisle;

  /// Member device ids and local times.
  final String addedBy;
  final DateTime addedAt;
  final String? tickedBy;
  final DateTime? tickedAt;

  bool get ticked => tickedBy != null;

  Map<String, Object?> toFields() => <String, Object?>{
        'name': name,
        if (quantity.isNotEmpty) 'qty': quantity,
        'aisle': aisle,
        'by': addedBy,
        'at': addedAt.toIso8601String(),
        if (tickedBy != null) 'tickedBy': tickedBy,
        if (tickedAt != null) 'tickedAt': tickedAt!.toIso8601String(),
      };

  static ShoppingItem fromRecord(FamilyRecord r) {
    final Map<String, Object?> f = r.fields;
    final Object? tb = f['tickedBy'];
    return ShoppingItem(
      id: r.id,
      name: '${f['name'] ?? ''}',
      quantity: '${f['qty'] ?? ''}',
      aisle: '${f['aisle'] ?? ShoppingAisles.other}',
      addedBy: '${f['by'] ?? r.writer}',
      addedAt: DateTime.tryParse('${f['at'] ?? ''}') ?? DateTime.fromMillisecondsSinceEpoch(r.wallMillis),
      tickedBy: tb is String ? tb : null,
      tickedAt: tb is String ? DateTime.tryParse('${f['tickedAt'] ?? ''}') : null,
    );
  }
}

/// Aisles in walking order, and a guess from the item's name.
abstract final class ShoppingAisles {
  static const String other = 'Other';

  static const Map<String, List<String>> words = <String, List<String>>{
    'Fruit & veg': <String>[
      'apple', 'banana', 'onion', 'potato', 'tomato', 'carrot', 'lemon', 'garlic', 'ginger', 'spinach', //
      'chilli', 'coriander', 'mango', 'orange', 'grape', 'cucumber', 'lettuce', 'fruit', 'veg', 'pea',
    ],
    'Dairy & eggs': <String>['milk', 'curd', 'yogurt', 'yoghurt', 'paneer', 'cheese', 'butter', 'ghee', 'egg', 'cream'],
    'Bakery': <String>['bread', 'bun', 'pav', 'cake', 'biscuit', 'cookie', 'rusk'],
    'Grains & staples': <String>[
      'rice', 'atta', 'flour', 'dal', 'lentil', 'sugar', 'salt', 'oil', 'pasta', 'oats', 'besan', 'poha', 'rava', //
    ],
    'Spices': <String>['masala', 'turmeric', 'haldi', 'jeera', 'cumin', 'pepper', 'spice', 'mustard'],
    'Snacks & drinks': <String>['tea', 'coffee', 'juice', 'chips', 'namkeen', 'chocolate', 'water', 'soda'],
    'Household': <String>['soap', 'detergent', 'shampoo', 'toothpaste', 'tissue', 'cleaner', 'brush', 'bulb', 'battery'],
  };

  static List<String> get order => <String>[...words.keys, other];

  static String guess(String name) {
    final String n = name.toLowerCase();
    for (final MapEntry<String, List<String>> e in words.entries) {
      for (final String w in e.value) {
        if (RegExp('\\b$w').hasMatch(n)) {
          return e.key;
        }
      }
    }
    return other;
  }
}

class SharedShoppingList extends ChangeNotifier {
  SharedShoppingList({FamilySpace? space, DateTime Function()? now})
      : _space = space,
        _now = now ?? DateTime.now;

  static const String collection = 'shopping';

  final FamilySpace? _space;
  final DateTime Function() _now;
  int _seq = 0;

  /// What the last change replaced, for Undo: record id to its old fields
  /// (null when it did not exist before).
  Map<String, Map<String, Object?>?>? _undo;

  FamilySpace get space => _space ?? FamilySpace.instance;
  FamilyStore get store => space.store;
  String get me => space.identity?.deviceId ?? 'local';
  bool get canUndo => _undo != null;

  List<ShoppingItem> get items => store.list(collection).map(ShoppingItem.fromRecord).toList();

  ShoppingItem? item(String id) {
    final FamilyRecord? r = store.get(collection, id);
    return r == null ? null : ShoppingItem.fromRecord(r);
  }

  /// Name of a member from the family's member list.
  String memberName(String id) {
    final FamilyRecord? r = store.get(FamilySpace.members, id);
    return r == null ? 'Someone' : '${r.fields['name'] ?? 'Someone'}';
  }

  /// Adds an item. A leading count in the name ("2 milk") becomes the
  /// quantity when [quantity] is empty. Null when the name is blank.
  ShoppingItem? add(String name, {String quantity = '', String? aisle}) {
    String n = name.trim();
    String q = quantity.trim();
    if (q.isEmpty) {
      final RegExpMatch? m = RegExp(r'^(\d+(?:\.\d+)?\s*(?:x|kg|g|l|ml|pcs|pack|packs|dozen)?)\s+(.+)$', caseSensitive: false)
          .firstMatch(n);
      if (m != null) {
        q = m.group(1)!.trim();
        n = m.group(2)!.trim();
      }
    }
    if (n.isEmpty) {
      return null;
    }
    final DateTime t = _now();
    final ShoppingItem it = ShoppingItem(
      id: '$me-${t.microsecondsSinceEpoch}-${_seq++}',
      name: n,
      quantity: q,
      aisle: (aisle == null || aisle.trim().isEmpty) ? ShoppingAisles.guess(n) : aisle.trim(),
      addedBy: me,
      addedAt: t,
    );
    _write(<String, Map<String, Object?>?>{it.id: it.toFields()});
    return it;
  }

  bool tick(String id) {
    final ShoppingItem? it = item(id);
    if (it == null || it.ticked) {
      return false;
    }
    final Map<String, Object?> f = Map<String, Object?>.of(it.toFields())
      ..['tickedBy'] = me
      ..['tickedAt'] = _now().toIso8601String();
    _write(<String, Map<String, Object?>?>{id: f});
    return true;
  }

  bool untick(String id) {
    final ShoppingItem? it = item(id);
    if (it == null || !it.ticked) {
      return false;
    }
    final Map<String, Object?> f = Map<String, Object?>.of(it.toFields())
      ..remove('tickedBy')
      ..remove('tickedAt');
    _write(<String, Map<String, Object?>?>{id: f});
    return true;
  }

  bool remove(String id) {
    if (item(id) == null) {
      return false;
    }
    _write(<String, Map<String, Object?>?>{id: null});
    return true;
  }

  /// Removes every ticked item; returns how many.
  int clearTicked() {
    final List<ShoppingItem> done = items.where((ShoppingItem i) => i.ticked).toList();
    if (done.isEmpty) {
      return 0;
    }
    _write(<String, Map<String, Object?>?>{for (final ShoppingItem i in done) i.id: null});
    return done.length;
  }

  bool undo() {
    final Map<String, Map<String, Object?>?>? u = _undo;
    if (u == null) {
      return false;
    }
    _undo = null;
    u.forEach(_set);
    notifyListeners();
    return true;
  }

  void _write(Map<String, Map<String, Object?>?> changes) {
    _undo = <String, Map<String, Object?>?>{
      for (final String id in changes.keys) id: store.get(collection, id)?.fields,
    };
    changes.forEach(_set);
    notifyListeners();
  }

  void _set(String id, Map<String, Object?>? fields) {
    if (fields == null) {
      store.delete(collection, id);
    } else {
      store.put(collection, id, fields);
    }
  }

  /// Items by aisle in walking order; in each aisle, still-to-buy first.
  List<MapEntry<String, List<ShoppingItem>>> grouped() {
    final Map<String, List<ShoppingItem>> by = <String, List<ShoppingItem>>{};
    for (final ShoppingItem i in items) {
      by.putIfAbsent(i.aisle, () => <ShoppingItem>[]).add(i);
    }
    final List<String> order = ShoppingAisles.order;
    final List<String> keys = by.keys.toList()
      ..sort((String a, String b) {
        int ia = order.indexOf(a);
        int ib = order.indexOf(b);
        ia = ia < 0 ? order.length - 1 : ia;
        ib = ib < 0 ? order.length - 1 : ib;
        return ia != ib ? ia.compareTo(ib) : a.compareTo(b);
      });
    return <MapEntry<String, List<ShoppingItem>>>[
      for (final String k in keys)
        MapEntry<String, List<ShoppingItem>>(
          k,
          by[k]!..sort((ShoppingItem a, ShoppingItem b) {
              if (a.ticked != b.ticked) {
                return a.ticked ? 1 : -1;
              }
              return a.addedAt.compareTo(b.addedAt);
            }),
        ),
    ];
  }

  /// The list as plain text, to share in a chat.
  String toText() {
    final StringBuffer b = StringBuffer('Shopping list\n');
    for (final MapEntry<String, List<ShoppingItem>> g in grouped()) {
      b.write('\n${g.key}\n');
      for (final ShoppingItem i in g.value) {
        b.write('${i.ticked ? '[x]' : '[ ]'} ${i.name}${i.quantity.isEmpty ? '' : ' (${i.quantity})'}\n');
      }
    }
    return b.toString();
  }

  static SharedShoppingList instance = SharedShoppingList();

  static void install(SharedShoppingList list) => instance = list;
}
