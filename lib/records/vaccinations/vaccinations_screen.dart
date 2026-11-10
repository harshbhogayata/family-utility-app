import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../app/widgets/result_bar.dart';
import '../../engines/records/vaccinations.dart';
import '../../engines/share/share_engine.dart';
import '../../tools/document_scanner/document_scanner_screen.dart';

typedef VaccineShare = Future<void> Function(String text);
typedef VaccineSave = Future<String?> Function(String text, String name);
typedef CertificateScan = Future<List<String>> Function(BuildContext context);

Future<void> _shareWith(VaccineShare? s, String text) async {
  if (s != null) {
    await s(text);
    return;
  }
  await ShareEngine.instance.shareText(text);
}

Future<String?> _saveToDocuments(String text, String name) async {
  final Directory dir = await getApplicationDocumentsDirectory();
  final File f = File('${dir.path}/$name');
  await f.writeAsString(text);
  return f.path;
}

Future<List<String>> _scanWithScanner(BuildContext context) async {
  final List<String>? saved = await Navigator.of(context).push<List<String>>(
    MaterialPageRoute<List<String>>(builder: (BuildContext context) => const DocumentScannerScreen(returnResult: true)),
  );
  return saved ?? <String>[];
}

DateTime? parseDay(String s) {
  final RegExpMatch? m = RegExp(r'^\s*(\d{1,2})[/.\-](\d{1,2})[/.\-](\d{4})\s*$').firstMatch(s);
  if (m == null) {
    return null;
  }
  final int d = int.parse(m.group(1)!), mo = int.parse(m.group(2)!), y = int.parse(m.group(3)!);
  final DateTime out = DateTime(y, mo, d);
  return out.month == mo && out.day == d ? out : null;
}

String _dmy(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

String stateLabel(DoseStatus s) => switch (s.state) {
      DoseState.given => 'Given ${Vaccinations.dayLabel(s.given!.on)}${s.due == null ? '' : ' · next ${Vaccinations.dayLabel(s.due!)}'}',
      DoseState.overdue => 'Overdue since ${Vaccinations.dayLabel(s.due!)}',
      DoseState.dueSoon => 'Due ${Vaccinations.dayLabel(s.due!)}',
      DoseState.later => s.due == null ? 'After dose 1' : 'Due ${Vaccinations.dayLabel(s.due!)}',
    };

/// Feature 092 — vaccination record for everyone in the family.
class VaccinationsScreen extends StatefulWidget {
  const VaccinationsScreen({super.key, this.vaccinations, this.scan, this.share, this.save});

  final Vaccinations? vaccinations;
  final CertificateScan? scan;
  final VaccineShare? share;
  final VaccineSave? save;

  @override
  State<VaccinationsScreen> createState() => _VaccinationsScreenState();
}

class _VaccinationsScreenState extends State<VaccinationsScreen> {
  Vaccinations get _v => widget.vaccinations ?? Vaccinations.instance;

  void _snack(String s) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
    }
  }

  Future<void> _save() async {
    String? where;
    try {
      where = await (widget.save ?? _saveToDocuments)(_v.toText(), 'Vaccination record.txt');
    } catch (_) {
      where = null;
    }
    _snack(where == null ? 'Could not save' : 'Saved to $where');
  }

  Future<void> _add() async {
    final TextEditingController name = TextEditingController();
    final TextEditingController born = TextEditingController();
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Add a person'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(key: const Key('vx-name'), controller: name, decoration: const InputDecoration(labelText: 'Name', hintText: 'Aarav')),
            TextField(
              key: const Key('vx-born'),
              controller: born,
              keyboardType: TextInputType.datetime,
              decoration: const InputDecoration(labelText: 'Date of birth', hintText: '14/01/2026'),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(key: const Key('vx-save'), onPressed: () => Navigator.pop(context, true), child: const Text('Add')),
        ],
      ),
    );
    if (ok != true) {
      return;
    }
    final DateTime? b = parseDay(born.text);
    final VaccinePerson? p = b == null ? null : _v.addPerson(name: name.text, born: b);
    _snack(p == null
        ? 'Type a name and a date of birth'
        : 'Added ${p.name} with the ${p.kind == ScheduleKind.child ? 'child' : 'adult'} schedule');
  }

  void _open(VaccinePerson p) {
    unawaited(Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext _) => VaccinePersonScreen(vaccinations: _v, personId: p.id, scan: widget.scan, share: widget.share, save: widget.save),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Vaccinations')),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('vx-add'),
        onPressed: () => unawaited(_add()),
        icon: const Icon(Icons.person_add_alt),
        label: const Text('Add person'),
      ),
      bottomNavigationBar: ResultBar(
        onShare: () => unawaited(_shareWith(widget.share, _v.toText())),
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
    final ColorScheme cs = Theme.of(context).colorScheme;
    final List<VaccinePerson> people = _v.people;
    if (people.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'Add a child or an adult. The Indian immunisation schedule is filled in from the date of birth, with reminders a week before each dose.',
          style: text.bodyMedium,
        ),
      );
    }
    final List<(VaccinePerson, DoseStatus)> due = _v.dueNow();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: <Widget>[
        if (due.isNotEmpty) ...<Widget>[
          Text('Due now', style: text.titleMedium),
          for (final (VaccinePerson, DoseStatus) d in due)
            ListTile(
              key: Key('vx-due-${d.$1.id}-${d.$2.dose.id}'),
              contentPadding: EdgeInsets.zero,
              minTileHeight: 48,
              leading: Icon(d.$2.state == DoseState.overdue ? Icons.warning_amber_outlined : Icons.event_outlined,
                  color: d.$2.state == DoseState.overdue ? cs.error : null),
              title: Text('${d.$1.name}: ${d.$2.dose.name}'),
              subtitle: Text(stateLabel(d.$2)),
              onTap: () => _open(d.$1),
            ),
          const Divider(),
        ],
        Text('People', style: text.titleMedium),
        for (final VaccinePerson p in people)
          Card(
            key: Key('vx-${p.id}'),
            margin: const EdgeInsets.symmetric(vertical: 6),
            child: ListTile(
              minTileHeight: 56,
              leading: Icon(p.kind == ScheduleKind.child ? Icons.child_care : Icons.person_outline),
              title: Text(p.name),
              subtitle: Text('Born ${Vaccinations.dayLabel(p.born)} · ${p.given.length} dose${p.given.length == 1 ? '' : 's'} recorded'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _open(p),
            ),
          ),
      ],
    );
  }
}

