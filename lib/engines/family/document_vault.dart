import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../security/private_vault.dart' show VaultCipher;
import 'family_space.dart';
import 'family_store.dart';

/// Feature 074 — Shared document vault with expiry.
///
/// Aadhaar, PAN, passports, vehicle papers and insurance, per member. The
/// file itself is AES-256-GCM encrypted on the phone that added it (key in
/// Keystore / Keychain, the same cipher as the private vault). Only the
/// card's details — member, kind, title and expiry date, never the number
/// or the picture — go into the family store, so every family phone sees
/// what is expiring and gets the 30, 7 and 1 day reminders. Nothing is
/// uploaded.

enum FamilyDocType {
  aadhaar('Aadhaar'),
  pan('PAN card'),
  passport('Passport'),
  vehicle('Vehicle papers'),
  insurance('Insurance'),
  other('Other');

  const FamilyDocType(this.label);
  final String label;

  static FamilyDocType parse(Object? name) =>
      FamilyDocType.values.firstWhere((FamilyDocType t) => t.name == name, orElse: () => FamilyDocType.other);
}

@immutable
class FamilyDocument {
  const FamilyDocument({
    required this.id,
    required this.member,
    required this.type,
    required this.title,
    required this.holder,
    required this.addedAt,
    this.expiry,
  });

  final String id;

  /// Member device id the document belongs to.
  final String member;
  final FamilyDocType type;
  final String title;

  /// Device that holds the encrypted file.
  final String holder;
  final DateTime addedAt;

  /// Expiry day, or null when it does not expire (Aadhaar, PAN).
  final DateTime? expiry;

  int? daysLeft(DateTime today) {
    final DateTime? e = expiry;
    if (e == null) {
      return null;
    }
    return DateTime.utc(e.year, e.month, e.day).difference(DateTime.utc(today.year, today.month, today.day)).inDays;
  }

  Map<String, Object?> toFields() => <String, Object?>{
        'member': member,
        'type': type.name,
        'title': title,
        'holder': holder,
        'at': addedAt.toIso8601String(),
        if (expiry != null) 'expiry': DocumentVault.dayKey(expiry!),
      };

  static FamilyDocument fromRecord(FamilyRecord r) {
    final Map<String, Object?> f = r.fields;
    return FamilyDocument(
      id: r.id,
      member: '${f['member'] ?? r.writer}',
      type: FamilyDocType.parse(f['type']),
      title: '${f['title'] ?? ''}',
      holder: '${f['holder'] ?? r.writer}',
      addedAt: DateTime.tryParse('${f['at'] ?? ''}') ?? DateTime.fromMillisecondsSinceEpoch(r.wallMillis),
      expiry: f['expiry'] == null ? null : DateTime.tryParse('${f['expiry']}'),
    );
  }
}

/// Encrypted files on this phone, by document id.
abstract class DocumentBlobStore {
  Future<Uint8List?> read(String id);

  Future<void> write(String id, Uint8List data);

  Future<void> delete(String id);
}

class MemoryDocumentBlobStore implements DocumentBlobStore {
  final Map<String, Uint8List> files = <String, Uint8List>{};

  @override
  Future<Uint8List?> read(String id) async => files[id];

  @override
  Future<void> write(String id, Uint8List data) async => files[id] = data;

  @override
  Future<void> delete(String id) async => files.remove(id);
}

/// Covers ID numbers on a photo of a document; returns the masked image.
abstract class DocumentMasker {
  Future<Uint8List> mask(Uint8List image);
}

/// Turns a photo of a document into a PDF.
typedef DocumentPdfMaker = Future<Uint8List> Function(Uint8List image);

class DocumentVaultException implements Exception {
  const DocumentVaultException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// One reminder: [document] expires in [days] days.
@immutable
class DocumentReminder {
  const DocumentReminder(this.document, this.days);
  final FamilyDocument document;
  final int days;

  String get text => days == 1
      ? '${document.title} expires tomorrow'
      : '${document.title} expires in $days days';
}

class DocumentVault extends ChangeNotifier {
  DocumentVault({
    required VaultCipher cipher,
    required DocumentBlobStore blobs,
    FamilySpace? space,
    DateTime Function()? now,
  })  : _cipher = cipher,
        _blobs = blobs,
        _space = space,
        _now = now ?? DateTime.now;

  static const String collection = 'documents';

  /// Days before expiry when every family phone is reminded.
  static const List<int> reminderDays = <int>[30, 7, 1];

  /// Hour of the day the reminders fall due.
  static const int reminderHour = 9;

