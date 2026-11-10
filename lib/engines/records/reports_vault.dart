import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../family/document_vault.dart';
import '../pdf/pdf_ocr.dart';
import '../security/private_vault.dart';
import '../security/secure_notes.dart' show MemoryKeyStore;

/// Feature 091 — Reports vault.
///
/// Lab reports (photo or PDF) kept encrypted on this phone with AES-GCM
/// (the cipher of 056), listed by date. A value such as HbA1c is tagged on
/// each report — typed in, or found by on-device OCR (008) — and charted
/// across reports. The list itself is encrypted too. Nothing is uploaded.

class ReportValue {
  const ReportValue(this.value, [this.unit = '']);
  final double value;
  final String unit;
}

class LabReport {
  const LabReport({
    required this.id,
    required this.title,
    required this.date,
    required this.fileName,
    this.values = const <String, ReportValue>{},
  });

  final String id;
  final String title;
  final DateTime date;
  final String fileName;

  /// Tagged values by name (e.g. "HbA1c").
  final Map<String, ReportValue> values;

  bool get isPdf => fileName.toLowerCase().endsWith('.pdf');

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'title': title,
        'date': date.toIso8601String(),
        'file': fileName,
        'values': <String, Object?>{
          for (final MapEntry<String, ReportValue> e in values.entries) e.key: <String, Object?>{'v': e.value.value, 'u': e.value.unit},
        },
      };

  static LabReport fromJson(Map<String, Object?> j) {
    final Map<String, ReportValue> values = <String, ReportValue>{};
    final Object? raw = j['values'];
    if (raw is Map) {
      for (final MapEntry<Object?, Object?> e in raw.entries) {
        final Object? m = e.value;
        if (m is Map && m['v'] is num) {
          values['${e.key}'] = ReportValue((m['v'] as num).toDouble(), '${m['u'] ?? ''}');
        }
      }
    }
    return LabReport(
      id: '${j['id'] ?? ''}',
      title: '${j['title'] ?? ''}',
      date: DateTime.tryParse('${j['date'] ?? ''}') ?? DateTime(2000),
      fileName: '${j['file'] ?? ''}',
      values: values,
    );
  }

  LabReport withValues(Map<String, ReportValue> next) => LabReport(id: id, title: title, date: date, fileName: fileName, values: next);
}

/// Reads the text of a report image on the phone.
abstract interface class ReportTextReader {
  Future<String> read(Uint8List image);
}

class NoReportText implements ReportTextReader {
  const NoReportText();
  @override
  Future<String> read(Uint8List image) async => '';
}

/// On-device OCR through the app's text recognizer (ML Kit on phones).
class OcrReportTextReader implements ReportTextReader {
  const OcrReportTextReader(this.recognizer);
  final TextRecognizerEngine recognizer;

  @override
  Future<String> read(Uint8List image) async {
    final img.Image? page = img.decodeImage(image);
    if (page == null) {
      return '';
    }
    final Uint8List jpeg = img.encodeJpg(page, quality: 90);
    return wordsToText(await recognizer.recognize(page, jpeg, OcrScript.latin));
  }
}

class ReportsVault extends ChangeNotifier {
  ReportsVault({
    required VaultCipher cipher,
    required DocumentBlobStore blobs,
    ReportTextReader reader = const NoReportText(),
    DateTime Function()? now,
  })  : _cipher = cipher,
        _blobs = blobs,
        _reader = reader,
        _now = now ?? DateTime.now;

  static const String indexId = 'index';

  /// Values looked for when a report is read by OCR.
  static const List<String> commonTags = <String>[
    'HbA1c', 'Glucose', 'Haemoglobin', 'Cholesterol', 'HDL', 'LDL', 'Triglycerides', //
    'TSH', 'Creatinine', 'Vitamin D', 'Vitamin B12', 'Uric acid',
  ];

  final VaultCipher _cipher;
  final DocumentBlobStore _blobs;
  final ReportTextReader _reader;
  final DateTime Function() _now;
  int _seq = 0;

