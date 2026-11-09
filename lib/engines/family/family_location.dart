import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'family_space.dart';
import 'family_store.dart';

/// Feature 076 — Live family location.
///
/// Each member chooses whether to share. A shared position is one record
/// per member in the family store's `locations` collection (latest fix
/// only), so it travels over the family's own Wi-Fi or folder sync and
/// nowhere else. Places (home, school, office) live in `places`; every
/// phone works out arrive and leave from the shared positions and tells
/// its own person. The 7-day trail stays on this phone only.

@immutable
class LocationFix {
  const LocationFix(this.lat, this.lng, this.at, {this.accuracy = 0});

  final double lat;
  final double lng;
  final DateTime at;

  /// Metres.
  final double accuracy;

  Map<String, Object?> toJson() => <String, Object?>{
        'lat': lat,
        'lng': lng,
        'at': at.toIso8601String(),
        if (accuracy > 0) 'acc': accuracy,
      };

  static LocationFix? fromJson(Map<String, Object?> j) {
    final Object? lat = j['lat'];
    final Object? lng = j['lng'];
    final DateTime? at = DateTime.tryParse('${j['at'] ?? ''}');
    if (lat is! num || lng is! num || at == null) {
      return null;
    }
    final Object? acc = j['acc'];
    return LocationFix(lat.toDouble(), lng.toDouble(), at, accuracy: acc is num ? acc.toDouble() : 0);
  }
}

/// Great-circle distance in metres.
double distanceMetres(double lat1, double lng1, double lat2, double lng2) {
  const double r = 6371000;
  final double p1 = lat1 * math.pi / 180;
  final double p2 = lat2 * math.pi / 180;
  final double dp = (lat2 - lat1) * math.pi / 180;
  final double dl = (lng2 - lng1) * math.pi / 180;
  final double a = math.sin(dp / 2) * math.sin(dp / 2) + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) * math.sin(dl / 2);
  return 2 * r * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

@immutable
class FamilyPlace {
  const FamilyPlace({required this.id, required this.name, required this.lat, required this.lng, this.radius = 150});

  final String id;
  final String name;
  final double lat;
  final double lng;

  /// Metres.
  final double radius;

  bool contains(LocationFix f) => distanceMetres(lat, lng, f.lat, f.lng) <= radius;

  Map<String, Object?> toFields() => <String, Object?>{'name': name, 'lat': lat, 'lng': lng, 'radius': radius};

  static FamilyPlace fromRecord(FamilyRecord r) {
    final Map<String, Object?> f = r.fields;
    final Object? lat = f['lat'];
    final Object? lng = f['lng'];
    final Object? rad = f['radius'];
    return FamilyPlace(
      id: r.id,
      name: '${f['name'] ?? 'Place'}',
      lat: lat is num ? lat.toDouble() : 0,
      lng: lng is num ? lng.toDouble() : 0,
      radius: rad is num ? rad.toDouble() : 150,
    );
  }
}

/// A member's shared position as the family sees it.
@immutable
class MemberLocation {
  const MemberLocation(this.member, this.sharing, this.fix);
  final String member;
  final bool sharing;
  final LocationFix? fix;
}

@immutable
class PlaceEvent {
  const PlaceEvent({required this.member, required this.place, required this.arrived, required this.at});
  final String member;
  final FamilyPlace place;
  final bool arrived;
  final DateTime at;
}

/// The 7-day trail, kept on this phone only.
abstract class LocationHistoryStore {
  Future<List<LocationFix>> read();

  Future<void> write(List<LocationFix> fixes);
}

class MemoryLocationHistoryStore implements LocationHistoryStore {
  List<LocationFix> fixes = <LocationFix>[];

  @override
  Future<List<LocationFix>> read() async => List<LocationFix>.of(fixes);

  @override
  Future<void> write(List<LocationFix> f) async => fixes = List<LocationFix>.of(f);
}

class FamilyLocation extends ChangeNotifier {
  FamilyLocation({FamilySpace? space, LocationHistoryStore? history, DateTime Function()? now})
      : _space = space,
        _history = history ?? MemoryLocationHistoryStore(),
        _now = now ?? DateTime.now;

  static const String locations = 'locations';
  static const String places = 'places';

