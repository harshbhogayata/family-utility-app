import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../app/widgets/result_bar.dart';
import '../../engines/records/expense_tracker.dart';
import '../../engines/records/quick_add.dart';
import '../../engines/share/share_engine.dart';

/// Feature 121 — type "paid 350 milk", check what was understood, then save
/// it to the expense ledger.
class QuickAddScreen extends StatefulWidget {
  const QuickAddScreen({super.key, this.ledger, this.now, this.share, this.save});

  final ExpenseTracker? ledger;
  final DateTime Function()? now;
  final Future<void> Function(String text)? share;
  final Future<String?> Function(String text)? save;

  @override
  State<QuickAddScreen> createState() => _QuickAddScreenState();
}

class _QuickAddScreenState extends State<QuickAddScreen> {
  ExpenseTracker get _ledger => widget.ledger ?? ExpenseTracker.instance;
  late final QuickAddParser _parser = QuickAddParser(now: widget.now);
  final TextEditingController _text = TextEditingController();
  QuickEntry? _entry;
  final List<Expense> _saved = <Expense>[];

  static const List<String> _mon = <String>[
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec', //
  ];

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _snack(String s) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
    }
  }

  String _date(DateTime d) => '${d.day} ${_mon[d.month - 1]} ${d.year}';

  String _line(Expense e) => '${_date(e.at)}: ₹${formatPaise(e.paise)} ${e.category}${e.note.isEmpty ? '' : ' — ${e.note}'}';

  String get _summary => _saved.isEmpty ? 'Nothing added yet' : 'Added\n${_saved.map(_line).join('\n')}';

  void _confirm() {
    final QuickEntry? e = _entry;
    if (e == null) {
      return;
    }
    final Expense? saved = QuickAddParser.save(e, _ledger, now: widget.now);
    if (saved == null) {
      _snack('Could not add that');
      return;
    }
    setState(() {
      _saved.insert(0, saved);
      _entry = null;
      _text.clear();
    });
    _snack('Added ₹${formatPaise(saved.paise)} to ${saved.category}');
  }

  void _undo() {
    if (_saved.isNotEmpty && _ledger.remove(_saved.first.id)) {
      setState(() => _saved.removeAt(0));
      _snack('Undone');
    } else {
      _snack('Nothing to undo');
    }
  }

  Future<void> _share() async {
    final Future<void> Function(String)? s = widget.share;
    if (s != null) {
      await s(_summary);
    } else {
      await ShareEngine.instance.shareText(_summary, subject: 'Expenses added');
    }
  }

  Future<void> _save() async {
    String? where;
    try {
      final Future<String?> Function(String)? s = widget.save;
      if (s != null) {
        where = await s(_summary);
      } else {
        final Directory dir = await getApplicationDocumentsDirectory();
        final File f = File('${dir.path}/Quick-add.txt');
        await f.writeAsString(_summary);
        where = f.path;
      }
    } catch (_) {
      where = null;
    }
    _snack(where == null ? 'Could not save' : 'Saved to $where');
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final QuickEntry? e = _entry;
    return Scaffold(
      appBar: AppBar(title: const Text('Quick add')),
      bottomNavigationBar: ResultBar(onShare: () => unawaited(_share()), onSave: () => unawaited(_save()), onUndo: _undo),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          TextField(
            key: const Key('quick-text'),
            controller: _text,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'What did you pay?',
              hintText: 'paid 350 milk · kal Ramesh ko 500 diye',
            ),
            onChanged: (String v) => setState(() => _entry = _parser.parse(v)),
          ),
          const SizedBox(height: 16),
          if (e == null && _text.text.trim().isNotEmpty)
            Text('Add an amount, like 350 or ₹1,200', style: text.bodyMedium),
          if (e != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('Check before saving', style: text.titleSmall),
                    const SizedBox(height: 8),
                    _field('Amount', '₹${formatPaise(e.paise)}', 'quick-amount'),
                    _field('Item', e.item.isEmpty ? '—' : e.item, 'quick-item'),
                    _field('Category', e.category, 'quick-category'),
                    _field('Person', e.person ?? '—', 'quick-person'),
                    _field('Date', _date(e.date), 'quick-date'),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      key: const Key('quick-confirm'),
                      style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 48)),
                      onPressed: _confirm,
                      icon: const Icon(Icons.check),
                      label: const Text('Save to expenses'),
                    ),
                  ],
                ),
              ),
            ),
          if (_saved.isNotEmpty) ...<Widget>[
            const SizedBox(height: 16),
            Text('Added this time', style: text.titleSmall),
            for (final Expense s in _saved) Text(_line(s)),
          ],
        ],
      ),
    );
  }

  Widget _field(String label, String value, String key) {
    return Semantics(
      container: true,
      label: '$label: $value',
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: <Widget>[
              SizedBox(width: 88, child: Text(label)),
              Expanded(child: Text(value, key: Key(key))),
            ],
          ),
        ),
      ),
    );
  }
}
