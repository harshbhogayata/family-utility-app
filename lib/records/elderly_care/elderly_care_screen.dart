import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../app/widgets/result_bar.dart';
import '../../engines/records/elderly_care.dart';
import '../../engines/records/medicine_reminders.dart';
import '../../engines/share/share_engine.dart';

/// Feature 093 — a care circle for a parent: roles, shared medicines and a
/// log of visits and notes.
class ElderlyCareScreen extends StatefulWidget {
  const ElderlyCareScreen({super.key, this.care, this.share, this.save});

  final ElderlyCare? care;

  /// Shares the summary text; defaults to the share sheet.
  final Future<void> Function(String text)? share;

  /// Saves the summary and returns where; defaults to the app's documents.
  final Future<String?> Function(String text, String name)? save;

  @override
  State<ElderlyCareScreen> createState() => _ElderlyCareScreenState();
}

class _ElderlyCareScreenState extends State<ElderlyCareScreen> {
  ElderlyCare get _c => widget.care ?? ElderlyCare.instance;
  final TextEditingController _entry = TextEditingController();
  CareEntryKind _kind = CareEntryKind.visit;
  String? _selected;

  @override
  void dispose() {
    _entry.dispose();
    super.dispose();
  }

  void _snack(String s) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
    }
  }

  CareCircle? get _circle {
    final List<CareCircle> v = _c.visible;
    if (v.isEmpty) {
      return null;
    }
    return v.firstWhere((CareCircle c) => c.id == _selected, orElse: () => v.first);
  }

  String get _text => _circle == null ? '' : _c.toText(_circle!.id);
  String get _name => 'Care log ${_circle?.name ?? ''}.txt';

  Future<void> _share() async {
    if (_circle == null) {
      _snack('Start a care circle first');
      return;
    }
    final Future<void> Function(String)? s = widget.share;
    if (s != null) {
      await s(_text);
      return;
    }
    await ShareEngine.instance.shareText(_text, subject: 'Care log ${_circle!.name}');
  }

  static Future<String?> _saveToDocuments(String text, String name) async {
    final Directory dir = await getApplicationDocumentsDirectory();
    final File f = File('${dir.path}/$name');
    await f.writeAsString(text);
    return f.path;
  }

  Future<void> _save() async {
    if (_circle == null) {
      _snack('Start a care circle first');
      return;
    }
    String? where;
    try {
      where = await (widget.save ?? _saveToDocuments)(_text, _name);
    } catch (_) {
      where = null;
    }
    _snack(where == null ? 'Could not save the log' : 'Saved to $where');
  }

  Future<String?> _ask(String title, String label, Key fieldKey, {String? hint}) async {
    final TextEditingController t = TextEditingController();
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(title),
        content: TextField(key: fieldKey, controller: t, autofocus: true, decoration: InputDecoration(labelText: label, hintText: hint)),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(key: const Key('care-dialog-ok'), onPressed: () => Navigator.pop(context, true), child: const Text('OK')),
        ],
      ),
    );
    return ok == true ? t.text : null;
  }

  Future<void> _newCircle() async {
    final String? name = await _ask('New care circle', 'Who is it for?', const Key('care-circle-name'), hint: 'Nani');
    if (name == null) {
      return;
    }
    final CareCircle? c = _c.create(name: name);
    if (c == null) {
      _snack('Type a name');
      return;
    }
    setState(() => _selected = c.id);
  }

  Future<void> _addMedicine(CareCircle c) async {
    final TextEditingController name = TextEditingController();
    final TextEditingController times = TextEditingController();
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text('Medicine for ${c.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(key: const Key('care-med-name'), controller: name, decoration: const InputDecoration(labelText: 'Medicine')),
            TextField(
              key: const Key('care-med-times'),
              controller: times,
              decoration: const InputDecoration(labelText: 'Times', hintText: '08:00, 20:00'),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(key: const Key('care-med-save'), onPressed: () => Navigator.pop(context, true), child: const Text('Add')),
        ],
      ),
    );
    if (ok != true) {
      return;
    }
    final List<int>? t = Medicine.parseTimes(times.text);
    final Medicine? m = t == null ? null : _c.addMedicine(c.id, name: name.text, times: t);
    _snack(m == null ? 'Type a name and times like 08:00, 20:00' : 'Added ${m.name} for ${c.name}');
  }

  void _log(CareCircle c) {
    final CareEntry? e = _c.addEntry(c.id, _kind, _entry.text);
    if (e == null) {
      _snack('Write what happened first');
      return;
    }
    _entry.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Elderly care'),
        actions: <Widget>[
          IconButton(
            key: const Key('care-new'),
            tooltip: 'New care circle',
            onPressed: () => unawaited(_newCircle()),
            icon: const Icon(Icons.group_add_outlined),
          ),
        ],
      ),
      bottomNavigationBar: ResultBar(
        onShare: () => unawaited(_share()),
        onSave: () => unawaited(_save()),
        onUndo: () => _snack(_c.undo() ? 'Undone' : 'Nothing to undo'),
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge(<Listenable>[_c, _c.store]),
        builder: (BuildContext context, Widget? _) => _body(context),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final CareCircle? c = _circle;
    if (c == null) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Text('Keep medicines, visits and notes for a parent in one place, shared with siblings on their own phones.',
              style: text.bodyMedium),
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const Key('care-start'),
            style: FilledButton.styleFrom(minimumSize: const Size(88, 48)),
            onPressed: () => unawaited(_newCircle()),
            icon: const Icon(Icons.group_add_outlined),
            label: const Text('Start a care circle'),
          ),
        ],
      );
    }
    final List<CareCircle> circles = _c.visible;
    final bool manage = _c.canManage(c);
    final bool write = _c.canWrite(c);
    final Map<String, String> family = _c.members;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: <Widget>[
        if (circles.length > 1)
          DropdownButtonFormField<String>(
            key: const Key('care-pick'),
            initialValue: c.id,
            decoration: const InputDecoration(labelText: 'Care circle'),
            items: <DropdownMenuItem<String>>[
              for (final CareCircle x in circles) DropdownMenuItem<String>(value: x.id, child: Text(x.name)),
            ],
            onChanged: (String? v) => setState(() => _selected = v),
          ),
        Text('Caring for ${c.name}', key: const Key('care-title'), style: text.titleLarge),
        Text('You are ${_c.myRole(c)?.label ?? 'not in this circle'}', style: text.bodySmall),
        const SizedBox(height: 12),
        Text('Circle', style: text.titleMedium),
        for (final MapEntry<String, CareRole> e in c.roles.entries)
          ListTile(
            key: Key('care-member-${e.key}'),
            contentPadding: EdgeInsets.zero,
            minTileHeight: 56,
            title: Text(_c.nameOf(e.key)),
            subtitle: Text(e.value.hint),
            trailing: manage
                ? DropdownButton<CareRole?>(
                    value: e.value,
                    items: <DropdownMenuItem<CareRole?>>[
                      for (final CareRole r in CareRole.values) DropdownMenuItem<CareRole?>(value: r, child: Text(r.label)),
                      const DropdownMenuItem<CareRole?>(value: null, child: Text('Remove')),
                    ],
                    onChanged: (CareRole? r) {
                      if (!_c.setRole(c.id, e.key, r)) {
                        _snack('A circle needs at least one lead');
                      }
                    },
                  )
                : Text(e.value.label),
          ),
        if (manage)
          for (final MapEntry<String, String> m in family.entries.where((MapEntry<String, String> m) => !c.roles.containsKey(m.key)))
            ListTile(
              key: Key('care-invite-${m.key}'),
              contentPadding: EdgeInsets.zero,
              minTileHeight: 56,
              leading: const Icon(Icons.person_add_alt_outlined),
              title: Text('Add ${m.value} as helper'),
              onTap: () => _c.setRole(c.id, m.key, CareRole.helper),
            ),
        const Divider(height: 24),
        Row(
          children: <Widget>[
            Expanded(child: Text('Medicines', style: text.titleMedium)),
            if (write)
              TextButton.icon(
                key: const Key('care-med-add'),
                style: TextButton.styleFrom(minimumSize: const Size(88, 48)),
                onPressed: () => unawaited(_addMedicine(c)),
                icon: const Icon(Icons.add),
                label: const Text('Add'),
              ),
          ],
        ),
        for (final Medicine m in _c.medicinesFor(c))
          ListTile(
            key: Key('care-med-${m.id}'),
            contentPadding: EdgeInsets.zero,
            minTileHeight: 56,
            leading: const Icon(Icons.medication_outlined),
            title: Text(m.name),
            subtitle: Text('${m.times.map(Medicine.clock).join(', ')} · ${m.stock} left'),
          ),
        const Divider(height: 24),
        Text('Log', style: text.titleMedium),
        if (write) ...<Widget>[
          const SizedBox(height: 8),
          SegmentedButton<CareEntryKind>(
            key: const Key('care-kind'),
            segments: <ButtonSegment<CareEntryKind>>[
              for (final CareEntryKind k in CareEntryKind.values) ButtonSegment<CareEntryKind>(value: k, label: Text(k.label)),
            ],
            selected: <CareEntryKind>{_kind},
            onSelectionChanged: (Set<CareEntryKind> v) => setState(() => _kind = v.first),
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  key: const Key('care-entry'),
                  controller: _entry,
                  decoration: const InputDecoration(labelText: 'What happened?', hintText: 'Took her for a walk, BP fine'),
                  onSubmitted: (_) => _log(c),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                key: const Key('care-log'),
                style: FilledButton.styleFrom(minimumSize: const Size(64, 48)),
                onPressed: () => _log(c),
                child: const Text('Add'),
              ),
            ],
          ),
        ],
        for (final CareEntry e in _c.logFor(c.id))
          ListTile(
            key: Key('care-entry-${e.id}'),
            contentPadding: EdgeInsets.zero,
            minTileHeight: 56,
            title: Text(e.text),
            subtitle: Text('${e.kind.label} · ${ElderlyCare.stamp(e.at)} · ${_c.nameOf(e.by)}'),
          ),
      ],
    );
  }
}
