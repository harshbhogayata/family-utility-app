import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../platform/one_search.dart';
import 'expense_tracker.dart';
import 'reports_vault.dart' show NoReportText, ReportTextReader;

/// Feature 085 — Receipt vault.
///
/// Receipt photos kept in the app's own folder with the shop, amount, date,
/// tags and the text read by on-device OCR. Full-text search over all of it
/// (the index of 114 One search), a link to an expense (080) and a warranty
/// period. Nothing is uploaded.

class Receipt {
  const Receipt({
    required this.id,
    required this.shop,
    required this.date,
    this.paise,
    this.photo,
    this.text = '',
    this.tags = const <String>[],
    this.expenseId,
    this.product = '',
    this.warrantyMonths,
  });

  final String id;
  final String shop;
  final DateTime date;

  /// Amount in paise, when known.
  final int? paise;

  /// The receipt photo in the app's folder.
  final String? photo;

  /// Text read from the photo on the phone.
  final String text;
  final List<String> tags;

  /// The expense this receipt was filed as, if any.
  final String? expenseId;

  /// What the warranty covers, and for how long.
  final String product;
  final int? warrantyMonths;

  DateTime? get warrantyEnds =>
      warrantyMonths == null ? null : DateTime(date.year, date.month + warrantyMonths!, date.day);

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'shop': shop,
        'date': date.toIso8601String(),
        if (paise != null) 'paise': paise,
        if (photo != null) 'photo': photo,
        if (text.isNotEmpty) 'text': text,
        'tags': tags,
        if (expenseId != null) 'expense': expenseId,
        if (product.isNotEmpty) 'product': product,
        if (warrantyMonths != null) 'warranty': warrantyMonths,
      };

  static Receipt fromJson(Map<String, Object?> j) {
    final Object? t = j['tags'];
    final Object? p = j['paise'];
    final Object? w = j['warranty'];
    return Receipt(
      id: '${j['id'] ?? ''}',
      shop: '${j['shop'] ?? ''}',
      date: DateTime.tryParse('${j['date'] ?? ''}') ?? DateTime(2000),
      paise: p is num ? p.toInt() : null,
      photo: j['photo'] as String?,
      text: '${j['text'] ?? ''}',
      tags: t is List ? t.whereType<String>().toList() : const <String>[],
      expenseId: j['expense'] as String?,
      product: '${j['product'] ?? ''}',
      warrantyMonths: w is num ? w.toInt() : null,
    );
  }

  Receipt copyWith({List<String>? tags, String? expenseId, String? product, int? warrantyMonths, bool clearWarranty = false}) => Receipt(
        id: id,
        shop: shop,
        date: date,
        paise: paise,
        photo: photo,
        text: text,
        tags: tags ?? this.tags,
        expenseId: expenseId ?? this.expenseId,
        product: clearWarranty ? '' : (product ?? this.product),
        warrantyMonths: clearWarranty ? null : (warrantyMonths ?? this.warrantyMonths),
      );
}

abstract interface class ReceiptStore {
  Future<List<Receipt>> load();
  Future<void> save(List<Receipt> all);
}

class MemoryReceiptStore implements ReceiptStore {
  List<Receipt> saved = <Receipt>[];
  @override
  Future<List<Receipt>> load() async => List<Receipt>.of(saved);
  @override
  Future<void> save(List<Receipt> all) async => saved = List<Receipt>.of(all);
}

class FileReceiptStore implements ReceiptStore {
  FileReceiptStore(this.folder);
  final Future<Directory> Function() folder;

  Future<File> _file() async {
    final Directory d = await folder();
    if (!await d.exists()) {
      await d.create(recursive: true);
    }
    return File('${d.path}/receipts.json');
  }

  @override
  Future<List<Receipt>> load() async {
    final File f = await _file();
    if (!await f.exists()) {
      return <Receipt>[];
    }
    final Object? j = jsonDecode(await f.readAsString());
    return j is List ? j.whereType<Map<String, Object?>>().map(Receipt.fromJson).toList() : <Receipt>[];
  }

  @override
  Future<void> save(List<Receipt> all) async {
    final File f = await _file();
    await f.writeAsString(jsonEncode(all.map((Receipt r) => r.toJson()).toList()), flush: true);
  }
}

/// What OCR suggests for a new receipt.
class ReceiptGuess {
  const ReceiptGuess({this.shop = '', this.paise, this.date});
  final String shop;
  final int? paise;
  final DateTime? date;
}