  final VaultCipher _cipher;
  final DocumentBlobStore _blobs;
  final FamilySpace? _space;
  final DateTime Function() _now;
  int _seq = 0;

  /// For Undo: id to the fields it had before (null when it was new).
  MapEntry<String, Map<String, Object?>?>? _undo;

  FamilySpace get space => _space ?? FamilySpace.instance;
  FamilyStore get store => space.store;
  String get me => space.identity?.deviceId ?? 'local';
  bool get canUndo => _undo != null;

  static String dayKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String memberName(String id) {
    final FamilyRecord? r = store.get(FamilySpace.members, id);
    return r == null ? (id == me ? 'Me' : 'Someone') : '${r.fields['name'] ?? 'Someone'}';
  }

  /// Soonest expiry first; documents that do not expire last, by title.
  List<FamilyDocument> get documents {
    final List<FamilyDocument> all = store.list(collection).map(FamilyDocument.fromRecord).toList();
    all.sort((FamilyDocument a, FamilyDocument b) {
      if (a.expiry != null && b.expiry != null && a.expiry != b.expiry) {
        return a.expiry!.compareTo(b.expiry!);
      }
      if ((a.expiry == null) != (b.expiry == null)) {
        return a.expiry == null ? 1 : -1;
      }
      return a.title.compareTo(b.title);
    });
    return all;
  }

  FamilyDocument? document(String id) {
    final FamilyRecord? r = store.get(collection, id);
    return r == null ? null : FamilyDocument.fromRecord(r);
  }

  /// Documents grouped by member, in member-name order.
  List<MapEntry<String, List<FamilyDocument>>> byMember() {
    final Map<String, List<FamilyDocument>> by = <String, List<FamilyDocument>>{};
    for (final FamilyDocument d in documents) {
      by.putIfAbsent(d.member, () => <FamilyDocument>[]).add(d);
    }
    final List<String> keys = by.keys.toList()..sort((String a, String b) => memberName(a).compareTo(memberName(b)));
    return <MapEntry<String, List<FamilyDocument>>>[
      for (final String k in keys) MapEntry<String, List<FamilyDocument>>(k, by[k]!),
    ];
  }

  /// Encrypts [bytes] on this phone and lists the document for the family.
  Future<FamilyDocument> add({
    required String member,
    required FamilyDocType type,
    required Uint8List bytes,
    String title = '',
    DateTime? expiry,
  }) async {
    if (bytes.isEmpty) {
      throw const DocumentVaultException('The file is empty.');
    }
    final DateTime now = _now();
    final String t = title.trim();
    final FamilyDocument d = FamilyDocument(
      id: '$me-${now.microsecondsSinceEpoch}-${_seq++}',
      member: member,
      type: type,
      title: t.isEmpty ? '${type.label} · ${memberName(member)}' : t,
      holder: me,
      addedAt: now,
      expiry: expiry == null ? null : DateTime(expiry.year, expiry.month, expiry.day),
    );
    await _blobs.write(d.id, await _cipher.encrypt(bytes));
    _write(d.id, d.toFields());
    return d;
  }

  /// The decrypted file, or an error when it lives on another phone.
  Future<Uint8List> open(FamilyDocument d) async {
    final Uint8List? data = await _blobs.read(d.id);
    if (data == null) {
      throw DocumentVaultException('The file is on ${memberName(d.holder)}\'s phone. Open it there to send it.');
    }
    return _cipher.decrypt(data);
  }

  bool setExpiry(String id, DateTime? expiry) {
    final FamilyDocument? d = document(id);
    if (d == null) {
      return false;
    }
    final Map<String, Object?> f = Map<String, Object?>.of(d.toFields())..remove('expiry');
    if (expiry != null) {
      f['expiry'] = dayKey(expiry);
    }
    _write(id, f);
    return true;
  }

  /// Unlists a document. The encrypted file stays until the next change,
  /// so Undo can bring it back.
  bool remove(String id) {
    if (document(id) == null) {
      return false;
    }
    _write(id, null);
    return true;
  }

  bool undo() {
    final MapEntry<String, Map<String, Object?>?>? u = _undo;
    if (u == null) {
      return false;
    }
    _undo = null;
    _set(u.key, u.value);
    notifyListeners();
    return true;
  }

  void _write(String id, Map<String, Object?>? fields) {
    final MapEntry<String, Map<String, Object?>?>? previous = _undo;
    if (previous != null && previous.value != null && document(previous.key) == null && previous.key != id) {
      unawaited(_blobs.delete(previous.key)); // a removal that can no longer be undone
    }
    _undo = MapEntry<String, Map<String, Object?>?>(id, store.get(collection, id)?.fields);
    _set(id, fields);
    notifyListeners();
  }

