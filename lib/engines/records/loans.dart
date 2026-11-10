import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../family/family_space.dart';
import '../family/family_store.dart';
import 'bills.dart' show Bill;
import 'expense_tracker.dart' show formatPaise;

/// Feature 087 — Loan tracker.
///
/// Home, car, personal or education loans: the EMI from amount, rate and
/// tenure; the month-by-month amortisation schedule; the balance today;
/// what a prepayment would save (EMI kept, tenure shortened); and a
/// reminder before each EMI. Kept on the phone (or the family store);
/// nothing is uploaded.

class Prepayment {
  const Prepayment(this.on, this.paise);
  final DateTime on;
  final int paise;

  Map<String, Object?> toJson() => <String, Object?>{'on': on.toIso8601String(), 'paise': paise};

  static Prepayment? fromJson(Object? o) {
    if (o is! Map) {
      return null;
    }
    final DateTime? on = DateTime.tryParse('${o['on'] ?? ''}');
    final Object? p = o['paise'];
    return on == null || p is! num ? null : Prepayment(on, p.toInt());
  }
}

class EmiRow {
  const EmiRow({required this.n, required this.on, required this.emi, required this.interest, required this.principal, required this.balance});

  final int n;
  final DateTime on;
  final int emi;
  final int interest;
  final int principal;

  /// Balance left after this EMI.
  final int balance;
}

class Loan {
  const Loan({
    required this.id,
    required this.name,
    required this.principal,
    required this.ratePct,
    required this.months,
    required this.firstEmi,
    this.prepayments = const <Prepayment>[],
  });

  final String id;
  final String name;
  final int principal;

  /// Yearly interest rate in percent (reducing balance).
  final double ratePct;
  final int months;
  final DateTime firstEmi;
  final List<Prepayment> prepayments;

  int get emiDay => firstEmi.day;

  /// The monthly instalment, in paise.
  int get emi => Loans.emiFor(principal, ratePct, months);

  Map<String, Object?> toFields() => <String, Object?>{
        'name': name,
        'principal': principal,
        'rate': ratePct,
        'months': months,
        'first': firstEmi.toIso8601String(),
        'prepay': prepayments.map((Prepayment p) => p.toJson()).toList(),
      };

  static Loan fromRecord(FamilyRecord r) {
    final Map<String, Object?> f = r.fields;
    final Object? p = f['principal'];
    final Object? rate = f['rate'];
    final Object? m = f['months'];
    final Object? pre = f['prepay'];
    return Loan(
      id: r.id,
      name: '${f['name'] ?? ''}',
      principal: p is num ? p.toInt() : 0,
      ratePct: rate is num ? rate.toDouble() : 0,
      months: m is num && m > 0 ? m.toInt() : 1,
      firstEmi: DateTime.tryParse('${f['first'] ?? ''}') ?? DateTime(2000),
      prepayments: pre is List ? pre.map(Prepayment.fromJson).whereType<Prepayment>().toList() : const <Prepayment>[],
    );
  }

  Loan withPrepayments(List<Prepayment> next) =>
      Loan(id: id, name: name, principal: principal, ratePct: ratePct, months: months, firstEmi: firstEmi, prepayments: next);
}

/// What a prepayment would change.
class PrepaymentEffect {
  const PrepaymentEffect({required this.monthsSaved, required this.interestSaved, required this.newLastEmi, required this.oldLastEmi});
  final int monthsSaved;
  final int interestSaved;
  final DateTime newLastEmi;
  final DateTime oldLastEmi;
}

class LoanReminder {
  const LoanReminder({required this.id, required this.at, required this.title, required this.body, required this.payload});
  final int id;
  final DateTime at;
  final String title;
  final String body;
  final String payload;
}

abstract interface class LoanReminderScheduler {
  Future<void> replaceAll(List<LoanReminder> reminders);
}

class NoLoanReminders implements LoanReminderScheduler {
  const NoLoanReminders();
  @override
  Future<void> replaceAll(List<LoanReminder> reminders) async {}
}

class Loans extends ChangeNotifier {
  Loans({
    FamilySpace? space,
    FamilyStore? soloStore,
    LoanReminderScheduler reminders = const NoLoanReminders(),
    DateTime Function()? now,
    this.remindHour = 9,
  })  : _space = space,
        _solo = soloStore,
        _scheduler = reminders,
        _now = now ?? DateTime.now;

