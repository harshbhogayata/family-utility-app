import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

/// Feature 089 — BP and sugar logs.
///
/// Blood pressure (systolic / diastolic / pulse) and blood sugar (mg/dL with
/// fasting, after-meal or random) readings, typed in one line so an entry
/// takes a few seconds; a trend series for the chart; and a PDF of any date
/// range to hand to the doctor. Readings live in the app's own folder and
/// the PDF is written on the phone. Nothing is uploaded.

enum ReadingKind {
  bp('Blood pressure'),
  sugar('Blood sugar');

  const ReadingKind(this.label);
  final String label;

  static ReadingKind byName(Object? n) =>
      ReadingKind.values.firstWhere((ReadingKind k) => k.name == n, orElse: () => ReadingKind.bp);
}

enum SugarContext {
  fasting('Fasting'),
  afterMeal('After meal'),
  random('Random');

  const SugarContext(this.label);
  final String label;

  static SugarContext byName(Object? n) =>
      SugarContext.values.firstWhere((SugarContext c) => c.name == n, orElse: () => SugarContext.random);
}

/// Where a reading sits against common adult reference ranges. A guide for
/// the log, not a diagnosis.
enum ReadingBand {
  low('Low'),
  normal('Normal'),
  elevated('Elevated'),
  high('High');

  const ReadingBand(this.label);
  final String label;
}

class HealthReading {
  const HealthReading({
    required this.id,
    required this.kind,
    required this.at,
    this.systolic = 0,
    this.diastolic = 0,
    this.pulse,
    this.sugar = 0,
    this.context = SugarContext.random,
    this.note = '',
  });

  final String id;
  final ReadingKind kind;
  final DateTime at;

  /// mmHg; only for [ReadingKind.bp].
  final int systolic;
  final int diastolic;

  /// Beats per minute, optional.
  final int? pulse;

  /// mg/dL; only for [ReadingKind.sugar].
  final int sugar;
  final SugarContext context;
  final String note;

  /// The number the chart draws: systolic for BP, mg/dL for sugar.
  int get value => kind == ReadingKind.bp ? systolic : sugar;

  /// "128/84 · 72 bpm" or "110 mg/dL fasting".
  String get display => kind == ReadingKind.bp
      ? '$systolic/$diastolic${pulse == null ? '' : ' · $pulse bpm'}'
      : '$sugar mg/dL ${context.label.toLowerCase()}';

  ReadingBand get band {
    if (kind == ReadingKind.bp) {
      if (systolic < 90 || diastolic < 60) {
        return ReadingBand.low;
      }
      if (systolic >= 130 || diastolic >= 80) {
        return ReadingBand.high;
      }
      if (systolic >= 120) {
        return ReadingBand.elevated;
      }
      return ReadingBand.normal;
    }
    if (sugar < 70) {
      return ReadingBand.low;
    }
    switch (context) {
      case SugarContext.fasting:
        return sugar >= 126 ? ReadingBand.high : (sugar >= 100 ? ReadingBand.elevated : ReadingBand.normal);
      case SugarContext.afterMeal:
      case SugarContext.random:
        return sugar >= 200 ? ReadingBand.high : (sugar >= 140 ? ReadingBand.elevated : ReadingBand.normal);
    }
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'kind': kind.name,
        'at': at.millisecondsSinceEpoch,
        if (kind == ReadingKind.bp) 'sys': systolic,
        if (kind == ReadingKind.bp) 'dia': diastolic,
        if (pulse != null) 'pulse': pulse,
        if (kind == ReadingKind.sugar) 'sugar': sugar,
        if (kind == ReadingKind.sugar) 'ctx': context.name,
        'note': note,
      };

