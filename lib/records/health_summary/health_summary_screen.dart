import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../app/widgets/result_bar.dart';
import '../../engines/records/health_readings.dart';
import '../../engines/records/health_summary.dart';
import '../../engines/records/medicine_reminders.dart';
import '../../engines/records/reports_vault.dart';
import '../../engines/share/share_engine.dart';

/// Feature 094 — Health summary PDF: one page for a new doctor, generated
/// from the records on the phone, with only the sections the person picks.
class HealthSummaryScreen extends StatefulWidget {
  const HealthSummaryScreen({
    super.key,
    this.summary,
    this.medicines,
    this.members,
    this.readings,
    this.reports,
    this.share,
    this.save,
    this.now,
  });

  final HealthSummary? summary;

  /// Medicines this phone can see; defaults to the medicine reminders.
  final List<Medicine> Function()? medicines;

  /// Member ids and names whose medicines can be picked.
  final Map<String, String> Function()? members;
  final List<HealthReading> Function()? readings;
  final List<LabReport> Function()? reports;

  /// Shares the PDF; defaults to the share sheet.
  final Future<void> Function(Uint8List pdf, String name)? share;

  /// Saves the PDF and returns where; defaults to the app's documents.
  final Future<String?> Function(Uint8List pdf, String name)? save;
  final DateTime Function()? now;

  @override
  State<HealthSummaryScreen> createState() => _HealthSummaryScreenState();
}

class _HealthSummaryScreenState extends State<HealthSummaryScreen> {
  HealthSummary get _s => widget.summary ?? HealthSummary.instance;
  final TextEditingController _name = TextEditingController();
  final TextEditingController _condition = TextEditingController();
  final TextEditingController _allergy = TextEditingController();
  String? _member;

  DateTime _now() => (widget.now ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    _lastName = _s.profile.name;
    _name.text = _lastName;
    _s.addListener(_syncName);
  }

  String _lastName = '';

  /// Follows the stored name when it changes (load, undo), not while typing.
  void _syncName() {
    if (_s.profile.name != _lastName) {
      _lastName = _s.profile.name;
      _name.text = _lastName;
    }
  }

  @override
  void dispose() {
    _s.removeListener(_syncName);
    _name.dispose();
    _condition.dispose();
    _allergy.dispose();
    super.dispose();
  }

