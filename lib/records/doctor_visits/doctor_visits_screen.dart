import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../app/widgets/result_bar.dart';
import '../../engines/records/doctor_visits.dart';
import '../../engines/share/share_engine.dart';
import '../../tools/document_scanner/document_scanner_screen.dart';

/// Feature 090 — doctor visits, scanned prescriptions and the next
/// appointment on the shared calendar.
class DoctorVisitsScreen extends StatefulWidget {
  const DoctorVisitsScreen({super.key, this.visits, this.scan, this.share, this.save});

  final DoctorVisits? visits;

  /// Opens the document scanner and returns the saved pages; defaults to
  /// the app's own scanner (047).
  final Future<List<String>> Function()? scan;

  /// Shares text with optional files; defaults to the share sheet.
  final Future<void> Function(String text, List<String> files)? share;
  final Future<String?> Function(String text, String name)? save;

  @override
  State<DoctorVisitsScreen> createState() => _DoctorVisitsScreenState();
}

class _DoctorVisitsScreenState extends State<DoctorVisitsScreen> {
  DoctorVisits get _v => widget.visits ?? DoctorVisits.instance;

  void _snack(String s) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
    }
  }

  Future<void> _share(String text, List<String> files) async {
    final Future<void> Function(String, List<String>)? s = widget.share;
    if (s != null) {
      await s(text, files);
      return;
    }
    final List<String> present = files.where((String p) => File(p).existsSync()).toList();
    if (present.isEmpty) {
      await ShareEngine.instance.shareText(text);
    } else {
      await ShareEngine.instance.shareFiles(present, text: text);
    }
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
      where = await (widget.save ?? _saveToDocuments)(_v.toText(), 'Doctor visits.txt');
    } catch (_) {
      where = null;
    }
    _snack(where == null ? 'Could not save the visits' : 'Saved to $where');
  }

  Future<List<String>> _scan() async {
    final Future<List<String>> Function()? s = widget.scan;
    if (s != null) {
      return s();
    }
    final List<String>? saved = await Navigator.of(context).push<List<String>>(
      MaterialPageRoute<List<String>>(builder: (BuildContext context) => const DocumentScannerScreen(returnResult: true)),
    );
    return saved ?? <String>[];
  }

  Future<void> _scanInto(DoctorVisit v) async {
    List<String> pages = <String>[];
    try {
      pages = await _scan();
    } catch (_) {
      pages = <String>[];
    }
    if (!mounted) {
      return;
    }
    _snack(_v.attachPrescriptions(v.id, pages) ? 'Prescription added' : 'No pages scanned');
  }

  static DateTime? parseDay(String s) {
    final RegExpMatch? m = RegExp(r'^\s*(\d{1,2})[/.\-](\d{1,2})[/.\-](\d{4})\s*$').firstMatch(s);
    if (m == null) {
      return null;
    }
    final int d = int.parse(m.group(1)!);
    final int mo = int.parse(m.group(2)!);
    final int y = int.parse(m.group(3)!);
    final DateTime out = DateTime(y, mo, d);
    return out.month == mo && out.day == d ? out : null;
  }

  /// "24/08/2026" or "24/08/2026 10:30".
  static DateTime? parseWhen(String s) {
    final RegExpMatch? m = RegExp(r'^\s*(\S+)(?:\s+(\d{1,2}):(\d{2}))?\s*$').firstMatch(s);
    if (m == null) {
      return null;
    }
    final DateTime? day = parseDay(m.group(1)!);
    if (day == null) {
      return null;
    }
    final int h = m.group(2) == null ? 10 : int.parse(m.group(2)!);
    final int min = m.group(3) == null ? 0 : int.parse(m.group(3)!);
    if (h > 23 || min > 59) {
      return null;
    }
    return DateTime(day.year, day.month, day.day, h, min);
  }

  Future<void> _add() async {
    final TextEditingController person = TextEditingController();
    final TextEditingController doctor = TextEditingController();
    final TextEditingController date = TextEditingController(text: _fmtDay(DateTime.now()));
    final TextEditingController notes = TextEditingController();
    final TextEditingController next = TextEditingController();
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Add a visit'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextField(key: const Key('dv-person'), controller: person, decoration: const InputDecoration(labelText: 'Who went')),
              TextField(key: const Key('dv-doctor'), controller: doctor, decoration: const InputDecoration(labelText: 'Doctor')),
              TextField(
                key: const Key('dv-date'),
                controller: date,
                keyboardType: TextInputType.datetime,
                decoration: const InputDecoration(labelText: 'Visit date', hintText: '24/08/2026'),
              ),
              TextField(
                key: const Key('dv-notes'),
                controller: notes,
                maxLines: 3,
                minLines: 1,
                decoration: const InputDecoration(labelText: 'Notes'),
              ),
              TextField(
                key: const Key('dv-next'),
                controller: next,
                keyboardType: TextInputType.datetime,
                decoration: const InputDecoration(labelText: 'Next appointment (optional)', hintText: '07/09/2026 10:30'),
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(key: const Key('dv-save'), onPressed: () => Navigator.pop(context, true), child: const Text('Add')),
        ],
      ),
    );
    if (ok != true) {
      return;
    }
    final DateTime? day = parseDay(date.text);
    final DateTime? nextAt = next.text.trim().isEmpty ? null : parseWhen(next.text);
    if (day == null || (next.text.trim().isNotEmpty && nextAt == null)) {
      _snack('Type dates like 24/08/2026 and times like 10:30');
      return;
    }
    final DoctorVisit? v = _v.add(person: person.text, doctor: doctor.text, date: day, notes: notes.text, nextAt: nextAt);
    _snack(v == null ? 'Add who went or the doctor; the next appointment must be ahead' : 'Visit added');
  }

  Future<void> _next(DoctorVisit v) async {
    final TextEditingController t = TextEditingController(text: v.nextAt == null ? '' : '${_fmtDay(v.nextAt!)} ${_hm(v.nextAt!)}');
    final String? res = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Next appointment'),
        content: TextField(
          key: const Key('dv-next-when'),
          controller: t,
          keyboardType: TextInputType.datetime,
          decoration: const InputDecoration(labelText: 'Date and time', hintText: '07/09/2026 10:30'),
        ),
        actions: <Widget>[
          if (v.nextAt != null) TextButton(key: const Key('dv-next-clear'), onPressed: () => Navigator.pop(context, ''), child: const Text('Clear')),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(key: const Key('dv-next-save'), onPressed: () => Navigator.pop(context, t.text), child: const Text('Set')),
        ],
      ),
    );
    if (res == null) {
      return;
    }
    if (res.trim().isEmpty) {
      _snack(_v.setNext(v.id, null) ? 'Appointment cleared' : 'Nothing to clear');
      return;
    }
    final DateTime? at = parseWhen(res);
    _snack(at != null && _v.setNext(v.id, at) ? 'On the family calendar, reminder the day before' : 'Pick a time ahead, like 07/09/2026 10:30');
  }

  static String _two(int n) => n.toString().padLeft(2, '0');
  static String _fmtDay(DateTime d) => '${_two(d.day)}/${_two(d.month)}/${d.year}';
  static String _hm(DateTime d) => '${_two(d.hour)}:${_two(d.minute)}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Doctor visits')),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('dv-add'),
        onPressed: () => unawaited(_add()),
        icon: const Icon(Icons.add),
        label: const Text('Add visit'),
      ),
      bottomNavigationBar: ResultBar(
        onShare: () => unawaited(_share(_v.toText(), <String>[for (final DoctorVisit v in _v.all) ...v.prescriptions])),
        onSave: () => unawaited(_save()),
        onUndo: () => _snack(_v.undo() ? 'Undone' : 'Nothing to undo'),
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge(<Listenable>[_v, _v.store]),
        builder: (BuildContext context, Widget? _) => _body(context),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final List<DoctorVisit> list = _v.all;
    if (list.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text('No visits yet. Add one, scan the prescription and set the next appointment.', style: text.bodyMedium),
      );
    }
    final List<DoctorVisit> soon = _v.upcoming;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: <Widget>[
        if (soon.isNotEmpty) ...<Widget>[
          Text('Coming up', style: text.titleMedium),
          for (final DoctorVisit v in soon)
            Text(
              '${DoctorVisits.timeLabel(v.nextAt!)} · ${v.doctor.isEmpty ? 'Doctor' : v.doctor}${v.person.isEmpty ? '' : ' · ${v.person}'}',
              key: Key('dv-soon-${v.id}'),
            ),
          const SizedBox(height: 8),
          Text('Visits', style: text.titleMedium),
        ],
        for (final DoctorVisit v in list) _card(context, v),
      ],
    );
  }

  Widget _card(BuildContext context, DoctorVisit v) {
    final TextTheme text = Theme.of(context).textTheme;
    final String title = <String>[if (v.person.isNotEmpty) v.person, if (v.doctor.isNotEmpty) v.doctor].join(' · ');
    return Card(
      key: Key('dv-${v.id}'),
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(title, style: text.titleMedium),
            Text(DoctorVisits.dayLabel(v.date), style: text.bodySmall),
            if (v.notes.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(v.notes)),
            for (int i = 0; i < v.prescriptions.length; i++)
              Row(
                children: <Widget>[
                  const Icon(Icons.description_outlined, size: 18),
                  const SizedBox(width: 6),
                  Expanded(child: Text(DoctorVisits.fileName(v.prescriptions[i]))),
                  IconButton(
                    tooltip: 'Remove prescription',
                    onPressed: () => _v.removePrescription(v.id, i),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            if (v.nextAt != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Next: ${DoctorVisits.timeLabel(v.nextAt!)}', key: Key('dv-next-${v.id}')),
              ),
            Wrap(
              spacing: 8,
              children: <Widget>[
                TextButton.icon(
                  key: Key('dv-scan-${v.id}'),
                  style: TextButton.styleFrom(minimumSize: const Size(88, 48)),
                  onPressed: () => unawaited(_scanInto(v)),
                  icon: const Icon(Icons.document_scanner_outlined),
                  label: const Text('Scan prescription'),
                ),
                TextButton.icon(
                  key: Key('dv-appt-${v.id}'),
                  style: TextButton.styleFrom(minimumSize: const Size(88, 48)),
                  onPressed: () => unawaited(_next(v)),
                  icon: const Icon(Icons.event_outlined),
                  label: const Text('Next appointment'),
                ),
                TextButton.icon(
                  key: Key('dv-share-${v.id}'),
                  style: TextButton.styleFrom(minimumSize: const Size(88, 48)),
                  onPressed: () => unawaited(_share(DoctorVisits.visitText(v), v.prescriptions)),
                  icon: const Icon(Icons.share_outlined),
                  label: const Text('Share'),
                ),
                TextButton.icon(
                  key: Key('dv-delete-${v.id}'),
                  style: TextButton.styleFrom(minimumSize: const Size(88, 48)),
                  onPressed: () => _v.remove(v.id),
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
