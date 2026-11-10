import 'dart:async';

import 'package:flutter/foundation.dart';

import '../family/family_space.dart';
import '../family/family_store.dart';
import 'bills.dart' show Bill;
import 'receipt_vault.dart' show Receipt;

/// Feature 086 — Warranty tracker.
///
/// Purchase date, warranty end, the bill from the receipt vault (085) and
/// the service number one tap away; reminders 30 and 7 days before the
/// warranty ends. Shared on the family store; nothing is uploaded.

class Warranty {
  const Warranty({
    required this.id,
    required this.product,
    required this.bought,
    required this.months,
    this.servicePhone = '',
    this.receiptId,
  });

  final String id;
  final String product;
  final DateTime bought;
  final int months;
  final String servicePhone;

  /// The bill in the receipt vault, if linked.
  final String? receiptId;

  DateTime get ends => Bill.addMonths(bought, months, bought.day);

  String get dialable => servicePhone.replaceAll(RegExp(r'[^0-9+]'), '');

  Uri? get callUri => dialable.isEmpty ? null : Uri(scheme: 'tel', path: dialable);

  Map<String, Object?> toFields() => <String, Object?>{
        'product': product,
        'bought': bought.toIso8601String(),
        'months': months,
        if (servicePhone.isNotEmpty) 'phone': servicePhone,
        if (receiptId != null) 'receipt': receiptId,
      };

  static Warranty fromRecord(FamilyRecord r) {
    final Map<String, Object?> f = r.fields;
    final Object? m = f['months'];
    final Object? rc = f['receipt'];
    return Warranty(
      id: r.id,
      product: '${f['product'] ?? ''}',
      bought: DateTime.tryParse('${f['bought'] ?? ''}') ?? DateTime(2000),
      months: m is num ? m.toInt() : 12,
      servicePhone: '${f['phone'] ?? ''}',
      receiptId: rc is String ? rc : null,
    );
  }

  Warranty withReceipt(String? id) =>
      Warranty(id: this.id, product: product, bought: bought, months: months, servicePhone: servicePhone, receiptId: id);
}

enum WarrantyState { active, endingSoon, expired }

class WarrantyReminder {
  const WarrantyReminder({required this.id, required this.at, required this.title, required this.body, required this.payload});
  final int id;
  final DateTime at;
  final String title;
  final String body;
  final String payload;
}

abstract interface class WarrantyReminderScheduler {
  Future<void> replaceAll(List<WarrantyReminder> reminders);
}

class NoWarrantyReminders implements WarrantyReminderScheduler {
  const NoWarrantyReminders();
  @override
  Future<void> replaceAll(List<WarrantyReminder> reminders) async {}
}

class Warranties extends ChangeNotifier {
  Warranties({
    FamilySpace? space,
    FamilyStore? soloStore,
    WarrantyReminderScheduler reminders = const NoWarrantyReminders(),
    DateTime Function()? now,
    this.remindHour = 10,
  })  : _space = space,
        _solo = soloStore,
        _scheduler = reminders,
        _now = now ?? DateTime.now;

  static const String collection = 'warranties';
  static const String payloadPrefix = 'warranty:';
  static const int idBase = 7000000;
  static const List<int> daysAhead = <int>[30, 7];

  final FamilySpace? _space;
  final FamilyStore? _solo;
  final WarrantyReminderScheduler _scheduler;
  final DateTime Function() _now;
  final int remindHour;
  int _seq = 0;

  FamilySpace get space => _space ?? FamilySpace.instance;
  FamilyStore get store => space.inFamily ? space.store : (_solo ?? space.store);

  /// Ending soonest first; expired ones last.
  List<Warranty> get all {
    final DateTime t = _today();
    final List<Warranty> l = store.list(collection).map(Warranty.fromRecord).toList();
    l.sort((Warranty a, Warranty b) {
      final bool ea = a.ends.isBefore(t), eb = b.ends.isBefore(t);
      if (ea != eb) {
        return ea ? 1 : -1;
      }
      final int c = ea ? b.ends.compareTo(a.ends) : a.ends.compareTo(b.ends);
      return c != 0 ? c : a.product.compareTo(b.product);
    });
    return l;
  }

  Warranty? byId(String id) {
    final FamilyRecord? r = store.get(collection, id);
    return r == null ? null : Warranty.fromRecord(r);
  }

  DateTime _today() {
    final DateTime n = _now();
    return DateTime(n.year, n.month, n.day);
  }

  int daysLeft(Warranty w) {
    final DateTime t = _today();
    return DateTime.utc(w.ends.year, w.ends.month, w.ends.day).difference(DateTime.utc(t.year, t.month, t.day)).inDays;
  }