  static HealthReading? fromJson(Map<String, Object?> j) {
    final Object? id = j['id'];
    final Object? at = j['at'];
    if (id is! String || at is! num) {
      return null;
    }
    int intOf(Object? o) => o is num ? o.toInt() : 0;
    final Object? p = j['pulse'];
    return HealthReading(
      id: id,
      kind: ReadingKind.byName(j['kind']),
      at: DateTime.fromMillisecondsSinceEpoch(at.toInt()),
      systolic: intOf(j['sys']),
      diastolic: intOf(j['dia']),
      pulse: p is num ? p.toInt() : null,
      sugar: intOf(j['sugar']),
      context: SugarContext.byName(j['ctx']),
      note: '${j['note'] ?? ''}',
    );
  }
}

/// What one typed line means, before it becomes a reading.
class ParsedReading {
  const ParsedReading.bp(this.systolic, this.diastolic, this.pulse, this.note)
      : kind = ReadingKind.bp,
        sugar = 0,
        context = SugarContext.random;

  const ParsedReading.sugar(this.sugar, this.context, this.note)
      : kind = ReadingKind.sugar,
        systolic = 0,
        diastolic = 0,
        pulse = null;

  final ReadingKind kind;
  final int systolic;
  final int diastolic;
  final int? pulse;
  final int sugar;
  final SugarContext context;
  final String note;
}

abstract interface class HealthReadingStore {
  Future<List<HealthReading>> load();
  Future<void> save(List<HealthReading> all);
}

class MemoryHealthReadingStore implements HealthReadingStore {
  List<HealthReading> saved = <HealthReading>[];
  @override
  Future<List<HealthReading>> load() async => List<HealthReading>.of(saved);
  @override
  Future<void> save(List<HealthReading> all) async => saved = List<HealthReading>.of(all);
}

/// health_readings.json in the app's private folder.
class FileHealthReadingStore implements HealthReadingStore {
  FileHealthReadingStore(this.folder);
  final Future<Directory> Function() folder;

  Future<File> _file() async => File('${(await folder()).path}/health_readings.json');

  @override
  Future<List<HealthReading>> load() async {
    final File f = await _file();
    if (!f.existsSync()) {
      return <HealthReading>[];
    }
    final Object? json = jsonDecode(await f.readAsString());
    if (json is! List) {
      return <HealthReading>[];
    }
    return json
        .whereType<Map<dynamic, dynamic>>()
        .map((Map<dynamic, dynamic> m) => HealthReading.fromJson(Map<String, Object?>.from(m)))
        .whereType<HealthReading>()
        .toList();
  }

  @override
  Future<void> save(List<HealthReading> all) async {
    final File f = await _file();
    await f.parent.create(recursive: true);
    final File tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode(all.map((HealthReading r) => r.toJson()).toList()));
    await tmp.rename(f.path);
  }
}

class HealthReadings extends ChangeNotifier {
  HealthReadings({HealthReadingStore? store, DateTime Function()? now})
      : _store = store ?? MemoryHealthReadingStore(),
        _now = now ?? DateTime.now;

  final HealthReadingStore _store;
  final DateTime Function() _now;
  final List<HealthReading> _all = <HealthReading>[];
  List<HealthReading>? _undo;
  bool _loaded = false;
  int _seq = 0;

  bool get loaded => _loaded;

  /// Every reading, newest first.
  List<HealthReading> get all => List<HealthReading>.unmodifiable(_all);

  Future<void> load() async {
    try {
      _all
        ..clear()
        ..addAll(await _store.load());
      _sort();
    } catch (e) {
      debugPrint('health readings load: $e');
    }
    _loaded = true;
    notifyListeners();
  }

  void _sort() => _all.sort((HealthReading a, HealthReading b) => b.at.compareTo(a.at));

  void _changed() {
    _sort();
    notifyListeners();
    unawaited(_store.save(List<HealthReading>.of(_all)).catchError((Object e) => debugPrint('health readings save: $e')));
  }

  static bool validBp(int sys, int dia) => sys >= 50 && sys <= 300 && dia >= 30 && dia <= 200 && sys > dia;
  static bool validSugar(int mg) => mg >= 20 && mg <= 700;

  HealthReading? _put(HealthReading r) {
    _undo = List<HealthReading>.of(_all);
    _all.add(r);
    _changed();
    return r;
  }

