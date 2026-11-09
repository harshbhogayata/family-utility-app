import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Feature 080 — Expense tracker.
///
/// Entries with amount, category, note and an optional receipt photo kept
/// in the app's own folder; month and category totals; CSV export; and
/// quick-add from a line of text like "450 groceries milk and eggs".
/// Everything stays on this phone.

class Expense {
  const Expense({
    required this.id,
    required this.paise,
    required this.category,
    required this.at,
    this.note = '',
    this.photo,
  });

  final String id;

  /// Amount in the smallest unit (paise), so totals never drift.
  final int paise;
  final String category;
  final DateTime at;
  final String note;

  /// Path of the receipt photo in the app's folder, if any.
  final String? photo;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'paise': paise,
        'category': category,
        'at': at.millisecondsSinceEpoch,
        'note': note,
        if (photo != null) 'photo': photo,
      };

  static Expense? fromJson(Map<String, Object?> j) {
    final Object? id = j['id'];
    final Object? p = j['paise'];
    final Object? at = j['at'];
    if (id is! String || p is! num || at is! num) {
      return null;
    }
    return Expense(
      id: id,
      paise: p.toInt(),
      category: '${j['category'] ?? ExpenseTracker.other}',
      at: DateTime.fromMillisecondsSinceEpoch(at.toInt()),
      note: '${j['note'] ?? ''}',
      photo: j['photo'] as String?,
    );
  }
}

/// "1,234.50" for 123450 paise.
String formatPaise(int paise) {
  final bool neg = paise < 0;
  final int a = paise.abs();
  final String rupees = (a ~/ 100).toString();
  final StringBuffer b = StringBuffer();
  for (int i = 0; i < rupees.length; i++) {
    if (i > 0 && (rupees.length - i) % 3 == 0) {
      b.write(',');
    }
    b.write(rupees[i]);
  }
  final int p = a % 100;
  return '${neg ? '-' : ''}$b${p == 0 ? '' : '.${p.toString().padLeft(2, '0')}'}';
}

/// Parses "1,200.5", "₹99" or "Rs 40" into paise; null if not an amount.
int? parsePaise(String text) {
  final String t = text.replaceAll(RegExp(r'(₹|rs\.?|inr)', caseSensitive: false), '').replaceAll(',', '').trim();
  final RegExpMatch? m = RegExp(r'^(\d+)(?:\.(\d{1,2}))?$').firstMatch(t);
  if (m == null) {
    return null;
  }
  final String frac = (m.group(2) ?? '').padRight(2, '0');
  return int.parse(m.group(1)!) * 100 + (frac.isEmpty ? 0 : int.parse(frac));
}

abstract interface class ExpenseStore {
  Future<List<Expense>> load();
  Future<void> save(List<Expense> all);
}

class MemoryExpenseStore implements ExpenseStore {
  List<Expense> saved = <Expense>[];
  @override
  Future<List<Expense>> load() async => List<Expense>.of(saved);
  @override
  Future<void> save(List<Expense> all) async => saved = List<Expense>.of(all);
}

/// expenses.json in the app's private folder.
class FileExpenseStore implements ExpenseStore {
  FileExpenseStore(this.folder);
  final Future<Directory> Function() folder;

  Future<File> _file() async => File('${(await folder()).path}/expenses.json');

  @override
  Future<List<Expense>> load() async {
    final File f = await _file();
    if (!f.existsSync()) {
      return <Expense>[];
    }
    final Object? json = jsonDecode(await f.readAsString());
    if (json is! List) {
      return <Expense>[];
    }
    return json
        .whereType<Map>()
        .map((Map m) => Expense.fromJson(Map<String, Object?>.from(m)))
        .whereType<Expense>()
        .toList();
  }

  @override
  Future<void> save(List<Expense> all) async {
    final File f = await _file();
    await f.parent.create(recursive: true);
    final File tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode(all.map((Expense e) => e.toJson()).toList()));
    await tmp.rename(f.path);
  }
}

class ExpenseTracker extends ChangeNotifier {
  ExpenseTracker({ExpenseStore? store, DateTime Function()? now})
      : _store = store ?? MemoryExpenseStore(),
        _now = now ?? DateTime.now;

  static const String other = 'Other';

  /// Categories and the words quick-add maps to them.
  static const Map<String, List<String>> categories = <String, List<String>>{
    'Groceries': <String>['grocery', 'groceries', 'vegetables', 'veggies', 'milk', 'kirana', 'fruit', 'fruits'],
    'Food': <String>['food', 'lunch', 'dinner', 'breakfast', 'snacks', 'restaurant', 'swiggy', 'zomato', 'tea', 'coffee'],
    'Transport': <String>['auto', 'cab', 'taxi', 'uber', 'ola', 'bus', 'metro', 'train', 'travel', 'parking'],
    'Fuel': <String>['fuel', 'petrol', 'diesel', 'cng'],
    'Bills': <String>['bill', 'bills', 'electricity', 'water', 'gas', 'internet', 'wifi', 'recharge', 'mobile', 'rent'],
    'Health': <String>['medicine', 'medicines', 'doctor', 'pharmacy', 'chemist', 'hospital', 'lab'],
    'Shopping': <String>['shopping', 'clothes', 'shoes', 'amazon', 'flipkart', 'gift'],
    'Education': <String>['school', 'fees', 'books', 'tuition', 'stationery', 'course'],
    'Home': <String>['home', 'repair', 'maid', 'cleaning', 'furniture', 'plumber', 'electrician'],
    other: <String>[],
  };