  void _set(String id, Map<String, Object?>? fields) {
    if (fields == null) {
      store.delete(collection, id);
    } else {
      store.put(collection, id, fields);
    }
  }

  // ---- sending ----

  static bool isPdf(Uint8List b) => b.length > 4 && b[0] == 0x25 && b[1] == 0x50 && b[2] == 0x44 && b[3] == 0x46;

  /// The document as a PDF: a PDF is sent as it is, a photo becomes one page.
  Future<Uint8List> asPdf(FamilyDocument d, DocumentPdfMaker toPdf) async {
    final Uint8List bytes = await open(d);
    return isPdf(bytes) ? bytes : toPdf(bytes);
  }

  /// A PDF of the photo with the ID number covered (Aadhaar keeps only its
  /// last four digits).
  Future<Uint8List> maskedPdf(FamilyDocument d, DocumentMasker masker, DocumentPdfMaker toPdf) async {
    final Uint8List bytes = await open(d);
    if (isPdf(bytes)) {
      throw const DocumentVaultException('Masking works on a photo or scan of the card, not on a PDF.');
    }
    return toPdf(await masker.mask(bytes));
  }

  // ---- reminders ----

  /// When the [days]-before reminder for [expiry] falls due.
  static DateTime reminderAt(DateTime expiry, int days) =>
      DateTime(expiry.year, expiry.month, expiry.day - days, reminderHour);

  /// Reminders that fell due after [since], up to and including [now].
  List<DocumentReminder> dueReminders(DateTime since, DateTime now) {
    final List<DocumentReminder> out = <DocumentReminder>[];
    for (final FamilyDocument d in documents) {
      final DateTime? e = d.expiry;
      if (e == null) {
        continue;
      }
      for (final int days in reminderDays) {
        final DateTime at = reminderAt(e, days);
        if (at.isAfter(since) && !at.isAfter(now)) {
          out.add(DocumentReminder(d, days));
        }
      }
    }
    return out;
  }

  /// Plain-text list of what expires when, to share or save.
  String toText() {
    final DateTime today = _now();
    final StringBuffer b = StringBuffer('Family documents\n');
    for (final MapEntry<String, List<FamilyDocument>> g in byMember()) {
      b.write('\n${memberName(g.key)}\n');
      for (final FamilyDocument d in g.value) {
        final int? left = d.daysLeft(today);
        b.write('- ${d.title} (${d.type.label})');
        if (d.expiry != null) {
          b.write(' · expires ${dayKey(d.expiry!)}');
          b.write(left! < 0 ? ' · expired' : ' · $left days left');
        }
        b.write('\n');
      }
    }
    return b.toString();
  }

  static DocumentVault? instance;

  static void install(DocumentVault vault) => instance = vault;
}

/// Last time reminders were checked, kept across app starts.
abstract class DocumentReminderMarks {
  Future<DateTime?> read();

  Future<void> write(DateTime at);
}

class MemoryDocumentReminderMarks implements DocumentReminderMarks {
  DateTime? value;

  @override
  Future<DateTime?> read() async => value;

  @override
  Future<void> write(DateTime at) async => value = at;
}

abstract class DocumentReminderSink {
  Future<void> remind(DocumentReminder reminder);
}

/// Fires every reminder that fell due since the last check, even when the
/// app was closed at the time (checked at start and every hour after).
class DocumentReminderWatcher {
  DocumentReminderWatcher({
    required this.vault,
    required this.sink,
    required this.marks,
    DateTime Function()? now,
    this.every = const Duration(hours: 1),
  }) : _now = now ?? DateTime.now;

  final DocumentVault vault;
  final DocumentReminderSink sink;
  final DocumentReminderMarks marks;
  final DateTime Function() _now;
  final Duration every;
  Timer? _timer;

  void start() {
    unawaited(check());
    _timer?.cancel();
    _timer = Timer.periodic(every, (_) => unawaited(check()));
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<int> check() async {
    final DateTime now = _now();
    DateTime? since;
    try {
      since = await marks.read();
    } catch (_) {
      since = null;
    }
    // First run: catch up on the last day only, not on years of history.
    since ??= now.subtract(const Duration(days: 1));
    final List<DocumentReminder> due = vault.dueReminders(since, now);
    for (final DocumentReminder r in due) {
      try {
        await sink.remind(r);
      } catch (_) {
        // Notifications off: the vault screen still shows days left.
      }
    }
    try {
      await marks.write(now);
    } catch (_) {
      // Checked again next time.
    }
    return due.length;
  }

  static DocumentReminderWatcher? instance;
}