  String _id() => 'h${_now().microsecondsSinceEpoch}-${_seq++}';

  HealthReading? addBp({required int systolic, required int diastolic, int? pulse, String note = '', DateTime? at}) {
    if (!validBp(systolic, diastolic) || (pulse != null && (pulse < 20 || pulse > 250))) {
      return null;
    }
    return _put(HealthReading(
      id: _id(),
      kind: ReadingKind.bp,
      at: at ?? _now(),
      systolic: systolic,
      diastolic: diastolic,
      pulse: pulse,
      note: note.trim(),
    ));
  }

  HealthReading? addSugar({required int mgdl, SugarContext context = SugarContext.random, String note = '', DateTime? at}) {
    if (!validSugar(mgdl)) {
      return null;
    }
    return _put(HealthReading(id: _id(), kind: ReadingKind.sugar, at: at ?? _now(), sugar: mgdl, context: context, note: note.trim()));
  }

  bool remove(String id) {
    final int i = _all.indexWhere((HealthReading r) => r.id == id);
    if (i < 0) {
      return false;
    }
    _undo = List<HealthReading>.of(_all);
    _all.removeAt(i);
    _changed();
    return true;
  }

  bool undo() {
    final List<HealthReading>? u = _undo;
    if (u == null) {
      return false;
    }
    _undo = null;
    _all
      ..clear()
      ..addAll(u);
    _changed();
    return true;
  }

