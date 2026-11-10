import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/widgets/result_bar.dart';
import '../../engines/records/expense_tracker.dart' show parsePaise;
import '../../engines/records/maintenance_log.dart';
import '../../engines/share/share_engine.dart';

/// Feature 098 — AC service, water filter, pest control and the rest:
/// a repeat interval per item, next due date, reminders, service history
/// and the service person's number to call.
class MaintenanceScreen extends StatefulWidget {
  const MaintenanceScreen({super.key, this.log, this.call, this.share, this.save});

  final MaintenanceLog? log;

  /// Opens the phone app; defaults to url_launcher.
  final Future<bool> Function(Uri uri)? call;
  final Future<void> Function(String text)? share;
  final Future<String?> Function(String text, String name)? save;

  @override
  State<MaintenanceScreen> createState() => _MaintenanceScreenState();
}

class _MaintenanceScreenState extends State<MaintenanceScreen> {
  MaintenanceLog get _m => widget.log ?? MaintenanceLog.instance;

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
      where = await (widget.save ?? _saveToDocuments)(_m.toText(), 'Maintenance log.txt');
    } catch (_) {
      where = null;
    }
    _snack(where == null ? 'Could not save' : 'Saved to $where');
  }

  Future<void> _call(UpkeepItem i) async {
    final Uri? uri = i.callUri;
    if (uri == null) {
      _snack('Add the service number first');
      return;
    }
    bool ok;
    try {
      ok = await (widget.call ?? launchUrl)(uri);
    } catch (_) {
      ok = false;
    }
    if (!ok) {
      _snack('No phone app found');
    }
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
    final TextEditingController last = TextEditingController();
    final TextEditingController contact = TextEditingController();
    final TextEditingController phone = TextEditingController();
    UpkeepKind kind = UpkeepKind.ac;
    int every = 3;
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Add an upkeep item'),
        content: StatefulBuilder(
          builder: (BuildContext context, StateSetter set) => SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                DropdownButtonFormField<UpkeepKind>(
                  key: const Key('upkeep-kind'),
                  initialValue: kind,
                  decoration: const InputDecoration(labelText: 'What'),
                  items: <DropdownMenuItem<UpkeepKind>>[
                    for (final UpkeepKind k in UpkeepKind.values) DropdownMenuItem<UpkeepKind>(value: k, child: Text(k.label)),
                  ],
                  onChanged: (UpkeepKind? v) => set(() => kind = v ?? kind),
                ),
                TextField(key: const Key('upkeep-name'), controller: name, decoration: const InputDecoration(labelText: 'Name (optional)', hintText: 'Bedroom AC')),
                DropdownButtonFormField<int>(
                  key: const Key('upkeep-every'),
                  initialValue: every,
                  decoration: const InputDecoration(labelText: 'Repeats'),
                  items: <DropdownMenuItem<int>>[
                    for (final int m in MaintenanceLog.periods) DropdownMenuItem<int>(value: m, child: Text(MaintenanceLog.periodLabel(m))),
                  ],
                  onChanged: (int? v) => set(() => every = v ?? every),
                ),
                TextField(
                  key: const Key('upkeep-last'),
                  controller: last,
                  keyboardType: TextInputType.datetime,
                  decoration: const InputDecoration(labelText: 'Last done (blank if due now)', hintText: '05/12/2026'),
                ),
                TextField(key: const Key('upkeep-contact'), controller: contact, decoration: const InputDecoration(labelText: 'Service person (optional)')),
                TextField(
                  key: const Key('upkeep-phone'),
                  controller: phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Their number (optional)'),
                ),
              ],
            ),
          ),
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(key: const Key('upkeep-save'), onPressed: () => Navigator.pop(context, true), child: const Text('Add')),
        ],
      ),
    );
    if (ok != true) {
      return;
    }
    final DateTime? lastDone = last.text.trim().isEmpty ? null : parseDay(last.text);
    final UpkeepItem? i = last.text.trim().isNotEmpty && lastDone == null
        ? null
        : _m.add(name: name.text, kind: kind, everyMonths: every, lastDone: lastDone, contactName: contact.text, contactPhone: phone.text);
    _snack(i == null ? 'Type the last service date like 05/12/2026, not in the future' : 'Added ${i.name}. Next due ${MaintenanceLog.dayLabel(i.nextDue)}');
  }

  Future<void> _done(UpkeepItem i) async {
    final TextEditingController cost = TextEditingController();
    final TextEditingController note = TextEditingController();
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text('${i.name} done today'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              key: const Key('upkeep-cost'),
              controller: cost,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Cost (₹, optional)'),
            ),
            TextField(key: const Key('upkeep-note'), controller: note, decoration: const InputDecoration(labelText: 'Note (optional)', hintText: 'Gas top-up')),
          ],
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(key: const Key('upkeep-done-save'), onPressed: () => Navigator.pop(context, true), child: const Text('Log service')),
        ],
      ),
    );
    if (ok != true) {
      return;
    }
    final int? p = cost.text.trim().isEmpty ? null : parsePaise(cost.text);
    final bool logged = (cost.text.trim().isEmpty || p != null) && _m.markDone(i.id, paise: p, note: note.text);
    _snack(logged ? 'Logged. Next due ${MaintenanceLog.dayLabel(_m.byId(i.id)!.nextDue)}' : 'Type the cost as a number');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Maintenance log')),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('upkeep-add'),
        onPressed: () => unawaited(_add()),
        icon: const Icon(Icons.add),
        label: const Text('Add item'),
      ),
      bottomNavigationBar: ResultBar(
        onShare: () => unawaited(_shareText(_m.toText())),
        onSave: () => unawaited(_save()),
        onUndo: () => _snack(_m.undo() ? 'Undone' : 'Nothing to undo'),
      ),
      body: ListenableBuilder(listenable: Listenable.merge(<Listenable>[_m, _m.store]), builder: (BuildContext context, Widget? _) => _body(context)),
    );
  }

  Widget _body(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final List<UpkeepItem> list = _m.all;
    if (list.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text('Nothing logged yet. Add AC service, water filter, pest control and other upkeep.', style: text.bodyMedium),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: <Widget>[for (final UpkeepItem i in list) _card(context, i)],
    );
  }

  Widget _card(BuildContext context, UpkeepItem i) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme cs = Theme.of(context).colorScheme;
    final int days = _m.daysUntil(i);
    final UpkeepState st = _m.state(i);
    final String when = st == UpkeepState.overdue
        ? 'Overdue by ${-days} day${days == -1 ? '' : 's'}'
        : (days == 0 ? 'Due today' : (days == 1 ? 'Due tomorrow' : 'Due in $days days'));
    final String contact = <String>[i.contactName, i.contactPhone].where((String s) => s.isNotEmpty).join(' · ');
    final int spent = MaintenanceLog.spent(i);
    return Card(
      key: Key('upkeep-${i.id}'),
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(i.name, style: text.titleMedium),
            Text('${i.kind.label} · ${MaintenanceLog.periodLabel(i.everyMonths)} · next ${MaintenanceLog.dayLabel(i.nextDue)}', style: text.bodySmall),
            Text(when, key: Key('upkeep-when-${i.id}'), style: text.bodyMedium?.copyWith(color: st == UpkeepState.overdue ? cs.error : null)),
            if (contact.isNotEmpty) Text('Service: $contact', style: text.bodySmall),
            if (i.visits.isNotEmpty) ...<Widget>[
              const SizedBox(height: 4),
              for (final ServiceVisit v in i.visits.reversed.take(3))
                Text(
                  'Done ${MaintenanceLog.dayLabel(v.on)}${v.paise == null ? '' : ' · ${MaintenanceLog.amountLabel(v.paise!)}'}${v.note.isEmpty ? '' : ' · ${v.note}'}',
                  style: text.bodySmall,
                ),
              if (spent > 0) Text('Spent ${MaintenanceLog.amountLabel(spent)} in all', style: text.bodySmall),
            ],
            Wrap(
              spacing: 8,
              children: <Widget>[
                TextButton.icon(
                  key: Key('upkeep-done-${i.id}'),
                  style: TextButton.styleFrom(minimumSize: const Size(88, 48)),
                  onPressed: () => unawaited(_done(i)),
                  icon: const Icon(Icons.build_circle_outlined),
                  label: const Text('Done today'),
                ),
                if (i.callUri != null)
                  TextButton.icon(
                    key: Key('upkeep-call-${i.id}'),
                    style: TextButton.styleFrom(minimumSize: const Size(88, 48)),
                    onPressed: () => unawaited(_call(i)),
                    icon: const Icon(Icons.call_outlined),
                    label: Text(i.contactName.isEmpty ? 'Call' : 'Call ${i.contactName}'),
                  ),
                TextButton.icon(
                  key: Key('upkeep-delete-${i.id}'),
                  style: TextButton.styleFrom(minimumSize: const Size(88, 48)),
                  onPressed: () => _m.remove(i.id),
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
