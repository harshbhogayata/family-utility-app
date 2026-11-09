import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../app/widgets/result_bar.dart';
import '../../engines/records/health_readings.dart';
import '../../engines/share/share_engine.dart';

/// Feature 089 — BP and sugar logs: one-line entry, trend chart, and a PDF
/// of any date range for the doctor.
class HealthLogScreen extends StatefulWidget {
  const HealthLogScreen({super.key, this.log, this.share, this.save, this.now, this.pickRange});

  final HealthLog? log;

  /// Shares the PDF; defaults to the share sheet.
  final Future<void> Function(Uint8List pdf, String name)? share;

  /// Saves the PDF and returns where; defaults to the app's documents.
  final Future<String?> Function(Uint8List pdf, String name)? save;
  final DateTime Function()? now;

  /// Picks a date range; defaults to the Material range picker.
  final Future<DateTimeRange?> Function(BuildContext context, DateTimeRange current)? pickRange;

  @override
  State<HealthLogScreen> createState() => _HealthLogScreenState();
}

class _HealthLogScreenState extends State<HealthLogScreen> {
  HealthLog get _log => widget.log ?? HealthLog.instance;
  final TextEditingController _entry = TextEditingController();
  ReadingKind _kind = ReadingKind.bp;
  late DateTimeRange _range;

  DateTime _now() => (widget.now ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    final DateTime n = _now();
    final DateTime today = DateTime(n.year, n.month, n.day);
    _range = DateTimeRange(start: today.subtract(const Duration(days: 29)), end: today);
  }

  @override
  void dispose() {
    _entry.dispose();
    super.dispose();
  }

