import 'package:flutter/foundation.dart';

import '../family/family_space.dart';
import '../family/family_store.dart';

/// Feature 100 — Loyalty cards.
///
/// A store card's barcode is scanned once on the phone (051's on-device
/// scanner), kept on the family store, and drawn again at full brightness at
/// the till. Works offline; nothing is uploaded.

/// The symbologies a store card uses. Names match what is stored.
enum CardFormat { code128, ean13, ean8, upcA, code39, itf, codabar, qr, pdf417, dataMatrix, aztec }

class LoyaltyCard {
  const LoyaltyCard({
    required this.id,
    required this.store,
    required this.number,
    required this.format,
    this.note = '',
    this.uses = 0,
  });

  final String id;
  final String store;
  final String number;
  final CardFormat format;
  final String note;

  /// How many times it was shown at the till; most used float to the top.
  final int uses;

  bool get isLinear => format != CardFormat.qr && format != CardFormat.pdf417 && format != CardFormat.dataMatrix && format != CardFormat.aztec;

  Map<String, Object?> toFields() => <String, Object?>{
        'store': store,
        'number': number,
        'format': format.name,
        if (note.isNotEmpty) 'note': note,
        if (uses > 0) 'uses': uses,
      };

  static LoyaltyCard fromRecord(FamilyRecord r) {
    final Map<String, Object?> f = r.fields;
    final Object? u = f['uses'];
    return LoyaltyCard(
      id: r.id,
      store: '${f['store'] ?? ''}',
      number: '${f['number'] ?? ''}',
      format: LoyaltyCards.formatByName('${f['format'] ?? ''}') ?? CardFormat.code128,
      note: '${f['note'] ?? ''}',
      uses: u is num ? u.toInt() : 0,
    );
  }

  LoyaltyCard copyWith({String? store, String? number, CardFormat? format, String? note, int? uses}) => LoyaltyCard(
        id: id,
        store: store ?? this.store,
        number: number ?? this.number,
        format: format ?? this.format,
        note: note ?? this.note,
        uses: uses ?? this.uses,
      );
}

/// Turns the phone's window to full brightness while a card is shown.
abstract interface class ScreenBrightness {
  /// The window's level, 0..1, or null when the system decides.
  Future<double?> current();

  /// Null hands control back to the system.
  Future<void> set(double? level);
}

class NoScreenBrightness implements ScreenBrightness {
  const NoScreenBrightness();
  @override
  Future<double?> current() async => null;
  @override
  Future<void> set(double? level) async {}
}

class LoyaltyCards extends ChangeNotifier {
  LoyaltyCards({FamilySpace? space, FamilyStore? soloStore, DateTime Function()? now})
      : _space = space,
        _solo = soloStore,
        _now = now ?? DateTime.now;

  static const String collection = 'loyalty_cards';

  final FamilySpace? _space;
  final FamilyStore? _solo;
  final DateTime Function() _now;
  int _seq = 0;

  FamilySpace get space => _space ?? FamilySpace.instance;
  FamilyStore get store => space.inFamily ? space.store : (_solo ?? space.store);

  static CardFormat? formatByName(String name) {
    for (final CardFormat f in CardFormat.values) {
      if (f.name.toLowerCase() == name.trim().toLowerCase()) {
        return f;
      }
    }
    return null;
  }

  static String formatLabel(CardFormat f) => switch (f) {
        CardFormat.code128 => 'Code 128',
        CardFormat.ean13 => 'EAN-13',
        CardFormat.ean8 => 'EAN-8',
        CardFormat.upcA => 'UPC-A',
        CardFormat.code39 => 'Code 39',
        CardFormat.itf => 'ITF',
        CardFormat.codabar => 'Codabar',
        CardFormat.qr => 'QR code',
        CardFormat.pdf417 => 'PDF417',
        CardFormat.dataMatrix => 'Data Matrix',
        CardFormat.aztec => 'Aztec',
      };

  /// Most used first, then by store name.
  List<LoyaltyCard> get all {
    final List<LoyaltyCard> l = store.list(collection).map(LoyaltyCard.fromRecord).toList();
    l.sort((LoyaltyCard a, LoyaltyCard b) {
      final int c = b.uses.compareTo(a.uses);
      return c != 0 ? c : a.store.toLowerCase().compareTo(b.store.toLowerCase());
    });
    return l;
  }

  List<LoyaltyCard> search(String q) {
    final String s = q.trim().toLowerCase();
    if (s.isEmpty) {
      return all;
    }
    return all.where((LoyaltyCard c) => c.store.toLowerCase().contains(s) || c.number.contains(s) || c.note.toLowerCase().contains(s)).toList();
  }

  LoyaltyCard? byId(String id) {
    final FamilyRecord? r = store.get(collection, id);
    return r == null ? null : LoyaltyCard.fromRecord(r);
  }

  /// GS1 mod-10 check digit over [digits] (without the check digit).
  static int checkDigit(String digits) {
    int sum = 0;
    for (int i = 0; i < digits.length; i++) {
      final int d = digits.codeUnitAt(digits.length - 1 - i) - 48;
      sum += i.isEven ? d * 3 : d;
    }
    return (10 - sum % 10) % 10;
  }