  static const Duration movingEvery = Duration(minutes: 2);
  static const Duration stillEvery = Duration(minutes: 15);
  static const Duration keepHistory = Duration(days: 7);

  /// Moving when this far from the last fix (metres).
  static const double movedMetres = 50;

  final FamilySpace? _space;
  final LocationHistoryStore _history;
  final DateTime Function() _now;
  int _seq = 0;
  List<LocationFix> _trail = <LocationFix>[];

  /// member/place id to inside, for arrive and leave.
  final Map<String, bool> _inside = <String, bool>{};

  /// For Undo: "collection/id" to the fields it had before.
  MapEntry<String, Map<String, Object?>?>? _undo;

  FamilySpace get space => _space ?? FamilySpace.instance;
  FamilyStore get store => space.store;
  String get me => space.identity?.deviceId ?? 'local';
  List<LocationFix> get trail => List<LocationFix>.unmodifiable(_trail);

  String memberName(String id) {
    final FamilyRecord? r = store.get(FamilySpace.members, id);
    return r == null ? 'Someone' : '${r.fields['name'] ?? 'Someone'}';
  }

  Future<void> load() async {
    try {
      _trail = await _history.read();
    } catch (_) {
      _trail = <LocationFix>[];
    }
    _prune();
    notifyListeners();
  }

  // ---- sharing ----

  bool get sharing => store.get(locations, me)?.fields['sharing'] == true;

  /// Turns sharing on or off for this phone's member. Off removes the
  /// shared position at once.
  void setSharing(bool on) {
    if (on == sharing) {
      return;
    }
    _write(locations, me, <String, Object?>{'sharing': on});
  }

  /// Takes a new fix: keeps it in the local trail and, when sharing,
  /// shares it. Returns how long to wait before the next fix.
  Future<Duration> report(LocationFix fix) async {
    final LocationFix? last = _trail.isEmpty ? null : _trail.last;
    _trail = <LocationFix>[..._trail, fix];
    _prune();
    try {
      await _history.write(_trail);
    } catch (_) {
      // Kept in memory; written next time.
    }
    if (sharing) {
      store.put(locations, me, <String, Object?>{'sharing': true, ...fix.toJson()});
    }
    notifyListeners();
    return nextInterval(last, fix);
  }

  /// Battery-aware: every 2 minutes while moving, 15 while still.
  static Duration nextInterval(LocationFix? last, LocationFix fix) {
    if (last == null) {
      return movingEvery;
    }
    return distanceMetres(last.lat, last.lng, fix.lat, fix.lng) >= movedMetres ? movingEvery : stillEvery;
  }

  void _prune() {
    final DateTime cutoff = _now().subtract(keepHistory);
    _trail = _trail.where((LocationFix f) => f.at.isAfter(cutoff)).toList();
  }

  /// Every member's shared state, this phone first.
  List<MemberLocation> get members {
    final List<MemberLocation> out = <MemberLocation>[];
    for (final FamilyRecord m in store.list(FamilySpace.members)) {
      final FamilyRecord? r = store.get(locations, m.id);
      final bool on = r?.fields['sharing'] == true;
      out.add(MemberLocation(m.id, on, on ? LocationFix.fromJson(r!.fields) : null));
    }
    out.sort((MemberLocation a, MemberLocation b) {
      if (a.member == me) {
        return -1;
      }
      if (b.member == me) {
        return 1;
      }
      return memberName(a.member).compareTo(memberName(b.member));
    });
    return out;
  }

  // ---- places ----

  List<FamilyPlace> get placeList => store.list(places).map(FamilyPlace.fromRecord).toList();

  FamilyPlace? addPlace(String name, double lat, double lng, {double radius = 150}) {
    final String n = name.trim();
    if (n.isEmpty) {
      return null;
    }
    final FamilyPlace p = FamilyPlace(
      id: '$me-${_now().microsecondsSinceEpoch}-${_seq++}',
      name: n,
      lat: lat,
      lng: lng,
      radius: radius,
    );
    _write(places, p.id, p.toFields());
    return p;
  }

  bool removePlace(String id) {
    if (store.get(places, id) == null) {
      return false;
    }
    _write(places, id, null);
    return true;
  }

