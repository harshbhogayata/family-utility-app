import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../app/widgets/result_bar.dart';
import '../../engines/records/medicine_reminders.dart';
import '../../engines/share/share_engine.dart';

/// Feature 088 — today's doses with Taken / Snooze / Skip, tablets left,
/// refill, and who may see each schedule.
class MedicineScreen extends StatefulWidget {
  const MedicineScreen({super.key, this.reminders, this.share, this.save});

  final MedicineReminders? reminders;
  final Future<void> Function(String text)? share;
  final Future<String?> Function(String text)? save;

  @override
  State<MedicineScreen> createState() => _MedicineScreenState();
}

class _MedicineScreenState extends State<MedicineScreen> {
  MedicineReminders get _m => widget.reminders ?? MedicineReminders.instance;

  @override
  void initState() {
    super.initState();
    unawaited(_m.reschedule());
  }

  void _snack(String s) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
    }
  }

  Future<void> _share() async {
    final Future<void> Function(String)? s = widget.share;
    if (s != null) {
      await s(_m.toText());
    } else {
      await ShareEngine.instance.shareText(_m.toText(), subject: 'Medicines');
    }
  }

  static Future<String?> _saveToDocuments(String text) async {
    final Directory dir = await getApplicationDocumentsDirectory();
    final File f = File('${dir.path}/Medicines.txt');
    await f.writeAsString(text);
    return f.path;
  }

  Future<void> _save() async {
    String? where;
    try {
      where = await (widget.save ?? _saveToDocuments)(_m.toText());
    } catch (_) {
      where = null;
    }
    _snack(where == null ? 'Could not save the list' : 'Saved to $where');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Medicines')),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('med-add'),
        onPressed: () => unawaited(_add()),
        icon: const Icon(Icons.add),
        label: const Text('Add medicine'),
      ),
      bottomNavigationBar: ResultBar(
        onShare: () => unawaited(_share()),
        onSave: () => unawaited(_save()),
        onUndo: () => _snack(_m.undo() ? 'Undone' : 'Nothing to undo'),
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge(<Listenable>[_m, _m.store]),
        builder: (BuildContext context, Widget? _) => _body(context),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final List<Medicine> meds = _m.visible;
    final List<Dose> today = _m.today;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: <Widget>[
        Text('Today', style: text.titleMedium),
        if (today.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text('No doses today. Add a medicine to get reminders.', style: text.bodyMedium),
          ),
        for (final Dose d in today) _doseTile(d),
        const SizedBox(height: 16),
        Text('Medicines and stock', style: text.titleMedium),
        for (final Medicine m in meds) _medicineCard(m),
      ],
    );
  }

  Widget _doseTile(Dose d) {
    final Medicine m = d.medicine;
    final String time = Medicine.clock(d.due.hour * 60 + d.due.minute);
    final String who = m.memberId == _m.me ? '' : ' · ${_m.nameOf(m.memberId)}';
    return Semantics(
      container: true,
      label: '${m.name} at $time$who, ${d.status.label}',
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('$time  ${m.name}$who', style: Theme.of(context).textTheme.titleSmall),
              Text('${m.tabletsPerDose} tablet${m.tabletsPerDose == 1 ? '' : 's'} · ${d.status.label}'),
              if (d.open)
                Wrap(
                  spacing: 8,
                  children: <Widget>[
                    FilledButton(
                      key: Key('taken-${d.key}'),
                      style: FilledButton.styleFrom(minimumSize: const Size(88, 48)),
                      onPressed: () => _m.markTaken(m.id, d.due),
                      child: const Text('Taken'),
                    ),
                    OutlinedButton(
                      key: Key('snooze-${d.key}'),
                      style: OutlinedButton.styleFrom(minimumSize: const Size(88, 48)),
                      onPressed: () {
                        if (_m.snooze(m.id, d.due) != null) {
                          _snack('Reminding again in ${_m.snoozeFor.inMinutes} minutes');
                        }
                      },
                      child: const Text('Snooze'),
                    ),
                    TextButton(
                      key: Key('skip-${d.key}'),
                      style: TextButton.styleFrom(minimumSize: const Size(88, 48)),
                      onPressed: () => _m.skip(m.id, d.due),
                      child: const Text('Skip'),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _medicineCard(Medicine m) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme c = Theme.of(context).colorScheme;
    return Card(
      key: Key('med-${m.id}'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('${m.name} — ${_m.nameOf(m.memberId)}', style: text.titleSmall),
            Text('${m.tabletsPerDose} at ${m.times.map(Medicine.clock).join(', ')}'),
            Text(
              '${m.stock} tablets left · about ${m.daysLeft} days${m.needsRefill ? ' · refill now' : ''}',
              key: Key('stock-${m.id}'),
              style: m.needsRefill ? text.bodyMedium?.copyWith(color: c.error) : text.bodyMedium,
            ),
            if (m.carers.isNotEmpty) Text('Carers: ${m.carers.map(_m.nameOf).join(', ')}', style: text.bodySmall),
            Wrap(
              spacing: 8,
              children: <Widget>[
                OutlinedButton(
                  key: Key('refill-${m.id}'),
                  style: OutlinedButton.styleFrom(minimumSize: const Size(88, 48)),
                  onPressed: () => unawaited(_refill(m)),
                  child: const Text('Refill'),
                ),
                if (_m.canGrant(m) && _m.members.length > 1)
                  OutlinedButton(
                    key: Key('carers-${m.id}'),
                    style: OutlinedButton.styleFrom(minimumSize: const Size(88, 48)),
                    onPressed: () => unawaited(_carers(m)),
                    child: const Text('Carers'),
                  ),
                TextButton(
                  key: Key('remove-${m.id}'),
                  style: TextButton.styleFrom(minimumSize: const Size(88, 48)),
                  onPressed: () => _m.remove(m.id),
                  child: const Text('Remove'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _refill(Medicine m) async {
    final TextEditingController count = TextEditingController(text: '${m.perDay * 30}');
    final int? n = await showDialog<int>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text('Refill ${m.name}'),
        content: TextField(
          key: const Key('refill-count'),
          controller: count,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Tablets added'),
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            key: const Key('refill-ok'),
            onPressed: () => Navigator.pop(context, int.tryParse(count.text.trim())),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (n != null && !_m.refill(m.id, n)) {
      _snack('Enter how many tablets you added');
    }
  }

  Future<void> _carers(Medicine m) async {
    await showDialog<void>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Who can see this'),
        content: ListenableBuilder(
          listenable: _m,
          builder: (BuildContext context, Widget? _) {
            final Medicine now = _m.byId(m.id) ?? m;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                for (final MapEntry<String, String> e in _m.members.entries)
                  if (e.key != now.memberId)
                    CheckboxListTile(
                      key: Key('carer-${e.key}'),
                      title: Text(e.value),
                      value: now.carers.contains(e.key),
                      onChanged: (bool? v) => _m.setCarer(now.id, e.key, v ?? false),
                    ),
              ],
            );
          },
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
        ],
      ),
    );
  }

  Future<void> _add() async {
    final TextEditingController name = TextEditingController();
    final TextEditingController times = TextEditingController(text: '08:00, 20:00');
    final TextEditingController per = TextEditingController(text: '1');
    final TextEditingController stock = TextEditingController(text: '30');
    final TextEditingController refillAt = TextEditingController(text: '5');
    String member = _m.me;
    final Map<String, String> members = _m.members;
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Add medicine'),
        content: StatefulBuilder(
          builder: (BuildContext context, StateSetter set) => SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (members.length > 1)
                  DropdownButtonFormField<String>(
                    key: const Key('med-member'),
                    initialValue: member,
                    decoration: const InputDecoration(labelText: 'For'),
                    items: <DropdownMenuItem<String>>[
                      for (final MapEntry<String, String> e in members.entries)
                        DropdownMenuItem<String>(value: e.key, child: Text(e.value)),
                    ],
                    onChanged: (String? v) => set(() => member = v ?? member),
                  ),
                TextField(
                  key: const Key('med-name'),
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Medicine'),
                ),
                TextField(
                  key: const Key('med-times'),
                  controller: times,
                  decoration: const InputDecoration(labelText: 'Dose times', helperText: 'e.g. 08:00, 14:00, 21:00'),
                ),
                TextField(
                  key: const Key('med-per'),
                  controller: per,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Tablets per dose'),
                ),
                TextField(
                  key: const Key('med-stock'),
                  controller: stock,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Tablets left'),
                ),
                TextField(
                  key: const Key('med-refill-at'),
                  controller: refillAt,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Remind to refill at'),
                ),
              ],
            ),
          ),
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(key: const Key('med-save'), onPressed: () => Navigator.pop(context, true), child: const Text('Add')),
        ],
      ),
    );
    if (ok == true) {
      final List<int>? t = Medicine.parseTimes(times.text);
      final Medicine? added = t == null
          ? null
          : _m.add(
              name: name.text,
              times: t,
              memberId: member,
              tabletsPerDose: int.tryParse(per.text.trim()) ?? 0,
              stock: int.tryParse(stock.text.trim()) ?? -1,
              refillAt: int.tryParse(refillAt.text.trim()) ?? 5,
            );
      _snack(added == null ? 'Check the name, times (like 08:00) and numbers' : 'Added ${added.name}');
    }
  }
}
