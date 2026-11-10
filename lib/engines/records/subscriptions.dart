import 'dart:async';

import 'package:flutter/foundation.dart';

import '../family/family_space.dart';
import '../family/family_store.dart';
import 'bills.dart' show Bill;
import 'expense_tracker.dart' show formatPaise;

/// Feature 084 — Subscription tracker.
///
/// Streaming, apps, cloud storage and memberships with their renewal date,
/// free trials that turn into paid plans, a reminder a few days before
/// each renewal and the total they cost per year. Shared on the family
/// store; nothing is uploaded.

class Subscription {
  const Subscription({
    required this.id,
    required this.name,
    required this.paise,
    required this.renews,
    required this.renewDay,
    this.everyMonths = 1,
    this.trial = false,
    this.remindDays = 3,
  });

  final String id;
  final String name;

  /// Price per renewal.
  final int paise;

  /// Next renewal (or the day a free trial turns paid).
  final DateTime renews;
  final int renewDay;
  final int everyMonths;
  final bool trial;
  final int remindDays;

  /// What it costs over a year.
  int get perYear => paise * 12 ~/ everyMonths;

  Map<String, Object?> toFields() => <String, Object?>{
        'name': name,
        'paise': paise,
        'renews': renews.toIso8601String(),
        'day': renewDay,
        'every': everyMonths,
        if (trial) 'trial': true,
        'remind': remindDays,
      };

  static Subscription fromRecord(FamilyRecord r) {
    final Map<String, Object?> f = r.fields;
    final DateTime renews = DateTime.tryParse('${f['renews'] ?? ''}') ?? DateTime(2000);
    int intOf(Object? o, int d) => o is num ? o.toInt() : d;
    return Subscription(
      id: r.id,
      name: '${f['name'] ?? ''}',
      paise: intOf(f['paise'], 0),
      renews: renews,
      renewDay: intOf(f['day'], renews.day),
      everyMonths: intOf(f['every'], 1) <= 0 ? 1 : intOf(f['every'], 1),
      trial: f['trial'] == true,
      remindDays: intOf(f['remind'], 3),
    );
  }

  Subscription renewed() => Subscription(
        id: id,
        name: name,
        paise: paise,
        renews: Bill.addMonths(renews, everyMonths, renewDay),
        renewDay: renewDay,
        everyMonths: everyMonths,
        remindDays: remindDays,
      );
}

class SubscriptionReminder {
  const SubscriptionReminder({required this.id, required this.at, required this.title, required this.body, required this.payload});
  final int id;
  final DateTime at;
  final String title;
  final String body;
  final String payload;
}

abstract interface class SubscriptionReminderScheduler {
  Future<void> replaceAll(List<SubscriptionReminder> reminders);
}

class NoSubscriptionReminders implements SubscriptionReminderScheduler {
  const NoSubscriptionReminders();
  @override
  Future<void> replaceAll(List<SubscriptionReminder> reminders) async {}
}

class Subscriptions extends ChangeNotifier {
  Subscriptions({
    FamilySpace? space,
    FamilyStore? soloStore,
    SubscriptionReminderScheduler reminders = const NoSubscriptionReminders(),
    DateTime Function()? now,
    this.remindHour = 9,
  })  : _space = space,
        _solo = soloStore,
        _scheduler = reminders,
        _now = now ?? DateTime.now;

  static const String collection = 'subscriptions';
  static const String payloadPrefix = 'sub:';
  static const int idBase = 5000000;
  static const List<int> periods = <int>[1, 3, 6, 12];

  final FamilySpace? _space;
  final FamilyStore? _solo;
  final SubscriptionReminderScheduler _scheduler;
  final DateTime Function() _now;
  final int remindHour;
  int _seq = 0;

  FamilySpace get space => _space ?? FamilySpace.instance;
  FamilyStore get store => space.inFamily ? space.store : (_solo ?? space.store);

  /// Next renewal first.
  List<Subscription> get all {
    final List<Subscription> l = store.list(collection).map(Subscription.fromRecord).toList();
    l.sort((Subscription a, Subscription b) {
      final int c = a.renews.compareTo(b.renews);
      return c != 0 ? c : a.name.compareTo(b.name);
    });
    return l;
  }

