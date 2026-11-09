import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'expense_tracker.dart' show formatPaise;

/// Feature 081 — Shared expenses and settle-up.
///
/// Groups of people (family members or friends, by name) share bills split
/// equally or by custom amounts. Balances are kept in paise so they always
/// add up to zero; settle-up turns them into the fewest payments, and each
/// payment gets a drafted reminder the person can send from their own
/// messaging app. Everything stays on this phone.

const String selfName = 'Me';

class SplitGroup {
  const SplitGroup({required this.id, required this.name, required this.people});

  final String id;
  final String name;

  /// Names, with [selfName] first.
  final List<String> people;

  Map<String, Object?> toJson() => <String, Object?>{'id': id, 'name': name, 'people': people};

  static SplitGroup? fromJson(Map<String, Object?> j) {
    final Object? id = j['id'];
    final Object? people = j['people'];
    if (id is! String || people is! List) {
      return null;
    }
    return SplitGroup(id: id, name: '${j['name'] ?? 'Group'}', people: people.map((Object? p) => '$p').toList());
  }
}

class SharedExpense {
  const SharedExpense({
    required this.id,
    required this.groupId,
    required this.description,
    required this.paise,
    required this.paidBy,
    required this.shares,
    required this.at,
    this.settlement = false,
  });

  final String id;
  final String groupId;
  final String description;
  final int paise;
  final String paidBy;

  /// What each person owes of [paise]; adds up to [paise].
  final Map<String, int> shares;
  final DateTime at;

  /// A payment between two people, not a bill.
  final bool settlement;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'group': groupId,
        'desc': description,
        'paise': paise,
        'paidBy': paidBy,
        'shares': shares,
        'at': at.millisecondsSinceEpoch,
        if (settlement) 'settlement': true,
      };

  static SharedExpense? fromJson(Map<String, Object?> j) {
    final Object? id = j['id'];
    final Object? group = j['group'];
    final Object? p = j['paise'];
    final Object? at = j['at'];
    final Object? shares = j['shares'];
    if (id is! String || group is! String || p is! num || at is! num || shares is! Map) {
      return null;
    }
    final Map<String, int> s = <String, int>{};
    shares.forEach((Object? k, Object? v) {
      if (v is num) {
        s['$k'] = v.toInt();
      }
    });
    return SharedExpense(
      id: id,
      groupId: group,
      description: '${j['desc'] ?? ''}',
      paise: p.toInt(),
      paidBy: '${j['paidBy'] ?? selfName}',
      shares: s,
      at: DateTime.fromMillisecondsSinceEpoch(at.toInt()),
      settlement: j['settlement'] == true,
    );
  }
}

/// One payment that clears balances: [from] pays [to].
@immutable
class Transfer {
  const Transfer(this.from, this.to, this.paise);
  final String from;
  final String to;
  final int paise;

  @override
  bool operator ==(Object other) => other is Transfer && other.from == from && other.to == to && other.paise == paise;

  @override
  int get hashCode => Object.hash(from, to, paise);

  @override
  String toString() => '$from → $to ₹${formatPaise(paise)}';
}

class SplitError implements Exception {
  const SplitError(this.message);
  final String message;
  @override
  String toString() => message;
}

abstract final class Splits {
  /// [paise] split as evenly as paise allow; the first people in the list
  /// take the odd paise.
  static Map<String, int> equal(int paise, List<String> people) {
    if (people.isEmpty) {
      throw const SplitError('Pick at least one person to split with');
    }
    if (paise <= 0) {
      throw const SplitError('Enter an amount');
    }
    final int base = paise ~/ people.length;
    final int extra = paise % people.length;
    return <String, int>{
      for (int i = 0; i < people.length; i++) people[i]: base + (i < extra ? 1 : 0),
    };
  }

  /// Custom amounts that must add up to [paise]. Zero shares are dropped.
  static Map<String, int> custom(int paise, Map<String, int> amounts) {
    if (paise <= 0) {
      throw const SplitError('Enter an amount');
    }
    if (amounts.values.any((int v) => v < 0)) {
      throw const SplitError('Shares cannot be negative');
    }
    final int sum = amounts.values.fold<int>(0, (int a, int b) => a + b);
    if (sum != paise) {
      final int diff = paise - sum;
      throw SplitError(diff > 0
          ? 'Shares are ₹${formatPaise(diff)} short of ₹${formatPaise(paise)}'
          : 'Shares are ₹${formatPaise(-diff)} over ₹${formatPaise(paise)}');
    }
    return <String, int>{
      for (final MapEntry<String, int> e in amounts.entries)
        if (e.value > 0) e.key: e.value,
    };
  }

  /// Net per person: positive is owed to them, negative they owe.
  static Map<String, int> balances(Iterable<SharedExpense> expenses, List<String> people) {
    final Map<String, int> net = <String, int>{for (final String p in people) p: 0};
    for (final SharedExpense e in expenses) {
      net[e.paidBy] = (net[e.paidBy] ?? 0) + e.paise;
      e.shares.forEach((String who, int owed) => net[who] = (net[who] ?? 0) - owed);
    }
    return net;
  }