  static const String collection = 'loans';
  static const String payloadPrefix = 'loan:';
  static const int idBase = 6000000;
  static const int remindDaysBefore = 2;
  static const int maxMonths = 600;

  final FamilySpace? _space;
  final FamilyStore? _solo;
  final LoanReminderScheduler _scheduler;
  final DateTime Function() _now;
  final int remindHour;
  int _seq = 0;

  FamilySpace get space => _space ?? FamilySpace.instance;
  FamilyStore get store => space.inFamily ? space.store : (_solo ?? space.store);

  List<Loan> get all {
    final List<Loan> l = store.list(collection).map(Loan.fromRecord).toList();
    l.sort((Loan a, Loan b) => a.name.compareTo(b.name));
    return l;
  }

  Loan? byId(String id) {
    final FamilyRecord? r = store.get(collection, id);
    return r == null ? null : Loan.fromRecord(r);
  }

  /// EMI = P·r·(1+r)^n / ((1+r)^n − 1), r the monthly rate; rounded up to
  /// the next paisa as banks do.
  static int emiFor(int principal, double ratePct, int months) {
    if (principal <= 0 || months <= 0) {
      return 0;
    }
    final double r = ratePct / 1200;
    if (r == 0) {
      return (principal / months).ceil();
    }
    final double f = math.pow(1 + r, months).toDouble();
    return (principal * r * f / (f - 1)).ceil();
  }

  /// Month by month with the loan's prepayments (and [extra]) applied on
  /// their dates; the EMI stays the same so the tenure shortens.
  static List<EmiRow> schedule(Loan l, {List<Prepayment> extra = const <Prepayment>[]}) {
    final double r = l.ratePct / 1200;
    final int emi = l.emi;
    final List<Prepayment> pre = <Prepayment>[...l.prepayments, ...extra]..sort((Prepayment a, Prepayment b) => a.on.compareTo(b.on));
    int pi = 0;
    int bal = l.principal;
    final List<EmiRow> rows = <EmiRow>[];
    for (int n = 1; bal > 0 && n <= maxMonths; n++) {
      final DateTime on = Bill.addMonths(l.firstEmi, n - 1, l.emiDay);
      while (pi < pre.length && !pre[pi].on.isAfter(on)) {
        bal -= pre[pi].paise;
        pi++;
      }
      if (bal <= 0) {
        break;
      }
      final int interest = (bal * r).round();
      int principal = emi - interest;
      if (principal <= 0) {
        break; // the EMI no longer covers the interest
      }
      if (principal > bal) {
        principal = bal;
      }
      bal -= principal;
      rows.add(EmiRow(n: n, on: on, emi: principal + interest, interest: interest, principal: principal, balance: bal));
    }
    return rows;
  }

  static int totalInterest(List<EmiRow> rows) => rows.fold<int>(0, (int s, EmiRow r) => s + r.interest);

  /// Balance after the EMIs paid up to [on] and the prepayments made by then.
  static int balanceOn(Loan l, DateTime on) {
    int bal = l.principal;
    for (final Prepayment p in l.prepayments) {
      if (!p.on.isAfter(on)) {
        bal -= p.paise;
      }
    }
    for (final EmiRow r in schedule(l)) {
      if (!r.on.isAfter(on)) {
        bal -= r.principal;
      }
    }
    return bal < 0 ? 0 : bal;
  }

  int balanceToday(Loan l) => balanceOn(l, _now());

  EmiRow? nextEmi(Loan l) {
    final DateTime n = _now();
    final DateTime today = DateTime(n.year, n.month, n.day);
    for (final EmiRow r in schedule(l)) {
      if (!r.on.isBefore(today)) {
        return r;
      }
    }
    return null;
  }

