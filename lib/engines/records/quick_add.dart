import 'expense_tracker.dart';

/// Feature 121 — Quick-add.
///
/// Reads one line in English or Hinglish — "paid 350 milk", "kal Ramesh ko
/// 500 diye", "2k rent on 1/11" — into amount, item, person and date. The
/// screen shows the result and only saves it to the expense ledger (080)
/// after the person confirms.

class QuickEntry {
  const QuickEntry({required this.paise, required this.item, required this.category, required this.date, this.person});

  final int paise;
  final String item;
  final String category;
  final DateTime date;
  final String? person;

  /// The ledger note: item, and who it went to.
  String get note => person == null ? item : (item.isEmpty ? 'To $person' : '$item — $person');
}

class QuickAddParser {
  QuickAddParser({DateTime Function()? now}) : _now = now ?? DateTime.now;

  final DateTime Function() _now;

  static const Set<String> _filler = <String>{
    'paid', 'pay', 'payed', 'gave', 'give', 'given', 'spent', 'spend', 'bought', 'buy', 'got', 'for', 'on', 'to', 'of', //
    'rs', 'rs.', 'inr', 'rupees', 'rupee', 'rupaye', 'rupay', '₹', '/-', 'the', 'a', 'an', 'and',
    'diya', 'diye', 'di', 'de', 'liya', 'liye', 'li', 'kharcha', 'kharch', 'kharche', 'ka', 'ke', 'ki', 'ko',
    'mein', 'me', 'se', 'wala', 'wale', 'kiya', 'kiye', 'bhara', 'bhare',
  };

  /// Hinglish and common words first; then the ledger's own guess.
  static const Map<String, String> _hinglish = <String, String>{
    'doodh': 'Groceries', 'dudh': 'Groceries', 'sabzi': 'Groceries', 'sabji': 'Groceries', 'kirana': 'Groceries',
    'atta': 'Groceries', 'chawal': 'Groceries', 'anda': 'Groceries', 'ande': 'Groceries', 'phal': 'Groceries',
    'khana': 'Food', 'chai': 'Food', 'nashta': 'Food', 'samosa': 'Food',
    'kiraya': 'Bills', 'bijli': 'Bills', 'paani': 'Bills', 'pani': 'Bills', 'cylinder': 'Bills',
    'dawai': 'Health', 'dawa': 'Health', 'dava': 'Health', 'davai': 'Health',
    'kapde': 'Shopping', 'kapda': 'Shopping', 'joote': 'Shopping',
    'rickshaw': 'Transport', 'auto': 'Transport', 'bhada': 'Transport', 'kiraaya': 'Bills',
    'kitab': 'Education', 'kitaben': 'Education', 'fees': 'Education', 'fee': 'Education',
    'kaamwali': 'Home', 'bai': 'Home', 'safai': 'Home', 'dhobi': 'Home', 'istri': 'Home',
  };

  static const List<String> _months = <String>[
    'january', 'february', 'march', 'april', 'may', 'june', //
    'july', 'august', 'september', 'october', 'november', 'december',
  ];
  static const List<String> _days = <String>['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday'];

  static String categoryFor(String item) {
    for (final String w in item.toLowerCase().split(RegExp(r'[^a-z]+'))) {
      final String? c = _hinglish[w];
      if (c != null) {
        return c;
      }
    }
    return ExpenseTracker.guessCategory(item);
  }

  /// "350", "₹350", "350rs", "350/-", "1,200.50", "2k", "1.5k".
  static int? amountOf(String token) {
    String t = token.toLowerCase().replaceAll(RegExp(r'(/-|rs\.?|₹|inr|rupees|rupaye)'), '').trim();
    int mult = 1;
    if (t.endsWith('k')) {
      mult = 1000;
      t = t.substring(0, t.length - 1);
    }
    if (!RegExp(r'^\d[\d,]*(\.\d{1,2})?$').hasMatch(t)) {
      return null;
    }
    final double? v = double.tryParse(t.replaceAll(',', ''));
    if (v == null) {
      return null;
    }
    return (v * mult * 100).round();
  }

  int? _monthOf(String w) {
    if (w.length < 3) {
      return null;
    }
    final int i = _months.indexWhere((String m) => m.startsWith(w));
    return i < 0 ? null : i + 1;
  }

  /// The most recent date with this day and month, not in the future.
  DateTime _pastDate(int day, int month, int? year) {
    final DateTime today = _today;
    if (year != null) {
      return DateTime(year < 100 ? 2000 + year : year, month, day);
    }
    final DateTime d = DateTime(today.year, month, day);
    return d.isAfter(today) ? DateTime(today.year - 1, month, day) : d;
  }

  DateTime get _today {
    final DateTime n = _now();
    return DateTime(n.year, n.month, n.day);
  }

