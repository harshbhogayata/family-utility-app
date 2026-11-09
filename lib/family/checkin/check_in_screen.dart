import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../app/theme.dart';
import '../../app/widgets/result_bar.dart';
import '../../engines/family/check_ins.dart';
import '../../engines/family/family_location.dart';
import '../../engines/share/share_engine.dart';

typedef CheckInTextAction = Future<String?> Function(String text);

/// Feature 077 — "Reached safely" in one tap, automatic on arriving at a
/// saved place, and the family feed of check-ins.
class CheckInScreen extends StatefulWidget {
  const CheckInScreen({super.key, this.checkIns, this.share, this.save});

  final CheckIns? checkIns;
  final CheckInTextAction? share;
  final CheckInTextAction? save;

  @override
  State<CheckInScreen> createState() => _CheckInScreenState();
}

class _CheckInScreenState extends State<CheckInScreen> {
  final TextEditingController _note = TextEditingController();

  CheckIns get _c => widget.checkIns ?? CheckIns.instance!;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  void _snack(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  void _checkIn() {
    final CheckIn c = _c.checkIn(note: _note.text);
    _note.clear();
    _snack('Posted: ${_c.lineFor(c)}');
  }

  Future<void> _share() async {
    final String text = _c.toText();
    final CheckInTextAction? s = widget.share;
    if (s != null) {
      await s(text);
    } else {
      await ShareEngine.instance.shareText(text, subject: 'Family check-ins');
    }
  }

  Future<void> _save() async {
    final String text = _c.toText();
    final CheckInTextAction s = widget.save ?? _saveToDocuments;
    String? where;
    try {
      where = await s(text);
    } catch (_) {
      where = null;
    }
    if (mounted) {
      _snack(where == null ? 'Could not save' : 'Saved to $where');
    }
  }

  static Future<String?> _saveToDocuments(String text) async {
    final Directory dir = await getApplicationDocumentsDirectory();
    final File f = File('${dir.path}/Family check-ins.txt');
    await f.writeAsString(text);
    return f.path;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Check in')),
      bottomNavigationBar: ResultBar(
        onShare: () => unawaited(_share()),
        onSave: () => unawaited(_save()),
        onUndo: () => _snack(_c.undo() ? 'Check-in taken back' : 'Nothing to undo'),
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge(<Listenable>[_c, _c.store, _c.location]),
        builder: (BuildContext context, Widget? _) => _body(context),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final FamilyPlace? here = _c.currentPlace;
    final List<CheckIn> feed = _c.feed;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      children: <Widget>[
        TextField(
          controller: _note,
          decoration: const InputDecoration(labelText: 'Add a note (optional)'),
          textCapitalization: TextCapitalization.sentences,
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 56,
          child: FilledButton.icon(
            onPressed: _checkIn,
            icon: const Icon(Icons.verified_user_outlined),
            label: Text(here == null ? 'Reached safely' : 'Reached ${here.name} safely'),
          ),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Check in automatically'),
          subtitle: const Text('When this phone arrives at a family place (Home, School, Office)'),
          value: _c.autoOn,
          onChanged: _c.setAuto,
        ),
        const SizedBox(height: 12),
        Semantics(header: true, child: Text('Family feed', style: text.titleMedium)),
        if (feed.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text('No check-ins in the last 7 days.', style: text.bodyMedium),
          ),
        for (final CheckIn c in feed)
          ListTile(
            key: Key('checkin-${c.id}'),
            contentPadding: EdgeInsets.zero,
            minTileHeight: 48,
            leading: Icon(c.auto ? Icons.place : Icons.verified_user, color: AppColors.accent),
            title: Text(_c.lineFor(c)),
          ),
      ],
    );
  }
}
