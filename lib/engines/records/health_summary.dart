import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'health_readings.dart';
import 'medicine_reminders.dart';
import 'reports_vault.dart';

/// Feature 094 — Health summary PDF.
///
/// One page for a new doctor: conditions, allergies, current medicines,
/// recent BP and sugar readings and the latest tagged lab values. It is
/// generated from the records already on the phone (088 medicines, 089
/// readings, 091 reports); the person picks which sections go in. The PDF
/// is written in Dart with the PDF's built-in Helvetica, so it needs no
/// fonts or network, and nothing is uploaded.

enum SummarySection {
  conditions('Conditions'),
  allergies('Allergies'),
  medicines('Current medicines'),
  readings('Recent readings'),
  reports('Latest lab results');

  const SummarySection(this.label);
  final String label;

  static SummarySection? byName(String s) {
    for (final SummarySection v in values) {
      if (v.name == s) {
        return v;
      }
    }
    return null;
  }
}

/// What the person types once and keeps: name, conditions, allergies, and
/// which sections the summary includes.
class HealthProfile {
  const HealthProfile({
    this.name = '',
    this.born,
    this.conditions = const <String>[],
    this.allergies = const <String>[],
    this.sections = const <SummarySection>{
      SummarySection.conditions,
      SummarySection.allergies,
      SummarySection.medicines,
      SummarySection.readings,
      SummarySection.reports,
    },
  });

  final String name;
  final DateTime? born;
  final List<String> conditions;
  final List<String> allergies;
  final Set<SummarySection> sections;

  HealthProfile copyWith({
    String? name,
    DateTime? born,
    bool clearBorn = false,
    List<String>? conditions,
    List<String>? allergies,
    Set<SummarySection>? sections,
  }) =>
      HealthProfile(
        name: name ?? this.name,
        born: clearBorn ? null : (born ?? this.born),
        conditions: conditions ?? this.conditions,
        allergies: allergies ?? this.allergies,
        sections: sections ?? this.sections,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'name': name,
        if (born != null) 'born': born!.toIso8601String(),
        'conditions': conditions,
        'allergies': allergies,
        'sections': sections.map((SummarySection s) => s.name).toList(),
      };

  static HealthProfile fromJson(Object? j) {
    if (j is! Map) {
      return const HealthProfile();
    }
    List<String> strings(Object? o) => o is List ? o.map((Object? e) => '$e').where((String s) => s.trim().isNotEmpty).toList() : <String>[];
    final Object? s = j['sections'];
    final Set<SummarySection> sections = s is List
        ? s.map((Object? e) => SummarySection.byName('$e')).whereType<SummarySection>().toSet()
        : const HealthProfile().sections;
    return HealthProfile(
      name: '${j['name'] ?? ''}',
      born: DateTime.tryParse('${j['born'] ?? ''}'),
      conditions: strings(j['conditions']),
      allergies: strings(j['allergies']),
      sections: sections,
    );
  }
}

abstract interface class HealthProfileStore {
  Future<HealthProfile> load();
  Future<void> save(HealthProfile p);
}

class MemoryHealthProfileStore implements HealthProfileStore {
  HealthProfile saved = const HealthProfile();

  @override
  Future<HealthProfile> load() async => saved;

  @override
  Future<void> save(HealthProfile p) async => saved = p;
}

/// Kept as JSON in the app's own folder.
class FileHealthProfileStore implements HealthProfileStore {
  FileHealthProfileStore(this.folder);
  final Future<Directory> Function() folder;

  Future<File> _file() async => File('${(await folder()).path}/health_profile.json');

  @override
  Future<HealthProfile> load() async {
    final File f = await _file();
    if (!f.existsSync()) {
      return const HealthProfile();
    }
    try {
      return HealthProfile.fromJson(jsonDecode(await f.readAsString()));
    } on FormatException {
      return const HealthProfile();
    }
  }

