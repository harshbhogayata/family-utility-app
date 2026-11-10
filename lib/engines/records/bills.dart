import 'dart:async';

import 'package:flutter/foundation.dart';

import '../family/family_space.dart';
import '../family/family_store.dart';
import 'expense_tracker.dart' show formatPaise;

/// Feature 083 — Bill reminders.
///
/// Electricity, water, gas, internet, rent and society dues with a due
/// date that repeats every 1, 2, 3, 6 or 12 months; reminders 3 days ahead
/// and on the day; mark paid with the amount (kept as history) and attach
/// the receipt from the receipt vault (085). Shared on the family store;
/// nothing is uploaded.

enum BillKind {
  electricity('Electricity'),
  water('Water'),
  gas('Gas'),
  internet('Internet'),
  rent('Rent'),
  society('Society dues'),
  other('Other');

  const BillKind(this.label);
  final String label;

  static BillKind byName(Object? n) => BillKind.values.firstWhere((BillKind k) => k.name == n, orElse: () => BillKind.other);
}

class BillPayment {
  const BillPayment({required this.on, required this.paise, required this.dueFor, this.receiptId});

  final DateTime on;
  final int paise;

  /// The due date this payment settled.
  final DateTime dueFor;

  /// A receipt in the receipt vault, if attached.
  final String? receiptId;

  Map<String, Object?> toJson() => <String, Object?>{
        'on': on.toIso8601String(),
        'paise': paise,
        'for': dueFor.toIso8601String(),
        if (receiptId != null) 'receipt': receiptId,
      };

  static BillPayment? fromJson(Object? o) {
    if (o is! Map) {
      return null;
    }
    final DateTime? on = DateTime.tryParse('${o['on'] ?? ''}');
    final DateTime? dueFor = DateTime.tryParse('${o['for'] ?? ''}');
    final Object? p = o['paise'];
    if (on == null || dueFor == null || p is! num) {
      return null;
    }
    final Object? r = o['receipt'];
    return BillPayment(on: on, paise: p.toInt(), dueFor: dueFor, receiptId: r is String ? r : null);
  }

  BillPayment withReceipt(String? id) => BillPayment(on: on, paise: paise, dueFor: dueFor, receiptId: id);
}

class Bill {
  const Bill({
    required this.id,
    required this.name,
    required this.kind,
    required this.nextDue,
    required this.dueDay,
    this.everyMonths = 1,
    this.paise,
    this.payments = const <BillPayment>[],
  });

  final String id;
  final String name;
  final BillKind kind;

  /// The next unpaid due date.
  final DateTime nextDue;

  /// The day of the month it falls due (kept so 31st stays 31st after a
  /// short month).
  final int dueDay;
  final int everyMonths;

  /// Usual amount, if known.
  final int? paise;

  /// Oldest first.
  final List<BillPayment> payments;

  Map<String, Object?> toFields() => <String, Object?>{
        'name': name,
        'kind': kind.name,
        'next': nextDue.toIso8601String(),
        'day': dueDay,
        'every': everyMonths,
        if (paise != null) 'paise': paise,
        'payments': payments.map((BillPayment p) => p.toJson()).toList(),
      };

  static Bill fromRecord(FamilyRecord r) {
    final Map<String, Object?> f = r.fields;
    final DateTime next = DateTime.tryParse('${f['next'] ?? ''}') ?? DateTime(2000);
    final Object? day = f['day'];
    final Object? every = f['every'];
    final Object? p = f['paise'];
    final Object? pays = f['payments'];
    return Bill(
      id: r.id,
      name: '${f['name'] ?? ''}',
      kind: BillKind.byName(f['kind']),
      nextDue: next,
      dueDay: day is num ? day.toInt() : next.day,
      everyMonths: every is num && every > 0 ? every.toInt() : 1,
      paise: p is num ? p.toInt() : null,
      payments: pays is List ? pays.map(BillPayment.fromJson).whereType<BillPayment>().toList() : const <BillPayment>[],
    );
  }