  WarrantyState state(Warranty w) {
    final int d = daysLeft(w);
    return d < 0 ? WarrantyState.expired : (d <= 30 ? WarrantyState.endingSoon : WarrantyState.active);
  }

  final List<(String, Map<String, Object?>?)> _undo = <(String, Map<String, Object?>?)>[];

  void _remember(Iterable<String> ids) {
    _undo
      ..clear()
      ..addAll(ids.map((String id) => (id, store.get(collection, id)?.fields)));
  }

  void _changed() {
    notifyListeners();
    unawaited(reschedule());
  }

  String _newId() => 'w${_now().microsecondsSinceEpoch}-${_seq++}';

  Warranty? add({required String product, required DateTime bought, required int months, String servicePhone = '', String? receiptId}) {
    if (product.trim().isEmpty || months <= 0 || months > 240 || bought.isAfter(_now())) {
      return null;
    }
    final String id = _newId();
    final Warranty w = Warranty(
      id: id,
      product: product.trim(),
      bought: DateTime(bought.year, bought.month, bought.day),
      months: months,
      servicePhone: servicePhone.trim(),
      receiptId: receiptId,
    );
    _remember(<String>[id]);
    store.put(collection, id, w.toFields());
    _changed();
    return w;
  }

  /// Adds a warranty for each receipt that has one set in the receipt
  /// vault and is not tracked yet. One undo removes them all.
  int importFromReceipts(List<Receipt> receipts) {
    final Set<String> have = <String>{for (final Warranty w in all) if (w.receiptId != null) w.receiptId!};
    final List<(String, Map<String, Object?>)> puts = <(String, Map<String, Object?>)>[];
    for (final Receipt r in receipts) {
      if (r.warrantyMonths == null || have.contains(r.id)) {
        continue;
      }
      have.add(r.id);
      final String id = _newId();
      puts.add((
        id,
        Warranty(id: id, product: r.product.isEmpty ? r.shop : r.product, bought: r.date, months: r.warrantyMonths!, receiptId: r.id).toFields(),
      ));
    }
    if (puts.isEmpty) {
      return 0;
    }
    _remember(puts.map(((String, Map<String, Object?>) p) => p.$1));
    for (final (String, Map<String, Object?>) p in puts) {
      store.put(collection, p.$1, p.$2);
    }
    _changed();
    return puts.length;
  }

  bool linkReceipt(String id, String? receiptId) {
    final Warranty? w = byId(id);
    if (w == null) {
      return false;
    }
    _remember(<String>[id]);
    store.put(collection, id, w.withReceipt(receiptId).toFields());
    _changed();
    return true;
  }

  bool remove(String id) {
    if (byId(id) == null) {
      return false;
    }
    _remember(<String>[id]);
    store.delete(collection, id);
    _changed();
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

  /// 30 and 7 days before each warranty ends.
  List<WarrantyReminder> reminders() {
    final DateTime now = _now();
    final List<WarrantyReminder> out = <WarrantyReminder>[];
    for (final Warranty w in all) {
      for (final int d in daysAhead) {
        final DateTime at = DateTime(w.ends.year, w.ends.month, w.ends.day - d, remindHour);
        if (!at.isAfter(now)) {
          continue;
        }
        out.add(WarrantyReminder(
          id: _id('${w.id}@$d'),
          at: at,
          title: '${w.product} warranty ends in $d days',
          body: 'Ends ${dayLabel(w.ends)}. Get anything fixed while it is covered.',
          payload: '$payloadPrefix${w.id}',
        ));
      }
    }
    out.sort((WarrantyReminder a, WarrantyReminder b) => a.at.compareTo(b.at));
    return out;
  }

  Future<void> reschedule() async {
    try {
      await _scheduler.replaceAll(reminders());
    } catch (e) {
      debugPrint('warranty reminders: $e');
    }
  }

  static const List<String> months = <String>['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  static String dayLabel(DateTime d) => '${d.day} ${months[d.month - 1]} ${d.year}';

  String toText() {
    final StringBuffer b = StringBuffer('Warranties\n');
    for (final Warranty w in all) {
      b.write('- ${w.product}: bought ${dayLabel(w.bought)}, ${state(w) == WarrantyState.expired ? 'ended' : 'till'} ${dayLabel(w.ends)}');
      if (w.servicePhone.isNotEmpty) {
        b.write(' · service ${w.servicePhone}');
      }
      b.write('\n');
    }
    return b.toString();
  }

  static Warranties instance = Warranties();
  static void install(Warranties w) => instance = w;
}