  void _snack(String s) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
    }
  }

  Map<String, String> get _members {
    try {
      return (widget.members ?? () => MedicineReminders.instance.members)();
    } catch (_) {
      return const <String, String>{};
    }
  }

  List<Medicine> get _medicines {
    List<Medicine> all;
    try {
      all = (widget.medicines ?? () => MedicineReminders.instance.visible)();
    } catch (_) {
      all = const <Medicine>[];
    }
    final String? m = _member;
    return m == null ? all : all.where((Medicine x) => x.memberId == m).toList();
  }

  List<SummaryBlock> _blocks() => HealthSummary.compose(
        profile: _s.profile,
        medicines: _medicines,
        readings: (widget.readings ?? () => HealthReadings.instance.all)(),
        reports: (widget.reports ?? () => ReportsVault.instance.reports)(),
        now: _now(),
      );

  String get _pdfName => HealthSummary.fileName(_s.profile, _now());

  Uint8List _pdf() => HealthSummary.pdf(profile: _s.profile, blocks: _blocks(), now: _now());

  Future<void> _share() async {
    final Uint8List bytes = _pdf();
    final Future<void> Function(Uint8List, String)? s = widget.share;
    if (s != null) {
      await s(bytes, _pdfName);
      return;
    }
    final Directory dir = await getTemporaryDirectory();
    final File f = File('${dir.path}/$_pdfName');
    await f.writeAsBytes(bytes);
    await ShareEngine.instance.shareFiles(<String>[f.path]);
  }

  static Future<String?> _saveToDocuments(Uint8List pdf, String name) async {
    final Directory dir = await getApplicationDocumentsDirectory();
    final File f = File('${dir.path}/$name');
    await f.writeAsBytes(pdf);
    return f.path;
  }

  Future<void> _save() async {
    String? where;
    try {
      where = await (widget.save ?? _saveToDocuments)(_pdf(), _pdfName);
    } catch (_) {
      where = null;
    }
    _snack(where == null ? 'Could not save the PDF' : 'Saved to $where');
  }

  void _addCondition() {
    if (_s.addCondition(_condition.text) > 0) {
      _condition.clear();
    }
  }

  void _addAllergy() {
    if (_s.addAllergy(_allergy.text) > 0) {
      _allergy.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Health summary')),
      bottomNavigationBar: ResultBar(
        onShare: () => unawaited(_share()),
        onSave: () => unawaited(_save()),
        onUndo: () => _snack(_s.undo() ? 'Undone' : 'Nothing to undo'),
        saveLabel: 'Save PDF',
      ),
      body: ListenableBuilder(listenable: _s, builder: (BuildContext context, Widget? _) => _body(context)),
    );
  }

  Widget _entry({
    required Key fieldKey,
    required Key buttonKey,
    required TextEditingController controller,
    required String label,
    required String hint,
    required VoidCallback onAdd,
  }) {
    return Row(
      children: <Widget>[
        Expanded(
          child: TextField(
            key: fieldKey,
            controller: controller,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(labelText: label, hintText: hint),
            onSubmitted: (_) => onAdd(),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton(
          key: buttonKey,
          style: FilledButton.styleFrom(minimumSize: const Size(64, 48)),
          onPressed: onAdd,
          child: const Text('Add'),
        ),
      ],
    );
  }

  Widget _chips(String prefix, List<String> items, bool Function(String) remove) {
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: <Widget>[
        for (final String c in items)
          InputChip(
            key: Key('$prefix-$c'),
            label: Text(c),
            materialTapTargetSize: MaterialTapTargetSize.padded,
            deleteButtonTooltipMessage: 'Remove $c',
            onDeleted: () => remove(c),
          ),
      ],
    );
  }

  Widget _body(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final HealthProfile p = _s.profile;
    final Map<String, String> members = _members;
    final List<SummaryBlock> blocks = _blocks();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: <Widget>[
        Text('One page for a new doctor, made from your records on this phone. Nothing is uploaded.', style: text.bodyMedium),
        const SizedBox(height: 12),
        TextField(
          key: const Key('summary-name'),
          controller: _name,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(labelText: 'Name on the summary'),
          onSubmitted: _s.setName,
          onTapOutside: (_) => _s.setName(_name.text),
        ),
        const SizedBox(height: 16),
        Text('Sections', style: text.titleMedium),
        const SizedBox(height: 4),
        for (final SummarySection sec in SummarySection.values)
          CheckboxListTile(
            key: Key('summary-section-${sec.name}'),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(sec.label),
            value: p.sections.contains(sec),
            onChanged: (bool? v) => _s.setSection(sec, v ?? false),
          ),
        if (members.length > 1) ...<Widget>[
          const SizedBox(height: 8),
          DropdownButtonFormField<String?>(
            key: const Key('summary-member'),
            initialValue: _member,
            decoration: const InputDecoration(labelText: 'Whose medicines'),
            items: <DropdownMenuItem<String?>>[
              const DropdownMenuItem<String?>(value: null, child: Text('Everyone I can see')),
              for (final MapEntry<String, String> e in members.entries) DropdownMenuItem<String?>(value: e.key, child: Text(e.value)),
            ],
            onChanged: (String? v) => setState(() => _member = v),
          ),
        ],
        const Divider(height: 32),
        Text('Conditions', style: text.titleMedium),
        const SizedBox(height: 8),
        _entry(
          fieldKey: const Key('summary-condition'),
          buttonKey: const Key('summary-condition-add'),
          controller: _condition,
          label: 'Add a condition',
          hint: 'Type 2 diabetes, hypertension',
          onAdd: _addCondition,
        ),
        _chips('condition', p.conditions, _s.removeCondition),
        const SizedBox(height: 16),
        Text('Allergies', style: text.titleMedium),
        const SizedBox(height: 8),
        _entry(
          fieldKey: const Key('summary-allergy'),
          buttonKey: const Key('summary-allergy-add'),
          controller: _allergy,
          label: 'Add an allergy',
          hint: 'Penicillin',
          onAdd: _addAllergy,
        ),
        _chips('allergy', p.allergies, _s.removeAllergy),
        const Divider(height: 32),
        Text('Preview', style: text.titleMedium),
        const SizedBox(height: 8),
        if (blocks.isEmpty) const Text('No sections chosen.', key: Key('summary-empty')),
        for (final SummaryBlock b in blocks)
          Semantics(
            container: true,
            label: '${b.title}: ${b.lines.join('. ')}',
            child: ExcludeSemantics(
              child: Card(
                key: Key('summary-block-${b.section.name}'),
                margin: const EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(b.title, style: text.titleSmall),
                      const SizedBox(height: 4),
                      for (final String l in b.lines) Text(l, style: text.bodySmall),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