  void _snack(String s) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
    }
  }

  List<HealthReading> get _shown => _log.inRange(_kind, _range.start, _range.end);

  String get _pdfName => HealthPdf.fileName(_kind, _range.start, _range.end);

  Uint8List _pdf() => HealthPdf.build(kind: _kind, readings: _shown, from: _range.start, to: _range.end, made: _now());

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

  void _add() {
    final HealthReading? r = _log.quickAdd(_entry.text, prefer: _kind);
    if (r == null) {
      _snack(_kind == ReadingKind.bp ? 'Type it like 120/80 or 120/80 72' : 'Type it like 110 fasting or 150 after meal');
      return;
    }
    _entry.clear();
    final DateTime d = DateTime(r.at.year, r.at.month, r.at.day);
    setState(() {
      _kind = r.kind;
      if (d.isAfter(_range.end)) {
        _range = DateTimeRange(start: _range.start, end: d);
      }
    });
    _snack('Saved ${r.display} · ${r.band.label}');
  }

  Future<void> _pickRange() async {
    final DateTimeRange? r = await (widget.pickRange ??
        (BuildContext c, DateTimeRange cur) => showDateRangePicker(
              context: c,
              firstDate: DateTime(2000),
              lastDate: _now().add(const Duration(days: 1)),
              initialDateRange: cur,
            ))(context, _range);
    if (r != null) {
      setState(() => _range = r);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('BP and sugar')),
      bottomNavigationBar: ResultBar(
        onShare: () => unawaited(_share()),
        onSave: () => unawaited(_save()),
        onUndo: () => _snack(_log.undo() ? 'Undone' : 'Nothing to undo'),
        saveLabel: 'Save PDF',
      ),
      body: ListenableBuilder(listenable: _log, builder: (BuildContext context, Widget? _) => _body(context)),
    );
  }

  Widget _body(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme cs = Theme.of(context).colorScheme;
    final List<HealthReading> rs = _shown;
    final ({int count, int avg, int min, int max, int avgDia})? s = HealthLog.summary(rs);
    final String summary = s == null
        ? 'No readings in this range.'
        : _kind == ReadingKind.bp
            ? '${s.count} readings · average ${s.avg}/${s.avgDia}'
            : '${s.count} readings · average ${s.avg} mg/dL';
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: <Widget>[
        SegmentedButton<ReadingKind>(
          key: const Key('health-kind'),
          segments: const <ButtonSegment<ReadingKind>>[
            ButtonSegment<ReadingKind>(value: ReadingKind.bp, label: Text('BP'), icon: Icon(Icons.favorite_outline)),
            ButtonSegment<ReadingKind>(value: ReadingKind.sugar, label: Text('Sugar'), icon: Icon(Icons.water_drop_outlined)),
          ],
          selected: <ReadingKind>{_kind},
          onSelectionChanged: (Set<ReadingKind> v) => setState(() => _kind = v.first),
        ),
        const SizedBox(height: 12),
        Row(
          children: <Widget>[
            Expanded(
              child: TextField(
                key: const Key('health-entry'),
                controller: _entry,
                keyboardType: TextInputType.text,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: _kind == ReadingKind.bp ? 'New BP reading' : 'New sugar reading',
                  hintText: _kind == ReadingKind.bp ? '120/80 72' : '110 fasting',
                ),
                onSubmitted: (_) => _add(),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              key: const Key('health-add'),
              style: FilledButton.styleFrom(minimumSize: const Size(64, 48)),
              onPressed: _add,
              child: const Text('Add'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          key: const Key('health-range'),
          style: OutlinedButton.styleFrom(minimumSize: const Size(88, 48)),
          onPressed: () => unawaited(_pickRange()),
          icon: const Icon(Icons.date_range_outlined),
          label: Text('${readingDate(_range.start)} to ${readingDate(_range.end)}'),
        ),
        const SizedBox(height: 8),
        Text(summary, key: const Key('health-summary'), style: text.bodyMedium),
        const SizedBox(height: 8),
        Semantics(
          container: true,
          label: '${_kind.label} trend chart. $summary',
          child: ExcludeSemantics(
            child: SizedBox(
              key: const Key('health-chart'),
              height: 180,
              child: CustomPaint(
                painter: _TrendPainter(rs, _kind, cs.primary, cs.tertiary, cs.outlineVariant),
              ),
            ),
          ),
        ),
        const Divider(height: 24),
        for (final HealthReading r in rs.reversed)
          ListTile(
            key: Key('reading-${r.id}'),
            contentPadding: EdgeInsets.zero,
            minTileHeight: 56,
            title: Text(r.display),
            subtitle: Text('${readingStamp(r.at)} · ${r.band.label}${r.note.isEmpty ? '' : ' · ${r.note}'}'),
            trailing: IconButton(
              tooltip: 'Delete reading',
              onPressed: () => _log.remove(r.id),
              icon: const Icon(Icons.delete_outline),
            ),
          ),
      ],
    );
  }
}

class _TrendPainter extends CustomPainter {
  _TrendPainter(this.rs, this.kind, this.main, this.second, this.grid);

  final List<HealthReading> rs;
  final ReadingKind kind;
  final Color main;
  final Color second;
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
    if (rs.isEmpty) {
      return;
    }
    double lo = kind == ReadingKind.bp ? 60 : 70, hi = kind == ReadingKind.bp ? 160 : 200;
    for (final HealthReading r in rs) {
      for (final int v in <int>[r.value, if (kind == ReadingKind.bp) r.diastolic]) {
        lo = v < lo ? v.toDouble() : lo;
        hi = v > hi ? v.toDouble() : hi;
      }
    }
    final int t0 = rs.first.at.millisecondsSinceEpoch, t1 = rs.last.at.millisecondsSinceEpoch;
    double x(HealthReading r) => t1 == t0 ? size.width / 2 : (r.at.millisecondsSinceEpoch - t0) / (t1 - t0) * size.width;
    double y(num v) => size.height - (v - lo) / (hi - lo) * size.height;
    void series(Color c, int Function(HealthReading) v) {
      final Paint p = Paint()
        ..color = c
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;
      final Path path = Path();
      for (int i = 0; i < rs.length; i++) {
        final Offset o = Offset(x(rs[i]), y(v(rs[i])));
        if (i == 0) {
          path.moveTo(o.dx, o.dy);
        } else {
          path.lineTo(o.dx, o.dy);
        }
        canvas.drawCircle(o, 3, Paint()..color = c);
      }
      canvas.drawPath(path, p);
    }

    series(main, (HealthReading r) => r.value);
    if (kind == ReadingKind.bp) {
      series(second, (HealthReading r) => r.diastolic);
    }
  }

  @override
  bool shouldRepaint(_TrendPainter old) => true;
}
