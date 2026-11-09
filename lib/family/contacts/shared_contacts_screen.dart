import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/widgets/result_bar.dart';
import '../../engines/family/shared_contacts.dart';
import '../../engines/platform/home_widgets.dart';
import '../../engines/share/share_engine.dart';

typedef ContactsTextAction = Future<String?> Function(String text);
typedef ContactsLauncher = Future<bool> Function(Uri uri);

/// Feature 075 — the family's shared contacts: tags, one-tap call or
/// WhatsApp, and up to three pinned to the home widget's speed dial.
class SharedContactsScreen extends StatefulWidget {
  const SharedContactsScreen({super.key, this.contacts, this.share, this.save, this.launch});

  final SharedContacts? contacts;
  final ContactsTextAction? share;
  final ContactsTextAction? save;
  final ContactsLauncher? launch;

  @override
  State<SharedContactsScreen> createState() => _SharedContactsScreenState();
}

class _SharedContactsScreenState extends State<SharedContactsScreen> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _phone = TextEditingController();
  String _tag = ContactTags.presets.first;
  String? _filter;

  SharedContacts get _c => widget.contacts ?? SharedContacts.instance;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  void _snack(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  void _add() {
    final ContactOutcome r = _c.add(_name.text, _phone.text, tags: <String>[_tag]);
    switch (r) {
      case ContactOutcome.added:
        _name.clear();
        _phone.clear();
      case ContactOutcome.missingName:
        _snack('Type a name first');
      case ContactOutcome.badNumber:
        _snack('That does not look like a phone number');
      case ContactOutcome.duplicate:
        _snack('That number is already in the list');
      case ContactOutcome.speedDialFull:
        _snack('Speed dial has room for ${WidgetSnapshot.maxSpeedDial}');
    }
  }

  Future<void> _open(Uri uri, String what) async {
    bool ok;
    try {
      ok = await (widget.launch ?? (Uri u) => launchUrl(u, mode: LaunchMode.externalApplication))(uri);
    } catch (_) {
      ok = false;
    }
    if (!ok && mounted) {
      _snack('Could not open $what');
    }
  }

  void _pin(SharedContact c) {
    if (_c.setSpeedDial(c.id, !c.speedDial)) {
      _snack(c.speedDial ? 'Removed ${c.name} from speed dial' : 'Added ${c.name} to speed dial');
    } else {
      _snack('Speed dial has room for ${WidgetSnapshot.maxSpeedDial}; unpin one first');
    }
  }

  Future<void> _share() async {
    final String text = _c.toText();
    final ContactsTextAction? s = widget.share;
    if (s != null) {
      await s(text);
    } else {
      await ShareEngine.instance.shareText(text, subject: 'Family contacts');
    }
  }

  static Future<String?> _saveToDocuments(String text) async {
    final Directory dir = await getApplicationDocumentsDirectory();
    final File f = File('${dir.path}/Family contacts.txt');
    await f.writeAsString(text);
    return f.path;
  }

  Future<void> _save() async {
    String? where;
    try {
      where = await (widget.save ?? _saveToDocuments)(_c.toText());
    } catch (_) {
      where = null;
    }
    if (mounted) {
      _snack(where == null ? 'Could not save the list' : 'Saved to $where');
    }
  }

  void _undo() => _snack(_c.undo() ? 'Undone' : 'Nothing to undo');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Family contacts')),
      bottomNavigationBar: ResultBar(
        onShare: () => unawaited(_share()),
        onSave: () => unawaited(_save()),
        onUndo: _undo,
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge(<Listenable>[_c, _c.store]),
        builder: (BuildContext context, Widget? _) => _body(context),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final List<String> tags = _c.tagsInUse;
    final String? filter = tags.contains(_filter) ? _filter : null;
    final List<SharedContact> shown = _c.filter(tag: filter);
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(children: <Widget>[
            TextField(
              key: const Key('contact-name'),
              controller: _name,
              decoration: const InputDecoration(labelText: 'Name', hintText: 'Ramesh plumber'),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('contact-phone'),
              controller: _phone,
              decoration: const InputDecoration(labelText: 'Phone number'),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 8),
            Row(children: <Widget>[
              Expanded(
                child: DropdownButtonFormField<String>(
                  key: const Key('contact-tag'),
                  initialValue: _tag,
                  decoration: const InputDecoration(labelText: 'Tag'),
                  items: <DropdownMenuItem<String>>[
                    for (final String t in ContactTags.presets) DropdownMenuItem<String>(value: t, child: Text(t)),
                  ],
                  onChanged: (String? t) => setState(() => _tag = t ?? _tag),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                key: const Key('contact-add'),
                style: FilledButton.styleFrom(minimumSize: const Size(44, 48)),
                onPressed: _add,
                icon: const Icon(Icons.person_add_alt),
                label: const Text('Add'),
              ),
            ]),
          ]),
        ),
        if (tags.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Wrap(spacing: 8, runSpacing: 4, children: <Widget>[
              ChoiceChip(
                label: const Text('All'),
                selected: filter == null,
                onSelected: (_) => setState(() => _filter = null),
              ),
              for (final String t in tags)
                ChoiceChip(
                  key: Key('filter-$t'),
                  label: Text(t),
                  selected: filter == t,
                  onSelected: (_) => setState(() => _filter = t),
                ),
            ]),
          ),
        if (shown.isEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'No contacts yet. Anyone you add shows on every family phone. '
              'Pin up to ${WidgetSnapshot.maxSpeedDial} with the star for the home widget\'s speed dial.',
              style: text.bodyMedium,
            ),
          ),
        for (final SharedContact c in shown) _tile(c),
      ],
    );
  }

  Widget _tile(SharedContact c) {
    return ListTile(
      key: Key('contact-${c.id}'),
      minTileHeight: 56,
      title: Text(c.name),
      subtitle: Text('${c.phone} · ${c.tags.join(', ')}'),
      leading: IconButton(
        key: Key('pin-${c.id}'),
        tooltip: c.speedDial ? 'Unpin ${c.name} from speed dial' : 'Pin ${c.name} to speed dial',
        icon: Icon(c.speedDial ? Icons.star : Icons.star_border),
        onPressed: () => _pin(c),
      ),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
        IconButton(
          key: Key('call-${c.id}'),
          tooltip: 'Call ${c.name}',
          icon: const Icon(Icons.call_outlined),
          onPressed: () => unawaited(_open(c.callUri, 'the dialler')),
        ),
        IconButton(
          key: Key('whatsapp-${c.id}'),
          tooltip: 'WhatsApp ${c.name}',
          icon: const Icon(Icons.chat_outlined),
          onPressed: () => unawaited(_open(c.whatsAppUri, 'WhatsApp')),
        ),
        IconButton(
          tooltip: 'Remove ${c.name}',
          icon: const Icon(Icons.delete_outline),
          onPressed: () => _c.remove(c.id),
        ),
      ]),
    );
  }
}
