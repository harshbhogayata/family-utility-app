import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../../app/widgets/result_bar.dart';
import '../../engines/records/occasions.dart';
import '../../engines/share/share_engine.dart';

/// Feature 095 — birthdays and anniversaries, gift ideas and a drafted wish.
class OccasionsScreen extends StatefulWidget {
  const OccasionsScreen({super.key, this.occasions, this.share, this.save});

  final Occasions? occasions;

  /// Shares text (a wish or the list); defaults to the share sheet.
  final Future<void> Function(String text)? share;
  final Future<String?> Function(String text, String name)? save;

  @override
  State<OccasionsScreen> createState() => _OccasionsScreenState();
}

class _OccasionsScreenState extends State<OccasionsScreen> {
  Occasions get _o => widget.occasions ?? Occasions.instance;

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
      where = await (widget.save ?? _saveToDocuments)(_o.toText(), 'Birthdays and anniversaries.txt');
    } catch (_) {
      where = null;
    }
    _snack(where == null ? 'Could not save the list' : 'Saved to $where');
  }

  Future<void> _import() async {
    int n = 0;
    try {
      n = await _o.importFromContacts();
    } catch (_) {
      n = 0;
    }
    _snack(n == 0 ? 'No new dates in contacts' : 'Added $n from contacts');
  }

  Future<void> _add() async {
    final TextEditingController name = TextEditingController();
    final TextEditingController date = TextEditingController();
    OccasionKind kind = OccasionKind.birthday;
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Add a date'),
        content: StatefulBuilder(
          builder: (BuildContext context, StateSetter set) => Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextField(key: const Key('occ-name'), controller: name, decoration: const InputDecoration(labelText: 'Name')),
              TextField(
                key: const Key('occ-date'),
                controller: date,
                keyboardType: TextInputType.datetime,
                decoration: const InputDecoration(labelText: 'Date', hintText: '24/08 or 24/08/1965'),
              ),
              const SizedBox(height: 8),
              SegmentedButton<OccasionKind>(
                key: const Key('occ-kind'),
                segments: <ButtonSegment<OccasionKind>>[
                  for (final OccasionKind k in OccasionKind.values) ButtonSegment<OccasionKind>(value: k, label: Text(k.label)),
                ],
                selected: <OccasionKind>{kind},
                onSelectionChanged: (Set<OccasionKind> v) => set(() => kind = v.first),
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(key: const Key('occ-save'), onPressed: () => Navigator.pop(context, true), child: const Text('Add')),
        ],
      ),
    );
    if (ok != true) {
      return;
    }
    final RegExpMatch? m = RegExp(r'^\s*(\d{1,2})[/.\-](\d{1,2})(?:[/.\-](\d{4}))?\s*$').firstMatch(date.text);
    final Occasion? o = m == null
        ? null
        : _o.add(
            name: name.text,
            kind: kind,
            day: int.parse(m.group(1)!),
            month: int.parse(m.group(2)!),
            year: m.group(3) == null ? null : int.parse(m.group(3)!),
          );
    _snack(o == null ? 'Type a name and a date like 24/08' : 'Added ${o.name}');
  }

  Future<void> _gift(Occasion o) async {
    final TextEditingController t = TextEditingController();
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text('Gift idea for ${o.name}'),
        content: TextField(key: const Key('occ-gift'), controller: t, decoration: const InputDecoration(labelText: 'Idea')),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(key: const Key('occ-gift-save'), onPressed: () => Navigator.pop(context, true), child: const Text('Add')),
        ],
      ),
    );
    if (ok == true && !_o.addGift(o.id, t.text)) {
      _snack('Type an idea first');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Birthdays'),
        actions: <Widget>[
          IconButton(
            key: const Key('occ-import'),
            tooltip: 'Add from contacts',
            onPressed: () => unawaited(_import()),
            icon: const Icon(Icons.contacts_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('occ-add'),
        onPressed: () => unawaited(_add()),
        icon: const Icon(Icons.add),
        label: const Text('Add date'),
      ),
      bottomNavigationBar: ResultBar(
        onShare: () => unawaited(_shareText(_o.toText())),
        onSave: () => unawaited(_save()),
        onUndo: () => _snack(_o.undo() ? 'Undone' : 'Nothing to undo'),
      ),
      body: ListenableBuilder(listenable: Listenable.merge(<Listenable>[_o, _o.store]), builder: (BuildContext context, Widget? _) => _body(context)),
    );
  }

  Widget _body(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final List<Occasion> list = _o.upcoming;
    if (list.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text('No dates yet. Add one, or read birthdays from your contacts.', style: text.bodyMedium),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: <Widget>[
        for (final Occasion o in list) _card(context, o),
      ],
    );
  }

  Widget _card(BuildContext context, Occasion o) {
    final TextTheme text = Theme.of(context).textTheme;
    final int days = _o.daysUntil(o);
    final String when = days == 0 ? 'Today' : (days == 1 ? 'Tomorrow' : 'In $days days');
    final String wish = _o.draftWish(o);
    return Card(
      key: Key('occ-${o.id}'),
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(o.name, style: text.titleMedium),
            Text('${o.kind.label} · ${Occasions.dateLabel(o)} · $when', style: text.bodySmall),
            const SizedBox(height: 6),
            for (int i = 0; i < o.gifts.length; i++)
              Row(
                children: <Widget>[
                  const Icon(Icons.card_giftcard_outlined, size: 18),
                  const SizedBox(width: 6),
                  Expanded(child: Text(o.gifts[i])),
                  IconButton(
                    tooltip: 'Remove gift idea',
                    onPressed: () => _o.removeGift(o.id, i),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            Text(wish, key: Key('occ-wish-${o.id}'), style: text.bodyMedium),
            Wrap(
              spacing: 8,
              children: <Widget>[
                TextButton.icon(
                  key: Key('occ-send-${o.id}'),
                  style: TextButton.styleFrom(minimumSize: const Size(88, 48)),
                  onPressed: () => unawaited(_shareText(wish)),
                  icon: const Icon(Icons.send_outlined),
                  label: const Text('Send wish'),
                ),
                TextButton.icon(
                  key: Key('occ-copy-${o.id}'),
                  style: TextButton.styleFrom(minimumSize: const Size(88, 48)),
                  onPressed: () {
                    unawaited(Clipboard.setData(ClipboardData(text: wish)));
                    _snack('Wish copied');
                  },
                  icon: const Icon(Icons.copy_outlined),
                  label: const Text('Copy'),
                ),
                TextButton.icon(
                  key: Key('occ-gift-${o.id}'),
                  style: TextButton.styleFrom(minimumSize: const Size(88, 48)),
                  onPressed: () => unawaited(_gift(o)),
                  icon: const Icon(Icons.card_giftcard_outlined),
                  label: const Text('Gift idea'),
                ),
                TextButton.icon(
                  key: Key('occ-delete-${o.id}'),
                  style: TextButton.styleFrom(minimumSize: const Size(88, 48)),
                  onPressed: () => _o.remove(o.id),
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