class ReceiptVault extends ChangeNotifier implements SearchSource {
  ReceiptVault({ReceiptStore? store, ReportTextReader reader = const NoReportText(), ExpenseTracker? expenses, DateTime Function()? now})
      : _store = store ?? MemoryReceiptStore(),
        _reader = reader,
        _expenses = expenses,
        _now = now ?? DateTime.now;

  final ReceiptStore _store;
  final ReportTextReader _reader;
  final ExpenseTracker? _expenses;
  final DateTime Function() _now;
  int _seq = 0;

  List<Receipt> _all = <Receipt>[];
  List<Receipt>? _undo;
  SearchIndex? _index;

  ExpenseTracker get expenses => _expenses ?? ExpenseTracker.instance;

  /// Newest first.
  List<Receipt> get all {
    final List<Receipt> l = List<Receipt>.of(_all);
    l.sort((Receipt a, Receipt b) => b.date.compareTo(a.date));
    return l;
  }

  Receipt? byId(String id) {
    for (final Receipt r in _all) {
      if (r.id == id) {
        return r;
      }
    }
    return null;
  }

  Future<void> load() async {
    try {
      _all = await _store.load();
    } catch (e) {
      debugPrint('receipts load: $e');
    }
    _index = null;
    notifyListeners();
  }

  void _set(List<Receipt> next) {
    _undo = List<Receipt>.of(_all);
    _all = next;
    _index = null;
    notifyListeners();
    unawaited(_store.save(List<Receipt>.of(_all)).catchError((Object e) => debugPrint('receipts save: $e')));
  }

  /// Reads the receipt on the phone and suggests shop, amount and date.
  Future<(String, ReceiptGuess)> read(Uint8List image) async {
    String text = '';
    try {
      text = await _reader.read(image);
    } catch (e) {
      debugPrint('receipt OCR: $e');
    }
    return (text, guess(text));
  }

  static final RegExp _money = RegExp(r'(?:₹|rs\.?|inr)?\s*(\d{1,3}(?:,\d{2,3})+(?:\.\d{1,2})?|\d+\.\d{1,2}|\d+)', caseSensitive: false);

  static ReceiptGuess guess(String text) {
    final List<String> lines = text.split(RegExp(r'[\r\n]+')).map((String l) => l.trim()).where((String l) => l.isNotEmpty).toList();
    String shop = '';
    for (final String l in lines) {
      if (RegExp(r'[A-Za-z]{3,}').hasMatch(l) && !RegExp(r'invoice|receipt|bill|gst|tax', caseSensitive: false).hasMatch(l)) {
        shop = l;
        break;
      }
    }
    int? paise;
    final RegExp total = RegExp(r'(grand\s*total|net\s*amount|total|amount\s*paid|amount)', caseSensitive: false);
    for (final String l in lines) {
      final RegExpMatch? t = total.firstMatch(l);
      if (t == null) {
        continue;
      }
      final Iterable<RegExpMatch> ms = _money.allMatches(l.substring(t.end));
      if (ms.isNotEmpty) {
        final int? v = parsePaise(ms.last.group(1)!);
        if (v != null && v > 0) {
          paise = v; // the last total line wins (grand total comes last)
        }
      }
    }
    DateTime? date;
    final RegExpMatch? d = RegExp(r'\b(\d{1,2})[/.\-](\d{1,2})[/.\-](\d{2,4})\b').firstMatch(text);
    if (d != null) {
      final int day = int.parse(d.group(1)!), month = int.parse(d.group(2)!);
      int year = int.parse(d.group(3)!);
      year = year < 100 ? 2000 + year : year;
      final DateTime x = DateTime(year, month, day);
      if (x.month == month && x.day == day) {
        date = x;
      }
    }
    return ReceiptGuess(shop: shop, paise: paise, date: date);
  }

  Receipt? add({required String shop, int? paise, DateTime? date, String? photo, String text = '', List<String> tags = const <String>[]}) {
    if (shop.trim().isEmpty && paise == null && photo == null) {
      return null;
    }
    final DateTime now = _now();
    final Receipt r = Receipt(
      id: 'r${now.microsecondsSinceEpoch}-${_seq++}',
      shop: shop.trim().isEmpty ? 'Receipt' : shop.trim(),
      date: date ?? DateTime(now.year, now.month, now.day),
      paise: paise,
      photo: photo,
      text: text,
      tags: cleanTags(tags),
    );
    _set(<Receipt>[..._all, r]);
    return r;
  }

  static List<String> cleanTags(Iterable<String> tags) {
    final List<String> out = <String>[];
    for (final String t in tags) {
      final String c = t.trim();
      if (c.isNotEmpty && !out.any((String o) => o.toLowerCase() == c.toLowerCase())) {
        out.add(c);
      }
    }
    return out;
  }