  /// The fewest payments (greedy, largest first) that bring every balance
  /// to zero.
  static List<Transfer> settle(Map<String, int> balances) {
    final List<MapEntry<String, int>> owe =
        balances.entries.where((MapEntry<String, int> e) => e.value < 0).map((MapEntry<String, int> e) => MapEntry<String, int>(e.key, -e.value)).toList();
    final List<MapEntry<String, int>> owed =
        balances.entries.where((MapEntry<String, int> e) => e.value > 0).map((MapEntry<String, int> e) => MapEntry<String, int>(e.key, e.value)).toList();
    final List<Transfer> out = <Transfer>[];
    int guard = 0;
    while (owe.isNotEmpty && owed.isNotEmpty && guard++ < 1000) {
      owe.sort((MapEntry<String, int> a, MapEntry<String, int> b) => b.value.compareTo(a.value));
      owed.sort((MapEntry<String, int> a, MapEntry<String, int> b) => b.value.compareTo(a.value));
      final MapEntry<String, int> d = owe.first;
      final MapEntry<String, int> c = owed.first;
      final int amount = min(d.value, c.value);
      out.add(Transfer(d.key, c.key, amount));
      owe[0] = MapEntry<String, int>(d.key, d.value - amount);
      owed[0] = MapEntry<String, int>(c.key, c.value - amount);
      owe.removeWhere((MapEntry<String, int> e) => e.value == 0);
      owed.removeWhere((MapEntry<String, int> e) => e.value == 0);
    }
    return out;
  }

  /// A friendly nudge for one payment, from the phone owner's side.
  static String reminder(Transfer t, String groupName) {
    final String amount = '₹${formatPaise(t.paise)}';
    if (t.to == selfName) {
      return 'Hi ${t.from}, a gentle reminder from our "$groupName" expenses: '
          'you owe me $amount. Pay whenever it suits you. Thanks!';
    }
    if (t.from == selfName) {
      return 'Hi ${t.to}, as per our "$groupName" expenses I owe you $amount. '
          'Sending it soon. Thanks!';
    }
    return 'Hi ${t.from}, from our "$groupName" expenses: please pay ${t.to} $amount when you can. Thanks!';
  }
}

abstract interface class SharedExpenseStore {
  Future<Map<String, Object?>?> load();
  Future<void> save(Map<String, Object?> data);
}

class MemorySharedExpenseStore implements SharedExpenseStore {
  Map<String, Object?>? data;

  @override
  Future<Map<String, Object?>?> load() async => data;

  @override
  Future<void> save(Map<String, Object?> value) async {
    data = jsonDecode(jsonEncode(value)) as Map<String, Object?>;
  }
}

/// shared_expenses.json in the app's private folder.
class FileSharedExpenseStore implements SharedExpenseStore {
  FileSharedExpenseStore(this.folder);
  final Future<Directory> Function() folder;

  Future<File> _file() async => File('${(await folder()).path}/shared_expenses.json');

  @override
  Future<Map<String, Object?>?> load() async {
    final File f = await _file();
    if (!f.existsSync()) {
      return null;
    }
    final Object? json = jsonDecode(await f.readAsString());
    return json is Map<String, Object?> ? json : null;
  }

  @override
  Future<void> save(Map<String, Object?> data) async {
    final File f = await _file();
    await f.parent.create(recursive: true);
    final File tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode(data));
    await tmp.rename(f.path);
  }
}

class SharedExpenses extends ChangeNotifier {
  SharedExpenses({SharedExpenseStore? store, DateTime Function()? now})
      : _store = store ?? MemorySharedExpenseStore(),
        _now = now ?? DateTime.now;

  final SharedExpenseStore _store;
  final DateTime Function() _now;
  List<SplitGroup> _groups = <SplitGroup>[];
  List<SharedExpense> _expenses = <SharedExpense>[];
  final List<(List<SplitGroup>, List<SharedExpense>)> _undo = <(List<SplitGroup>, List<SharedExpense>)>[];

  List<SplitGroup> get groups => List<SplitGroup>.unmodifiable(_groups);
  bool get canUndo => _undo.isNotEmpty;

  SplitGroup? group(String id) {
    for (final SplitGroup g in _groups) {
      if (g.id == id) {
        return g;
      }
    }
    return null;
  }

  /// Newest first.
  List<SharedExpense> expensesOf(String groupId) =>
      _expenses.where((SharedExpense e) => e.groupId == groupId).toList()
        ..sort((SharedExpense a, SharedExpense b) => b.at.compareTo(a.at));

  Map<String, int> balancesOf(String groupId) {
    final SplitGroup? g = group(groupId);
    return Splits.balances(expensesOf(groupId), g?.people ?? const <String>[]);
  }

  List<Transfer> settleUp(String groupId) => Splits.settle(balancesOf(groupId));

