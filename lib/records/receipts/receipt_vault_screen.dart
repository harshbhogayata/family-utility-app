import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../../app/widgets/result_bar.dart';
import '../../engines/records/expense_tracker.dart';
import '../../engines/records/receipt_vault.dart';
import '../../engines/share/share_engine.dart';

/// A receipt photo kept in the app's folder, and its bytes for OCR.
typedef CapturedReceipt = ({String path, Uint8List bytes});

/// Feature 085 — receipts searchable by shop, amount or any word on them,
/// linked to an expense and a warranty.
class ReceiptVaultScreen extends StatefulWidget {
  const ReceiptVaultScreen({super.key, this.vault, this.capture, this.share, this.save});

  final ReceiptVault? vault;

  /// Takes a receipt photo; defaults to the camera.
  final Future<CapturedReceipt?> Function()? capture;
  final Future<void> Function(String text)? share;
  final Future<String?> Function(String text, String name)? save;

  @override
  State<ReceiptVaultScreen> createState() => _ReceiptVaultScreenState();
}

class _ReceiptVaultScreenState extends State<ReceiptVaultScreen> {
  ReceiptVault get _v => widget.vault ?? ReceiptVault.instance;
  final TextEditingController _q = TextEditingController();

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  void _snack(String s) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
    }
  }

  static Future<CapturedReceipt?> _camera() async {
    final XFile? x = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 80);
    if (x == null) {
      return null;
    }
    final Directory base = await getApplicationDocumentsDirectory();
    final Directory dir = Directory('${base.path}/receipts');
    await dir.create(recursive: true);
    final String path = '${dir.path}/receipt_${DateTime.now().millisecondsSinceEpoch}.jpg';
    await File(x.path).copy(path);
    return (path: path, bytes: await File(path).readAsBytes());
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
      where = await (widget.save ?? _saveToDocuments)(_v.toText(_v.search(_q.text)), 'Receipts.txt');
    } catch (_) {
      where = null;
    }
    _snack(where == null ? 'Could not save' : 'Saved to $where');
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

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
    CapturedReceipt? shot;
    try {
      shot = await (widget.capture ?? _camera)();
    } catch (_) {
      shot = null;
    }
    if (shot == null || !mounted) {
      return;
    }
    final (String, ReceiptGuess) read = await _v.read(shot.bytes);
    if (!mounted) {
      return;
    }
    final ReceiptGuess g = read.$2;
    final DateTime day = g.date ?? DateTime.now();
    final TextEditingController shop = TextEditingController(text: g.shop);
    final TextEditingController amount = TextEditingController(text: g.paise == null ? '' : formatPaise(g.paise!).replaceAll(',', ''));
    final TextEditingController date = TextEditingController(text: '${_two(day.day)}/${_two(day.month)}/${day.year}');
    final TextEditingController tags = TextEditingController();
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Save receipt'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextField(key: const Key('rc-shop'), controller: shop, decoration: const InputDecoration(labelText: 'Shop')),
              TextField(
                key: const Key('rc-amount'),
                controller: amount,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Amount (₹)'),
              ),
              TextField(key: const Key('rc-date'), controller: date, decoration: const InputDecoration(labelText: 'Date', hintText: '24/08/2026')),
              TextField(key: const Key('rc-tags'), controller: tags, decoration: const InputDecoration(labelText: 'Tags', hintText: 'tv, home')),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(key: const Key('rc-save'), onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok != true) {
      return;
    }
    final Receipt? r = _v.add(
      shop: shop.text,
      paise: amount.text.trim().isEmpty ? null : parsePaise(amount.text),
      date: parseDay(date.text),
      photo: shot.path,
      text: read.$1,
      tags: tags.text.split(','),
    );
    _snack(r == null ? 'Could not save the receipt' : 'Receipt saved');
  }

  Future<void> _warranty(Receipt r) async {
    final TextEditingController months = TextEditingController(text: r.warrantyMonths?.toString() ?? '12');
    final TextEditingController product = TextEditingController(text: r.product);
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Warranty'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(key: const Key('rc-product'), controller: product, decoration: const InputDecoration(labelText: 'Product')),
            TextField(
              key: const Key('rc-months'),
              controller: months,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Months (0 to clear)'),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(key: const Key('rc-warranty-save'), onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok != true) {
      return;
    }
    final int? m = int.tryParse(months.text.trim());
    _snack(m != null && _v.setWarranty(r.id, m, product: product.text) ? 'Warranty saved' : 'Type the months, like 12');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Receipts')),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('rc-add'),
        onPressed: () => unawaited(_add()),
        icon: const Icon(Icons.add_a_photo_outlined),
        label: const Text('Add receipt'),
      ),
      bottomNavigationBar: ResultBar(
        onShare: () => unawaited(_shareText(_v.toText(_v.search(_q.text)))),
        onSave: () => unawaited(_save()),
        onUndo: () => _snack(_v.undo() ? 'Undone' : 'Nothing to undo'),
      ),
      body: ListenableBuilder(listenable: _v, builder: (BuildContext context, Widget? _) => _body(context)),
    );
  }

  Widget _body(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final List<Receipt> list = _v.search(_q.text);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: <Widget>[
        TextField(
          key: const Key('rc-search'),
          controller: _q,
          onChanged: (String _) => setState(() {}),
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            labelText: 'Search shop, amount or any word',
          ),
        ),
        const SizedBox(height: 8),
        if (list.isEmpty)
          Text(_v.all.isEmpty ? 'No receipts yet. Add a photo; the text is read on this phone.' : 'No receipts match.', style: text.bodyMedium),
        for (final Receipt r in list) _card(context, r),
      ],
    );
  }

  Widget _card(BuildContext context, Receipt r) {
    final TextTheme text = Theme.of(context).textTheme;
    final String amount = r.paise == null ? '' : ' · ${ReceiptVault.amountLabel(r.paise!)}';
    return Card(
      key: Key('rc-${r.id}'),
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(r.shop, style: text.titleMedium),
            Text('${ReceiptVault.dayLabel(r.date)}$amount', style: text.bodySmall),
            if (r.tags.isNotEmpty) Text(r.tags.join(', '), style: text.bodySmall),
            if (r.expenseId != null) const Text('Filed as an expense'),
            if (r.warrantyEnds != null)
              Text('Warranty${r.product.isEmpty ? '' : ' (${r.product})'} till ${ReceiptVault.dayLabel(r.warrantyEnds!)}', key: Key('rc-w-${r.id}')),
            Wrap(
              spacing: 8,
              children: <Widget>[
                if (r.expenseId == null && r.paise != null)
                  TextButton.icon(
                    key: Key('rc-expense-${r.id}'),
                    style: TextButton.styleFrom(minimumSize: const Size(88, 48)),
                    onPressed: () => _snack(_v.fileAsExpense(r.id) == null ? 'Could not file it' : 'Added to expenses'),
                    icon: const Icon(Icons.account_balance_wallet_outlined),
                    label: const Text('File as expense'),
                  ),
                TextButton.icon(
                  key: Key('rc-warranty-${r.id}'),
                  style: TextButton.styleFrom(minimumSize: const Size(88, 48)),
                  onPressed: () => unawaited(_warranty(r)),
                  icon: const Icon(Icons.verified_outlined),
                  label: const Text('Warranty'),
                ),
                TextButton.icon(
                  key: Key('rc-delete-${r.id}'),
                  style: TextButton.styleFrom(minimumSize: const Size(88, 48)),
                  onPressed: () => _v.remove(r.id),
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
