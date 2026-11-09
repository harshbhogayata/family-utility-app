import 'package:flutter/foundation.dart';

import 'family_location.dart';
import 'family_space.dart';
import 'family_store.dart';

/// Feature 077 — Auto check-in.
///
/// "Reached safely" in one tap, posted to the family feed (the family
/// store's `checkins` collection, so it travels only over the family's own
/// Wi-Fi or folder sync). With auto check-in on, arriving at one of the
/// family's places (feature 076) posts the same message by itself.

@immutable
class CheckIn {
  const CheckIn({
    required this.id,
    required this.member,
    required this.at,
    required this.auto,
    this.place,
    this.note = '',
  });

  final String id;
  final String member;
  final DateTime at;
  final bool auto;

  /// Name of the saved place, if any.
  final String? place;
  final String note;

  Map<String, Object?> toFields() => <String, Object?>{
        'by': member,
        'at': at.toIso8601String(),
        'auto': auto,
        if (place != null) 'place': place,
        if (note.isNotEmpty) 'note': note,
      };

  static CheckIn fromRecord(FamilyRecord r) {
    final Map<String, Object?> f = r.fields;
    final Object? p = f['place'];
    return CheckIn(
      id: r.id,
      member: '${f['by'] ?? r.writer}',
      at: DateTime.tryParse('${f['at'] ?? ''}') ?? DateTime.fromMillisecondsSinceEpoch(r.wallMillis),
      auto: f['auto'] == true,
      place: p is String && p.isNotEmpty ? p : null,
      note: '${f['note'] ?? ''}',
    );
  }
}

class CheckIns extends ChangeNotifier {
  CheckIns({required this.location, FamilySpace? space, DateTime Function()? now})
      : _space = space,
        _now = now ?? DateTime.now;

  static const String collection = 'checkins';
  static const String prefs = 'checkinPrefs';

  /// An automatic check-in at the same place is not repeated within this.
  static const Duration autoQuiet = Duration(minutes: 30);

  /// Feed entries older than this are not shown.
  static const Duration feedKeeps = Duration(days: 7);

  final FamilyLocation location;
  final FamilySpace? _space;
  final DateTime Function() _now;
  int _seq = 0;
  String? _lastPlaceId;
  DateTime? _lastFixAt;
  String? _undoId;

  FamilySpace get space => _space ?? FamilySpace.instance;
  FamilyStore get store => space.store;
  String get me => space.identity?.deviceId ?? 'local';

  String memberName(String id) => location.memberName(id);

  /// Auto check-in for this phone's member; on by default.
  bool get autoOn => store.get(prefs, me)?.fields['auto'] != false;

  void setAuto(bool on) {
    store.put(prefs, me, <String, Object?>{'auto': on});
    notifyListeners();
  }

  /// Newest first, last 7 days.
  List<CheckIn> get feed {
    final DateTime cutoff = _now().subtract(feedKeeps);
    final List<CheckIn> all =
        store.list(collection).map(CheckIn.fromRecord).where((CheckIn c) => c.at.isAfter(cutoff)).toList();
    all.sort((CheckIn a, CheckIn b) => b.at.compareTo(a.at));
    return all;
  }

  /// The saved place this phone is at now, from its latest fix.
  FamilyPlace? get currentPlace {
    final List<LocationFix> t = location.trail;
    return t.isEmpty ? null : location.placeOf(t.last);
  }

  /// The one-tap "Reached safely".
  CheckIn checkIn({String note = ''}) => _post(auto: false, place: currentPlace?.name, note: note.trim());

  /// Looks at this phone's latest fix and checks in when it has just
  /// arrived at a saved place. Returns the check-in, or null.
  CheckIn? onLatestFix() {
    final List<LocationFix> t = location.trail;
    if (t.isEmpty) {
      return null;
    }
    final LocationFix f = t.last;
    if (_lastFixAt != null && !f.at.isAfter(_lastFixAt!)) {
      return null;
    }
    _lastFixAt = f.at;
    final FamilyPlace? p = location.placeOf(f);
    final String? before = _lastPlaceId;
    _lastPlaceId = p?.id;
    if (p == null || p.id == before || !autoOn) {
      return null;
    }
    // Same place again within the quiet time (a GPS wobble at the gate).
    for (final CheckIn c in feed) {
      if (c.member == me && c.place == p.name && f.at.difference(c.at).abs() < autoQuiet) {
        return null;
      }
    }
    return _post(auto: true, place: p.name, at: f.at);
  }

  CheckIn _post({required bool auto, String? place, String note = '', DateTime? at}) {
    final DateTime t = at ?? _now();
    final CheckIn c = CheckIn(
      id: '$me-${t.microsecondsSinceEpoch}-${_seq++}',
      member: me,
      at: t,
      auto: auto,
      place: place,
      note: note,
    );
    store.put(collection, c.id, c.toFields());
    _undoId = c.id;
    notifyListeners();
    return c;
  }

  /// Takes back the last check-in made on this phone.
  bool undo() {
    final String? id = _undoId;
    if (id == null || store.get(collection, id) == null) {
      return false;
    }
    _undoId = null;
    store.delete(collection, id);
    notifyListeners();
    return true;
  }

  static String _hm(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  String lineFor(CheckIn c) {
    final String where = c.place == null ? 'reached safely' : 'reached ${c.place} safely';
    final String how = c.auto ? ' (automatic)' : '';
    final String note = c.note.isEmpty ? '' : ' · ${c.note}';
    return '${memberName(c.member)} $where$how · ${_hm(c.at)}$note';
  }

  String toText() {
    final StringBuffer b = StringBuffer('Family check-ins\n');
    for (final CheckIn c in feed) {
      b.write('${lineFor(c)}\n');
    }
    return b.toString();
  }

  static CheckIns? instance;

  static void install(CheckIns c) => instance = c;
}