  QuickEntry? parse(String text) {
    final List<String> raw = text.trim().split(RegExp(r'\s+')).where((String s) => s.isNotEmpty).toList();
    final List<String> low = raw.map((String s) => s.toLowerCase().replaceAll(RegExp(r'[,!?]$'), '')).toList();
    final List<bool> used = List<bool>.filled(raw.length, false);
    int? paise;
    DateTime? date;
    String? person;

    for (int i = 0; i < raw.length; i++) {
      final String w = low[i];
      if (paise == null) {
        final int? a = amountOf(w);
        if (a != null && !(i + 1 < raw.length && _monthOf(low[i + 1]) != null && a < 3200)) {
          paise = a;
          used[i] = true;
          continue;
        }
      }
      if (date == null) {
        if (w == 'today' || w == 'aaj') {
          date = _today;
          used[i] = true;
          continue;
        }
        if (w == 'yesterday' || w == 'kal') {
          date = _today.subtract(const Duration(days: 1));
          used[i] = true;
          continue;
        }
        if (w == 'parso' || w == 'parson') {
          date = _today.subtract(const Duration(days: 2));
          used[i] = true;
          continue;
        }
        final RegExpMatch? dm = RegExp(r'^(\d{1,2})[/\-.](\d{1,2})(?:[/\-.](\d{2,4}))?$').firstMatch(w);
        if (dm != null) {
          final int d = int.parse(dm.group(1)!);
          final int m = int.parse(dm.group(2)!);
          if (d >= 1 && d <= 31 && m >= 1 && m <= 12) {
            date = _pastDate(d, m, dm.group(3) == null ? null : int.parse(dm.group(3)!));
            used[i] = true;
            continue;
          }
        }
        // "5 march" or "march 5"
        final RegExpMatch? dn = RegExp(r'^(\d{1,2})(st|nd|rd|th)?$').firstMatch(w);
        if (dn != null && i + 1 < raw.length && _monthOf(low[i + 1]) != null) {
          date = _pastDate(int.parse(dn.group(1)!), _monthOf(low[i + 1])!, null);
          used[i] = true;
          used[i + 1] = true;
          i++;
          continue;
        }
        final int? mo = _monthOf(w);
        if (mo != null && i + 1 < raw.length) {
          final RegExpMatch? dn2 = RegExp(r'^(\d{1,2})(st|nd|rd|th)?$').firstMatch(low[i + 1]);
          if (dn2 != null) {
            date = _pastDate(int.parse(dn2.group(1)!), mo, null);
            used[i] = true;
            used[i + 1] = true;
            i++;
            continue;
          }
        }
        final int wd = _days.indexWhere((String d) => w == d || (w.length >= 3 && d.startsWith(w) && w.length == 3));
        if (wd >= 0) {
          final DateTime t = _today;
          final int back = (t.weekday - (wd + 1)) % 7;
          date = t.subtract(Duration(days: back));
          used[i] = true;
          continue;
        }
      }
      if (person == null) {
        // "to Ramesh", "for Ramesh" (a name), "Ramesh ko"
        if ((w == 'to' || (w == 'for' && i + 1 < raw.length && _isName(raw[i + 1]))) &&
            i + 1 < raw.length &&
            !_filler.contains(low[i + 1]) &&
            amountOf(low[i + 1]) == null) {
          person = _clean(raw[i + 1]);
          used[i] = true;
          used[i + 1] = true;
          i++;
          continue;
        }
        if (i + 1 < raw.length && low[i + 1] == 'ko' && !_filler.contains(w) && amountOf(w) == null) {
          person = _clean(raw[i]);
          used[i] = true;
          used[i + 1] = true;
          i++;
          continue;
        }
      }
    }
    if (paise == null || paise <= 0) {
      return null;
    }
    final List<String> item = <String>[];
    for (int i = 0; i < raw.length; i++) {
      if (!used[i] && !_filler.contains(low[i])) {
        item.add(_clean(raw[i]));
      }
    }
    final String it = item.where((String s) => s.isNotEmpty).join(' ');
    return QuickEntry(
      paise: paise,
      item: it,
      category: categoryFor(it),
      date: date ?? _today,
      person: person == null || person.isEmpty ? null : _capital(person),
    );
  }

  static bool _isName(String s) => s.isNotEmpty && s[0].toUpperCase() == s[0] && RegExp(r'^[A-Za-z]').hasMatch(s);

  static String _clean(String s) => s.replaceAll(RegExp(r'[,!?.]+$'), '');

  static String _capital(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

  /// Saves a confirmed entry to the ledger, at the parsed date.
  static Expense? save(QuickEntry e, ExpenseTracker ledger, {DateTime Function()? now}) {
    final DateTime n = (now ?? DateTime.now)();
    final DateTime at = DateTime(e.date.year, e.date.month, e.date.day, n.hour, n.minute, n.second);
    return ledger.add(paise: e.paise, category: e.category, note: e.note, at: at);
  }
}
