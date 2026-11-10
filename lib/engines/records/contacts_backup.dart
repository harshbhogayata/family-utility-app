import 'dart:convert';
import 'dart:typed_data';

/// Feature 103 — Contacts backup.
///
/// Every contact on the phone written to one vCard (.vcf) file, photos
/// included, and the same file read back on a new phone. Restoring merges:
/// a card that matches a contact already there (same phone number, email or,
/// failing both, the same name) adds only what is missing to it, and a card
/// seen twice is not added twice. The file stays on the phone; the person
/// shares or saves it themselves.

/// One contact as the backup sees it.
class BackupContact {
  const BackupContact({
    this.id = '',
    this.first = '',
    this.last = '',
    this.display = '',
    this.phones = const <String>[],
    this.emails = const <String>[],
    this.org = '',
    this.photo,
  });

  /// The phone's id for a contact already there; empty for one from a file.
  final String id;
  final String first;
  final String last;
  final String display;
  final List<String> phones;
  final List<String> emails;
  final String org;

  /// JPEG (or PNG) bytes.
  final Uint8List? photo;

  String get name {
    if (display.trim().isNotEmpty) {
      return display.trim();
    }
    return '$first $last'.trim();
  }

  BackupContact copyWith({List<String>? phones, List<String>? emails, Uint8List? photo, String? org}) => BackupContact(
        id: id,
        first: first,
        last: last,
        display: display,
        phones: phones ?? this.phones,
        emails: emails ?? this.emails,
        org: org ?? this.org,
        photo: photo ?? this.photo,
      );
}

/// What a restore will do.
class RestorePlan {
  const RestorePlan({required this.add, required this.update, required this.same});

  /// New contacts to create.
  final List<BackupContact> add;

  /// Existing contacts (with their ids) and what they become.
  final List<BackupContact> update;

  /// Cards that were already on the phone in full, or repeated in the file.
  final int same;

  bool get isEmpty => add.isEmpty && update.isEmpty;
}

/// The phone's contacts; the plugin lives in lib/platform.
abstract interface class ContactsSource {
  Future<bool> allowed({required bool write});
  Future<List<BackupContact>> readAll();
  Future<void> insert(BackupContact c);
  Future<void> update(BackupContact c);
}

abstract final class ContactsBackup {
  // ---- writing ----

  static String _esc(String s) =>
      s.replaceAll(r'\', r'\\').replaceAll('\n', r'\n').replaceAll(',', r'\,').replaceAll(';', r'\;');

  /// Folds a content line at 75 octets as the vCard spec asks.
  static String fold(String line) {
    if (line.length <= 75) {
      return line;
    }
    final StringBuffer b = StringBuffer(line.substring(0, 75));
    int i = 75;
    while (i < line.length) {
      final int end = i + 74 < line.length ? i + 74 : line.length;
      b.write('\r\n ');
      b.write(line.substring(i, end));
      i = end;
    }
    return b.toString();
  }

  static bool _isPng(Uint8List b) => b.length > 4 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4e && b[3] == 0x47;

  /// vCard 3.0 for every contact, photos base64 inline.
  static String toVcf(List<BackupContact> contacts) {
    final StringBuffer out = StringBuffer();
    for (final BackupContact c in contacts) {
      final List<String> lines = <String>[
        'BEGIN:VCARD',
        'VERSION:3.0',
        'N:${_esc(c.last)};${_esc(c.first)};;;',
        'FN:${_esc(c.name)}',
        for (final String p in c.phones) 'TEL;TYPE=CELL:${_esc(p)}',
        for (final String e in c.emails) 'EMAIL:${_esc(e)}',
        if (c.org.trim().isNotEmpty) 'ORG:${_esc(c.org.trim())}',
        if (c.photo != null && c.photo!.isNotEmpty) 'PHOTO;ENCODING=b;TYPE=${_isPng(c.photo!) ? 'PNG' : 'JPEG'}:${base64.encode(c.photo!)}',
        'END:VCARD',
      ];
      for (final String l in lines) {
        out.write(fold(l));
        out.write('\r\n');
      }
    }
    return out.toString();
  }

  static String fileName(DateTime now) =>
      'Contacts ${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}.vcf';

  // ---- reading ----

  static String _unesc(String s) {
    final StringBuffer b = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      final String ch = s[i];
      if (ch == r'\' && i + 1 < s.length) {
        final String n = s[++i];
        b.write(n == 'n' || n == 'N' ? '\n' : n);
      } else {
        b.write(ch);
      }
    }
    return b.toString();
  }