  static final RegExp _digits = RegExp(r'^\d+$');

  /// Normalises a typed or scanned number for [f]; null when it cannot be
  /// drawn in that format. EAN/UPC numbers typed without their check digit
  /// get it added; a wrong check digit is refused.
  static String? normalise(String raw, CardFormat f) {
    final String t = raw.trim();
    if (t.isEmpty) {
      return null;
    }
    final String compact = t.replaceAll(RegExp(r'[\s-]'), '');
    String? gs1(int len) {
      if (!_digits.hasMatch(compact)) {
        return null;
      }
      if (compact.length == len - 1) {
        return '$compact${checkDigit(compact)}';
      }
      if (compact.length == len && checkDigit(compact.substring(0, len - 1)) == compact.codeUnitAt(len - 1) - 48) {
        return compact;
      }
      return null;
    }

    switch (f) {
      case CardFormat.ean13:
        return gs1(13);
      case CardFormat.ean8:
        return gs1(8);
      case CardFormat.upcA:
        return gs1(12);
      case CardFormat.itf:
        return _digits.hasMatch(compact) && compact.length.isEven ? compact : null;
      case CardFormat.codabar:
        return RegExp(r'^[0-9\-\$:/.+]+$').hasMatch(compact) ? compact : null;
      case CardFormat.code39:
        final String u = t.toUpperCase();
        return RegExp(r'^[0-9A-Z \-.\$/+%]+$').hasMatch(u) ? u : null;
      case CardFormat.code128:
        return t.codeUnits.every((int c) => c >= 32 && c < 127) ? t : null;
      case CardFormat.qr:
      case CardFormat.pdf417:
      case CardFormat.dataMatrix:
      case CardFormat.aztec:
        return t;
    }
  }

  /// A sensible format for a number typed by hand.
  static CardFormat guessFormat(String raw) {
    final String c = raw.trim().replaceAll(RegExp(r'[\s-]'), '');
    if (_digits.hasMatch(c)) {
      if (c.length == 13 && normalise(c, CardFormat.ean13) != null) {
        return CardFormat.ean13;
      }
      if (c.length == 12 && normalise(c, CardFormat.upcA) != null) {
        return CardFormat.upcA;
      }
      if (c.length == 8 && normalise(c, CardFormat.ean8) != null) {
        return CardFormat.ean8;
      }
    }
    return CardFormat.code128;
  }

  final List<(String, Map<String, Object?>?)> _undo = <(String, Map<String, Object?>?)>[];

  void _remember(String id) {
    _undo
      ..clear()
      ..add((id, store.get(collection, id)?.fields));
  }

  /// Null when the store name is empty or the number does not fit [format].
  LoyaltyCard? add({required String storeName, required String number, CardFormat? format, String note = ''}) {
    final CardFormat f = format ?? guessFormat(number);
    final String? n = normalise(number, f);
    if (storeName.trim().isEmpty || n == null) {
      return null;
    }
    final String id = 'lc${_now().microsecondsSinceEpoch}-${_seq++}';
    final LoyaltyCard c = LoyaltyCard(id: id, store: storeName.trim(), number: n, format: f, note: note.trim());
    _remember(id);
    store.put(collection, id, c.toFields());
    notifyListeners();
    return c;
  }

  /// Counts a showing at the till. Not undoable; it only reorders.
  void markShown(String id) {
    final LoyaltyCard? c = byId(id);
    if (c == null) {
      return;
    }
    store.put(collection, id, c.copyWith(uses: c.uses + 1).toFields());
    notifyListeners();
  }

  bool rename(String id, String storeName) {
    final LoyaltyCard? c = byId(id);
    if (c == null || storeName.trim().isEmpty) {
      return false;
    }
    _remember(id);
    store.put(collection, id, c.copyWith(store: storeName.trim()).toFields());
    notifyListeners();
    return true;
  }

  bool remove(String id) {
    if (byId(id) == null) {
      return false;
    }
    _remember(id);
    store.delete(collection, id);
    notifyListeners();
    return true;
  }

  bool undo() {
    if (_undo.isEmpty) {
      return false;
    }
    for (final (String, Map<String, Object?>?) u in _undo) {
      if (u.$2 == null) {
        store.delete(collection, u.$1);
      } else {
        store.put(collection, u.$1, u.$2!);
      }
    }
    _undo.clear();
    notifyListeners();
    return true;
  }

  static String cardText(LoyaltyCard c) =>
      '${c.store}: ${c.number} (${formatLabel(c.format)})${c.note.isEmpty ? '' : ' · ${c.note}'}';

  String toText() {
    final StringBuffer b = StringBuffer('Loyalty cards\n');
    for (final LoyaltyCard c in all) {
      b.write('- ${cardText(c)}\n');
    }
    return b.toString();
  }

  static LoyaltyCards instance = LoyaltyCards();
  static void install(LoyaltyCards c) => instance = c;
}
