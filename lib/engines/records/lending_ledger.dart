import 'dart:async';

import 'package:flutter/foundation.dart';

import '../family/family_store.dart';
import 'expense_tracker.dart' show formatPaise;

/// Feature 082 — Lending ledger.
///
/// Money lent to and borrowed from people: who, amount, date, an optional
/// due date and a status worked out from the repayments (open, part repaid,
/// settled). Reminders the day before and on the due date, and the next
/// morning while it stays overdue. Kept in this phone's own store; nothing
/// is uploaded or shared with the family.

enum LendDirection {
  lent('Lent', 'owes you'),
  borrowed('Borrowed', 'you owe');

  const LendDirection(this.label, this.owesPhrase);
  final String label;
  final String owesPhrase;

  static LendDirection byName(Object? n) =>
      LendDirection.values.firstWhere((LendDirection d) => d.name == n, orElse: () => LendDirection.lent);
}

enum LendStatus {
  open('Open'),
  partlyRepaid('Part repaid'),
  settled('Settled');

  const LendStatus(this.label);
  final String label;
}

class Repayment {
  const Repayment({required this.on, required this.paise});

  final DateTime on;
  final int paise;

  Map<String, Object?> toJson() => <String, Object?>{'on': on.toIso8601String(), 'paise': paise};

  static Repayment? fromJson(Object? o) {
    if (o is! Map) {
      return null;
    }
    final DateTime? on = DateTime.tryParse('${o['on'] ?? ''}');
    final Object? p = o['paise'];
    if (on == null || p is! num || p <= 0) {
      return null;
    }
    return Repayment(on: on, paise: p.toInt());
  }
}

class LendEntry {
  const LendEntry({
    required this.id,
    required this.direction,
    required this.who,
    required this.paise,
    required this.date,
    this.due,
    this.note = '',
    this.repayments = const <Repayment>[],
  });

  final String id;
  final LendDirection direction;
  final String who;
  final int paise;
  final DateTime date;
  final DateTime? due;
  final String note;

  /// Oldest first.
  final List<Repayment> repayments;

  int get repaid => repayments.fold<int>(0, (int s, Repayment r) => s + r.paise);
  int get remaining => paise - repaid < 0 ? 0 : paise - repaid;

  LendStatus get status => remaining == 0 ? LendStatus.settled : (repaid > 0 ? LendStatus.partlyRepaid : LendStatus.open);

  Map<String, Object?> toFields() => <String, Object?>{
        'dir': direction.name,
        'who': who,
        'paise': paise,
        'date': date.toIso8601String(),
        if (due != null) 'due': due!.toIso8601String(),
        if (note.isNotEmpty) 'note': note,
        'repaid': repayments.map((Repayment r) => r.toJson()).toList(),
      };

  static LendEntry fromRecord(FamilyRecord r) {
    final Map<String, Object?> f = r.fields;
    final Object? p = f['paise'];
    final Object? rep = f['repaid'];
    return LendEntry(
      id: r.id,
      direction: LendDirection.byName(f['dir']),
      who: '${f['who'] ?? ''}',
      paise: p is num ? p.toInt() : 0,
      date: DateTime.tryParse('${f['date'] ?? ''}') ?? DateTime(2000),
      due: f['due'] == null ? null : DateTime.tryParse('${f['due']}'),
      note: '${f['note'] ?? ''}',
      repayments: rep is List ? rep.map(Repayment.fromJson).whereType<Repayment>().toList() : const <Repayment>[],
    );
  }

  LendEntry withRepayments(List<Repayment> list) => LendEntry(
        id: id,
        direction: direction,
        who: who,
        paise: paise,
        date: date,
        due: due,
        note: note,
        repayments: list,
      );
}

class LendReminder {
  const LendReminder({required this.id, required this.at, required this.title, required this.body, required this.payload});
  final int id;
  final DateTime at;
  final String title;
  final String body;
  final String payload;
}

abstract interface class LendReminderScheduler {
  Future<void> replaceAll(List<LendReminder> reminders);
}

class NoLendReminders implements LendReminderScheduler {
  const NoLendReminders();
  @override
  Future<void> replaceAll(List<LendReminder> reminders) async {}
}

/// Net position with one person: positive means they owe you.
class PersonBalance {
  const PersonBalance(this.who, this.netPaise);
  final String who;
  final int netPaise;
}

