import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../app/widgets/result_bar.dart';
import '../../engines/records/expense_tracker.dart' show parsePaise;
import '../../engines/records/lending_ledger.dart';
import '../../engines/share/share_engine.dart';

/// Feature 082 — money lent and borrowed: who, amount, date, due date and
/// status, with reminders before the due date.
class LendingScreen extends StatefulWidget {
  const LendingScreen({super.key, this.ledger, this.share, this.save});

  final LendingLedger? ledger;
  final Future<void> Function(String text)? share;
  final Future<String?> Function(String text, String name)? save;

  @override
  State<LendingScreen> createState() => _LendingScreenState();
}

class _LendingScreenState extends State<LendingScreen> {
  LendingLedger get _l => widget.ledger ?? LendingLedger.instance;

  void _snack(String s) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
    }
  }

  Future<void> _shareText(String text) async {
    final Future<void> Function(String)? s = widget.share;
    if (s != null) {
      await s(text);
      return;
    }
    await ShareEngine.instance.shareText(text);
  }

  static Future<String?> _saveToDocuments(String text, String name) async {
    final Directory dir = await getApplicationDocumentsDirectory();
    final File f = File('${dir.path}/$name');
    await f.writeAsString(text);
    return f.path;
  }

  Future<void> _save() async {
    String? where;
    try {
      where = await (widget.save ?? _saveToDocuments)(_l.toText(), 'Lending ledger.txt');
    } catch (_) {
      where = null;
    }
    _snack(where == null ? 'Could not save' : 'Saved to $where');
  }

  static DateTime? parseDay(String s) {
    final RegExpMatch? m = RegExp(r'^\s*(\d{1,2})[/.\-](\d{1,2})[/.\-](\d{4})\s*$').firstMatch(s);
    if (m == null) {
      return null;
    }
    final int d = int.parse(m.group(1)!), mo = int.parse(m.group(2)!), y = int.parse(m.group(3)!);
    final DateTime out = DateTime(y, mo, d);
    return out.month == mo && out.day == d ? out : null;
  }

  Future<void> _add() async {
    final TextEditingController who = TextEditingController();
    final TextEditingController amount = TextEditingController();
    final TextEditingController date = TextEditingController();
    final TextEditingController due = TextEditingController();
    final TextEditingController note = TextEditingController();
    LendDirection dir = LendDirection.lent;
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Add money lent or borrowed'),
        content: StatefulBuilder(
          builder: (BuildContext context, StateSetter set) => SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                SegmentedButton<LendDirection>(
                  key: const Key('lend-direction'),
                  segments: <ButtonSegment<LendDirection>>[
                    for (final LendDirection d in LendDirection.values)
                      ButtonSegment<LendDirection>(value: d, label: Text(d == LendDirection.lent ? 'I lent' : 'I borrowed', key: Key('lend-dir-${d.name}'))),
                  ],
                  selected: <LendDirection>{dir},
                  onSelectionChanged: (Set<LendDirection> s) => set(() => dir = s.first),
                ),
                TextField(key: const Key('lend-who'), controller: who, decoration: const InputDecoration(labelText: 'Who')),
                TextField(
                  key: const Key('lend-amount'),
                  controller: amount,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Amount (₹)'),
                ),
                TextField(
                  key: const Key('lend-date'),
                  controller: date,
                  keyboardType: TextInputType.datetime,
                  decoration: const InputDecoration(labelText: 'Date (blank for today)', hintText: '05/12/2026'),
                ),
                TextField(
                  key: const Key('lend-due'),
                  controller: due,
                  keyboardType: TextInputType.datetime,
                  decoration: const InputDecoration(labelText: 'Due date (optional)', hintText: '05/01/2027'),
                ),
                TextField(key: const Key('lend-note'), controller: note, decoration: const InputDecoration(labelText: 'Note (optional)')),
              ],
            ),
          ),
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(key: const Key('lend-save'), onPressed: () => Navigator.pop(context, true), child: const Text('Add')),
        ],
      ),
    );
    if (ok != true) {
      return;
    }
    final int? p = parsePaise(amount.text);
    final DateTime? on = date.text.trim().isEmpty ? null : parseDay(date.text);
    final DateTime? dueOn = due.text.trim().isEmpty ? null : parseDay(due.text);
    final bool datesOk = (date.text.trim().isEmpty || on != null) && (due.text.trim().isEmpty || dueOn != null);
    final LendEntry? e = p == null || !datesOk ? null : _l.add(direction: dir, who: who.text, paise: p, date: on, due: dueOn, note: note.text);
    _snack(e == null ? 'Type who, an amount, and dates like 05/12/2026 (due on or after the date)' : 'Added: ${LendingLedger.headline(e)}');
  }

  Future<void> _repay(LendEntry e) async {
    final TextEditingController amount = TextEditingController(text: (e.remaining / 100).toStringAsFixed(e.remaining % 100 == 0 ? 0 : 2));
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(e.direction == LendDirection.lent ? '${e.who} paid back' : 'You paid ${e.who} back'),
        content: TextField(
          key: const Key('lend-repay-amount'),
          controller: amount,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Amount (₹)'),
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(key: const Key('lend-repay-save'), onPressed: () => Navigator.pop(context, true), child: const Text('Record')),
        ],
      ),
    );
    if (ok != true) {
      return;
    }
    final int? p = parsePaise(amount.text);
    if (p == null || !_l.repay(e.id, p)) {
      _snack('Type the amount paid back');
      return;
    }
    final LendEntry now = _l.byId(e.id)!;
    _snack(now.status == LendStatus.settled ? 'Settled' : '${LendingLedger.amountLabel(now.remaining)} left');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Lending ledger')),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('lend-add'),
        onPressed: () => unawaited(_add()),
        icon: const Icon(Icons.add),
        label: const Text('Add'),
      ),
      bottomNavigationBar: ResultBar(
        onShare: () => unawaited(_shareText(_l.toText())),
        onSave: () => unawaited(_save()),
        onUndo: () => _snack(_l.undo() ? 'Undone' : 'Nothing to undo'),
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge(<Listenable>[_l, _l.store]),
        builder: (BuildContext context, Widget? _) => _body(context),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final List<LendEntry> list = _l.all;
    if (list.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text('Nothing lent or borrowed yet. Add who, how much and when it is due back.', style: text.bodyMedium),
      );
    }
    final (int toYou, int byYou) = _l.totals();
    final List<PersonBalance> people = _l.balances();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: <Widget>[
        Semantics(
          container: true,
          child: Text(
            'Owed to you ${LendingLedger.amountLabel(toYou)} · You owe ${LendingLedger.amountLabel(byYou)}',
            key: const Key('lend-totals'),
            style: text.titleMedium,
          ),
        ),
        for (final PersonBalance p in people)
          Text(
            p.netPaise > 0
                ? '${p.who} owes you ${LendingLedger.amountLabel(p.netPaise)}'
                : 'You owe ${p.who} ${LendingLedger.amountLabel(-p.netPaise)}',
            style: text.bodySmall,
          ),
        const SizedBox(height: 8),
        for (final LendEntry e in list) _card(context, e),
      ],
    );
  }

  Widget _card(BuildContext context, LendEntry e) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme cs = Theme.of(context).colorScheme;
    final int? days = _l.daysUntil(e);
    final bool settled = e.status == LendStatus.settled;
    final String when = settled || days == null
        ? e.status.label
        : (days < 0
            ? 'Overdue by ${-days} day${days == -1 ? '' : 's'}'
            : (days == 0 ? 'Due today' : (days == 1 ? 'Due tomorrow' : 'Due in $days days')));
    return Card(
      key: Key('lend-${e.id}'),
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(settled ? '${e.who} · settled' : LendingLedger.headline(e), style: text.titleMedium),
            Text(
              '${e.direction.label} ${LendingLedger.amountLabel(e.paise)} on ${LendingLedger.dayLabel(e.date)}'
              '${e.due == null ? '' : ' · due ${LendingLedger.dayLabel(e.due!)}'} · ${e.status.label}',
              style: text.bodySmall,
            ),
            if (e.note.isNotEmpty) Text(e.note, style: text.bodySmall),
            Text(when, key: Key('lend-when-${e.id}'), style: text.bodyMedium?.copyWith(color: _l.isOverdue(e) ? cs.error : null)),
            for (final Repayment r in e.repayments.reversed.take(3))
              Text('Paid back ${LendingLedger.amountLabel(r.paise)} on ${LendingLedger.dayLabel(r.on)}', style: text.bodySmall),
            Wrap(
              spacing: 8,
              children: <Widget>[
                if (!settled) ...<Widget>[
                  TextButton.icon(
                    key: Key('lend-repay-${e.id}'),
                    style: TextButton.styleFrom(minimumSize: const Size(88, 48)),
                    onPressed: () => unawaited(_repay(e)),
                    icon: const Icon(Icons.payments_outlined),
                    label: const Text('Paid back'),
                  ),
                  TextButton.icon(
                    key: Key('lend-settle-${e.id}'),
                    style: TextButton.styleFrom(minimumSize: const Size(88, 48)),
                    onPressed: () => _snack(_l.settle(e.id) ? 'Settled' : 'Already settled'),
                    icon: const Icon(Icons.done_all),
                    label: const Text('Settle'),
                  ),
                ],
                TextButton.icon(
                  key: Key('lend-delete-${e.id}'),
                  style: TextButton.styleFrom(minimumSize: const Size(88, 48)),
                  onPressed: () => _l.remove(e.id),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Delete'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