  /// What paying [paise] extra on [on] would save.
  static PrepaymentEffect whatIf(Loan l, int paise, DateTime on) {
    final List<EmiRow> base = schedule(l);
    final List<EmiRow> alt = schedule(l, extra: <Prepayment>[Prepayment(on, paise)]);
    final DateTime fallback = l.firstEmi;
    return PrepaymentEffect(
      monthsSaved: base.length - alt.length,
      interestSaved: totalInterest(base) - totalInterest(alt),
      newLastEmi: alt.isEmpty ? on : alt.last.on,
      oldLastEmi: base.isEmpty ? fallback : base.last.on,
    );
  }

  (String, Map<String, Object?>?)? _undo;

  void _remember(String id) => _undo = (id, store.get(collection, id)?.fields);

  void _changed() {
    notifyListeners();
    unawaited(reschedule());
  }

  Loan? add({required String name, required int principal, required double ratePct, required int months, required DateTime firstEmi}) {
    if (name.trim().isEmpty || principal <= 0 || ratePct < 0 || ratePct > 60 || months <= 0 || months > maxMonths) {
      return null;
    }
    final String id = 'l${_now().microsecondsSinceEpoch}-${_seq++}';
    final Loan l = Loan(
      id: id,
      name: name.trim(),
      principal: principal,
      ratePct: ratePct,
      months: months,
      firstEmi: DateTime(firstEmi.year, firstEmi.month, firstEmi.day),
    );
    _remember(id);
    store.put(collection, id, l.toFields());
    _changed();
    return l;
  }

  /// Records a prepayment actually made.
  bool prepay(String id, int paise, {DateTime? on}) {
    final Loan? l = byId(id);
    if (l == null || paise <= 0) {
      return false;
    }
    final DateTime n = on ?? _now();
    _remember(id);
    store.put(collection, id, l.withPrepayments(<Prepayment>[...l.prepayments, Prepayment(DateTime(n.year, n.month, n.day), paise)]).toFields());
    _changed();
    return true;
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

  static int _id(String key) {
    int h = 0;
    for (final int c in key.codeUnits) {
      h = (h * 31 + c) & 0x3FFFF;
    }
    return idBase + h;
  }

  static String amountLabel(int paise) => '₹${formatPaise(paise)}';

  /// The next EMI of each loan: [remindDaysBefore] days ahead and on the day.
  List<LoanReminder> reminders() {
    final DateTime now = _now();
    final List<LoanReminder> out = <LoanReminder>[];
    for (final Loan l in all) {
      final EmiRow? e = nextEmi(l);
      if (e == null) {
        continue;
      }
      for (final int d in <int>[remindDaysBefore, 0]) {
        final DateTime at = DateTime(e.on.year, e.on.month, e.on.day - d, remindHour);
        if (!at.isAfter(now)) {
          continue;
        }
        out.add(LoanReminder(
          id: _id('${l.id}@$d'),
          at: at,
          title: d == 0 ? '${l.name} EMI is due today' : '${l.name} EMI in $d days',
          body: '${amountLabel(e.emi)} on ${dayLabel(e.on)}. Keep the balance in the account.',
          payload: '$payloadPrefix${l.id}',
        ));
      }
    }
    out.sort((LoanReminder a, LoanReminder b) => a.at.compareTo(b.at));
    return out;
  }

  Future<void> reschedule() async {
    try {
      await _scheduler.replaceAll(reminders());
    } catch (e) {
      debugPrint('loan reminders: $e');
    }
  }

  static const List<String> months = <String>['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  static String dayLabel(DateTime d) => '${d.day} ${months[d.month - 1]} ${d.year}';

  static String monthLabel(DateTime d) => '${months[d.month - 1]} ${d.year}';

  /// The schedule as CSV, to share or save.
  static String scheduleCsv(Loan l) {
    String rupees(int p) => '${p ~/ 100}.${(p % 100).toString().padLeft(2, '0')}';
    final StringBuffer b = StringBuffer('No,Date,EMI,Interest,Principal,Balance\r\n');
    for (final EmiRow r in schedule(l)) {
      final String d = '${r.on.year}-${r.on.month.toString().padLeft(2, '0')}-${r.on.day.toString().padLeft(2, '0')}';
      b.write('${r.n},$d,${rupees(r.emi)},${rupees(r.interest)},${rupees(r.principal)},${rupees(r.balance)}\r\n');
    }
    return b.toString();
  }

  static Loans instance = Loans();
  static void install(Loans l) => instance = l;
}
