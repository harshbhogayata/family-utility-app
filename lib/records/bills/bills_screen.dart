import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../app/widgets/result_bar.dart';
import '../../engines/records/bills.dart';
import '../../engines/records/expense_tracker.dart' show parsePaise;
import '../../engines/records/receipt_vault.dart';
import '../../engines/share/share_engine.dart';

/// Feature 083 — bills with due dates, reminders, amount history, mark
/// paid and the receipt attached from the receipt vault.
class BillsScreen extends StatefulWidget {
  const BillsScreen({super.key, this.bills, this.receipts, this.share, this.save});

  final Bills? bills;
  final ReceiptVault? receipts;
  final Future<void> Function(String text)? share;
  final Future<String?> Function(String text, String name)? save;

  @override
  State<BillsScreen> createState() => _BillsScreenState();
}

class _BillsScreenState extends State<BillsScreen> {
  Bills get _b => widget.bills ?? Bills.instance;
  ReceiptVault get _r => widget.receipts ?? ReceiptVault.instance;

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
      where = await (widget.save ?? _saveToDocuments)(_b.toText(), 'Bills.txt');
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

  static String periodLabel(int months) => switch (months) {
        1 => 'Monthly',
        2 => 'Every 2 months',
        3 => 'Quarterly',
        6 => 'Every 6 months',
        _ => 'Yearly',
      };