/// One person's schedule: mark doses given, attach certificate scans.
class VaccinePersonScreen extends StatefulWidget {
  const VaccinePersonScreen({super.key, required this.vaccinations, required this.personId, this.scan, this.share, this.save});

  final Vaccinations vaccinations;
  final String personId;
  final CertificateScan? scan;
  final VaccineShare? share;
  final VaccineSave? save;

  @override
  State<VaccinePersonScreen> createState() => _VaccinePersonScreenState();
}

class _VaccinePersonScreenState extends State<VaccinePersonScreen> {
  Vaccinations get _v => widget.vaccinations;

  void _snack(String s) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
    }
  }

  Future<void> _markGiven(VaccinePerson p, DoseStatus s) async {
    final DateTime now = DateTime.now();
    final DateTime suggest = s.due != null && s.due!.isBefore(now) && s.state != DoseState.given ? s.due! : now;
    final TextEditingController on = TextEditingController(text: _dmy(suggest));
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text('${s.dose.name} given'),
        content: TextField(
          key: const Key('vx-given-on'),
          controller: on,
          keyboardType: TextInputType.datetime,
          decoration: const InputDecoration(labelText: 'Given on', hintText: '24/08/2026'),
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(key: const Key('vx-given-save'), onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok != true) {
      return;
    }
    final DateTime? d = parseDay(on.text);
    final bool done = d != null && _v.markGiven(p.id, s.dose.id, on: d);
    _snack(done ? '${s.dose.name} recorded' : 'Type a date between the birth date and today');
  }

  Future<void> _attach(VaccinePerson p, DoseStatus s) async {
    List<String> pages = <String>[];
    try {
      pages = await (widget.scan ?? _scanWithScanner)(context);
    } catch (_) {
      pages = <String>[];
    }
    int n = 0;
    for (final String path in pages) {
      if (_v.attachCertificate(p.id, s.dose.id, path)) {
        n++;
      }
    }
    _snack(n == 0 ? 'No certificate attached' : 'Certificate attached');
  }

  Future<void> _save(VaccinePerson p) async {
    String? where;
    try {
      where = await (widget.save ?? _saveToDocuments)(_v.toText(p), 'Vaccinations ${p.name}.txt');
    } catch (_) {
      where = null;
    }
    _snack(where == null ? 'Could not save' : 'Saved to $where');
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[_v, _v.store]),
      builder: (BuildContext context, Widget? _) {
        final VaccinePerson? p = _v.byId(widget.personId);
        if (p == null) {
          return Scaffold(appBar: AppBar(), body: const Center(child: Text('This person was removed.')));
        }
        return Scaffold(
          appBar: AppBar(title: Text(p.name)),
          bottomNavigationBar: ResultBar(
            onShare: () => unawaited(_shareWith(widget.share, _v.toText(p))),
            onSave: () => unawaited(_save(p)),
            onUndo: () => _snack(_v.undo() ? 'Undone' : 'Nothing to undo'),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: <Widget>[for (final DoseStatus s in _v.schedule(p)) _row(context, p, s)],
          ),
        );
      },
    );
  }

  Widget _row(BuildContext context, VaccinePerson p, DoseStatus s) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme cs = Theme.of(context).colorScheme;
    final bool given = s.given != null;
    final int certs = s.given?.certificates.length ?? 0;
    return Card(
      key: Key('vx-dose-${s.dose.id}'),
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('${s.dose.name} · ${s.dose.when}', style: text.titleSmall),
            Text(
              stateLabel(s),
              key: Key('vx-state-${s.dose.id}'),
              style: text.bodyMedium?.copyWith(color: s.state == DoseState.overdue ? cs.error : null),
            ),
            if (certs > 0) Text('$certs certificate scan${certs == 1 ? '' : 's'} attached', style: text.bodySmall),
            Wrap(
              spacing: 4,
              children: <Widget>[
                TextButton.icon(
                  key: Key('vx-give-${s.dose.id}'),
                  style: TextButton.styleFrom(minimumSize: const Size(88, 48)),
                  onPressed: () => unawaited(_markGiven(p, s)),
                  icon: const Icon(Icons.check_circle_outline),
                  label: Text(given && s.dose.repeatDays != null ? 'Record next dose' : (given ? 'Change date' : 'Mark given')),
                ),
                if (given)
                  TextButton.icon(
                    key: Key('vx-cert-${s.dose.id}'),
                    style: TextButton.styleFrom(minimumSize: const Size(88, 48)),
                    onPressed: () => unawaited(_attach(p, s)),
                    icon: const Icon(Icons.document_scanner_outlined),
                    label: const Text('Scan certificate'),
                  ),
                if (given)
                  TextButton.icon(
                    key: Key('vx-ungive-${s.dose.id}'),
                    style: TextButton.styleFrom(minimumSize: const Size(88, 48)),
                    onPressed: () => _v.unmark(p.id, s.dose.id),
                    icon: const Icon(Icons.undo),
                    label: const Text('Not given'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