  static List<String> get categoryNames => categories.keys.toList();

  final ExpenseStore _store;
  final DateTime Function() _now;
  final List<Expense> _all = <Expense>[];
  List<Expense>? _undo;
  bool _loaded = false;

  bool get loaded => _loaded;

  /// Every entry, newest first.
  List<Expense> get all => List<Expense>.unmodifiable(_all);

  Future<void> load() async {
    try {
      _all
        ..clear()
        ..addAll(await _store.load());
      _sort();
    } catch (e) {
      debugPrint('expenses load: $e');
    }
    _loaded = true;
    notifyListeners();
  }

  void _sort() => _all.sort((Expense a, Expense b) => b.at.compareTo(a.at));

  void _changed() {
    _sort();
    notifyListeners();
    unawaited(_store.save(List<Expense>.of(_all)).catchError((Object e) => debugPrint('expenses save: $e')));
  }

  int _seq = 0;

  Expense? add({required int paise, required String category, String note = '', String? photo, DateTime? at}) {
    if (paise <= 0) {
      return null;
    }
    final String cat = categories.containsKey(category) ? category : other;
    final Expense e = Expense(
      id: 'e${_now().microsecondsSinceEpoch}-${_seq++}',
      paise: paise,
      category: cat,
      at: at ?? _now(),
      note: note.trim(),
      photo: photo,
    );
    _undo = List<Expense>.of(_all);
    _all.add(e);
    _changed();
    return e;
  }

  bool remove(String id) {
    final int i = _all.indexWhere((Expense e) => e.id == id);
    if (i < 0) {
      return false;
    }
    _undo = List<Expense>.of(_all);
    _all.removeAt(i);
    _changed();
    return true;
  }

  bool undo() {
    final List<Expense>? u = _undo;
    if (u == null) {
      return false;
    }
    _undo = null;
    _all
      ..clear()
      ..addAll(u);
    _changed();
    return true;
  }

  /// Guesses the category from words in [text].
  static String guessCategory(String text) {
    final List<String> words = text.toLowerCase().split(RegExp(r'[^a-z]+'));
    for (final MapEntry<String, List<String>> c in categories.entries) {
      if (words.contains(c.key.toLowerCase()) || c.value.any(words.contains)) {
        return c.key;
      }
    }
    return other;
  }

  /// Reads "450 groceries milk", "petrol 500" or "₹1,200 school fees".
  static ({int paise, String category, String note})? parseQuick(String text) {
    final List<String> parts = text.trim().split(RegExp(r'\s+'));
    int? paise;
    final List<String> rest = <String>[];
    for (final String p in parts) {
      final int? v = paise == null ? parsePaise(p) : null;
      if (v != null) {
        paise = v;
      } else if (p.isNotEmpty && !RegExp(r'^(₹|rs\.?|inr)$', caseSensitive: false).hasMatch(p)) {
        rest.add(p);
      }
    }
    if (paise == null || paise <= 0) {
      return null;
    }
    final String note = rest.join(' ');
    return (paise: paise, category: guessCategory(note), note: note);
  }

  Expense? quickAdd(String text) {
    final ({int paise, String category, String note})? q = parseQuick(text);
    return q == null ? null : add(paise: q.paise, category: q.category, note: q.note);
  }

  List<Expense> inMonth(int year, int month) =>
      _all.where((Expense e) => e.at.year == year && e.at.month == month).toList();

  int monthTotal(int year, int month) => inMonth(year, month).fold<int>(0, (int s, Expense e) => s + e.paise);

  /// Category totals for a month, largest first.
  List<MapEntry<String, int>> categoryTotals(int year, int month) {
    final Map<String, int> t = <String, int>{};
    for (final Expense e in inMonth(year, month)) {
      t[e.category] = (t[e.category] ?? 0) + e.paise;
    }
    final List<MapEntry<String, int>> out = t.entries.toList()
      ..sort((MapEntry<String, int> a, MapEntry<String, int> b) => b.value.compareTo(a.value));
    return out;
  }

  static String _csvCell(String s) =>
      s.contains(RegExp(r'[",\n\r]')) ? '"${s.replaceAll('"', '""')}"' : s;

  /// CSV of one month (or everything when [year] is null), oldest first.
  String toCsv({int? year, int? month}) {
    final List<Expense> rows = (year == null || month == null ? List<Expense>.of(_all) : inMonth(year, month)).reversed.toList();
    final StringBuffer b = StringBuffer('Date,Amount,Category,Note,Receipt\r\n');
    for (final Expense e in rows) {
      final String d =
          '${e.at.year}-${e.at.month.toString().padLeft(2, '0')}-${e.at.day.toString().padLeft(2, '0')}';
      final String amt = '${e.paise ~/ 100}.${(e.paise % 100).toString().padLeft(2, '0')}';
      final String receipt = e.photo == null ? '' : e.photo!.split(RegExp(r'[/\\]')).last;
      b.write('$d,$amt,${_csvCell(e.category)},${_csvCell(e.note)},${_csvCell(receipt)}\r\n');
    }
    return b.toString();
  }

  static ExpenseTracker instance = ExpenseTracker();
  static void install(ExpenseTracker t) => instance = t;
}
