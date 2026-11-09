import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../app/theme.dart';
import '../../app/widgets/result_bar.dart';
import '../../engines/family/shared_shopping_list.dart';
import '../../engines/share/share_engine.dart';

typedef ShoppingTextAction = Future<String?> Function(String text);

/// Feature 072 — the shared shopping list: add with a quantity, grouped by
/// aisle, ticked live by whoever is at the shop, with who and when.
class SharedShoppingScreen extends StatefulWidget {
  const SharedShoppingScreen({super.key, this.list, this.share, this.save});

  final SharedShoppingList? list;
  final ShoppingTextAction? share;

  /// Saves the list as text; returns where it went, or null.
  final ShoppingTextAction? save;

  @override
  State<SharedShoppingScreen> createState() => _SharedShoppingScreenState();
}

class _SharedShoppingScreenState extends State<SharedShoppingScreen> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _qty = TextEditingController();

  SharedShoppingList get _list => widget.list ?? SharedShoppingList.instance;

  @override
  void dispose() {
    _name.dispose();
    _qty.dispose();
    super.dispose();
  }

  static String _time(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  void _snack(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  void _add() {
    final ShoppingItem? it = _list.add(_name.text, quantity: _qty.text);
    if (it == null) {
      _snack('Type what to buy first');
      return;
    }
    _name.clear();
    _qty.clear();
  }

  Future<void> _share() async {
    final String text = _list.toText();
    final ShoppingTextAction? s = widget.share;
    if (s != null) {
      await s(text);
    } else {
      await ShareEngine.instance.shareText(text, subject: 'Shopping list');
    }
  }

  Future<void> _save() async {
    final String text = _list.toText();
    final ShoppingTextAction s = widget.save ?? _saveToDocuments;
    String? where;
    try {
      where = await s(text);
    } catch (_) {
      where = null;
    }
    if (mounted) {
      _snack(where == null ? 'Could not save the list' : 'Saved to $where');
    }
  }

  static Future<String?> _saveToDocuments(String text) async {
    final Directory dir = await getApplicationDocumentsDirectory();
    final File f = File('${dir.path}/Shopping list.txt');
    await f.writeAsString(text);
    return f.path;
  }

  void _undo() => _snack(_list.undo() ? 'Undone' : 'Nothing to undo');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Shopping list'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Clear ticked items',
            icon: const Icon(Icons.playlist_remove),
            onPressed: () {
              final int n = _list.clearTicked();
              _snack(n == 0 ? 'Nothing ticked yet' : 'Cleared $n ticked');
            },
          ),
        ],
      ),
      bottomNavigationBar: ResultBar(
        onShare: () => unawaited(_share()),
        onSave: () => unawaited(_save()),
        onUndo: _undo,
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(children: <Widget>[
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Add an item'),
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _add(),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _qty,
                  decoration: const InputDecoration(labelText: 'Qty'),
                  onSubmitted: (_) => _add(),
                ),
              ),
              const SizedBox(width: 4),
              IconButton.filled(
                tooltip: 'Add to list',
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                onPressed: _add,
                icon: const Icon(Icons.add),
              ),
            ]),
          ),
          Expanded(
            child: ListenableBuilder(
              listenable: Listenable.merge(<Listenable>[_list, _list.store]),
              builder: (BuildContext context, Widget? _) => _body(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final List<MapEntry<String, List<ShoppingItem>>> groups = _list.grouped();
    if (groups.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'The list is empty. Anything you add shows on every family phone, '
          'and a tick at the shop shows for everyone.',
          style: text.bodyMedium,
        ),
      );
    }
    return ListView(
      children: <Widget>[
        for (final MapEntry<String, List<ShoppingItem>> g in groups) ...<Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Semantics(header: true, child: Text(g.key, style: text.titleSmall)),
          ),
          for (final ShoppingItem i in g.value) _tile(i),
        ],
      ],
    );
  }

  Widget _tile(ShoppingItem i) {
    final String name = i.quantity.isEmpty ? i.name : '${i.name} · ${i.quantity}';
    final String who = i.ticked
        ? 'Ticked by ${_list.memberName(i.tickedBy!)}${i.tickedAt == null ? '' : ' at ${_time(i.tickedAt!)}'}'
        : 'Added by ${_list.memberName(i.addedBy)}';
    return MergeSemantics(
      child: CheckboxListTile(
        key: Key('shopping-${i.id}'),
        controlAffinity: ListTileControlAffinity.leading,
        value: i.ticked,
        onChanged: (bool? v) => v == true ? _list.tick(i.id) : _list.untick(i.id),
        title: Text(
          name,
          style: i.ticked ? const TextStyle(decoration: TextDecoration.lineThrough, color: AppColors.muted) : null,
        ),
        subtitle: Text(who),
        secondary: IconButton(
          tooltip: 'Remove ${i.name}',
          icon: const Icon(Icons.close),
          onPressed: () => _list.remove(i.id),
        ),
      ),
    );
  }
}