  Future<void> load() async {
    try {
      final Map<String, Object?>? data = await _store.load();
      if (data != null) {
        final Object? g = data['groups'];
        final Object? e = data['expenses'];
        _groups = g is List
            ? g.whereType<Map>().map((Map m) => SplitGroup.fromJson(Map<String, Object?>.from(m))).whereType<SplitGroup>().toList()
            : <SplitGroup>[];
        _expenses = e is List
            ? e
                .whereType<Map>()
                .map((Map m) => SharedExpense.fromJson(Map<String, Object?>.from(m)))
                .whereType<SharedExpense>()
                .toList()
            : <SharedExpense>[];
      }
    } catch (_) {
      // A damaged file starts empty rather than crashing the screen.
    }
    notifyListeners();
  }

  void _remember() {
    _undo.add((List<SplitGroup>.of(_groups), List<SharedExpense>.of(_expenses)));
    if (_undo.length > 30) {
      _undo.removeAt(0);
    }
  }

  Future<void> _persist() async {
    notifyListeners();
    await _store.save(<String, Object?>{
      'v': 1,
      'groups': _groups.map((SplitGroup g) => g.toJson()).toList(),
      'expenses': _expenses.map((SharedExpense e) => e.toJson()).toList(),
    });
  }

  static String newId() {
    final Random r = Random();
    return '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${r.nextInt(1 << 20).toRadixString(36)}';
  }

  /// [people] are the others; [selfName] is always first.
  Future<SplitGroup> addGroup(String name, List<String> people) async {
    final List<String> names = <String>[selfName];
    for (final String p in people) {
      final String t = p.trim();
      if (t.isNotEmpty && !names.any((String n) => n.toLowerCase() == t.toLowerCase())) {
        names.add(t);
      }
    }
    if (names.length < 2) {
      throw const SplitError('Add at least one other person');
    }
    final SplitGroup g = SplitGroup(id: newId(), name: name.trim().isEmpty ? 'Group' : name.trim(), people: names);
    _remember();
    _groups = <SplitGroup>[..._groups, g];
    await _persist();
    return g;
  }

  Future<void> removeGroup(String id) async {
    _remember();
    _groups = _groups.where((SplitGroup g) => g.id != id).toList();
    _expenses = _expenses.where((SharedExpense e) => e.groupId != id).toList();
    await _persist();
  }

  Future<SharedExpense> addExpense({
    required String groupId,
    required String description,
    required int paise,
    required String paidBy,
    required Map<String, int> shares,
  }) async {
    final SplitGroup? g = group(groupId);
    if (g == null) {
      throw const SplitError('That group is gone');
    }
    final int sum = shares.values.fold<int>(0, (int a, int b) => a + b);
    if (sum != paise || shares.isEmpty) {
      throw const SplitError('Shares must add up to the amount');
    }
    final SharedExpense e = SharedExpense(
      id: newId(),
      groupId: groupId,
      description: description.trim().isEmpty ? 'Expense' : description.trim(),
      paise: paise,
      paidBy: paidBy,
      shares: Map<String, int>.of(shares),
      at: _now(),
    );
    _remember();
    _expenses = <SharedExpense>[..._expenses, e];
    await _persist();
    return e;
  }

  /// Records [t] as paid.
  Future<SharedExpense> settle(String groupId, Transfer t) async {
    final SharedExpense e = SharedExpense(
      id: newId(),
      groupId: groupId,
      description: '${t.from} paid ${t.to}',
      paise: t.paise,
      paidBy: t.from,
      shares: <String, int>{t.to: t.paise},
      at: _now(),
      settlement: true,
    );
    _remember();
    _expenses = <SharedExpense>[..._expenses, e];
    await _persist();
    return e;
  }

  Future<void> removeExpense(String id) async {
    _remember();
    _expenses = _expenses.where((SharedExpense e) => e.id != id).toList();
    await _persist();
  }

  Future<bool> undo() async {
    if (_undo.isEmpty) {
      return false;
    }
    final (List<SplitGroup> g, List<SharedExpense> e) = _undo.removeLast();
    _groups = g;
    _expenses = e;
    await _persist();
    return true;
  }

  /// Balances and settle-up, as text to share or save.
  String summary(String groupId) {
    final SplitGroup? g = group(groupId);
    if (g == null) {
      return '';
    }
    final StringBuffer b = StringBuffer('${g.name}\n');
    final Map<String, int> bal = balancesOf(groupId);
    for (final String p in g.people) {
      final int v = bal[p] ?? 0;
      b.writeln(v == 0
          ? '$p: settled'
          : v > 0
              ? '$p: gets back ₹${formatPaise(v)}'
              : '$p: owes ₹${formatPaise(-v)}');
    }
    final List<Transfer> plan = settleUp(groupId);
    if (plan.isNotEmpty) {
      b.writeln('\nTo settle up:');
      for (final Transfer t in plan) {
        b.writeln('${t.from} pays ${t.to} ₹${formatPaise(t.paise)}');
      }
    }
    return b.toString().trimRight();
  }

  static SharedExpenses instance = SharedExpenses();
  static void install(SharedExpenses s) => instance = s;
}
