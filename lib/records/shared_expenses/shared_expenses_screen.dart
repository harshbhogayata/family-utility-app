import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../app/widgets/result_bar.dart';
import '../../engines/family/family_space.dart';
import '../../engines/family/family_store.dart' show FamilyRecord;
import '../../engines/records/expense_tracker.dart' show formatPaise, parsePaise;
import '../../engines/records/shared_expenses.dart';
import '../../engines/share/share_engine.dart';

typedef TextSink = Future<void> Function(String text);
typedef TextSaver = Future<String?> Function(String name, String text);

/// Feature 081 — split bills with family or friends and settle up.
class SharedExpensesScreen extends StatefulWidget {
  const SharedExpensesScreen({super.key, this.store, this.familyNames, this.share, this.save});

  final SharedExpenses? store;

  /// Names offered when making a group; defaults to the family space members.
  final List<String>? familyNames;
  final TextSink? share;
  final TextSaver? save;

  @override
  State<SharedExpensesScreen> createState() => _SharedExpensesScreenState();
}

class _SharedExpensesScreenState extends State<SharedExpensesScreen> {
  SharedExpenses get _s => widget.store ?? SharedExpenses.instance;

  @override
  void initState() {
    super.initState();
    _s.addListener(_changed);
  }

  @override
  void dispose() {
    _s.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) {
      setState(() {});
    }
  }

  void _snack(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(m)));
    }
  }

  List<String> get _family {
    final List<String>? given = widget.familyNames;
    if (given != null) {
      return given;
    }
    final FamilySpace space = FamilySpace.instance;
    if (!space.inFamily) {
      return const <String>[];
    }
    final String? mine = space.identity?.memberName;
    return space.memberRecords
        .map((FamilyRecord r) => '${r.fields['name'] ?? ''}'.trim())
        .where((String n) => n.isNotEmpty && n != mine)
        .toList();
  }

  Future<void> _newGroup() async {
    final TextEditingController name = TextEditingController();
    final TextEditingController people = TextEditingController(text: _family.join(', '));
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('New group'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              key: const Key('group-name'),
              controller: name,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Name', hintText: 'Home, Goa trip'),
            ),
            TextField(
              key: const Key('group-people'),
              controller: people,
              decoration: const InputDecoration(labelText: 'People besides you', hintText: 'Ramesh, Priya'),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(key: const Key('group-ok'), onPressed: () => Navigator.of(context).pop(true), child: const Text('Create')),
        ],
      ),
    );
    if (ok != true) {
      return;
    }
    try {
      final SplitGroup g = await _s.addGroup(name.text, people.text.split(','));
      if (mounted) {
        await _open(g);
      }
    } on SplitError catch (e) {
      _snack(e.message);
    }
  }

  Future<void> _open(SplitGroup g) => Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (BuildContext context) =>
              SplitGroupScreen(store: _s, groupId: g.id, share: widget.share, save: widget.save),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final List<SplitGroup> groups = _s.groups;
    return Scaffold(
      appBar: AppBar(title: const Text('Shared expenses')),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('new-group'),
        onPressed: () => unawaited(_newGroup()),
        icon: const Icon(Icons.group_add_outlined),
        label: const Text('New group'),
      ),
      body: groups.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('Make a group for the home or a trip, then add who paid for what.', textAlign: TextAlign.center),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
              children: <Widget>[
                for (final SplitGroup g in groups) _groupTile(g),
              ],
            ),
    );
  }

  Widget _groupTile(SplitGroup g) {
    final int mine = _s.balancesOf(g.id)[selfName] ?? 0;
    return ListTile(
      key: Key('group-${g.name}'),
      contentPadding: EdgeInsets.zero,
      minTileHeight: 56,
      leading: const Icon(Icons.groups_outlined),
      title: Text(g.name),
      subtitle: Text(mine == 0
          ? 'You are settled'
          : mine > 0
              ? 'You get back ₹${formatPaise(mine)}'
              : 'You owe ₹${formatPaise(-mine)}'),
      onTap: () => unawaited(_open(g)),
    );
  }
}

class SplitGroupScreen extends StatefulWidget {
  const SplitGroupScreen({super.key, required this.store, required this.groupId, this.share, this.save});

  final SharedExpenses store;
  final String groupId;
  final TextSink? share;
  final TextSaver? save;

  @override
  State<SplitGroupScreen> createState() => _SplitGroupScreenState();
}

class _SplitGroupScreenState extends State<SplitGroupScreen> {
  SharedExpenses get _s => widget.store;

