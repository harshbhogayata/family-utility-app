import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/widgets/result_bar.dart';
import '../../engines/records/receipt_vault.dart';
import '../../engines/records/warranties.dart';
import '../../engines/share/share_engine.dart';

/// Feature 086 — warranties with the bill linked from the receipt vault
/// and the service number one tap away.
class WarrantiesScreen extends StatefulWidget {
  const WarrantiesScreen({super.key, this.warranties, this.receipts, this.call, this.share, this.save});

  final Warranties? warranties;
  final ReceiptVault? receipts;

  /// Opens the phone app; defaults to url_launcher.
  final Future<bool> Function(Uri uri)? call;
  final Future<void> Function(String text)? share;
  final Future<String?> Function(String text, String name)? save;

  @override
  State<WarrantiesScreen> createState() => _WarrantiesScreenState();
}

class _WarrantiesScreenState extends State<WarrantiesScreen> {
  Warranties get _w => widget.warranties ?? Warranties.instance;
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
      where = await (widget.save ?? _saveToDocuments)(_w.toText(), 'Warranties.txt');
    } catch (_) {
      where = null;
    }
    _snack(where == null ? 'Could not save' : 'Saved to $where');
  }

  Future<void> _call(Warranty w) async {
    final Uri? uri = w.callUri;
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

  void _import() {
    final int n = _w.importFromReceipts(_r.all);
    _snack(n == 0 ? 'No new warranties in the receipt vault' : 'Added $n from receipts');
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
    final TextEditingController product = TextEditingController();
    final TextEditingController bought = TextEditingController();
    final TextEditingController months = TextEditingController(text: '12');
    final TextEditingController phone = TextEditingController();
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Add a warranty'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextField(key: const Key('w-product'), controller: product, decoration: const InputDecoration(labelText: 'Product', hintText: 'Washing machine')),
              TextField(
                key: const Key('w-bought'),
                controller: bought,
                keyboardType: TextInputType.datetime,
                decoration: const InputDecoration(labelText: 'Bought on', hintText: '24/08/2026'),
              ),
              TextField(
                key: const Key('w-months'),
                controller: months,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Warranty (months)'),
              ),
              TextField(
                key: const Key('w-phone'),
                controller: phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Service number (optional)'),
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(key: const Key('w-save'), onPressed: () => Navigator.pop(context, true), child: const Text('Add')),
        ],
      ),
    );
    if (ok != true) {
      return;
    }
    final DateTime? d = parseDay(bought.text);
    final int? m = int.tryParse(months.text.trim());
    final Warranty? w = d == null || m == null ? null : _w.add(product: product.text, bought: d, months: m, servicePhone: phone.text);
    _snack(w == null ? 'Type the product, purchase date and months' : 'Added ${w.product}');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Warranties'),
        actions: <Widget>[
          IconButton(
            key: const Key('w-import'),
            tooltip: 'Add from receipts',
            onPressed: _import,
            icon: const Icon(Icons.receipt_long_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('w-add'),
        onPressed: () => unawaited(_add()),
        icon: const Icon(Icons.add),
        label: const Text('Add warranty'),
      ),
      bottomNavigationBar: ResultBar(
        onShare: () => unawaited(_shareText(_w.toText())),
        onSave: () => unawaited(_save()),
        onUndo: () => _snack(_w.undo() ? 'Undone' : 'Nothing to undo'),
      ),
      body: ListenableBuilder(listenable: Listenable.merge(<Listenable>[_w, _w.store]), builder: (BuildContext context, Widget? _) => _body(context)),
    );
  }

  Widget _body(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final List<Warranty> list = _w.all;
    if (list.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text('No warranties yet. Add one, or bring them in from the receipt vault.', style: text.bodyMedium),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: <Widget>[for (final Warranty w in list) _card(context, w)],
    );
  }

  Widget _card(BuildContext context, Warranty w) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme cs = Theme.of(context).colorScheme;
    final int days = _w.daysLeft(w);
    final WarrantyState st = _w.state(w);
    final String status = st == WarrantyState.expired
        ? 'Ended ${Warranties.dayLabel(w.ends)}'
        : 'Covered till ${Warranties.dayLabel(w.ends)} · $days day${days == 1 ? '' : 's'} left';
    final Receipt? bill = w.receiptId == null ? null : _r.byId(w.receiptId!);
    return Card(
      key: Key('w-${w.id}'),
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(w.product, style: text.titleMedium),
            Text('Bought ${Warranties.dayLabel(w.bought)} · ${w.months} months', style: text.bodySmall),
            Text(status, key: Key('w-status-${w.id}'), style: text.bodyMedium?.copyWith(color: st == WarrantyState.active ? null : cs.error)),
            if (bill != null)
              Text(
                'Bill: ${bill.shop}${bill.paise == null ? '' : ' · ${ReceiptVault.amountLabel(bill.paise!)}'}',
                key: Key('w-bill-${w.id}'),
                style: text.bodySmall,
              ),
            Wrap(
              spacing: 8,
              children: <Widget>[
                TextButton.icon(
                  key: Key('w-call-${w.id}'),
                  style: TextButton.styleFrom(minimumSize: const Size(88, 48)),
                  onPressed: () => unawaited(_call(w)),
                  icon: const Icon(Icons.call_outlined),
                  label: Text(w.servicePhone.isEmpty ? 'Service number' : 'Call ${w.servicePhone}'),
                ),
                TextButton.icon(
                  key: Key('w-delete-${w.id}'),
                  style: TextButton.styleFrom(minimumSize: const Size(88, 48)),
                  onPressed: () => _w.remove(w.id),
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