  List<LabReport> _reports = <LabReport>[];
  List<LabReport>? _undo;
  final Set<String> _pendingDelete = <String>{};
  bool _loaded = false;

  bool get loaded => _loaded;
  bool get canUndo => _undo != null;

  /// Newest first.
  List<LabReport> get reports {
    final List<LabReport> l = List<LabReport>.of(_reports);
    l.sort((LabReport a, LabReport b) => b.date.compareTo(a.date));
    return l;
  }

  LabReport? byId(String id) {
    for (final LabReport r in _reports) {
      if (r.id == id) {
        return r;
      }
    }
    return null;
  }

  /// Every tag used on any report, sorted.
  List<String> get tags {
    final Set<String> s = <String>{for (final LabReport r in _reports) ...r.values.keys};
    return s.toList()..sort((String a, String b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }

  Future<void> load() async {
    try {
      final Uint8List? data = await _blobs.read(indexId);
      if (data != null) {
        final Object? j = jsonDecode(utf8.decode(await _cipher.decrypt(data)));
        if (j is List) {
          _reports = j.whereType<Map<String, Object?>>().map(LabReport.fromJson).toList();
        }
      }
    } catch (e) {
      debugPrint('reports vault: $e');
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> _saveIndex() async {
    final List<Map<String, Object?>> j = _reports.map((LabReport r) => r.toJson()).toList();
    await _blobs.write(indexId, await _cipher.encrypt(utf8.encode(jsonEncode(j))));
  }

  void _remember() {
    _flushDeletes();
    _undo = List<LabReport>.of(_reports);
  }

  void _flushDeletes() {
    for (final String id in _pendingDelete) {
      unawaited(_blobs.delete('r_$id'));
    }
    _pendingDelete.clear();
  }

  /// Encrypts and keeps a report. With an image, known values are read by
  /// OCR and tagged straight away.
  Future<LabReport> add({required Uint8List bytes, required String fileName, String title = '', DateTime? date}) async {
    final DateTime now = _now();
    final String id = '${now.microsecondsSinceEpoch}-${_seq++}';
    await _blobs.write('r_$id', await _cipher.encrypt(bytes));
    Map<String, ReportValue> found = <String, ReportValue>{};
    if (!fileName.toLowerCase().endsWith('.pdf')) {
      try {
        found = findValues(await _reader.read(bytes));
      } catch (e) {
        debugPrint('report OCR: $e');
      }
    }
    final LabReport r = LabReport(
      id: id,
      title: title.trim().isEmpty ? 'Lab report' : title.trim(),
      date: date ?? DateTime(now.year, now.month, now.day),
      fileName: fileName,
      values: found,
    );
    _remember();
    _reports = <LabReport>[..._reports, r];
    await _saveIndex();
    notifyListeners();
    return r;
  }

  /// The decrypted file.
  Future<Uint8List> open(String id) async {
    final Uint8List? data = await _blobs.read('r_$id');
    if (data == null) {
      throw StateError('report file missing');
    }
    return _cipher.decrypt(data);
  }

  Future<bool> _replace(String id, LabReport Function(LabReport) change) async {
    final LabReport? r = byId(id);
    if (r == null) {
      return false;
    }
    _remember();
    _reports = <LabReport>[for (final LabReport x in _reports) x.id == id ? change(x) : x];
    await _saveIndex();
    notifyListeners();
    return true;
  }

  /// Tags (or re-tags) one value on a report.
  Future<bool> tagValue(String id, String tag, double value, {String unit = ''}) async {
    final String t = tag.trim();
    if (t.isEmpty || value.isNaN || value.isInfinite) {
      return false;
    }
    return _replace(id, (LabReport r) => r.withValues(<String, ReportValue>{...r.values, t: ReportValue(value, unit.trim())}));
  }

  Future<bool> untag(String id, String tag) async {
    final LabReport? r = byId(id);
    if (r == null || !r.values.containsKey(tag)) {
      return false;
    }
    return _replace(id, (LabReport x) => x.withValues(Map<String, ReportValue>.of(x.values)..remove(tag)));
  }

  Future<bool> remove(String id) async {
    if (byId(id) == null) {
      return false;
    }
    _remember();
    _reports = _reports.where((LabReport r) => r.id != id).toList();
    _pendingDelete.add(id); // the file goes once the removal can no longer be undone
    await _saveIndex();
    notifyListeners();
    return true;
  }

  Future<bool> undo() async {
    final List<LabReport>? u = _undo;
    if (u == null) {
      return false;
    }
    _undo = null;
    final Set<String> back = u.map((LabReport r) => r.id).toSet();
    _pendingDelete.removeWhere(back.contains);
    _reports = u;
    await _saveIndex();
    notifyListeners();
    return true;
  }

  /// One value across reports, oldest first.
  List<(DateTime, double)> series(String tag) {
    final List<LabReport> withTag = _reports.where((LabReport r) => r.values.containsKey(tag)).toList()
      ..sort((LabReport a, LabReport b) => a.date.compareTo(b.date));
    return <(DateTime, double)>[for (final LabReport r in withTag) (r.date, r.values[tag]!.value)];
  }

  String unitOf(String tag) {
    for (final LabReport r in reports) {
      final ReportValue? v = r.values[tag];
      if (v != null && v.unit.isNotEmpty) {
        return v.unit;
      }
    }
    return '';
  }

  /// Finds "<tag> ... <number> <unit>" on a line for each common tag.
  static Map<String, ReportValue> findValues(String text, {List<String> tags = commonTags}) {
    final Map<String, ReportValue> out = <String, ReportValue>{};
    final List<String> lines = text.split(RegExp(r'[\r\n]+'));
    for (final String tag in tags) {
      final RegExp name = RegExp('(^|[^A-Za-z])${RegExp.escape(tag)}(?![A-Za-z])', caseSensitive: false);
      for (final String line in lines) {
        final RegExpMatch? at = name.firstMatch(line);
        if (at == null) {
          continue;
        }
        final String rest = line.substring(at.end);
        final RegExpMatch? m = RegExp(r'(\d+(?:\.\d+)?)\s*(%|mg/dl|mg/l|g/dl|mmol/l|miu/l|uiu/ml|µiu/ml|ng/ml|pg/ml|nmol/l)?', caseSensitive: false).firstMatch(rest);
        if (m != null) {
          out[tag] = ReportValue(double.parse(m.group(1)!), m.group(2) ?? '');
          break;
        }
      }
    }
    return out;
  }

  static const List<String> months = <String>['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  static String dayLabel(DateTime d) => '${d.day} ${months[d.month - 1]} ${d.year}';

  static String number(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  /// One value over time as text, to share.
  String seriesText(String tag) {
    final String unit = unitOf(tag);
    final StringBuffer b = StringBuffer('$tag over time\n');
    for (final (DateTime, double) p in series(tag)) {
      b.write('- ${dayLabel(p.$1)}: ${number(p.$2)}${unit.isEmpty ? '' : ' $unit'}\n');
    }
    return b.toString();
  }

  /// Every report with its tagged values, newest first.
  String toText() {
    final StringBuffer b = StringBuffer('Lab reports\n');
    for (final LabReport r in reports) {
      final String vals = r.values.entries.map((MapEntry<String, ReportValue> e) => '${e.key} ${number(e.value.value)}${e.value.unit.isEmpty ? '' : ' ${e.value.unit}'}').join(', ');
      b.write('- ${dayLabel(r.date)}: ${r.title}${vals.isEmpty ? '' : ' · $vals'}\n');
    }
    return b.toString();
  }

  static ReportsVault? _instance;
  static ReportsVault get instance => _instance ??= ReportsVault(cipher: VaultCipher(MemoryKeyStore()), blobs: MemoryDocumentBlobStore());
  static void install(ReportsVault v) => _instance = v;
}
