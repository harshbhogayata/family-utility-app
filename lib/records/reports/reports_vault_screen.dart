import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../app/widgets/result_bar.dart';
import '../../engines/records/reports_vault.dart';
import '../../engines/share/share_engine.dart';

/// A picked report file.
typedef PickedReport = ({Uint8List bytes, String name});

/// Feature 091 — lab reports kept encrypted, one value charted over time.
class ReportsVaultScreen extends StatefulWidget {
  const ReportsVaultScreen({super.key, this.vault, this.pick, this.share, this.save, this.shareFile});

  final ReportsVault? vault;

  /// Picks a report photo or PDF; defaults to the system picker.
  final Future<PickedReport?> Function()? pick;

  /// Shares text; defaults to the share sheet.
  final Future<void> Function(String text)? share;
  final Future<String?> Function(String text, String name)? save;

  /// Shares a decrypted report; defaults to a temp file and the share sheet.
  final Future<void> Function(Uint8List bytes, String name)? shareFile;

  @override
  State<ReportsVaultScreen> createState() => _ReportsVaultScreenState();
}

class _ReportsVaultScreenState extends State<ReportsVaultScreen> {
  ReportsVault get _v => widget.vault ?? ReportsVault.instance;
  String? _tag;

  void _snack(String s) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
    }
  }

  static Future<PickedReport?> _pickSystem() async {
    final FilePickerResult? r = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: <String>['jpg', 'jpeg', 'png', 'webp', 'pdf'],
      withData: true,
    );
    final PlatformFile? f = r == null || r.files.isEmpty ? null : r.files.first;
    if (f == null) {
      return null;
    }
    final Uint8List? data = f.bytes ?? (f.path == null ? null : await File(f.path!).readAsBytes());
    return data == null ? null : (bytes: data, name: f.name);
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

  String get _resultText => _tag == null ? _v.toText() : _v.seriesText(_tag!);

  Future<void> _save() async {
    String? where;
    try {
      where = await (widget.save ?? _saveToDocuments)(_resultText, _tag == null ? 'Lab reports.txt' : '$_tag over time.txt');
    } catch (_) {
      where = null;
    }
    _snack(where == null ? 'Could not save' : 'Saved to $where');
  }

  Future<void> _shareReport(LabReport r) async {
    try {
      final Uint8List bytes = await _v.open(r.id);
      final Future<void> Function(Uint8List, String)? s = widget.shareFile;
      if (s != null) {
        await s(bytes, r.fileName);
        return;
      }
      final Directory dir = await getTemporaryDirectory();
      final File f = File('${dir.path}/${r.fileName}');
      await f.writeAsBytes(bytes, flush: true);
      await ShareEngine.instance.shareFiles(<String>[f.path]);
    } catch (_) {
      _snack('Could not open the report');
    }
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

  static String _two(int n) => n.toString().padLeft(2, '0');

  Future<void> _add() async {
    PickedReport? picked;
    try {
      picked = await (widget.pick ?? _pickSystem)();
    } catch (_) {
      picked = null;
    }
    if (picked == null || !mounted) {
      return;
    }
    final DateTime n = DateTime.now();
    final TextEditingController title = TextEditingController();
    final TextEditingController date = TextEditingController(text: '${_two(n.day)}/${_two(n.month)}/${n.year}');
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Add report'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(key: const Key('rv-title'), controller: title, decoration: const InputDecoration(labelText: 'Name', hintText: 'Thyroid panel')),
            TextField(
              key: const Key('rv-date'),
              controller: date,
              keyboardType: TextInputType.datetime,
              decoration: const InputDecoration(labelText: 'Report date', hintText: '24/08/2026'),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(key: const Key('rv-save'), onPressed: () => Navigator.pop(context, true), child: const Text('Add')),
        ],
      ),
    );
    if (ok != true) {
      return;
    }
    final DateTime? day = parseDay(date.text);
    if (day == null) {
      _snack('Type the date like 24/08/2026');
      return;
    }
    final LabReport r = await _v.add(bytes: picked.bytes, fileName: picked.name, title: title.text, date: day);
    _snack(r.values.isEmpty ? 'Report kept, encrypted' : 'Report kept, found ${r.values.keys.join(', ')}');
  }

  Future<void> _tagValue(LabReport r) async {
    final TextEditingController tag = TextEditingController(text: _tag ?? '');
    final TextEditingController value = TextEditingController();
    final TextEditingController unit = TextEditingController();
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Tag a value'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(key: const Key('rv-tag-name'), controller: tag, decoration: const InputDecoration(labelText: 'Value', hintText: 'HbA1c')),
            TextField(
              key: const Key('rv-tag-value'),
              controller: value,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Result', hintText: '6.8'),
            ),
            TextField(key: const Key('rv-tag-unit'), controller: unit, decoration: const InputDecoration(labelText: 'Unit (optional)', hintText: '%')),
          ],
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(key: const Key('rv-tag-save'), onPressed: () => Navigator.pop(context, true), child: const Text('Tag')),
        ],
      ),
    );
    if (ok != true) {
      return;
    }
    final double? v = double.tryParse(value.text.trim().replaceAll(',', '.'));
    final bool done = v != null && await _v.tagValue(r.id, tag.text, v, unit: unit.text);
    if (done) {
      setState(() => _tag = tag.text.trim());
    }
    _snack(done ? 'Tagged' : 'Type a name and a number');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Lab reports')),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('rv-add'),
        onPressed: () => unawaited(_add()),
        icon: const Icon(Icons.add),
        label: const Text('Add report'),
      ),
      bottomNavigationBar: ResultBar(
        onShare: () => unawaited(_shareText(_resultText)),
        onSave: () => unawaited(_save()),
        onUndo: () => unawaited(_v.undo().then((bool ok) => _snack(ok ? 'Undone' : 'Nothing to undo'))),
      ),
      body: ListenableBuilder(listenable: _v, builder: (BuildContext context, Widget? _) => _body(context)),
    );
  }

  Widget _body(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme cs = Theme.of(context).colorScheme;
    final List<LabReport> list = _v.reports;
    if (list.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text('No reports yet. Add a photo or PDF; it stays encrypted on this phone.', style: text.bodyMedium),
      );
    }
    final List<String> tags = _v.tags;
    final String? tag = tags.contains(_tag) ? _tag : (tags.isEmpty ? null : tags.first);
    final List<(DateTime, double)> points = tag == null ? const <(DateTime, double)>[] : _v.series(tag);
    final String unit = tag == null ? '' : _v.unitOf(tag);
    final String summary = points.isEmpty
        ? ''
        : '${points.length} result${points.length == 1 ? '' : 's'}, latest ${ReportsVault.number(points.last.$2)}${unit.isEmpty ? '' : ' $unit'} on ${ReportsVault.dayLabel(points.last.$1)}';
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: <Widget>[
        if (tag != null) ...<Widget>[
          Wrap(
            spacing: 8,
            children: <Widget>[
              for (final String t in tags)
                ChoiceChip(
                  key: Key('rv-chip-$t'),
                  label: Text(t),
                  selected: t == tag,
                  onSelected: (bool _) => setState(() => _tag = t),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(summary, key: const Key('rv-summary'), style: text.bodyMedium),
          const SizedBox(height: 8),
          Semantics(
            container: true,
            label: '$tag chart. $summary',
            child: ExcludeSemantics(
              child: SizedBox(
                key: const Key('rv-chart'),
                height: 180,
                child: CustomPaint(painter: _SeriesPainter(points, cs.primary, cs.outlineVariant)),
              ),
            ),
          ),
          const Divider(height: 24),
        ],
        for (final LabReport r in list) _card(context, r),
      ],
    );
  }

  Widget _card(BuildContext context, LabReport r) {
    final TextTheme text = Theme.of(context).textTheme;
    return Card(
      key: Key('rv-${r.id}'),
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(r.isPdf ? Icons.picture_as_pdf_outlined : Icons.image_outlined, size: 20),
                const SizedBox(width: 6),
                Expanded(child: Text(r.title, style: text.titleMedium)),
                const Icon(Icons.lock_outline, size: 16, semanticLabel: 'Encrypted'),
              ],
            ),
            Text(ReportsVault.dayLabel(r.date), style: text.bodySmall),
            for (final MapEntry<String, ReportValue> e in r.values.entries)
              Row(
                children: <Widget>[
                  Expanded(child: Text('${e.key}: ${ReportsVault.number(e.value.value)}${e.value.unit.isEmpty ? '' : ' ${e.value.unit}'}')),
                  IconButton(
                    tooltip: 'Remove ${e.key}',
                    onPressed: () => unawaited(_v.untag(r.id, e.key)),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            Wrap(
              spacing: 8,
              children: <Widget>[
                TextButton.icon(
                  key: Key('rv-tagvalue-${r.id}'),
                  style: TextButton.styleFrom(minimumSize: const Size(88, 48)),
                  onPressed: () => unawaited(_tagValue(r)),
                  icon: const Icon(Icons.sell_outlined),
                  label: const Text('Tag value'),
                ),
                TextButton.icon(
                  key: Key('rv-open-${r.id}'),
                  style: TextButton.styleFrom(minimumSize: const Size(88, 48)),
                  onPressed: () => unawaited(_shareReport(r)),
                  icon: const Icon(Icons.share_outlined),
                  label: const Text('Share report'),
                ),
                TextButton.icon(
                  key: Key('rv-delete-${r.id}'),
                  style: TextButton.styleFrom(minimumSize: const Size(88, 48)),
                  onPressed: () => unawaited(_v.remove(r.id)),
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

class _SeriesPainter extends CustomPainter {
  _SeriesPainter(this.points, this.line, this.grid);

  final List<(DateTime, double)> points;
  final Color line;
  final Color grid;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint g = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (int i = 0; i <= 4; i++) {
      final double y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), g);
    }
    if (points.isEmpty) {
      return;
    }
    double lo = points.first.$2, hi = points.first.$2;
    for (final (DateTime, double) p in points) {
      lo = p.$2 < lo ? p.$2 : lo;
      hi = p.$2 > hi ? p.$2 : hi;
    }
    final double pad = hi == lo ? (hi == 0 ? 1 : hi.abs() * 0.1) : (hi - lo) * 0.1;
    lo -= pad;
    hi += pad;
    final int t0 = points.first.$1.millisecondsSinceEpoch, t1 = points.last.$1.millisecondsSinceEpoch;
    double x(DateTime d) => t1 == t0 ? size.width / 2 : (d.millisecondsSinceEpoch - t0) / (t1 - t0) * size.width;
    double y(double v) => size.height - (v - lo) / (hi - lo) * size.height;
    final Paint p = Paint()
      ..color = line
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final Path path = Path();
    for (int i = 0; i < points.length; i++) {
      final Offset o = Offset(x(points[i].$1), y(points[i].$2));
      if (i == 0) {
        path.moveTo(o.dx, o.dy);
      } else {
        path.lineTo(o.dx, o.dy);
      }
      canvas.drawCircle(o, 3, Paint()..color = line);
    }
    canvas.drawPath(path, p);
  }

  @override
  bool shouldRepaint(_SeriesPainter old) => old.points != points || old.line != line;
}