  /// The place a fix is in, or null.
  FamilyPlace? placeOf(LocationFix f) {
    for (final FamilyPlace p in placeList) {
      if (p.contains(f)) {
        return p;
      }
    }
    return null;
  }

  /// Arrive and leave events since the last call, from everyone's shared
  /// positions. The first look at a member only records where they are.
  List<PlaceEvent> placeEvents() {
    final List<PlaceEvent> out = <PlaceEvent>[];
    final List<FamilyPlace> ps = placeList;
    for (final MemberLocation m in members) {
      final LocationFix? f = m.fix;
      if (f == null) {
        continue;
      }
      for (final FamilyPlace p in ps) {
        final String key = '${m.member}/${p.id}';
        final bool now = p.contains(f);
        final bool? before = _inside[key];
        _inside[key] = now;
        if (before != null && before != now) {
          out.add(PlaceEvent(member: m.member, place: p, arrived: now, at: f.at));
        }
      }
    }
    return out;
  }

  String eventText(PlaceEvent e) => '${memberName(e.member)} ${e.arrived ? 'arrived at' : 'left'} ${e.place.name}';

  // ---- undo and text ----

  bool undo() {
    final MapEntry<String, Map<String, Object?>?>? u = _undo;
    if (u == null) {
      return false;
    }
    _undo = null;
    final int i = u.key.indexOf('/');
    _set(u.key.substring(0, i), u.key.substring(i + 1), u.value);
    notifyListeners();
    return true;
  }

  void _write(String collection, String id, Map<String, Object?>? fields) {
    _undo = MapEntry<String, Map<String, Object?>?>('$collection/$id', store.get(collection, id)?.fields);
    _set(collection, id, fields);
    notifyListeners();
  }

  void _set(String collection, String id, Map<String, Object?>? fields) {
    if (fields == null) {
      store.delete(collection, id);
    } else {
      store.put(collection, id, fields);
    }
  }

  static String _hm(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  /// One line per member: where and when, for the list and for sharing.
  String lineFor(MemberLocation m) {
    final LocationFix? f = m.fix;
    if (!m.sharing || f == null) {
      return m.sharing ? 'Waiting for a first fix' : 'Not sharing';
    }
    final FamilyPlace? p = placeOf(f);
    final String where = p != null ? 'At ${p.name}' : '${f.lat.toStringAsFixed(4)}, ${f.lng.toStringAsFixed(4)}';
    return '$where · ${_hm(f.at)}';
  }

  String toText() {
    final StringBuffer b = StringBuffer('Family locations\n');
    for (final MemberLocation m in members) {
      b.write('${memberName(m.member)}: ${lineFor(m)}\n');
    }
    return b.toString();
  }

  static FamilyLocation instance = FamilyLocation();

  static void install(FamilyLocation l) => instance = l;
}

/// Gets one position from the phone; null when off or not allowed.
abstract class PositionSource {
  Future<LocationFix?> current();
}

abstract class PlaceEventSink {
  Future<void> notify(String text);
}

/// Takes fixes while the app runs, at the pace [FamilyLocation.report]
/// asks for, and turns everyone's moves into arrive/leave notifications.
class LocationTracker {
  LocationTracker({required this.location, required this.source, required this.sink});

  final FamilyLocation location;
  final PositionSource source;
  final PlaceEventSink sink;
  Timer? _timer;

  void start() {
    location.store.addListener(_onStore);
    _schedule(Duration.zero);
  }

  void stop() {
    location.store.removeListener(_onStore);
    _timer?.cancel();
    _timer = null;
  }

  void _onStore() {
    for (final PlaceEvent e in location.placeEvents()) {
      if (e.member != location.me) {
        unawaited(sink.notify(location.eventText(e)).catchError((Object _) {}));
      }
    }
  }

  void _schedule(Duration d) {
    _timer?.cancel();
    _timer = Timer(d, () => unawaited(tick()));
  }

  Future<void> tick() async {
    Duration next = FamilyLocation.stillEvery;
    if (location.sharing) {
      LocationFix? f;
      try {
        f = await source.current();
      } catch (_) {
        f = null;
      }
      if (f != null) {
        next = await location.report(f);
      }
    }
    if (_timer != null) {
      _schedule(next);
    }
  }

  static LocationTracker? instance;
}