  Future<void> _add() async {
    final TextEditingController name = TextEditingController();
    final TextEditingController due = TextEditingController();
    final TextEditingController amount = TextEditingController();
    BillKind kind = BillKind.electricity;
    int every = 1;
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Add a bill'),
        content: StatefulBuilder(
          builder: (BuildContext context, StateSetter set) => SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                DropdownButtonFormField<BillKind>(
                  key: const Key('bill-kind'),
                  initialValue: kind,
                  decoration: const InputDecoration(labelText: 'Type'),
                  items: <DropdownMenuItem<BillKind>>[
                    for (final BillKind k in BillKind.values) DropdownMenuItem<BillKind>(value: k, child: Text(k.label)),
                  ],
                  onChanged: (BillKind? v) => set(() => kind = v ?? kind),
                ),
                TextField(key: const Key('bill-name'), controller: name, decoration: const InputDecoration(labelText: 'Name (optional)', hintText: 'BESCOM')),
                TextField(
                  key: const Key('bill-due'),
                  controller: due,
                  keyboardType: TextInputType.datetime,
                  decoration: const InputDecoration(labelText: 'Next due date', hintText: '05/12/2026'),
                ),
                TextField(
                  key: const Key('bill-amount'),
                  controller: amount,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Usual amount (₹, optional)'),
                ),
                DropdownButtonFormField<int>(
                  key: const Key('bill-every'),
                  initialValue: every,
                  decoration: const InputDecoration(labelText: 'Repeats'),
                  items: <DropdownMenuItem<int>>[
                    for (final int m in Bills.periods) DropdownMenuItem<int>(value: m, child: Text(periodLabel(m))),
                  ],
                  onChanged: (int? v) => set(() => every = v ?? every),
                ),
              ],
            ),
          ),
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(key: const Key('bill-save'), onPressed: () => Navigator.pop(context, true), child: const Text('Add')),
        ],
      ),
    );
    if (ok != true) {
      return;
    }
    final DateTime? d = parseDay(due.text);
    final int? p = amount.text.trim().isEmpty ? null : parsePaise(amount.text);
    final Bill? b = d == null || (amount.text.trim().isNotEmpty && p == null)
        ? null
        : _b.add(name: name.text, kind: kind, due: d, everyMonths: every, paise: p);
    _snack(b == null ? 'Type the due date like 05/12/2026' : 'Added ${b.name}');
  }

  Future<void> _pay(Bill b) async {
    final TextEditingController amount = TextEditingController(text: b.paise == null ? '' : (b.paise! / 100).toStringAsFixed(b.paise! % 100 == 0 ? 0 : 2));
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text('Paid ${b.name}'),
        content: TextField(
          key: const Key('bill-paid-amount'),
          controller: amount,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Amount paid (₹)'),
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(key: const Key('bill-paid-save'), onPressed: () => Navigator.pop(context, true), child: const Text('Mark paid')),
        ],
      ),
    );
    if (ok != true) {
      return;
    }
    final int? p = parsePaise(amount.text);
    _snack(p != null && _b.markPaid(b.id, paise: p) ? 'Paid. Next due ${Bills.dayLabel(_b.byId(b.id)!.nextDue)}' : 'Type the amount paid');
  }

  Future<void> _attach(Bill b) async {
    final List<Receipt> receipts = _r.all;
    if (receipts.isEmpty) {
      _snack('No receipts in the receipt vault yet');
      return;
    }
    final String? id = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => SimpleDialog(
        title: const Text('Attach a receipt'),
        children: <Widget>[
          for (final Receipt r in receipts.take(30))
            SimpleDialogOption(
              key: Key('bill-receipt-${r.id}'),
              onPressed: () => Navigator.pop(context, r.id),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text('${r.shop} · ${ReceiptVault.dayLabel(r.date)}${r.paise == null ? '' : ' · ${ReceiptVault.amountLabel(r.paise!)}'}'),
              ),
            ),
        ],
      ),
    );
    if (id != null) {
      _snack(_b.attachReceipt(b.id, id) ? 'Receipt attached' : 'Mark it paid first');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Bills')),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('bill-add'),
        onPressed: () => unawaited(_add()),
        icon: const Icon(Icons.add),
        label: const Text('Add bill'),
      ),
      bottomNavigationBar: ResultBar(
        onShare: () => unawaited(_shareText(_b.toText())),
        onSave: () => unawaited(_save()),
        onUndo: () => _snack(_b.undo() ? 'Undone' : 'Nothing to undo'),
      ),
      body: ListenableBuilder(listenable: Listenable.merge(<Listenable>[_b, _b.store]), builder: (BuildContext context, Widget? _) => _body(context)),
    );
  }

  Widget _body(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final List<Bill> list = _b.all;
    if (list.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text('No bills yet. Add electricity, water, gas, internet, rent or society dues.', style: text.bodyMedium),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: <Widget>[for (final Bill b in list) _card(context, b)],
    );
  }

  Widget _card(BuildContext context, Bill b) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme cs = Theme.of(context).colorScheme;
    final int days = _b.daysUntil(b);
    final BillState st = _b.state(b);
    final String when = st == BillState.overdue
        ? 'Overdue by ${-days} day${days == -1 ? '' : 's'}'
        : (days == 0 ? 'Due today' : (days == 1 ? 'Due tomorrow' : 'Due in $days days'));
    final int? avg = Bills.average(b);
    return Card(
      key: Key('bill-${b.id}'),
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(b.name, style: text.titleMedium),
            Text(
              '${b.kind.label} · ${periodLabel(b.everyMonths)} · ${Bills.dayLabel(b.nextDue)}${b.paise == null ? '' : ' · ${Bills.amountLabel(b.paise!)}'}',
              style: text.bodySmall,
            ),
            Text(when, key: Key('bill-when-${b.id}'), style: text.bodyMedium?.copyWith(color: st == BillState.overdue ? cs.error : null)),
            if (b.payments.isNotEmpty) ...<Widget>[
              const SizedBox(height: 4),
              if (avg != null) Text('Average ${Bills.amountLabel(avg)}', style: text.bodySmall),
              for (final BillPayment p in b.payments.reversed.take(3))
                Text(
                  'Paid ${Bills.amountLabel(p.paise)} on ${Bills.dayLabel(p.on)}${p.receiptId == null ? '' : ' · receipt attached'}',
                  style: text.bodySmall,
                ),
            ],
            Wrap(
              spacing: 8,
              children: <Widget>[
                TextButton.icon(
                  key: Key('bill-pay-${b.id}'),
                  style: TextButton.styleFrom(minimumSize: const Size(88, 48)),
                  onPressed: () => unawaited(_pay(b)),
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('Mark paid'),
                ),
                if (b.payments.isNotEmpty)
                  TextButton.icon(
                    key: Key('bill-attach-${b.id}'),
                    style: TextButton.styleFrom(minimumSize: const Size(88, 48)),
                    onPressed: () => unawaited(_attach(b)),
                    icon: const Icon(Icons.receipt_long_outlined),
                    label: const Text('Attach receipt'),
                  ),
                TextButton.icon(
                  key: Key('bill-delete-${b.id}'),
                  style: TextButton.styleFrom(minimumSize: const Size(88, 48)),
                  onPressed: () => _b.remove(b.id),
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