  @override
  Future<void> save(HealthProfile p) async {
    final File f = await _file();
    await f.parent.create(recursive: true);
    final File tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode(p.toJson()));
    await tmp.rename(f.path);
  }
}

/// One section of the summary as plain lines.
class SummaryBlock {
  const SummaryBlock(this.section, this.lines);
  final SummarySection section;
  final List<String> lines;

  String get title => section.label;
}

class HealthSummary extends ChangeNotifier {
  HealthSummary({HealthProfileStore? store}) : _store = store ?? MemoryHealthProfileStore();

  final HealthProfileStore _store;
  HealthProfile _profile = const HealthProfile();
  final List<HealthProfile> _undo = <HealthProfile>[];

  HealthProfile get profile => _profile;
  bool get canUndo => _undo.isNotEmpty;

  Future<void> load() async {
    try {
      _profile = await _store.load();
    } catch (e) {
      debugPrint('health summary load: $e');
    }
    notifyListeners();
  }

  void _set(HealthProfile next) {
    _undo.add(_profile);
    if (_undo.length > 50) {
      _undo.removeAt(0);
    }
    _profile = next;
    notifyListeners();
    unawaited(_store.save(next).catchError((Object _) {}));
  }

  void setName(String name) {
    if (name.trim() == _profile.name) {
      return;
    }
    _set(_profile.copyWith(name: name.trim()));
  }

  void setBorn(DateTime? born) => _set(born == null ? _profile.copyWith(clearBorn: true) : _profile.copyWith(born: born));

  /// Adds one or more items separated by commas; returns how many were new.
  int addCondition(String text) => _addTo(text, conditions: true);

  int addAllergy(String text) => _addTo(text, conditions: false);

  int _addTo(String text, {required bool conditions}) {
    final List<String> cur = conditions ? _profile.conditions : _profile.allergies;
    final Set<String> seen = cur.map((String s) => s.toLowerCase()).toSet();
    final List<String> next = List<String>.of(cur);
    for (final String part in text.split(RegExp(r'[,;\n]'))) {
      final String p = part.trim();
      if (p.isNotEmpty && seen.add(p.toLowerCase())) {
        next.add(p);
      }
    }
    final int added = next.length - cur.length;
    if (added > 0) {
      _set(conditions ? _profile.copyWith(conditions: next) : _profile.copyWith(allergies: next));
    }
    return added;
  }

  bool removeCondition(String item) => _removeFrom(item, conditions: true);

  bool removeAllergy(String item) => _removeFrom(item, conditions: false);

  bool _removeFrom(String item, {required bool conditions}) {
    final List<String> cur = conditions ? _profile.conditions : _profile.allergies;
    if (!cur.contains(item)) {
      return false;
    }
    final List<String> next = cur.where((String s) => s != item).toList();
    _set(conditions ? _profile.copyWith(conditions: next) : _profile.copyWith(allergies: next));
    return true;
  }

  void setSection(SummarySection s, bool on) {
    if (_profile.sections.contains(s) == on) {
      return;
    }
    final Set<SummarySection> next = Set<SummarySection>.of(_profile.sections);
    if (on) {
      next.add(s);
    } else {
      next.remove(s);
    }
    _set(_profile.copyWith(sections: next));
  }

  bool undo() {
    if (_undo.isEmpty) {
      return false;
    }
    _profile = _undo.removeLast();
    notifyListeners();
    unawaited(_store.save(_profile).catchError((Object _) {}));
    return true;
  }

  // ---- composing ----

  static String _two(int n) => n.toString().padLeft(2, '0');

  static String clock(int minutes) => '${_two(minutes ~/ 60)}:${_two(minutes % 60)}';

  static String fileName(HealthProfile p, DateTime now) {
    final String who = p.name.trim().replaceAll(RegExp(r'[\\/:*?"<>|]'), '').trim();
    return 'Health summary${who.isEmpty ? '' : ' - $who'} ${readingDate(now)}.pdf';
  }