class LendingLedger extends ChangeNotifier {
  LendingLedger({
    FamilyStore? store,
    LendReminderScheduler reminders = const NoLendReminders(),
    DateTime Function()? now,
    this.remindHour = 9,
  })  : store = store ?? FamilyStore(deviceId: 'me'),
        _scheduler = reminders,
        _now = now ?? DateTime.now;

  static const String collection = 'lending';
  static const String payloadPrefix = 'lend:';
  static const int idBase = 9000000;

  final FamilyStore store;
  final LendReminderScheduler _scheduler;
  final DateTime Function() _now;
  final int remindHour;
  int _seq = 0;

  /// Open entries first (soonest due, then newest), settled ones last.
  List<LendEntry> get all {
    final List<LendEntry> l = store.list(collection).map(LendEntry.fromRecord).toList();
    int rank(LendEntry e) => e.status == LendStatus.settled ? 1 : 0;
    l.sort((LendEntry a, LendEntry b) {
      final int r = rank(a).compareTo(rank(b));
      if (r != 0) {
        return r;
      }
      if (a.due != null || b.due != null) {
        if (a.due == null) {
          return 1;
        }
        if (b.due == null) {
          return -1;
        }
        final int c = a.due!.compareTo(b.due!);
        if (c != 0) {
          return c;
        }
      }
      final int d = b.date.compareTo(a.date);
      return d != 0 ? d : a.who.compareTo(b.who);
    });
    return l;
  }

  LendEntry? byId(String id) {
    final FamilyRecord? r = store.get(collection, id);
    return r == null ? null : LendEntry.fromRecord(r);
  }

  (String, Map<String, Object?>?)? _undo;

  void _remember(String id) => _undo = (id, store.get(collection, id)?.fields);

  void _changed() {
    notifyListeners();
    unawaited(reschedule());
  }

  DateTime _today() {
    final DateTime n = _now();
    return DateTime(n.year, n.month, n.day);
  }

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  LendEntry? add({
    required LendDirection direction,
    required String who,
    required int paise,
    DateTime? date,
    DateTime? due,
    String note = '',
  }) {
    final String name = who.trim();
    final DateTime on = _day(date ?? _today());
    if (name.isEmpty || paise <= 0 || (due != null && _day(due).isBefore(on))) {
      return null;
    }
    final String id = 'l${_now().microsecondsSinceEpoch}-${_seq++}';
    final LendEntry e = LendEntry(
      id: id,
      direction: direction,
      who: name,
      paise: paise,
      date: on,
      due: due == null ? null : _day(due),
      note: note.trim(),
    );
    _remember(id);
    store.put(collection, id, e.toFields());
    _changed();
    return e;
  }

  /// Records money paid back; capped at what is still owed.
  bool repay(String id, int paise, {DateTime? on}) {
    final LendEntry? e = byId(id);
    if (e == null || paise <= 0 || e.remaining == 0) {
      return false;
    }
    final int amount = paise > e.remaining ? e.remaining : paise;
    _remember(id);
    store.put(
      collection,
      id,
      e.withRepayments(<Repayment>[...e.repayments, Repayment(on: _day(on ?? _today()), paise: amount)]).toFields(),
    );
    _changed();
    return true;
  }

  /// Marks the whole remainder as paid back.
  bool settle(String id, {DateTime? on}) {
    final LendEntry? e = byId(id);
    return e != null && repay(id, e.remaining, on: on);
  }

  bool remove(String id) {
    if (byId(id) == null) {
      return false;
    }
    _remember(id);
    store.delete(collection, id);
    _changed();
    return true;
  }

  bool undo() {
    final (String, Map<String, Object?>?)? u = _undo;
    if (u == null) {
      return false;
    }
    _undo = null;
    if (u.$2 == null) {
      store.delete(collection, u.$1);
    } else {
      store.put(collection, u.$1, u.$2!);
    }
    _changed();
    return true;
  }

  /// Days until the due date; null when there is none.
  int? daysUntil(LendEntry e) {
    if (e.due == null) {
      return null;
    }
    final DateTime t = _today();
    return DateTime.utc(e.due!.year, e.due!.month, e.due!.day).difference(DateTime.utc(t.year, t.month, t.day)).inDays;
  }

  bool isOverdue(LendEntry e) {
    final int? d = daysUntil(e);
    return e.status != LendStatus.settled && d != null && d < 0;
  }

