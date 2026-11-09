import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../../app/widgets/result_bar.dart';
import '../../engines/records/expense_tracker.dart';
import '../../engines/share/share_engine.dart';

/// Feature 080 — month view, category totals, quick-add and receipt photos.
class ExpenseScreen extends StatefulWidget {
  const ExpenseScreen({super.key, this.tracker, this.share, this.save, this.pickPhoto, this.now});

  final ExpenseTracker? tracker;

  /// Shares the CSV text; defaults to the share sheet.
  final Future<void> Function(String csv)? share;

  /// Saves the CSV and returns where; defaults to the app's documents.
  final Future<String?> Function(String csv, String name)? save;

  /// Takes or picks a receipt photo and returns its kept path.
  final Future<String?> Function()? pickPhoto;
  final DateTime Function()? now;

  @override
  State<ExpenseScreen> createState() => _ExpenseScreenState();
}

class _ExpenseScreenState extends State<ExpenseScreen> {
  ExpenseTracker get _t => widget.tracker ?? ExpenseTracker.instance;
  final TextEditingController _quick = TextEditingController();
  late DateTime _month;

  static const List<String> _months = <String>[
    'January', 'February', 'March', 'April', 'May', 'June', //
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  @override
  void initState() {
    super.initState();
    final DateTime n = (widget.now ?? DateTime.now)();
    _month = DateTime(n.year, n.month);
  }

  @override
  void dispose() {
    _quick.dispose();
    super.dispose();
  }

  void _snack(String s) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
    }
  }

  String get _csvName => 'Expenses ${_month.year}-${_month.month.toString().padLeft(2, '0')}.csv';
  String get _csv => _t.toCsv(year: _month.year, month: _month.month);

  Future<void> _share() async {
    final Future<void> Function(String)? s = widget.share;
    if (s != null) {
      await s(_csv);
      return;
    }
    final Directory dir = await getTemporaryDirectory();
    final File f = File('${dir.path}/$_csvName');
    await f.writeAsString(_csv);
    await ShareEngine.instance.shareFiles(<String>[f.path]);
  }

  static Future<String?> _saveToDocuments(String csv, String name) async {
    final Directory dir = await getApplicationDocumentsDirectory();
    final File f = File('${dir.path}/$name');
    await f.writeAsString(csv);
    return f.path;
  }

  Future<void> _save() async {
    String? where;
    try {
      where = await (widget.save ?? _saveToDocuments)(_csv, _csvName);
    } catch (_) {
      where = null;
    }
    _snack(where == null ? 'Could not save the CSV' : 'Saved to $where');
  }

  static Future<String?> _pickReceipt() async {
    final XFile? x = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 70);
    if (x == null) {
      return null;
    }
    final Directory base = await getApplicationDocumentsDirectory();
    final Directory dir = Directory('${base.path}/expenses/receipts');
    await dir.create(recursive: true);
    final String path = '${dir.path}/receipt_${DateTime.now().millisecondsSinceEpoch}.jpg';
    await File(x.path).copy(path);
    return path;
  }

  void _quickAdd() {
    final Expense? e = _t.quickAdd(_quick.text);
    if (e == null) {
      _snack('Start or end with an amount, like "450 groceries"');
      return;
    }
    _quick.clear();
    setState(() => _month = DateTime(e.at.year, e.at.month));
    _snack('Added ₹${formatPaise(e.paise)} to ${e.category}');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Expenses')),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('expense-add'),
        onPressed: () => unawaited(_add()),
        icon: const Icon(Icons.add),
        label: const Text('Add expense'),
      ),
      bottomNavigationBar: ResultBar(
        onShare: () => unawaited(_share()),
        onSave: () => unawaited(_save()),
        onUndo: () => _snack(_t.undo() ? 'Undone' : 'Nothing to undo'),
        saveLabel: 'Save CSV',
      ),
      body: ListenableBuilder(listenable: _t, builder: (BuildContext context, Widget? _) => _body(context)),
    );
  }

  Widget _body(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final List<Expense> entries = _t.inMonth(_month.year, _month.month);
    final int total = _t.monthTotal(_month.year, _month.month);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: TextField(
                key: const Key('expense-quick'),
                controller: _quick,
                decoration: const InputDecoration(labelText: 'Quick add', hintText: '450 groceries milk'),
                onSubmitted: (_) => _quickAdd(),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              key: const Key('expense-quick-add'),
              style: FilledButton.styleFrom(minimumSize: const Size(64, 48)),
              onPressed: _quickAdd,
              child: const Text('Add'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: <Widget>[
            IconButton(
              key: const Key('expense-prev'),
              tooltip: 'Previous month',
              onPressed: () => setState(() => _month = DateTime(_month.year, _month.month - 1)),
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: Text(
                '${_months[_month.month - 1]} ${_month.year}',
                textAlign: TextAlign.center,
                style: text.titleMedium,
              ),
            ),
            IconButton(
              key: const Key('expense-next'),
              tooltip: 'Next month',
              onPressed: () => setState(() => _month = DateTime(_month.year, _month.month + 1)),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        Semantics(
          container: true,
          label: 'Total this month ₹${formatPaise(total)}',
          child: ExcludeSemantics(
            child: Text('₹${formatPaise(total)}', key: const Key('expense-total'), style: text.headlineMedium, textAlign: TextAlign.center),
          ),
        ),
        const SizedBox(height: 8),
        for (final MapEntry<String, int> c in _t.categoryTotals(_month.year, _month.month))
          ListTile(
            key: Key('cat-${c.key}'),
            contentPadding: EdgeInsets.zero,
            minTileHeight: 44,
            title: Text(c.key),
            trailing: Text('₹${formatPaise(c.value)}'),
          ),
        const Divider(),
        if (entries.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text('No expenses this month.', style: text.bodyMedium),
          ),
        for (final Expense e in entries)
          ListTile(
            key: Key('expense-${e.id}'),
            contentPadding: EdgeInsets.zero,
            minTileHeight: 56,
            leading: Icon(e.photo == null ? Icons.receipt_long_outlined : Icons.photo_outlined),
            title: Text('₹${formatPaise(e.paise)} · ${e.category}'),
            subtitle: Text('${e.at.day} ${_months[e.at.month - 1].substring(0, 3)}${e.note.isEmpty ? '' : ' · ${e.note}'}'),
            trailing: IconButton(
              tooltip: 'Delete',
              onPressed: () => _t.remove(e.id),
              icon: const Icon(Icons.delete_outline),
            ),
          ),
      ],
    );
  }

  Future<void> _add() async {
    final TextEditingController amount = TextEditingController();
    final TextEditingController note = TextEditingController();
    String category = ExpenseTracker.categoryNames.first;
    String? photo;
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Add expense'),
        content: StatefulBuilder(
          builder: (BuildContext context, StateSetter set) => SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                TextField(
                  key: const Key('expense-amount'),
                  controller: amount,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Amount (₹)'),
                ),
                DropdownButtonFormField<String>(
                  key: const Key('expense-category'),
                  initialValue: category,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: <DropdownMenuItem<String>>[
                    for (final String c in ExpenseTracker.categoryNames) DropdownMenuItem<String>(value: c, child: Text(c)),
                  ],
                  onChanged: (String? v) => set(() => category = v ?? category),
                ),
                TextField(
                  key: const Key('expense-note'),
                  controller: note,
                  decoration: const InputDecoration(labelText: 'Note'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  key: const Key('expense-photo'),
                  style: OutlinedButton.styleFrom(minimumSize: const Size(88, 48)),
                  onPressed: () async {
                    String? p;
                    try {
                      p = await (widget.pickPhoto ?? _pickReceipt)();
                    } catch (_) {
                      p = null;
                    }
                    if (p != null) {
                      set(() => photo = p);
                    }
                  },
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: Text(photo == null ? 'Receipt photo' : 'Photo added'),
                ),
              ],
            ),
          ),
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(key: const Key('expense-save'), onPressed: () => Navigator.pop(context, true), child: const Text('Add')),
        ],
      ),
    );
    if (ok == true) {
      final int? p = parsePaise(amount.text);
      final Expense? e = p == null ? null : _t.add(paise: p, category: category, note: note.text, photo: photo);
      if (e == null) {
        _snack('Enter an amount, like 250 or 99.50');
      } else {
        setState(() => _month = DateTime(e.at.year, e.at.month));
      }
    }
  }
}
