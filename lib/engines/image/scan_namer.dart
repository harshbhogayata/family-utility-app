import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../pdf/pdf_ocr.dart';

/// Feature 053 — Auto-name scans.
///
/// Reads the first scanned page on the phone (the same on-device OCR as
/// feature 008), picks a title line and a date, and fills a name pattern
/// such as "{date} {title}". The person edits the name before it is saved.

const String defaultScanNamePattern = '{date} {title}';

const List<String> _months = <String>[
  'jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec', //
];

/// A date written in the text. Day comes first for numeric dates (India).
DateTime? findDate(String text) {
  DateTime? valid(int y, int m, int d) {
    if (y < 100) {
      y += 2000;
    }
    if (m < 1 || m > 12 || d < 1 || d > 31 || y < 1900 || y > 2100) {
      return null;
    }
    final DateTime t = DateTime(y, m, d);
    return t.month == m ? t : null;
  }

  final RegExpMatch? iso = RegExp(r'\b(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})\b').firstMatch(text);
  if (iso != null) {
    final DateTime? t = valid(int.parse(iso.group(1)!), int.parse(iso.group(2)!), int.parse(iso.group(3)!));
    if (t != null) {
      return t;
    }
  }
  for (final RegExpMatch m in RegExp(r'\b(\d{1,2})[-/.](\d{1,2})[-/.](\d{2,4})\b').allMatches(text)) {
    final DateTime? t = valid(int.parse(m.group(3)!), int.parse(m.group(2)!), int.parse(m.group(1)!));
    if (t != null) {
      return t;
    }
  }
  final String low = text.toLowerCase();
  for (final RegExpMatch m in RegExp(r'\b(\d{1,2})(?:st|nd|rd|th)?\s+([a-z]{3,9})\.?,?\s+(\d{4})\b').allMatches(low)) {
    final int mi = _months.indexOf(m.group(2)!.substring(0, 3));
    if (mi >= 0) {
      final DateTime? t = valid(int.parse(m.group(3)!), mi + 1, int.parse(m.group(1)!));
      if (t != null) {
        return t;
      }
    }
  }
  for (final RegExpMatch m in RegExp(r'\b([a-z]{3,9})\.?\s+(\d{1,2})(?:st|nd|rd|th)?,?\s+(\d{4})\b').allMatches(low)) {
    final int mi = _months.indexOf(m.group(1)!.substring(0, 3));
    if (mi >= 0) {
      final DateTime? t = valid(int.parse(m.group(3)!), mi + 1, int.parse(m.group(2)!));
      if (t != null) {
        return t;
      }
    }
  }
  return null;
}

/// The line most likely to be the document's title: near the top, mostly
/// letters, not a date or a number, not too long. Capitals score higher.
String? pickTitle(String text) {
  final List<String> lines = text
      .split('\n')
      .map((String l) => l.trim().replaceAll(RegExp(r'\s+'), ' '))
      .where((String l) => l.isNotEmpty)
      .toList();
  String? best;
  double bestScore = 0;
  for (int i = 0; i < lines.length && i < 8; i++) {
    final String l = lines[i];
    final int letters = RegExp(r'\p{L}', unicode: true).allMatches(l).length;
    if (letters < 3 || l.length > 60 || letters < l.length * 0.6 || findDate(l) != null) {
      continue;
    }
    double s = 10 - i.toDouble();
    if (l == l.toUpperCase() && l != l.toLowerCase()) {
      s += 3;
    }
    if (l.split(' ').length >= 2) {
      s += 1;
    }
    if (s > bestScore) {
      bestScore = s;
      best = l;
    }
  }
  return best;
}

/// Characters file systems refuse, and runs of spaces, out.
String safeFileName(String s) =>
    s.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

String _two(int v) => v.toString().padLeft(2, '0');

/// Fills [pattern]: {title}, {date} (YYYY-MM-DD), {time} (HH.MM).
String fillScanName(String pattern, {String? title, DateTime? date, required DateTime now}) {
  final DateTime d = date ?? now;
  final String out = pattern
      .replaceAll('{title}', title ?? 'Scan')
      .replaceAll('{date}', '${d.year}-${_two(d.month)}-${_two(d.day)}')
      .replaceAll('{time}', '${_two(now.hour)}.${_two(now.minute)}');
  final String safe = safeFileName(out);
  return safe.isEmpty ? 'Scan ${now.year}-${_two(now.month)}-${_two(now.day)}' : safe;
}

/// What the namer found, for the edit-before-save dialog.
class ScanNameSuggestion {
  const ScanNameSuggestion({required this.name, this.title, this.date});

  final String name;
  final String? title;
  final DateTime? date;
}

/// Where the person's pattern is kept.
abstract class ScanNamePatternStore {
  Future<String?> read();

  Future<void> write(String pattern);
}

class MemoryScanNamePatternStore implements ScanNamePatternStore {
  MemoryScanNamePatternStore([this.value]);

  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String pattern) async => value = pattern;
}

class ScanAutoNamer {
  ScanAutoNamer({required this.recognizer, required this.store, this.script = OcrScript.latin});

  final TextRecognizerEngine recognizer;
  final ScanNamePatternStore store;
  final OcrScript script;

  Future<String> pattern() async {
    try {
      final String? p = await store.read();
      return p == null || p.trim().isEmpty ? defaultScanNamePattern : p;
    } catch (_) {
      return defaultScanNamePattern;
    }
  }

  Future<void> setPattern(String p) => store.write(p.trim().isEmpty ? defaultScanNamePattern : p.trim());

  /// Names from text already read.
  Future<ScanNameSuggestion> fromText(String text, DateTime now) async {
    final String? title = pickTitle(text);
    final DateTime? date = findDate(text);
    return ScanNameSuggestion(
      name: fillScanName(await pattern(), title: title, date: date, now: now),
      title: title,
      date: date,
    );
  }

  /// Reads the first page on the phone and names it.
  Future<ScanNameSuggestion> suggest(Uint8List firstPageJpeg, DateTime now) async {
    final img.Image? page = img.decodeJpg(firstPageJpeg);
    if (page == null) {
      return fromText('', now);
    }
    final List<OcrWord> words = await recognizer.recognize(page, firstPageJpeg, script);
    return fromText(wordsToText(words), now);
  }

  static ScanAutoNamer? instance;
}