  static int? ageOn(DateTime? born, DateTime now) {
    if (born == null) {
      return null;
    }
    int a = now.year - born.year;
    if (now.month < born.month || (now.month == born.month && now.day < born.day)) {
      a--;
    }
    return a < 0 ? null : a;
  }

  /// The chosen sections, in a fixed order, from the records passed in.
  /// [readings] and [reports] may be in any order. Readings older than
  /// [readingDays] are left out.
  static List<SummaryBlock> compose({
    required HealthProfile profile,
    required List<Medicine> medicines,
    required List<HealthReading> readings,
    required List<LabReport> reports,
    required DateTime now,
    int readingDays = 90,
    int lastReadings = 5,
  }) {
    final List<SummaryBlock> out = <SummaryBlock>[];
    for (final SummarySection s in SummarySection.values) {
      if (!profile.sections.contains(s)) {
        continue;
      }
      switch (s) {
        case SummarySection.conditions:
          out.add(SummaryBlock(s, profile.conditions.isEmpty ? <String>['None recorded'] : List<String>.of(profile.conditions)));
        case SummarySection.allergies:
          out.add(SummaryBlock(s, profile.allergies.isEmpty ? <String>['No known allergies recorded'] : List<String>.of(profile.allergies)));
        case SummarySection.medicines:
          final List<Medicine> ms = List<Medicine>.of(medicines)..sort((Medicine a, Medicine b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
          out.add(SummaryBlock(s, ms.isEmpty ? <String>['None recorded'] : ms.map(medicineLine).toList()));
        case SummarySection.readings:
          out.add(SummaryBlock(s, readingLines(readings, now, days: readingDays, last: lastReadings)));
        case SummarySection.reports:
          out.add(SummaryBlock(s, reportLines(reports)));
      }
    }
    return out;
  }

  static String medicineLine(Medicine m) {
    final String dose = '${m.tabletsPerDose} ${m.tabletsPerDose == 1 ? 'tablet' : 'tablets'}';
    final String times = m.times.isEmpty ? 'as needed' : 'at ${m.times.map(clock).join(', ')}';
    final String note = m.note.trim().isEmpty ? '' : ' - ${m.note.trim()}';
    return '${m.name} - $dose $times$note';
  }

  static List<String> readingLines(List<HealthReading> all, DateTime now, {int days = 90, int last = 5}) {
    final DateTime from = DateTime(now.year, now.month, now.day).subtract(Duration(days: days - 1));
    final List<String> out = <String>[];
    for (final ReadingKind k in ReadingKind.values) {
      final List<HealthReading> rs = all.where((HealthReading r) => r.kind == k && !r.at.isBefore(from) && !r.at.isAfter(now)).toList()
        ..sort((HealthReading a, HealthReading b) => a.at.compareTo(b.at));
      if (rs.isEmpty) {
        continue;
      }
      final ({int count, int avg, int min, int max, int avgDia})? s = HealthReadings.summary(rs);
      if (s == null) {
        continue;
      }
      if (k == ReadingKind.bp) {
        out.add('Blood pressure: ${s.count} in the last $days days, average ${s.avg}/${s.avgDia} mmHg, systolic ${s.min} to ${s.max}');
      } else {
        out.add('Blood sugar: ${s.count} in the last $days days, average ${s.avg} mg/dL, range ${s.min} to ${s.max}');
      }
      final List<HealthReading> tail = rs.length > last ? rs.sublist(rs.length - last) : rs;
      for (final HealthReading r in tail.reversed) {
        out.add('  ${readingStamp(r.at)}  ${r.display}  (${r.band.label})');
      }
    }
    if (out.isEmpty) {
      out.add('No readings in the last $days days');
    }
    return out;
  }

  /// The newest value of each tag across the reports.
  static List<String> reportLines(List<LabReport> reports) {
    final List<LabReport> rs = List<LabReport>.of(reports)..sort((LabReport a, LabReport b) => b.date.compareTo(a.date));
    final Map<String, String> latest = <String, String>{};
    for (final LabReport r in rs) {
      r.values.forEach((String tag, ReportValue v) {
        if (latest.containsKey(tag)) {
          return;
        }
        final String num = v.value == v.value.roundToDouble() ? v.value.toStringAsFixed(0) : '${v.value}';
        final String unit = v.unit.trim().isEmpty ? '' : ' ${v.unit.trim()}';
        latest[tag] = '$tag: $num$unit (${readingDate(r.date)}${r.title.trim().isEmpty ? '' : ', ${r.title.trim()}'})';
      });
    }
    if (latest.isEmpty) {
      return <String>['No tagged lab values'];
    }
    final List<String> tags = latest.keys.toList()..sort((String a, String b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return tags.map((String t) => latest[t]!).toList();
  }

  // ---- PDF ----

  static const double _w = 595.28, _h = 841.89, _m = 48;

  static String _n(double v) => v.toStringAsFixed(2);

  static String _text(double x, double y, double size, String s, {bool bold = false}) =>
      'BT /${bold ? 'F2' : 'F1'} ${_n(size)} Tf ${_n(x)} ${_n(y)} Td (${HealthPdf.esc(s)}) Tj ET\n';

  /// Splits a line to fit [maxChars] (Helvetica at 10 pt is about 5 pt a
  /// character on average), breaking at spaces where it can.
  static List<String> wrap(String line, int maxChars) {
    if (line.length <= maxChars) {
      return <String>[line];
    }
    final List<String> out = <String>[];
    String rest = line;
    while (rest.length > maxChars) {
      int cut = rest.lastIndexOf(' ', maxChars);
      if (cut <= maxChars ~/ 3) {
        cut = maxChars;
      }
      out.add(rest.substring(0, cut).trimRight());
      rest = '    ${rest.substring(cut).trimLeft()}';
    }
    if (rest.trim().isNotEmpty) {
      out.add(rest);
    }
    return out;
  }

  static Uint8List pdf({required HealthProfile profile, required List<SummaryBlock> blocks, required DateTime now}) {
    final List<String> pages = <String>[];
    StringBuffer page = StringBuffer();
    double y = _h - _m - 14;
    page.write(_text(_m, y, 18, 'Health summary', bold: true));
    y -= 22;
    final List<String> who = <String>[];
    if (profile.name.trim().isNotEmpty) {
      who.add(profile.name.trim());
    }
    final int? age = ageOn(profile.born, now);
    if (profile.born != null) {
      who.add('born ${readingDate(profile.born!)}${age == null ? '' : ' (age $age)'}');
    }
    if (who.isNotEmpty) {
      page.write(_text(_m, y, 11, who.join(', ')));
      y -= 15;
    }
    page.write(_text(_m, y, 8, 'Made on the phone ${readingStamp(now)} from the person\'s own records. Not a diagnosis.'));
    y -= 22;

    void need(double h) {
      if (y - h < _m) {
        pages.add(page.toString());
        page = StringBuffer();
        y = _h - _m - 10;
      }
    }

    for (final SummaryBlock b in blocks) {
      need(40);
      page.write(_text(_m, y, 12, b.title, bold: true));
      page.write('0.7 G 0.5 w ${_n(_m)} ${_n(y - 4)} m ${_n(_w - _m)} ${_n(y - 4)} l S 0 G\n');
      y -= 18;
      for (final String line in b.lines) {
        for (final String part in wrap(line, 92)) {
          need(14);
          page.write(_text(_m + 6, y, 10, part.startsWith('  ') ? part : '- $part'));
          y -= 13;
        }
      }
      y -= 10;
    }
    if (blocks.isEmpty) {
      page.write(_text(_m, y, 10, 'No sections chosen.'));
    }
    pages.add(page.toString());
    return _assemble(pages);
  }

  static Uint8List _assemble(List<String> pageStreams) {
    final List<String> objs = <String>[];
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

  static HealthSummary instance = HealthSummary();
  static void install(HealthSummary s) => instance = s;
}
