import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../app/widgets/result_bar.dart';
import '../../engines/records/expense_tracker.dart' show parsePaise;
import '../../engines/records/subscriptions.dart';
import '../../engines/share/share_engine.dart';

/// Feature 084 — renewal dates, free trials ending and the yearly total.
class SubscriptionsScreen extends StatefulWidget {
  const SubscriptionsScreen({super.key, this.subscriptions, this.share, this.save});

  final Subscriptions? subscriptions;
  final Future<void> Function(String text)? share;
  final Future<String?> Function(String text, String name)? save;

  @override
  State<SubscriptionsScreen> createState() => _SubscriptionsScreenState();
}

class _SubscriptionsScreenState extends State<SubscriptionsScreen> {
  Subscriptions get _s => widget.subscriptions ?? Subscriptions.instance;

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
      where = await (widget.save ?? _saveToDocuments)(_s.toText(), 'Subscriptions.txt');
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
    final TextEditingController price = TextEditingController();
    final TextEditingController renews = TextEditingController();
    int every = 1;
    bool trial = false;
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Add a subscription'),
        content: StatefulBuilder(
          builder: (BuildContext context, StateSetter set) => SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                TextField(key: const Key('sub-name'), controller: name, decoration: const InputDecoration(labelText: 'Name', hintText: 'Netflix')),
                TextField(
                  key: const Key('sub-price'),
                  controller: price,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Price (₹)'),
                ),
                DropdownButtonFormField<int>(
                  key: const Key('sub-every'),
                  initialValue: every,
                  decoration: const InputDecoration(labelText: 'Billed every'),
                  items: <DropdownMenuItem<int>>[
                    for (final int m in Subscriptions.periods)
                      DropdownMenuItem<int>(value: m, child: Text(Subscriptions.periodLabel(m))),
                  ],
                  onChanged: (int? v) => set(() => every = v ?? every),
                ),
                TextField(
                  key: const Key('sub-renews'),
                  controller: renews,
                  keyboardType: TextInputType.datetime,
                  decoration: const InputDecoration(labelText: 'Next renewal or trial end', hintText: '05/12/2026'),
                ),
                SwitchListTile(
                  key: const Key('sub-trial'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Free trial'),
                  value: trial,
                  onChanged: (bool v) => set(() => trial = v),
                ),
              ],
            ),
          ),
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(key: const Key('sub-save'), onPressed: () => Navigator.pop(context, true), child: const Text('Add')),
        ],
      ),
    );
    if (ok != true) {
      return;
    }
    final DateTime? d = parseDay(renews.text);
    final int? p = parsePaise(price.text);
    final Subscription? s = d == null || p == null ? null : _s.add(name: name.text, paise: p, renews: d, everyMonths: every, trial: trial);
    _snack(s == null ? 'Type a name, a price and a date like 05/12/2026' : 'Added ${s.name}');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Subscriptions')),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('sub-add'),
        onPressed: () => unawaited(_add()),
        icon: const Icon(Icons.add),
        label: const Text('Add'),
      ),
      bottomNavigationBar: ResultBar(
        onShare: () => unawaited(_shareText(_s.toText())),
        onSave: () => unawaited(_save()),
        onUndo: () => _snack(_s.undo() ? 'Undone' : 'Nothing to undo'),
      ),
      body: ListenableBuilder(listenable: Listenable.merge(<Listenable>[_s, _s.store]), builder: (BuildContext context, Widget? _) => _body(context)),
    );
  }

  Widget _body(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final List<Subscription> list = _s.all;
    if (list.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text('No subscriptions yet. Add streaming, apps, cloud storage or memberships.', style: text.bodyMedium),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: <Widget>[
        Semantics(
          container: true,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('${Subscriptions.amountLabel(_s.yearlyTotal)} a year', key: const Key('sub-total'), style: text.headlineSmall),
                  Text('About ${Subscriptions.amountLabel(_s.monthlyAverage)} a month', style: text.bodySmall),
                ],
              ),
            ),
          ),
        ),
        for (final Subscription s in list) _card(context, s),
      ],
    );
  }

  Widget _card(BuildContext context, Subscription s) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme cs = Theme.of(context).colorScheme;
    final int days = _s.daysUntil(s);
    final String when = days < 0
        ? 'Was due ${Subscriptions.dayLabel(s.renews)}'
        : '${s.trial ? 'Trial ends' : 'Renews'} ${days == 0 ? 'today' : (days == 1 ? 'tomorrow' : 'in $days days')}';
    return Card(
      key: Key('sub-${s.id}'),
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(s.name, style: text.titleMedium),
            Text(
              '${Subscriptions.amountLabel(s.paise)} / ${Subscriptions.periodLabel(s.everyMonths)} · ${Subscriptions.amountLabel(s.perYear)} a year',
              style: text.bodySmall,
            ),
            Text(
              '$when · ${Subscriptions.dayLabel(s.renews)}',
              key: Key('sub-when-${s.id}'),
              style: text.bodyMedium?.copyWith(color: s.trial || days < 0 ? cs.error : null),
            ),
            Wrap(
              spacing: 8,
              children: <Widget>[
                TextButton.icon(
                  key: Key('sub-renew-${s.id}'),
                  style: TextButton.styleFrom(minimumSize: const Size(88, 48)),
                  onPressed: () => _snack(_s.renew(s.id) ? 'Next renewal ${Subscriptions.dayLabel(_s.byId(s.id)!.renews)}' : 'Could not renew'),
                  icon: const Icon(Icons.autorenew),
                  label: Text(s.trial ? 'Keep it' : 'Renewed'),
                ),
                TextButton.icon(
                  key: Key('sub-cancel-${s.id}'),
                  style: TextButton.styleFrom(minimumSize: const Size(88, 48)),
                  onPressed: () => _snack(_s.cancel(s.id) ? '${s.name} removed' : 'Could not remove'),
                  icon: const Icon(Icons.cancel_outlined),
                  label: const Text('Cancelled'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