  Subscription? byId(String id) {
    final FamilyRecord? r = store.get(collection, id);
    return r == null ? null : Subscription.fromRecord(r);
  }

  /// Everything per year (free trials counted at the price they turn into).
  int get yearlyTotal => all.fold<int>(0, (int s, Subscription x) => s + x.perYear);

  int get monthlyAverage => yearlyTotal ~/ 12;

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

  Subscription? add({required String name, required int paise, required DateTime renews, int everyMonths = 1, bool trial = false, int remindDays = 3}) {
    if (name.trim().isEmpty || paise < 0 || !periods.contains(everyMonths) || remindDays < 0 || remindDays > 30) {
      return null;
    }
    final String id = 's${_now().microsecondsSinceEpoch}-${_seq++}';
    final Subscription s = Subscription(
      id: id,
      name: name.trim(),
      paise: paise,
      renews: DateTime(renews.year, renews.month, renews.day),
      renewDay: renews.day,
      everyMonths: everyMonths,
      trial: trial,
      remindDays: remindDays,
    );
    _remember(id);
    store.put(collection, id, s.toFields());
    _changed();
    return s;
  }

  /// Moves to the next renewal; a trial becomes a paid plan.
  bool renew(String id) {
    final Subscription? s = byId(id);
    if (s == null) {
      return false;
    }
    _remember(id);
    store.put(collection, id, s.renewed().toFields());
    _changed();
    return true;
  }

  /// Cancelled: removed, with Undo.
  bool cancel(String id) {
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

  int daysUntil(Subscription s) {
    final DateTime t = _today();
    return DateTime.utc(s.renews.year, s.renews.month, s.renews.day).difference(DateTime.utc(t.year, t.month, t.day)).inDays;
  }

  static int _id(String key) {
    int h = 0;
    for (final int c in key.codeUnits) {
      h = (h * 31 + c) & 0x3FFFF;
    }
    return idBase + h;
  }

  static String amountLabel(int paise) => '₹${formatPaise(paise)}';

  /// [remindDays] before each renewal (a day before as well for trials).
  List<SubscriptionReminder> reminders() {
    final DateTime now = _now();
    final List<SubscriptionReminder> out = <SubscriptionReminder>[];
    for (final Subscription s in all) {
      final Set<int> before = <int>{s.remindDays, if (s.trial) 1};
      for (final int d in before) {
        final DateTime at = DateTime(s.renews.year, s.renews.month, s.renews.day - d, remindHour);
        if (!at.isAfter(now)) {
          continue;
        }
        final String when = d == 0 ? 'today' : (d == 1 ? 'tomorrow' : 'in $d days');
        out.add(SubscriptionReminder(
          id: _id('${s.id}@$d'),
          at: at,
          title: s.trial ? '${s.name} free trial ends $when' : '${s.name} renews $when',
          body: '${amountLabel(s.paise)} will be charged. Cancel before then if you do not need it.',
          payload: '$payloadPrefix${s.id}',
        ));
      }
    }
    out.sort((SubscriptionReminder a, SubscriptionReminder b) => a.at.compareTo(b.at));
    return out;
  }

  Future<void> reschedule() async {
    try {
      await _scheduler.replaceAll(reminders());
    } catch (e) {
      debugPrint('subscription reminders: $e');
    }
  }

  static const List<String> months = <String>['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  static String dayLabel(DateTime d) => '${d.day} ${months[d.month - 1]} ${d.year}';

  static String periodLabel(int months) => switch (months) {
        1 => 'month',
        3 => '3 months',
        6 => '6 months',
        _ => 'year',
      };

  String toText() {
    final StringBuffer b = StringBuffer('Subscriptions\n');
    for (final Subscription s in all) {
      b.write('- ${s.name}: ${amountLabel(s.paise)} / ${periodLabel(s.everyMonths)}, '
          '${s.trial ? 'trial ends' : 'renews'} ${dayLabel(s.renews)} (${amountLabel(s.perYear)} a year)\n');
    }
    b.write('Total ${amountLabel(yearlyTotal)} a year\n');
    return b.toString();
  }

  static Subscriptions instance = Subscriptions();
  static void install(Subscriptions s) => instance = s;
}