  @override
  void initState() {
    super.initState();
    _s.addListener(_changed);
  }

  @override
  void dispose() {
    _s.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) {
      setState(() {});
    }
  }

  void _snack(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(m)));
    }
  }

  Future<void> _shareText(String text, String subject) async {
    final TextSink? s = widget.share;
    if (s != null) {
      await s(text);
    } else {
      await ShareEngine.instance.shareText(text, subject: subject);
    }
  }

  Future<void> _save(SplitGroup g) async {
    String? where;
    final String text = _s.summary(g.id);
    try {
      final TextSaver? s = widget.save;
      if (s != null) {
        where = await s('${g.name}.txt', text);
      } else {
        final Directory dir = await getApplicationDocumentsDirectory();
        final File f = File('${dir.path}/Split-${g.name.replaceAll(RegExp(r'[^A-Za-z0-9 _-]'), '')}.txt');
        await f.writeAsString(text);
        where = f.path;
      }
    } catch (_) {
      where = null;
    }
    _snack(where == null ? 'Could not save' : 'Saved to $where');
  }

  Future<void> _undo() async {
    _snack(await _s.undo() ? 'Undone' : 'Nothing to undo');
  }

  Future<void> _addExpense(SplitGroup g) async {
    final Map<String, int>? done = await showDialog<Map<String, int>>(
      context: context,
      builder: (BuildContext context) => _ExpenseDialog(group: g, onSubmit: (String desc, int paise, String paidBy, Map<String, int> shares) async {
        await _s.addExpense(groupId: g.id, description: desc, paise: paise, paidBy: paidBy, shares: shares);
      }),
    );
    if (done != null) {
      _snack('Added');
    }
  }

  Future<void> _markPaid(Transfer t) async {
    await _s.settle(widget.groupId, t);
    _snack('${t.from} paid ${t.to} ₹${formatPaise(t.paise)}');
  }

  @override
  Widget build(BuildContext context) {
    final SplitGroup? g = _s.group(widget.groupId);
    final TextTheme text = Theme.of(context).textTheme;
    if (g == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: Text('This group was removed')));
    }
    final Map<String, int> bal = _s.balancesOf(g.id);
    final List<Transfer> plan = _s.settleUp(g.id);
    final List<SharedExpense> list = _s.expensesOf(g.id);
    return Scaffold(
      appBar: AppBar(title: Text(g.name)),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('add-expense'),
        onPressed: () => unawaited(_addExpense(g)),
        icon: const Icon(Icons.add),
        label: const Text('Add expense'),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      bottomNavigationBar: ResultBar(
        onShare: () => unawaited(_shareText(_s.summary(g.id), g.name)),
        onSave: () => unawaited(_save(g)),
        onUndo: () => unawaited(_undo()),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
        children: <Widget>[
          Text('Balances', style: text.titleMedium),
          for (final String p in g.people)
            Semantics(
              container: true,
              label: '$p: ${_balanceText(bal[p] ?? 0)}',
              child: ExcludeSemantics(
                child: ListTile(
                  key: Key('balance-$p'),
                  contentPadding: EdgeInsets.zero,
                  minTileHeight: 48,
                  title: Text(p),
                  trailing: Text(_balanceText(bal[p] ?? 0)),
                ),
              ),
            ),
          const SizedBox(height: 8),
          Text('Settle up', style: text.titleMedium),
          if (plan.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('Everyone is settled')),
          for (int i = 0; i < plan.length; i++)
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('${plan[i].from} pays ${plan[i].to} ₹${formatPaise(plan[i].paise)}', key: Key('transfer-$i')),
                    Wrap(
                      spacing: 8,
                      children: <Widget>[
                        TextButton.icon(
                          key: Key('remind-$i'),
                          style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                          onPressed: () => unawaited(_shareText(Splits.reminder(plan[i], g.name), 'Reminder')),
                          icon: const Icon(Icons.chat_outlined),
                          label: const Text('Send reminder'),
                        ),
                        TextButton.icon(
                          key: Key('paid-$i'),
                          style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                          onPressed: () => unawaited(_markPaid(plan[i])),
                          icon: const Icon(Icons.check),
                          label: const Text('Mark paid'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 8),
          Text('Expenses', style: text.titleMedium),
          if (list.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('Nothing added yet')),
          for (final SharedExpense e in list)
            ListTile(
              contentPadding: EdgeInsets.zero,
              minTileHeight: 56,
              leading: Icon(e.settlement ? Icons.swap_horiz : Icons.receipt_long_outlined),
              title: Text(e.description),
              subtitle: Text(e.settlement
                  ? '₹${formatPaise(e.paise)}'
                  : '₹${formatPaise(e.paise)} paid by ${e.paidBy} · split ${e.shares.length} ways'),
              trailing: IconButton(
                tooltip: 'Delete ${e.description}',
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                icon: const Icon(Icons.delete_outline),
                onPressed: () => unawaited(_s.removeExpense(e.id)),
              ),
            ),
        ],
      ),
    );
  }

  static String _balanceText(int v) => v == 0
      ? 'settled'
      : v > 0
          ? 'gets back ₹${formatPaise(v)}'
          : 'owes ₹${formatPaise(-v)}';
}

typedef _Submit = Future<void> Function(String desc, int paise, String paidBy, Map<String, int> shares);

class _ExpenseDialog extends StatefulWidget {
  const _ExpenseDialog({required this.group, required this.onSubmit});
  final SplitGroup group;
  final _Submit onSubmit;

  @override
  State<_ExpenseDialog> createState() => _ExpenseDialogState();
}

class _ExpenseDialogState extends State<_ExpenseDialog> {
  final TextEditingController _desc = TextEditingController();
  final TextEditingController _amount = TextEditingController();
  String _paidBy = selfName;
  bool _custom = false;
  late final Set<String> _included = widget.group.people.toSet();
  late final Map<String, TextEditingController> _shares = <String, TextEditingController>{
    for (final String p in widget.group.people) p: TextEditingController(),
  };
  String? _error;

  @override
  void dispose() {
    _desc.dispose();
    _amount.dispose();
    for (final TextEditingController c in _shares.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    final int? paise = parsePaise(_amount.text);
    try {
      if (paise == null) {
        throw const SplitError('Enter an amount');
      }
      final Map<String, int> shares;
      if (_custom) {
        final Map<String, int> amounts = <String, int>{};
        for (final MapEntry<String, TextEditingController> e in _shares.entries) {
          final String t = e.value.text.trim();
          if (t.isEmpty) {
            continue;
          }
          final int? v = parsePaise(t);
          if (v == null) {
            throw SplitError('Check the share for ${e.key}');
          }
          amounts[e.key] = v;
        }
        shares = Splits.custom(paise, amounts);
      } else {
        shares = Splits.equal(paise, widget.group.people.where(_included.contains).toList());
      }
      await widget.onSubmit(_desc.text, paise, _paidBy, shares);
      if (mounted) {
        Navigator.of(context).pop(shares);
      }
    } on SplitError catch (e) {
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<String> people = widget.group.people;
    return AlertDialog(
      title: const Text('Add expense'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            TextField(
              key: const Key('expense-desc'),
              controller: _desc,
              decoration: const InputDecoration(labelText: 'What for', hintText: 'Dinner, electricity'),
            ),
            TextField(
              key: const Key('expense-amount'),
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Amount (₹)'),
            ),
            DropdownButtonFormField<String>(
              key: const Key('expense-paid-by'),
              initialValue: _paidBy,
              decoration: const InputDecoration(labelText: 'Paid by'),
              items: <DropdownMenuItem<String>>[
                for (final String p in people) DropdownMenuItem<String>(value: p, child: Text(p)),
              ],
              onChanged: (String? v) => setState(() => _paidBy = v ?? selfName),
            ),
            const SizedBox(height: 8),
            SegmentedButton<bool>(
              key: const Key('expense-mode'),
              segments: const <ButtonSegment<bool>>[
                ButtonSegment<bool>(value: false, label: Text('Equally')),
                ButtonSegment<bool>(value: true, label: Text('Custom')),
              ],
              selected: <bool>{_custom},
              onSelectionChanged: (Set<bool> v) => setState(() => _custom = v.first),
            ),
            for (final String p in people)
              _custom
                  ? TextField(
                      key: Key('share-$p'),
                      controller: _shares[p],
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(labelText: '$p owes (₹)'),
                    )
                  : CheckboxListTile(
                      key: Key('include-$p'),
                      contentPadding: EdgeInsets.zero,
                      title: Text(p),
                      value: _included.contains(p),
                      onChanged: (bool? v) => setState(() => v == true ? _included.add(p) : _included.remove(p)),
                    ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!, key: const Key('expense-error'), style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(key: const Key('expense-ok'), onPressed: () => unawaited(_submit()), child: const Text('Add')),
      ],
    );
  }
}