  /// Splits on unescaped [sep].
  static List<String> _split(String s, String sep) {
    final List<String> out = <String>[];
    final StringBuffer cur = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (s[i] == r'\' && i + 1 < s.length) {
        cur.write(s[i]);
        cur.write(s[++i]);
      } else if (s[i] == sep) {
        out.add(cur.toString());
        cur.clear();
      } else {
        cur.write(s[i]);
      }
    }
    out.add(cur.toString());
    return out;
  }

  /// Reads vCard 2.1, 3.0 and 4.0 files (as other phones write them).
  static List<BackupContact> parse(String vcf) {
    final List<String> raw = vcf.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
    // Unfold: a line starting with a space or tab continues the previous
    // one; vCard 2.1 quoted-printable soft breaks end in "=".
    final List<String> lines = <String>[];
    for (final String l in raw) {
      if ((l.startsWith(' ') || l.startsWith('\t')) && lines.isNotEmpty) {
        lines[lines.length - 1] += l.substring(1);
      } else if (lines.isNotEmpty && lines.last.toUpperCase().contains('QUOTED-PRINTABLE') && lines.last.endsWith('=')) {
        lines[lines.length - 1] = lines.last.substring(0, lines.last.length - 1) + l;
      } else if (lines.isNotEmpty && lines.last.toUpperCase().startsWith('PHOTO') && !l.contains(':') && l.trim().isNotEmpty) {
        // vCard 2.1 base64 bodies run on over plain lines.
        lines[lines.length - 1] += l.trim();
      } else {
        lines.add(l);
      }
    }
    final List<BackupContact> out = <BackupContact>[];
    String first = '', last = '', display = '', org = '';
    List<String> phones = <String>[], emails = <String>[];
    Uint8List? photo;
    bool inCard = false;
    for (final String line in lines) {
      final int colon = line.indexOf(':');
      if (colon < 0) {
        continue;
      }
      final String head = line.substring(0, colon);
      String value = line.substring(colon + 1);
      final List<String> params = head.split(';');
      String key = params.first.toUpperCase();
      final int dot = key.indexOf('.');
      if (dot >= 0) {
        key = key.substring(dot + 1); // item1.TEL
      }
      final String upHead = head.toUpperCase();
      if (upHead.contains('QUOTED-PRINTABLE')) {
        value = _qp(value);
      }
      if (key == 'BEGIN' && value.trim().toUpperCase() == 'VCARD') {
        inCard = true;
        first = last = display = org = '';
        phones = <String>[];
        emails = <String>[];
        photo = null;
        continue;
      }
      if (!inCard) {
        continue;
      }
      switch (key) {
        case 'END':
          out.add(BackupContact(first: first, last: last, display: display, phones: phones, emails: emails, org: org, photo: photo));
          inCard = false;
        case 'N':
          final List<String> p = _split(value, ';');
          last = _unesc(p.isNotEmpty ? p[0] : '').trim();
          first = _unesc(p.length > 1 ? p[1] : '').trim();
        case 'FN':
          display = _unesc(value).trim();
        case 'TEL':
          final String t = _unesc(value).replaceFirst(RegExp('^tel:', caseSensitive: false), '').trim();
          if (t.isNotEmpty && !phones.contains(t)) {
            phones.add(t);
          }
        case 'EMAIL':
          final String e = _unesc(value).trim();
          if (e.isNotEmpty && !emails.contains(e)) {
            emails.add(e);
          }
        case 'ORG':
          org = _unesc(_split(value, ';').first).trim();
        case 'PHOTO':
          String data = value.trim();
          final int comma = data.indexOf('base64,');
          if (comma >= 0) {
            data = data.substring(comma + 7); // vCard 4.0 data: URI
          }
          if (upHead.contains('ENCODING=B') || upHead.contains('BASE64') || comma >= 0) {
            try {
              photo = base64.decode(data.replaceAll(RegExp(r'\s'), ''));
            } on FormatException {
              photo = null;
            }
          }
        default:
          break;
      }
    }
    return out;
  }

  static String _qp(String s) {
    final List<int> bytes = <int>[];
    for (int i = 0; i < s.length; i++) {
      if (s[i] == '=' && i + 2 < s.length) {
        final int? v = int.tryParse(s.substring(i + 1, i + 3), radix: 16);
        if (v != null) {
          bytes.add(v);
          i += 2;
          continue;
        }
      }
      bytes.addAll(utf8.encode(s[i]));
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  // ---- merging ----

  /// Digits only, last ten (so +91 98765 43210 and 098765-43210 match).
  static String phoneKey(String p) {
    final String d = p.replaceAll(RegExp(r'\D'), '');
    return d.length > 10 ? d.substring(d.length - 10) : d;
  }

  static String _nameKey(BackupContact c) => c.name.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

  static bool _matches(BackupContact a, BackupContact b) {
    final Set<String> ap = a.phones.map(phoneKey).where((String k) => k.length >= 6).toSet();
    if (b.phones.map(phoneKey).any(ap.contains)) {
      return true;
    }
    final Set<String> ae = a.emails.map((String e) => e.toLowerCase().trim()).toSet();
    if (b.emails.map((String e) => e.toLowerCase().trim()).any(ae.contains)) {
      return true;
    }
    final bool noIds = (a.phones.isEmpty && a.emails.isEmpty) || (b.phones.isEmpty && b.emails.isEmpty);
    return noIds && _nameKey(a).isNotEmpty && _nameKey(a) == _nameKey(b);
  }

  /// [c] with [incoming]'s phones, emails, photo and company added where
  /// missing; null when nothing would change.
  static BackupContact? _mergeInto(BackupContact c, BackupContact incoming) {
    final Set<String> pk = c.phones.map(phoneKey).toSet();
    final List<String> phones = List<String>.of(c.phones);
    for (final String p in incoming.phones) {
      if (pk.add(phoneKey(p))) {
        phones.add(p);
      }
    }
    final Set<String> ek = c.emails.map((String e) => e.toLowerCase()).toSet();
    final List<String> emails = List<String>.of(c.emails);
    for (final String e in incoming.emails) {
      if (ek.add(e.toLowerCase())) {
        emails.add(e);
      }
    }
    final bool addPhoto = (c.photo == null || c.photo!.isEmpty) && incoming.photo != null && incoming.photo!.isNotEmpty;
    final bool addOrg = c.org.trim().isEmpty && incoming.org.trim().isNotEmpty;
    if (phones.length == c.phones.length && emails.length == c.emails.length && !addPhoto && !addOrg) {
      return null;
    }
    return c.copyWith(phones: phones, emails: emails, photo: addPhoto ? incoming.photo : null, org: addOrg ? incoming.org : null);
  }

  /// Works out a restore of [incoming] onto [existing] with no duplicates.
  static RestorePlan plan(List<BackupContact> existing, List<BackupContact> incoming) {
    // Working copies: the phone's contacts and the ones this restore adds.
    final List<BackupContact> phone = List<BackupContact>.of(existing);
    final Set<int> changed = <int>{};
    final List<BackupContact> add = <BackupContact>[];
    int same = 0;
    for (final BackupContact inc in incoming) {
      if (inc.name.isEmpty && inc.phones.isEmpty && inc.emails.isEmpty) {
        continue;
      }
      final int hit = phone.indexWhere((BackupContact c) => _matches(c, inc));
      if (hit >= 0) {
        final BackupContact? m = _mergeInto(phone[hit], inc);
        if (m == null) {
          same++;
        } else {
          phone[hit] = m;
          changed.add(hit);
        }
        continue;
      }
      final int addHit = add.indexWhere((BackupContact c) => _matches(c, inc));
      if (addHit >= 0) {
        final BackupContact? m = _mergeInto(add[addHit], inc);
        if (m == null) {
          same++;
        } else {
          add[addHit] = m;
        }
        continue;
      }
      add.add(inc);
    }
    final List<int> idx = changed.toList()..sort();
    return RestorePlan(add: add, update: idx.map((int i) => phone[i]).toList(), same: same);
  }

  /// Applies [p]; returns how many contacts were added and updated.
  static Future<({int added, int updated})> apply(ContactsSource source, RestorePlan p) async {
    int added = 0, updated = 0;
    for (final BackupContact c in p.add) {
      await source.insert(c);
      added++;
    }
    for (final BackupContact c in p.update) {
      await source.update(c);
      updated++;
    }
    return (added: added, updated: updated);
  }
}