  Bill copyWith({DateTime? nextDue, List<BillPayment>? payments}) => Bill(
        id: id,
        name: name,
        kind: kind,
        nextDue: nextDue ?? this.nextDue,
        dueDay: dueDay,
        everyMonths: everyMonths,
        paise: paise,
        payments: payments ?? this.payments,
      );

  /// [dueDay] in the month [months] after [from], clamped to the month end.
  static DateTime addMonths(DateTime from, int months, int dueDay) {
    final DateTime first = DateTime(from.year, from.month + months, 1);
    final int last = DateTime(first.year, first.month + 1, 0).day;
    return DateTime(first.year, first.month, dueDay > last ? last : dueDay);
  }
}

enum BillState { overdue, dueSoon, later }

class BillReminder {
  const BillReminder({required this.id, required this.at, required this.title, required this.body, required this.payload});
  final int id;
  final DateTime at;
  final String title;
  final String body;
  final String payload;
}

abstract interface class BillReminderScheduler {
  Future<void> replaceAll(List<BillReminder> reminders);
}

class NoBillReminders implements BillReminderScheduler {
  const NoBillReminders();
  @override
  Future<void> replaceAll(List<BillReminder> reminders) async {}
}

class Bills extends ChangeNotifier {
  Bills({
    FamilySpace? space,
    FamilyStore? soloStore,
    BillReminderScheduler reminders = const NoBillReminders(),
    DateTime Function()? now,
    this.remindHour = 9,
  })  : _space = space,
        _solo = soloStore,
        _scheduler = reminders,
        _now = now ?? DateTime.now;

  static const String collection = 'bills';
  static const String payloadPrefix = 'bill:';
  static const int idBase = 4000000;
  static const int soonDays = 5;
  static const int remindDaysBefore = 3;
  static const List<int> periods = <int>[1, 2, 3, 6, 12];

  final FamilySpace? _space;
  final FamilyStore? _solo;
  final BillReminderScheduler _scheduler;
  final DateTime Function() _now;
  final int remindHour;
  int _seq = 0;

  FamilySpace get space => _space ?? FamilySpace.instance;
  FamilyStore get store => space.inFamily ? space.store : (_solo ?? space.store);

  /// Soonest due first.
  List<Bill> get all {
    final List<Bill> l = store.list(collection).map(Bill.fromRecord).toList();
    l.sort((Bill a, Bill b) {
      final int c = a.nextDue.compareTo(b.nextDue);
      return c != 0 ? c : a.name.compareTo(b.name);
    });
    return l;
  }