  bool _replace(String id, Receipt Function(Receipt) change) {
    if (byId(id) == null) {
      return false;
    }
    _set(<Receipt>[for (final Receipt r in _all) r.id == id ? change(r) : r]);
    return true;
  }

  bool setTags(String id, List<String> tags) => _replace(id, (Receipt r) => r.copyWith(tags: cleanTags(tags)));

  /// Files the receipt as an expense (once) and links the two.
  Expense? fileAsExpense(String id) {
    final Receipt? r = byId(id);
    if (r == null || r.paise == null || r.expenseId != null) {
      return null;
    }
    final Expense? e = expenses.add(
      paise: r.paise!,
      category: ExpenseTracker.guessCategory('${r.shop} ${r.tags.join(' ')}'),
      note: r.shop,
      photo: r.photo,
      at: r.date,
    );
    if (e == null) {
      return null;
    }
    _replace(id, (Receipt x) => x.copyWith(expenseId: e.id));
    return e;
  }

  /// Links a warranty for [months] from the receipt date; 0 clears it.
  bool setWarranty(String id, int months, {String product = ''}) {
    if (months < 0 || months > 240) {
      return false;
    }
    return _replace(id, (Receipt r) => months == 0 ? r.copyWith(clearWarranty: true) : r.copyWith(warrantyMonths: months, product: product.trim()));
  }

  /// Receipts whose warranty is still running, ending soonest first.
  List<Receipt> get underWarranty {
    final DateTime now = _now();
    final List<Receipt> l = _all.where((Receipt r) => r.warrantyEnds != null && r.warrantyEnds!.isAfter(now)).toList();
    l.sort((Receipt a, Receipt b) => a.warrantyEnds!.compareTo(b.warrantyEnds!));
    return l;
  }

  bool remove(String id) {
    if (byId(id) == null) {
      return false;
    }
    _set(_all.where((Receipt r) => r.id != id).toList());
    return true;
  }

  bool undo() {
    final List<Receipt>? u = _undo;
    if (u == null) {
      return false;
    }
    _undo = null;
    _all = u;
    _index = null;
    notifyListeners();
    unawaited(_store.save(List<Receipt>.of(_all)).catchError((Object e) => debugPrint('receipts save: $e')));
    return true;
  }

  static String amountLabel(int paise) => '₹${formatPaise(paise)}';

  static String dayLabel(DateTime d) => '${d.day} ${ReceiptMonths.names[d.month - 1]} ${d.year}';

  SearchDoc _doc(Receipt r) => SearchDoc(
        kind: SearchKind.file,
        ref: r.photo ?? r.id,
        title: r.shop,
        subtitle: '${r.paise == null ? '' : '${amountLabel(r.paise!)} ${(r.paise! ~/ 100)} '}${dayLabel(r.date)} ${r.tags.join(' ')}',
        body: '${r.product} ${r.text}',
      );

  /// Full-text search over shop, amount, date, tags and the OCR text.
  List<Receipt> search(String q) {
    if (q.trim().isEmpty) {
      return all;
    }
    final List<Receipt> list = _all;
    final SearchIndex index = _index ??= SearchIndex(list.map(_doc).toList());
    final Map<String, Receipt> byRef = <String, Receipt>{for (final Receipt r in list) r.photo ?? r.id: r};
    return index.query(q).map((SearchResult s) => byRef[s.doc.ref]).whereType<Receipt>().toList();
  }

  /// Receipts with a photo, for One search (114); a hit opens the photo.
  @override
  Future<List<SearchDoc>> collect() async => <SearchDoc>[for (final Receipt r in _all) if (r.photo != null) _doc(r)];

  String toText(List<Receipt> list) {
    final StringBuffer b = StringBuffer('Receipts\n');
    for (final Receipt r in list) {
      b.write('- ${dayLabel(r.date)}: ${r.shop}${r.paise == null ? '' : ' · ${amountLabel(r.paise!)}'}');
      if (r.tags.isNotEmpty) {
        b.write(' · ${r.tags.join(', ')}');
      }
      if (r.warrantyEnds != null) {
        b.write(' · warranty${r.product.isEmpty ? '' : ' (${r.product})'} till ${dayLabel(r.warrantyEnds!)}');
      }
      b.write('\n');
    }
    return b.toString();
  }

  static ReceiptVault instance = ReceiptVault();
  static void install(ReceiptVault v) => instance = v;
}

/// Short month names.
class ReceiptMonths {
  static const List<String> names = <String>['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
}
