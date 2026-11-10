import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../app/widgets/result_bar.dart';
import '../../engines/records/expense_tracker.dart' show parsePaise;
import '../../engines/records/loans.dart';
import '../../engines/share/share_engine.dart';

/// Feature 087 — loans with EMI, amortisation schedule, prepayment
/// what-if and EMI reminders.
class LoansScreen extends StatefulWidget {
  const LoansScreen({super.key, this.loans, this.share, this.save});

  final Loans? loans;
  final Future<void> Function(String text)? share;
  final Future<String?> Function(String text, String name)? save;

  @override
  State<LoansScreen> createState() => _LoansScreenState();
}

class _LoansScreenState extends State<LoansScreen> {
  Loans get _l => widget.loans ?? Loans.instance;
  String? _openId;
  PrepaymentEffect? _effect;
  final TextEditingController _extra = TextEditingController();

  @override
  void dispose() {
    _extra.dispose();
    super.dispose();
  }

  void _snack(String s) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
    }
  }

  Loan? get _open {
    final List<Loan> all = _l.all;
    for (final Loan x in all) {
      if (x.id == _openId) {
        return x;
      }
    }
    return all.isEmpty ? null : all.first;
  }

  String _resultText() {
    final Loan? l = _open;
    return l == null ? '' : Loans.scheduleCsv(l);
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
    final Loan? l = _open;
    if (l == null) {
      _snack('Add a loan first');
      return;
    }
    String? where;
    try {
      where = await (widget.save ?? _saveToDocuments)(_resultText(), '${l.name} schedule.csv');
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
    final TextEditingController name = TextEditingController();
    final TextEditingController amount = TextEditingController();
    final TextEditingController rate = TextEditingController();
    final TextEditingController months = TextEditingController();
    final TextEditingController first = TextEditingController();
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Add a loan'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextField(key: const Key('loan-name'), controller: name, decoration: const InputDecoration(labelText: 'Name', hintText: 'Home loan')),
              TextField(
                key: const Key('loan-amount'),
                controller: amount,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Loan amount (₹)'),
              ),
              TextField(
                key: const Key('loan-rate'),
                controller: rate,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Interest rate (% a year)'),
              ),
              TextField(
                key: const Key('loan-months'),
                controller: months,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Tenure (months)'),
              ),
              TextField(
                key: const Key('loan-first'),
                controller: first,
                keyboardType: TextInputType.datetime,
                decoration: const InputDecoration(labelText: 'First EMI date', hintText: '05/01/2026'),
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(key: const Key('loan-save'), onPressed: () => Navigator.pop(context, true), child: const Text('Add')),
        ],
      ),
    );
    if (ok != true) {
      return;
    }
    final int? p = parsePaise(amount.text);
    final double? r = double.tryParse(rate.text.trim());
    final int? m = int.tryParse(months.text.trim());
    final DateTime? d = parseDay(first.text);
    final Loan? l = p == null || r == null || m == null || d == null
        ? null
        : _l.add(name: name.text, principal: p, ratePct: r, months: m, firstEmi: d);
    if (l != null) {
      setState(() {
        _openId = l.id;
        _effect = null;
      });
    }
    _snack(l == null ? 'Fill in the amount, rate, months and first EMI date' : 'EMI ${Loans.amountLabel(l.emi)}');
  }

  void _whatIf(Loan l) {
    final int? p = parsePaise(_extra.text);
    if (p == null || p <= 0) {
      _snack('Type a prepayment amount');
      return;
    }
    final DateTime n = DateTime.now();
    final EmiRow? next = _l.nextEmi(l);
    setState(() => _effect = Loans.whatIf(l, p, next?.on ?? DateTime(n.year, n.month, n.day)));
  }

  void _prepay(Loan l) {
    final int? p = parsePaise(_extra.text);
    _snack(p != null && _l.prepay(l.id, p) ? 'Prepayment recorded' : 'Type a prepayment amount');
    setState(() => _effect = null);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Loans')),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('loan-add'),
        onPressed: () => unawaited(_add()),
        icon: const Icon(Icons.add),
        label: const Text('Add loan'),
      ),
      bottomNavigationBar: ResultBar(
        onShare: () => unawaited(_shareText(_resultText())),
        onSave: () => unawaited(_save()),
        onUndo: () {
          setState(() => _effect = null);
          _snack(_l.undo() ? 'Undone' : 'Nothing to undo');
        },
      ),
      body: ListenableBuilder(listenable: Listenable.merge(<Listenable>[_l, _l.store]), builder: (BuildContext context, Widget? _) => _body(context)),
    );
  }

  Widget _body(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final Loan? l = _open;
    if (l == null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text('No loans yet. Add one to see its EMI, schedule and what a prepayment saves.', style: text.bodyMedium),
      );
    }
    final List<EmiRow> rows = Loans.schedule(l);
    final EmiRow? next = _l.nextEmi(l);
    final int interest = Loans.totalInterest(rows);
    final PrepaymentEffect? e = _effect;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: <Widget>[
        Wrap(
          spacing: 8,
          children: <Widget>[
            for (final Loan x in _l.all)
              ChoiceChip(
                key: Key('loan-chip-${x.id}'),
                label: Text(x.name),
                selected: x.id == l.id,
                onSelected: (bool _) => setState(() {
                  _openId = x.id;
                  _effect = null;
                }),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text('EMI ${Loans.amountLabel(l.emi)}', key: const Key('loan-emi'), style: text.headlineSmall),
        Text('Balance today ${Loans.amountLabel(_l.balanceToday(l))}', key: const Key('loan-balance')),
        Text(next == null ? 'All EMIs paid' : 'Next EMI ${Loans.dayLabel(next.on)}', key: const Key('loan-next')),
        Text(
          '${rows.length} EMIs · interest ${Loans.amountLabel(interest)} · last ${rows.isEmpty ? '-' : Loans.monthLabel(rows.last.on)}',
          key: const Key('loan-summary'),
          style: text.bodySmall,
        ),
        const Divider(height: 24),
        Text('Prepayment what-if', style: text.titleMedium),
        TextField(
          key: const Key('loan-extra'),
          controller: _extra,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Pay extra (₹) at the next EMI'),
        ),
        Wrap(
          spacing: 8,
          children: <Widget>[
            TextButton.icon(
              key: const Key('loan-whatif'),
              style: TextButton.styleFrom(minimumSize: const Size(88, 48)),
              onPressed: () => _whatIf(l),
              icon: const Icon(Icons.calculate_outlined),
              label: const Text('What if'),
            ),
            TextButton.icon(
              key: const Key('loan-prepay'),
              style: TextButton.styleFrom(minimumSize: const Size(88, 48)),
              onPressed: () => _prepay(l),
              icon: const Icon(Icons.savings_outlined),
              label: const Text('I paid this'),
            ),
            TextButton.icon(
              key: const Key('loan-delete'),
              style: TextButton.styleFrom(minimumSize: const Size(88, 48)),
              onPressed: () => _l.remove(l.id),
              icon: const Icon(Icons.delete_outline),
              label: const Text('Delete loan'),
            ),
          ],
        ),
        if (e != null)
          Semantics(
            container: true,
            child: Text(
              'Saves ${e.monthsSaved} EMI${e.monthsSaved == 1 ? '' : 's'} and ${Loans.amountLabel(e.interestSaved)} interest; '
              'last EMI ${Loans.monthLabel(e.newLastEmi)} instead of ${Loans.monthLabel(e.oldLastEmi)}',
              key: const Key('loan-effect'),
            ),
          ),
        const Divider(height: 24),
        Text('Schedule', style: text.titleMedium),
        for (final EmiRow r in rows.take(120))
          ListTile(
            key: Key('loan-row-${r.n}'),
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text('${r.n}. ${Loans.dayLabel(r.on)} · ${Loans.amountLabel(r.emi)}'),
            subtitle: Text('Interest ${Loans.amountLabel(r.interest)} · principal ${Loans.amountLabel(r.principal)} · left ${Loans.amountLabel(r.balance)}'),
          ),
      ],
    );
  }
}
