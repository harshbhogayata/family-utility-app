import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../app/widgets/result_bar.dart';
import '../../engines/platform/home_widgets.dart';
import '../../engines/share/share_engine.dart';

typedef WidgetTextAction = Future<String?> Function(String text);

/// Feature 112 — preview the home-screen widget, set its speed-dial row, and
/// see how to add the widget and the quick-settings tile.
class HomeWidgetScreen extends StatefulWidget {
  const HomeWidgetScreen({super.key, this.widgets, this.share, this.save});

  final HomeWidgets? widgets;
  final WidgetTextAction? share;
  final WidgetTextAction? save;

  @override
  State<HomeWidgetScreen> createState() => _HomeWidgetScreenState();
}

class _HomeWidgetScreenState extends State<HomeWidgetScreen> {
  HomeWidgets get _w => widget.widgets ?? HomeWidgets.instance;

  final TextEditingController _label = TextEditingController();
  final TextEditingController _number = TextEditingController();
  List<SpeedDialEntry>? _before;

  @override
  void initState() {
    super.initState();
    if (_w.snapshot == null) {
      unawaited(_w.refresh());
    }
  }

  @override
  void dispose() {
    _label.dispose();
    _number.dispose();
    super.dispose();
  }

  void _snack(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  String _describe() => (_w.snapshot ?? WidgetSnapshot.build(now: DateTime.now(), speedDial: _w.speedDial)).describe();

  Future<void> _add() async {
    final SpeedDialEntry e = SpeedDialEntry(label: _label.text.trim(), number: _number.text.trim());
    if (!e.isValid) {
      _snack('Enter a name and a phone number');
      return;
    }
    if (_w.speedDial.length >= WidgetSnapshot.maxSpeedDial) {
      _snack('The widget has room for ${WidgetSnapshot.maxSpeedDial} numbers');
      return;
    }
    final List<SpeedDialEntry> before = _w.speedDial;
    final bool ok = await _w.addSpeedDial(e);
    if (!mounted) {
      return;
    }
    if (ok) {
      _before = before;
      _label.clear();
      _number.clear();
      _snack('Added ${e.label} to the widget');
    } else {
      _snack('That number is already on the widget');
    }
  }

  Future<void> _remove(int i) async {
    final List<SpeedDialEntry> before = _w.speedDial;
    if (await _w.removeSpeedDial(i)) {
      _before = before;
      if (mounted) {
        _snack('Removed ${before[i].label}');
      }
    }
  }

  Future<void> _share() async {
    final WidgetTextAction? s = widget.share;
    if (s != null) {
      await s(_describe());
    } else {
      await ShareEngine.instance.shareText(_describe(), subject: 'Home widget');
    }
  }

  static Future<String?> _saveToDocuments(String text) async {
    final Directory dir = await getApplicationDocumentsDirectory();
    final File f = File('${dir.path}/Home widget.txt');
    await f.writeAsString(text);
    return f.path;
  }

  Future<void> _save() async {
    String? where;
    try {
      where = await (widget.save ?? _saveToDocuments)(_describe());
    } catch (_) {
      where = null;
    }
    if (mounted) {
      _snack(where == null ? 'Could not save' : 'Saved to $where');
    }
  }

  Future<void> _undo() async {
    final List<SpeedDialEntry>? b = _before;
    _before = null;
    if (b != null) {
      await _w.setSpeedDial(b);
    }
    if (mounted) {
      _snack(b == null ? 'Nothing to undo' : 'Undone');
    }
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return ListenableBuilder(
      listenable: _w,
      builder: (BuildContext context, Widget? _) {
        final WidgetSnapshot snap =
            _w.snapshot ?? WidgetSnapshot.build(now: DateTime.now(), speedDial: _w.speedDial);
        return Scaffold(
          appBar: AppBar(title: const Text('Widgets and tile')),
          bottomNavigationBar: ResultBar(
            onShare: () => unawaited(_share()),
            onSave: () => unawaited(_save()),
            onUndo: () => unawaited(_undo()),
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              Text('Preview', style: text.titleMedium),
              const SizedBox(height: 8),
              _Preview(snapshot: snap),
              const SizedBox(height: 24),
              Text('Speed dial on the widget', style: text.titleMedium),
              const SizedBox(height: 4),
              Text(
                'Up to ${WidgetSnapshot.maxSpeedDial} numbers. Tapping one opens the phone dialler. '
                'Numbers stay on this phone.',
                style: text.bodyMedium,
              ),
              for (int i = 0; i < snap.speedDial.length; i++)
                ListTile(
                  key: Key('dial-$i'),
                  contentPadding: EdgeInsets.zero,
                  minTileHeight: 56,
                  leading: const Icon(Icons.call_outlined),
                  title: Text(snap.speedDial[i].label),
                  subtitle: Text(snap.speedDial[i].dialable),
                  trailing: IconButton(
                    key: Key('dial-remove-$i'),
                    tooltip: 'Remove ${snap.speedDial[i].label}',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => unawaited(_remove(i)),
                  ),
                ),
              const SizedBox(height: 8),
              TextField(
                key: const Key('dial-label'),
                controller: _label,
                decoration: const InputDecoration(labelText: 'Name', hintText: 'Doctor'),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 8),
              TextField(
                key: const Key('dial-number'),
                controller: _number,
                decoration: const InputDecoration(labelText: 'Phone number'),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  key: const Key('dial-add'),
                  style: FilledButton.styleFrom(minimumSize: const Size(44, 48)),
                  onPressed: () => unawaited(_add()),
                  icon: const Icon(Icons.add),
                  label: const Text('Add to widget'),
                ),
              ),
              const SizedBox(height: 24),
              Text('Adding them', style: text.titleMedium),
              const SizedBox(height: 4),
              Text(
                Platform.isIOS
                    ? 'Home Screen: touch and hold an empty spot, tap +, and pick Family. '
                        'Lock Screen (iOS 16+): touch and hold the Lock Screen, tap Customise, then add the Family widget.'
                    : 'Home screen: touch and hold an empty spot, tap Widgets, and drag Family onto the screen. '
                        'Quick settings: pull the shade down twice, tap the pencil, and drag the Scan tile up.',
                style: text.bodyMedium,
              ),
              const SizedBox(height: 8),
              Text(
                _w.published ? 'The widget is up to date.' : 'The widget updates when it is on the home screen.',
                key: const Key('widget-status'),
                style: text.bodySmall,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview({required this.snapshot});

  final WidgetSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final ColorScheme c = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;
    return Semantics(
      container: true,
      label: 'Widget preview',
      child: Container(
        key: const Key('widget-preview'),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: c.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: c.outline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.medication_outlined, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    snapshot.medicineDetail.isEmpty
                        ? snapshot.medicineTitle
                        : '${snapshot.medicineTitle} · ${snapshot.medicineDetail}',
                    key: const Key('preview-medicine'),
                    style: text.bodyLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                const _Pill(icon: Icons.document_scanner_outlined, label: 'Scan'),
                const _Pill(icon: Icons.content_paste, label: 'Paste'),
                for (final SpeedDialEntry e in snapshot.speedDial) _Pill(icon: Icons.call_outlined, label: e.label),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 18),
          const SizedBox(width: 6),
          Text(label),
        ],
      ),
    );
  }
}