  /// Reads one line: "120/80", "128/84 72", "bp 130 85 pulse 70",
  /// "110 fasting", "sugar 160 after lunch", "ppbs 150". [prefer] decides a
  /// bare single number (sugar) versus two numbers (BP) when unclear.
  static ParsedReading? parse(String text, {ReadingKind? prefer}) {
    final String t = text.trim().toLowerCase();
    if (t.isEmpty) {
      return null;
    }
    final List<int> nums = RegExp(r'\d+').allMatches(t).map((RegExpMatch m) => int.parse(m.group(0)!)).toList();
    final String words = t.replaceAll(RegExp(r'[\d/]+'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    final String note = words
        .split(' ')
        .where((String w) => w.isNotEmpty && !_markerWords.contains(w))
        .join(' ');
    final bool sugarWord = RegExp(r'\b(sugar|glucose|fbs|ppbs|rbs|fasting|after|pp|post|random|mg|mgdl)\b').hasMatch(t);
    final bool bpWord = RegExp(r'\b(bp|pressure|pulse|bpm|hr)\b').hasMatch(t) || RegExp(r'\d\s*/\s*\d').hasMatch(t);
    final bool asBp = bpWord || (!sugarWord && nums.length >= 2 && prefer != ReadingKind.sugar);
    if (asBp && nums.length >= 2) {
      final int? pulse = nums.length >= 3 ? nums[2] : null;
      if (!validBp(nums[0], nums[1])) {
        return null;
      }
      return ParsedReading.bp(nums[0], nums[1], pulse, note);
    }
    if (nums.isEmpty || !validSugar(nums.first)) {
      return null;
    }
    if (!sugarWord && prefer == ReadingKind.bp) {
      return null;
    }
    SugarContext ctx = SugarContext.random;
    if (RegExp(r'\b(fasting|fbs|empty)\b').hasMatch(t)) {
      ctx = SugarContext.fasting;
    } else if (RegExp(r'\b(after|pp|ppbs|post|meal|lunch|dinner|breakfast)\b').hasMatch(t)) {
      ctx = SugarContext.afterMeal;
    }
    return ParsedReading.sugar(nums.first, ctx, note);
  }

  static const Set<String> _markerWords = <String>{
    'bp', 'pressure', 'pulse', 'bpm', 'hr', 'sugar', 'glucose', 'fbs', 'ppbs', 'rbs', 'fasting', //
    'after', 'pp', 'post', 'random', 'mg', 'mgdl', 'mg/dl', 'dl', 'meal', 'empty',
  };

  HealthReading? quickAdd(String text, {ReadingKind? prefer}) {
    final ParsedReading? p = parse(text, prefer: prefer);
    if (p == null) {
      return null;
    }
    return p.kind == ReadingKind.bp
        ? addBp(systolic: p.systolic, diastolic: p.diastolic, pulse: p.pulse, note: p.note)
        : addSugar(mgdl: p.sugar, context: p.context, note: p.note);
  }

  /// Readings of [kind] from the start of [from]'s day to the end of [to]'s
  /// day, oldest first (the order the chart and the PDF use).
  List<HealthReading> inRange(ReadingKind kind, DateTime from, DateTime to) {
    final DateTime a = DateTime(from.year, from.month, from.day);
    final DateTime b = DateTime(to.year, to.month, to.day).add(const Duration(days: 1));
    return _all
        .where((HealthReading r) => r.kind == kind && !r.at.isBefore(a) && r.at.isBefore(b))
        .toList()
        .reversed
        .toList();
  }

  /// Average, lowest and highest of [rs] ([value] for each; BP also gives
  /// the diastolic average).
  static ({int count, int avg, int min, int max, int avgDia})? summary(List<HealthReading> rs) {
    if (rs.isEmpty) {
      return null;
    }
    int sum = 0, dia = 0, lo = rs.first.value, hi = rs.first.value;
    for (final HealthReading r in rs) {
      sum += r.value;
      dia += r.diastolic;
      lo = r.value < lo ? r.value : lo;
      hi = r.value > hi ? r.value : hi;
    }
    return (count: rs.length, avg: (sum / rs.length).round(), min: lo, max: hi, avgDia: (dia / rs.length).round());
  }

  static HealthReadings instance = HealthReadings();
  static void install(HealthReadings l) => instance = l;
}

String _two(int v) => v.toString().padLeft(2, '0');

/// "2026-03-05".
String readingDate(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';

/// "2026-03-05 08:30".
String readingStamp(DateTime d) => '${readingDate(d)} ${_two(d.hour)}:${_two(d.minute)}';

/// A plain vector PDF of readings for the doctor: a header, a summary, a
/// trend chart and a table. Written in Dart with the PDF's built-in
/// Helvetica, so it opens anywhere and needs no font files or network.
class HealthPdf {
  const HealthPdf._();

  static const double _w = 595.28, _h = 841.89, _m = 48;

  static String fileName(ReadingKind kind, DateTime from, DateTime to) =>
      '${kind == ReadingKind.bp ? 'BP' : 'Sugar'} readings ${readingDate(from)} to ${readingDate(to)}.pdf';

  /// PDF strings in Helvetica (WinAnsi): keep ASCII, escape the specials.
  static String esc(String s) {
    final StringBuffer b = StringBuffer();
    for (final int c in s.runes) {
      if (c == 0x28 || c == 0x29 || c == 0x5c) {
        b.write('\\${String.fromCharCode(c)}');
      } else if (c >= 0x20 && c < 0x7f) {
        b.writeCharCode(c);
      } else if (c == 0x2013 || c == 0x2014) {
        b.write('-');
      } else if (c == 0xb7) {
        b.write('-');
      } else {
        b.write('?');
      }
    }
    return b.toString();
  }

  static String _n(double v) => v.toStringAsFixed(2);

  static String _text(double x, double y, double size, String s, {bool bold = false}) =>
      'BT /${bold ? 'F2' : 'F1'} ${_n(size)} Tf ${_n(x)} ${_n(y)} Td (${esc(s)}) Tj ET\n';

  /// Builds the PDF. [readings] oldest first; [person] is optional.
  static Uint8List build({
    required ReadingKind kind,
    required List<HealthReading> readings,
    required DateTime from,
    required DateTime to,
    String person = '',
    DateTime? made,
  }) {
    final List<String> pages = <String>[];
    final StringBuffer first = StringBuffer();
    double y = _h - _m;
    first.write(_text(_m, y - 14, 18, kind == ReadingKind.bp ? 'Blood pressure log' : 'Blood sugar log', bold: true));
    y -= 34;
    first.write(_text(_m, y, 11, '${person.trim().isEmpty ? '' : '${person.trim()} - '}${readingDate(from)} to ${readingDate(to)}'));
    y -= 16;
    final ({int count, int avg, int min, int max, int avgDia})? s = HealthReadings.summary(readings);
    final String unit = kind == ReadingKind.bp ? 'mmHg' : 'mg/dL';
    final String sumLine = s == null
        ? 'No readings in this range.'
        : kind == ReadingKind.bp
            ? '${s.count} readings - average ${s.avg}/${s.avgDia} $unit - systolic range ${s.min} to ${s.max}'
            : '${s.count} readings - average ${s.avg} $unit - range ${s.min} to ${s.max}';
    first.write(_text(_m, y, 11, sumLine));
    y -= 14;
    if (made != null) {
      first.write(_text(_m, y, 8, 'Made on the phone ${readingStamp(made)}. Bands are common adult reference ranges, not a diagnosis.'));
    }
    y -= 20;
    // Trend chart.
    const double chartH = 180;
    final double cx = _m + 28, cw = _w - _m * 2 - 28, cy = y - chartH;
    first.write(_chart(kind, readings, cx, cy, cw, chartH));
    y = cy - 28;

    // Table.
    final List<String> head = kind == ReadingKind.bp
        ? <String>['Date and time', 'Systolic', 'Diastolic', 'Pulse', 'Band', 'Note']
        : <String>['Date and time', 'mg/dL', 'When', 'Band', 'Note'];
    final List<double> cols = kind == ReadingKind.bp
        ? <double>[_m, _m + 110, _m + 170, _m + 230, _m + 280, _m + 340]
        : <double>[_m, _m + 110, _m + 160, _m + 240, _m + 300];
    StringBuffer page = first;
    void header() {
      for (int i = 0; i < head.length; i++) {
        page.write(_text(cols[i], y, 9, head[i], bold: true));
      }
      page.write('0.6 G 0.5 w ${_n(_m)} ${_n(y - 4)} m ${_n(_w - _m)} ${_n(y - 4)} l S 0 G\n');
      y -= 16;
    }

    header();
    for (final HealthReading r in readings) {
      if (y < _m + 20) {
        pages.add(page.toString());
        page = StringBuffer();
        y = _h - _m - 10;
        header();
      }
      final List<String> cells = kind == ReadingKind.bp
          ? <String>[readingStamp(r.at), '${r.systolic}', '${r.diastolic}', r.pulse == null ? '-' : '${r.pulse}', r.band.label, r.note]
          : <String>[readingStamp(r.at), '${r.sugar}', r.context.label, r.band.label, r.note];
      for (int i = 0; i < cells.length; i++) {
        String c = cells[i];
        if (i == cells.length - 1 && c.length > 30) {
          c = '${c.substring(0, 29)}...';
        }
        page.write(_text(cols[i], y, 9, c));
      }
      y -= 13;
    }
    pages.add(page.toString());
    return _assemble(pages);
  }

  static String _chart(ReadingKind kind, List<HealthReading> rs, double x, double y, double w, double h) {
    final StringBuffer b = StringBuffer();
    b.write('0.75 G 0.5 w ${_n(x)} ${_n(y)} ${_n(w)} ${_n(h)} re S\n');
    final List<double> vals = <double>[];
    for (final HealthReading r in rs) {
      vals.add(r.value.toDouble());
      if (kind == ReadingKind.bp) {
        vals.add(r.diastolic.toDouble());
      }
    }
    double lo = kind == ReadingKind.bp ? 60 : 70, hi = kind == ReadingKind.bp ? 160 : 200;
    for (final double v in vals) {
      lo = v < lo ? v : lo;
      hi = v > hi ? v : hi;
    }
    lo = (lo / 10).floorToDouble() * 10;
    hi = (hi / 10).ceilToDouble() * 10;
    double py(double v) => y + (v - lo) / (hi - lo) * h;
    // Grid and axis labels.
    for (int i = 0; i <= 4; i++) {
      final double v = lo + (hi - lo) * i / 4;
      b.write('0.9 G ${_n(x)} ${_n(py(v))} m ${_n(x + w)} ${_n(py(v))} l S\n');
      b.write('0 g\n');
      b.write(_text(x - 26, py(v) - 3, 7, v.round().toString()));
    }
    if (rs.isEmpty) {
      return '${b}0 G 0 g\n';
    }
    final int t0 = rs.first.at.millisecondsSinceEpoch, t1 = rs.last.at.millisecondsSinceEpoch;
    double px(HealthReading r) => t1 == t0 ? x + w / 2 : x + (r.at.millisecondsSinceEpoch - t0) / (t1 - t0) * w;
    void line(String colour, double Function(HealthReading) v) {
      b.write('$colour RG 1.2 w\n');
      for (int i = 0; i < rs.length; i++) {
        b.write('${_n(px(rs[i]))} ${_n(py(v(rs[i])))} ${i == 0 ? 'm' : 'l'}\n');
      }
      b.write('S\n');
      for (final HealthReading r in rs) {
        b.write('${_n(px(r) - 1.5)} ${_n(py(v(r)) - 1.5)} 3 3 re f\n');
      }
    }

    b.write('0.85 0.2 0.2 rg\n');
    line('0.85 0.2 0.2', (HealthReading r) => r.value.toDouble());
    if (kind == ReadingKind.bp) {
      b.write('0.2 0.4 0.85 rg\n');
      line('0.2 0.4 0.85', (HealthReading r) => r.diastolic.toDouble());
    }
    b.write('0 g 0 G\n');
    b.write(_text(x, y - 12, 7, readingDate(rs.first.at)));
    b.write(_text(x + w - 44, y - 12, 7, readingDate(rs.last.at)));
    if (kind == ReadingKind.bp) {
      b.write(_text(x + w / 2 - 50, y - 12, 7, 'red: systolic   blue: diastolic'));
    }
    return b.toString();
  }

  static Uint8List _assemble(List<String> pageStreams) {
    final List<String> objs = <String>[];
    // 1 catalog, 2 pages, 3 F1, 4 F2, then page/content pairs.
    final List<int> kids = <int>[];
    for (int i = 0; i < pageStreams.length; i++) {
      kids.add(5 + i * 2);
    }
    objs.add('<< /Type /Catalog /Pages 2 0 R >>');
    objs.add('<< /Type /Pages /Kids [${kids.map((int k) => '$k 0 R').join(' ')}] /Count ${kids.length} >>');
    objs.add('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>');
    objs.add('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>');
    for (int i = 0; i < pageStreams.length; i++) {
      final int content = 6 + i * 2;
      objs.add('<< /Type /Page /Parent 2 0 R /MediaBox [0 0 ${_n(_w)} ${_n(_h)}] '
          '/Resources << /Font << /F1 3 0 R /F2 4 0 R >> >> /Contents $content 0 R >>');
      final List<int> data = latin1.encode(pageStreams[i]);
      objs.add('<< /Length ${data.length} >>\nstream\n${pageStreams[i]}\nendstream');
    }
    final BytesBuilder out = BytesBuilder();
    final List<int> offsets = <int>[];
    out.add(latin1.encode('%PDF-1.4\n'));
    for (int i = 0; i < objs.length; i++) {
      offsets.add(out.length);
      out.add(latin1.encode('${i + 1} 0 obj\n${objs[i]}\nendobj\n'));
    }
    final int xref = out.length;
    final StringBuffer x = StringBuffer('xref\n0 ${objs.length + 1}\n0000000000 65535 f \n');
    for (final int o in offsets) {
      x.write('${o.toString().padLeft(10, '0')} 00000 n \n');
    }
    x.write('trailer\n<< /Size ${objs.length + 1} /Root 1 0 R >>\nstartxref\n$xref\n%%EOF\n');
    out.add(latin1.encode(x.toString()));
    return out.toBytes();
  }
}