  Bill? byId(String id) {
    final FamilyRecord? r = store.get(collection, id);
    return r == null ? null : Bill.fromRecord(r);
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

  Bill? add({required String name, required BillKind kind, required DateTime due, int everyMonths = 1, int? paise}) {
    if (!periods.contains(everyMonths) || (paise != null && paise <= 0)) {
      return null;
    }
    final String n = name.trim().isEmpty ? kind.label : name.trim();
    final String id = 'b${_now().microsecondsSinceEpoch}-${_seq++}';
    final Bill b = Bill(
      id: id,
      name: n,
      kind: kind,
      nextDue: DateTime(due.year, due.month, due.day),
      dueDay: due.day,
      everyMonths: everyMonths,
      paise: paise,
    );
    _remember(id);
    store.put(collection, id, b.toFields());
    _changed();
    return b;
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

  /// Records a payment for the current due date and moves to the next one.
  bool markPaid(String id, {int? paise, DateTime? on, String? receiptId}) {
    final Bill? b = byId(id);
    final int? amount = paise ?? b?.paise;
    if (b == null || amount == null || amount <= 0) {
      return false;
    }
    final DateTime day = on ?? _today();
    _remember(id);
    store.put(
      collection,
      id,
      b.copyWith(
        nextDue: Bill.addMonths(b.nextDue, b.everyMonths, b.dueDay),
        payments: <BillPayment>[
          ...b.payments,
          BillPayment(on: DateTime(day.year, day.month, day.day), paise: amount, dueFor: b.nextDue, receiptId: receiptId),
        ],
      ).toFields(),
    );
    _changed();
    return true;
  }

  /// Attaches a receipt from the vault to a payment (the latest by default).
  bool attachReceipt(String id, String receiptId, {int? paymentIndex}) {
    final Bill? b = byId(id);
    if (b == null || b.payments.isEmpty || receiptId.isEmpty) {
      return false;
    }
    final int i = paymentIndex ?? b.payments.length - 1;
    if (i < 0 || i >= b.payments.length) {
      return false;
    }
    _remember(id);
    final List<BillPayment> next = List<BillPayment>.of(b.payments);
    next[i] = next[i].withReceipt(receiptId);
    store.put(collection, id, b.copyWith(payments: next).toFields());
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

  int daysUntil(Bill b) {
    final DateTime t = _today();
    return DateTime.utc(b.nextDue.year, b.nextDue.month, b.nextDue.day).difference(DateTime.utc(t.year, t.month, t.day)).inDays;
  }

  BillState state(Bill b) {
    final int d = daysUntil(b);
    return d < 0 ? BillState.overdue : (d <= soonDays ? BillState.dueSoon : BillState.later);
  }

  /// Average of the last payments, for comparing this bill to usual.
  static int? average(Bill b, {int last = 6}) {
    if (b.payments.isEmpty) {
      return null;
    }
    final List<BillPayment> p = b.payments.length > last ? b.payments.sublist(b.payments.length - last) : b.payments;
    return p.fold<int>(0, (int s, BillPayment x) => s + x.paise) ~/ p.length;
  }

  static int _id(String key) {
    int h = 0;
    for (final int c in key.codeUnits) {
      h = (h * 31 + c) & 0x3FFFF;
    }
    return idBase + h;
  }

  static String amountLabel(int paise) => '₹${formatPaise(paise)}';

  /// 3 days ahead and on the due day; tomorrow morning for overdue bills.
  List<BillReminder> reminders() {
    final DateTime now = _now();
    final DateTime today = _today();
    final List<BillReminder> out = <BillReminder>[];
    for (final Bill b in all) {
      final String amount = b.paise == null ? '' : ' · ${amountLabel(b.paise!)}';
      final List<(DateTime, String)> times = state(b) == BillState.overdue
          ? <(DateTime, String)>[(DateTime(today.year, today.month, today.day + 1, remindHour), 'is overdue')]
          : <(DateTime, String)>[
              (DateTime(b.nextDue.year, b.nextDue.month, b.nextDue.day - remindDaysBefore, remindHour), 'is due in $remindDaysBefore days'),
              (DateTime(b.nextDue.year, b.nextDue.month, b.nextDue.day, remindHour), 'is due today'),
            ];
      for (final (DateTime, String) t in times) {
        if (!t.$1.isAfter(now)) {
          continue;
        }
        out.add(BillReminder(
          id: _id('${b.id}@${t.$2}'),
          at: t.$1,
          title: '${b.name} ${t.$2}',
          body: 'Due ${dayLabel(b.nextDue)}$amount. Tap to mark paid.',
          payload: '$payloadPrefix${b.id}',
        ));
      }
    }
    out.sort((BillReminder a, BillReminder b) => a.at.compareTo(b.at));
    return out;
  }

  Future<void> reschedule() async {
    try {
      await _scheduler.replaceAll(reminders());
    } catch (e) {
      debugPrint('bill reminders: $e');
    }
  }

  static const List<String> months = <String>['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  static String dayLabel(DateTime d) => '${d.day} ${months[d.month - 1]} ${d.year}';

  String toText() {
    final StringBuffer b = StringBuffer('Bills\n');
    for (final Bill x in all) {
      b.write('- ${x.name}: due ${dayLabel(x.nextDue)}${x.paise == null ? '' : ' · ${amountLabel(x.paise!)}'}\n');
      for (final BillPayment p in x.payments.reversed.take(6)) {
        b.write('    paid ${amountLabel(p.paise)} on ${dayLabel(p.on)}${p.receiptId == null ? '' : ' (receipt)'}\n');
      }
    }
    return b.toString();
  }

  static Bills instance = Bills();
  static void install(Bills b) => instance = b;
}
