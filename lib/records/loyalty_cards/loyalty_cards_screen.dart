import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../app/widgets/result_bar.dart';
import '../../engines/records/loyalty_cards.dart';
import '../../engines/share/share_engine.dart';
import '../../platform/screen_brightness_platform.dart';
import 'loyalty_card_screen.dart';
import 'loyalty_scan_screen.dart';

/// Feature 100 — loyalty cards: scan a card once, show it at the till.
class LoyaltyCardsScreen extends StatefulWidget {
  const LoyaltyCardsScreen({super.key, this.cards, this.scan, this.brightness, this.share, this.save});

  final LoyaltyCards? cards;

  /// Opens the camera; defaults to [LoyaltyScanScreen].
  final Future<ScannedCard?> Function(BuildContext context)? scan;
  final ScreenBrightness? brightness;
  final Future<void> Function(String text)? share;
  final Future<String?> Function(String text, String name)? save;

  @override
  State<LoyaltyCardsScreen> createState() => _LoyaltyCardsScreenState();
}

class _LoyaltyCardsScreenState extends State<LoyaltyCardsScreen> {
  LoyaltyCards get _c => widget.cards ?? LoyaltyCards.instance;
  String _query = '';

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
      where = await (widget.save ?? _saveToDocuments)(_c.toText(), 'Loyalty cards.txt');
    } catch (_) {
      where = null;
    }
    _snack(where == null ? 'Could not save' : 'Saved to $where');
  }

  static Future<ScannedCard?> _scanWithCamera(BuildContext context) =>
      Navigator.of(context).push<ScannedCard>(MaterialPageRoute<ScannedCard>(builder: (BuildContext _) => const LoyaltyScanScreen()));

  Future<void> _scan() async {
    ScannedCard? got;
    try {
      got = await (widget.scan ?? _scanWithCamera)(context);
    } catch (_) {
      got = null;
    }
    if (got == null || !mounted) {
      return;
    }
    await _edit(number: got.number, format: got.format, scanned: true);
  }

  Future<void> _edit({String number = '', CardFormat? format, bool scanned = false}) async {
    final TextEditingController storeName = TextEditingController();
    final TextEditingController numberCtl = TextEditingController(text: number);
    final TextEditingController note = TextEditingController();
    CardFormat? chosen = format;
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setInner) => AlertDialog(
          title: Text(scanned ? 'Card scanned' : 'Add a card'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                TextField(
                  key: const Key('lc-store'),
                  controller: storeName,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Store', hintText: 'DMart'),
                ),
                TextField(
                  key: const Key('lc-number-field'),
                  controller: numberCtl,
                  decoration: const InputDecoration(labelText: 'Card number'),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<CardFormat?>(
                  key: const Key('lc-format'),
                  initialValue: chosen,
                  decoration: const InputDecoration(labelText: 'Barcode type'),
                  items: <DropdownMenuItem<CardFormat?>>[
                    const DropdownMenuItem<CardFormat?>(value: null, child: Text('Work it out')),
                    for (final CardFormat f in CardFormat.values)
                      DropdownMenuItem<CardFormat?>(value: f, child: Text(LoyaltyCards.formatLabel(f))),
                  ],
                  onChanged: (CardFormat? f) => setInner(() => chosen = f),
                ),
                TextField(
                  key: const Key('lc-note'),
                  controller: note,
                  decoration: const InputDecoration(labelText: 'Note (optional)', hintText: 'Mum\'s card'),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(key: const Key('lc-save'), onPressed: () => Navigator.pop(context, true), child: const Text('Add')),
          ],
        ),
      ),
    );
    if (ok != true) {
      return;
    }
    final LoyaltyCard? c = _c.add(storeName: storeName.text, number: numberCtl.text, format: chosen, note: note.text);
    _snack(c == null ? 'Type the store and a number that fits the barcode type' : 'Added ${c.store}');
  }

  Future<void> _show(LoyaltyCard c) async {
    _c.markShown(c.id);
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext _) => LoyaltyCardScreen(card: c, brightness: widget.brightness ?? WindowScreenBrightness()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Loyalty cards'),
        actions: <Widget>[
          IconButton(
            key: const Key('lc-type'),
            tooltip: 'Type a card number',
            onPressed: () => unawaited(_edit()),
            icon: const Icon(Icons.keyboard_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('lc-scan'),
        onPressed: () => unawaited(_scan()),
        icon: const Icon(Icons.qr_code_scanner),
        label: const Text('Scan a card'),
      ),
      bottomNavigationBar: ResultBar(
        onShare: () => unawaited(_shareText(_c.toText())),
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
    final List<LoyaltyCard> all = _c.all;
    if (all.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'No cards yet. Scan the barcode on a store card once; it shows here at full brightness, even with no signal.',
          style: text.bodyMedium,
        ),
      );
    }
    final List<LoyaltyCard> list = _c.search(_query);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: <Widget>[
        if (all.length > 4)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: TextField(
              key: const Key('lc-search'),
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Find a card'),
              onChanged: (String v) => setState(() => _query = v),
            ),
          ),
        for (final LoyaltyCard c in list) _tile(context, c),
      ],
    );
  }

  Widget _tile(BuildContext context, LoyaltyCard c) {
    return Card(
      key: Key('lc-${c.id}'),
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ListTile(
        minTileHeight: 64,
        leading: Icon(c.isLinear ? Icons.view_week_outlined : Icons.qr_code_2),
        title: Text(c.store),
        subtitle: Text('${c.number} · ${LoyaltyCards.formatLabel(c.format)}${c.note.isEmpty ? '' : ' · ${c.note}'}'),
        onTap: () => unawaited(_show(c)),
        trailing: IconButton(
          key: Key('lc-delete-${c.id}'),
          tooltip: 'Delete ${c.store} card',
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          onPressed: () {
            _c.remove(c.id);
            _snack('Deleted ${c.store}. Undo brings it back.');
          },
          icon: const Icon(Icons.delete_outline),
        ),
      ),
    );
  }
}