  /// Total still owed to you and by you across open entries.
  (int, int) totals() {
    int toYou = 0, byYou = 0;
    for (final LendEntry e in all) {
      if (e.direction == LendDirection.lent) {
        toYou += e.remaining;
      } else {
        byYou += e.remaining;
      }
    }
    return (toYou, byYou);
  }

  /// Net per person (names matched ignoring case), largest first; settled
  /// people are left out.
  List<PersonBalance> balances() {
    final Map<String, int> net = <String, int>{};
    final Map<String, String> shown = <String, String>{};
    for (final LendEntry e in all) {
      final String key = e.who.toLowerCase();
      shown.putIfAbsent(key, () => e.who);
      net[key] = (net[key] ?? 0) + (e.direction == LendDirection.lent ? e.remaining : -e.remaining);
    }
    final List<PersonBalance> out = <PersonBalance>[
      for (final MapEntry<String, int> m in net.entries)
        if (m.value != 0) PersonBalance(shown[m.key]!, m.value),
    ];
    out.sort((PersonBalance a, PersonBalance b) {
      final int c = b.netPaise.abs().compareTo(a.netPaise.abs());
      return c != 0 ? c : a.who.compareTo(b.who);
    });
    return out;
  }

  static int _id(String key) {
    int h = 0;
    for (final int c in key.codeUnits) {
      h = (h * 31 + c) & 0x3FFFF;
    }
    return idBase + h;
  }

  static String amountLabel(int paise) => '₹${formatPaise(paise)}';

  static String headline(LendEntry e) => e.direction == LendDirection.lent
      ? '${e.who} owes you ${amountLabel(e.remaining)}'
      : 'You owe ${e.who} ${amountLabel(e.remaining)}';

  /// The day before and on the due date; tomorrow morning while overdue.
  List<LendReminder> reminders() {
    final DateTime now = _now();
    final DateTime today = _today();
    final List<LendReminder> out = <LendReminder>[];
    for (final LendEntry e in all) {
      if (e.due == null || e.status == LendStatus.settled) {
        continue;
      }
      final DateTime d = e.due!;
      final List<(DateTime, String)> times = isOverdue(e)
          ? <(DateTime, String)>[(DateTime(today.year, today.month, today.day + 1, remindHour), 'overdue')]
          : <(DateTime, String)>[
              (DateTime(d.year, d.month, d.day - 1, remindHour), 'due tomorrow'),
              (DateTime(d.year, d.month, d.day, remindHour), 'due today'),
            ];
      for (final (DateTime, String) t in times) {
        if (!t.$1.isAfter(now)) {
          continue;
        }
        out.add(LendReminder(
          id: _id('${e.id}@${t.$2}'),
          at: t.$1,
          title: '${headline(e)} · ${t.$2}',
          body: '${e.direction.label} on ${dayLabel(e.date)}, due ${dayLabel(d)}. Tap to record a repayment.',
          payload: '$payloadPrefix${e.id}',
        ));
      }
    }
    out.sort((LendReminder a, LendReminder b) => a.at.compareTo(b.at));
    return out;
  }

  Future<void> reschedule() async {
    try {
      await _scheduler.replaceAll(reminders());
    } catch (e) {
      debugPrint('lending reminders: $e');
    }
  }

  static const List<String> months = <String>['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  static String dayLabel(DateTime d) => '${d.day} ${months[d.month - 1]} ${d.year}';

  String toText() {
    final (int toYou, int byYou) = totals();
    final StringBuffer b = StringBuffer('Lending ledger\n')
      ..write('Owed to you: ${amountLabel(toYou)}\n')
      ..write('You owe: ${amountLabel(byYou)}\n');
    for (final LendEntry e in all) {
      b.write('- ${e.direction.label} ${amountLabel(e.paise)} ${e.direction == LendDirection.lent ? 'to' : 'from'} ${e.who} '
          'on ${dayLabel(e.date)}${e.due == null ? '' : ', due ${dayLabel(e.due!)}'} · ${e.status.label}');
      if (e.status == LendStatus.partlyRepaid) {
        b.write(' (${amountLabel(e.remaining)} left)');
      }
      if (e.note.isNotEmpty) {
        b.write(' · ${e.note}');
      }
      b.write('\n');
    }
    return b.toString();
  }

  static LendingLedger instance = LendingLedger();
  static void install(LendingLedger l) => instance = l;
}
