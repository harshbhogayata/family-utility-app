import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../platform/home_layout.dart';
import '../platform/tool_order.dart';
import '../security/app_lock.dart';

/// Feature 069 — Profile per member.
///
/// One install, several people. Each profile keeps its own recents,
/// favourites, language choice and an optional PIN that guards switching
/// into it. Everything lives on the phone; nothing here is ever sent
/// anywhere, and there is no account behind a profile.

/// Languages a profile can pick. The UI strings follow in feature 110;
/// until then the choice is kept so it is ready when they land.
abstract final class ProfileLanguages {
  static const Map<String, String> names = <String, String>{
    'en': 'English',
    'hi': 'हिन्दी (Hindi)',
    'ta': 'தமிழ் (Tamil)',
    'te': 'తెలుగు (Telugu)',
    'bn': 'বাংলা (Bengali)',
    'mr': 'मराठी (Marathi)',
    'gu': 'ગુજરાતી (Gujarati)',
  };

  static String nameOf(String code) => names[code] ?? names['en']!;

  static bool isKnown(String code) => names.containsKey(code);
}

class MemberProfile {
  const MemberProfile({
    required this.id,
    required this.name,
    this.language = 'en',
    this.pinHash,
    this.pinSalt,
    this.recents = const <String>[],
    this.favourites = const <String>[],
    this.arranged = const <String>[],
    this.hidden = const <String>[],
  });

  final String id;
  final String name;
  final String language;
  final String? pinHash;
  final String? pinSalt;

  /// Tool ids, most recent first.
  final List<String> recents;

  /// Tool ids in the order they were starred.
  final List<String> favourites;

  /// The member's own order for unpinned tools on home; empty = default (116).
  final List<String> arranged;

  /// Tools this member hid from home (116).
  final List<String> hidden;

  HomeLayout get layout => HomeLayout(pinned: favourites, arranged: arranged, hidden: hidden);

  bool get hasPin => pinHash != null && pinSalt != null;

  String get initial => name.trim().isEmpty ? '?' : name.trim().substring(0, 1).toUpperCase();

  MemberProfile copyWith({
    String? name,
    String? language,
    String? pinHash,
    String? pinSalt,
    bool clearPin = false,
    List<String>? recents,
    List<String>? favourites,
    List<String>? arranged,
    List<String>? hidden,
  }) {
    return MemberProfile(
      id: id,
      name: name ?? this.name,
      language: language ?? this.language,
      pinHash: clearPin ? null : (pinHash ?? this.pinHash),
      pinSalt: clearPin ? null : (pinSalt ?? this.pinSalt),
      recents: recents ?? this.recents,
      favourites: favourites ?? this.favourites,
      arranged: arranged ?? this.arranged,
      hidden: hidden ?? this.hidden,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'name': name,
        'language': language,
        'pinHash': pinHash,
        'pinSalt': pinSalt,
        'recents': recents,
        'favourites': favourites,
        'arranged': arranged,
        'hidden': hidden,
      };

  static MemberProfile fromJson(Map<String, Object?> json) {
    List<String> strings(Object? v) =>
        v is List ? v.whereType<String>().toList() : const <String>[];
    final String lang = json['language'] as String? ?? 'en';
    return MemberProfile(
      id: json['id'] as String? ?? 'me',
      name: json['name'] as String? ?? 'Me',
      language: ProfileLanguages.isKnown(lang) ? lang : 'en',
      pinHash: json['pinHash'] as String?,
      pinSalt: json['pinSalt'] as String?,
      recents: strings(json['recents']),
      favourites: strings(json['favourites']),
      arranged: strings(json['arranged']),
      hidden: strings(json['hidden']),
    );
  }
}

abstract class ProfileStore {
  Future<String?> read();

  Future<void> write(String json);
}

class MemoryProfileStore implements ProfileStore {
  MemoryProfileStore([this.value]);

  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String json) async => value = json;
}

enum SwitchOutcome { switched, needsPin, wrongPin, unknown }

class MemberProfiles extends ChangeNotifier {
  MemberProfiles(this._store, {String Function()? newId}) : _newId = newId ?? _defaultId;

  final ProfileStore _store;
  final String Function() _newId;

  static const int maxRecents = 8;
  static const int maxProfiles = 8;
  static const MemberProfile starter = MemberProfile(id: 'me', name: 'Me');

  List<MemberProfile> _profiles = <MemberProfile>[starter];
  String _activeId = starter.id;

  static int _counter = 0;
  static String _defaultId() {
    _counter++;
    return 'p${DateTime.now().microsecondsSinceEpoch}_$_counter';
  }

  List<MemberProfile> get profiles => List<MemberProfile>.unmodifiable(_profiles);

  MemberProfile get active =>
      _profiles.firstWhere((MemberProfile p) => p.id == _activeId, orElse: () => _profiles.first);

  MemberProfile? byId(String id) {
    for (final MemberProfile p in _profiles) {
      if (p.id == id) {
        return p;
      }
    }
    return null;
  }

  bool get canAdd => _profiles.length < maxProfiles;

  Future<void> load() async {
    try {
      final String? text = await _store.read();
      if (text == null || text.isEmpty) {
        return;
      }
      final Object? data = jsonDecode(text);
      if (data is! Map) {
        return;
      }
      final Object? list = data['profiles'];
      final List<MemberProfile> loaded = <MemberProfile>[];
      if (list is List) {
        for (final Object? item in list) {
          if (item is Map) {
            loaded.add(MemberProfile.fromJson(Map<String, Object?>.from(item)));
          }
        }
      }
      if (loaded.isEmpty) {
        return;
      }
      _profiles = loaded;
      final String? activeId = data['active'] as String?;
      _activeId = byId(activeId ?? '') != null ? activeId! : loaded.first.id;
      notifyListeners();
    } catch (_) {
      // A broken file leaves the starter profile; nothing else is lost.
    }
  }

  String encode() => jsonEncode(<String, Object?>{
        'active': _activeId,
        'profiles': _profiles.map((MemberProfile p) => p.toJson()).toList(),
      });

  Future<void> _save() async {
    notifyListeners();
    try {
      await _store.write(encode());
    } catch (_) {
      // Kept in memory for this session at worst.
    }
  }

  void _replace(MemberProfile p) {
    _profiles = _profiles.map((MemberProfile x) => x.id == p.id ? p : x).toList();
  }

  /// Adds a member. Returns null when the name is blank or the list is full.
  Future<MemberProfile?> add(String name, {String language = 'en'}) async {
    final String clean = name.trim();
    if (clean.isEmpty || !canAdd) {
      return null;
    }
    final MemberProfile p = MemberProfile(
      id: _newId(),
      name: clean,
      language: ProfileLanguages.isKnown(language) ? language : 'en',
    );
    _profiles = <MemberProfile>[..._profiles, p];
    await _save();
    return p;
  }

  Future<void> rename(String id, String name) async {
    final MemberProfile? p = byId(id);
    final String clean = name.trim();
    if (p == null || clean.isEmpty) {
      return;
    }
    _replace(p.copyWith(name: clean));
    await _save();
  }

  /// Removes a member; the last profile always stays.
  Future<bool> remove(String id) async {
    if (_profiles.length <= 1 || byId(id) == null) {
      return false;
    }
    _profiles = _profiles.where((MemberProfile p) => p.id != id).toList();
    if (_activeId == id) {
      _activeId = _profiles.first.id;
    }
    await _save();
    return true;
  }

  /// Switches to [id]. A profile with a PIN asks for it first.
  Future<SwitchOutcome> switchTo(String id, {String? pin}) async {
    final MemberProfile? p = byId(id);
    if (p == null) {
      return SwitchOutcome.unknown;
    }
    if (p.id != _activeId && p.hasPin) {
      if (pin == null) {
        return SwitchOutcome.needsPin;
      }
      if (!PinHasher.verify(pin, p.pinSalt!, p.pinHash!)) {
        return SwitchOutcome.wrongPin;
      }
    }
    _activeId = p.id;
    await _save();
    return SwitchOutcome.switched;
  }

  Future<bool> setPin(String id, String pin) async {
    final MemberProfile? p = byId(id);
    if (p == null || !PinHasher.isValidPin(pin)) {
      return false;
    }
    final String salt = PinHasher.newSalt();
    _replace(p.copyWith(pinSalt: salt, pinHash: PinHasher.hash(pin, salt)));
    await _save();
    return true;
  }

  Future<void> clearPin(String id) async {
    final MemberProfile? p = byId(id);
    if (p == null) {
      return;
    }
    _replace(p.copyWith(clearPin: true));
    await _save();
  }

  Future<void> setLanguage(String id, String code) async {
    final MemberProfile? p = byId(id);
    if (p == null || !ProfileLanguages.isKnown(code)) {
      return;
    }
    _replace(p.copyWith(language: code));
    await _save();
  }

  /// Notes that the active member opened [toolId].
  Future<void> recordRecent(String toolId) async {
    final MemberProfile p = active;
    final List<String> next = <String>[toolId, ...p.recents.where((String t) => t != toolId)];
    _replace(p.copyWith(recents: next.take(maxRecents).toList()));
    await _save();
  }

  Future<void> clearRecents() async {
    _replace(active.copyWith(recents: const <String>[]));
    await _save();
  }

  bool isFavourite(String toolId) => active.favourites.contains(toolId);

  /// Pins or unpins [toolId]. Pinning a hidden tool shows it again (116).
  Future<void> toggleFavourite(String toolId) => setLayout(active.layout.togglePinned(toolId));

  /// Moves a pinned tool to [index] in the active member's pins (115).
  Future<void> movePin(String toolId, int index) async {
    final MemberProfile p = active;
    _replace(p.copyWith(favourites: ToolOrder.move(p.favourites, toolId, index)));
    await _save();
  }

  /// The active member's home layout: pins, own order, hidden tools (116).
  HomeLayout get layout => active.layout;

  /// Replaces the active member's home layout (116).
  Future<void> setLayout(HomeLayout layout) async {
    _replace(active.copyWith(
      favourites: List<String>.of(layout.pinned),
      arranged: List<String>.of(layout.arranged),
      hidden: List<String>.of(layout.hidden),
    ));
    await _save();
  }

  /// The home grid order for the active member: pinned first, then their own
  /// order (or recents when they never arranged), hidden tools left out.
  List<String> orderTools(List<String> all) => active.layout.visible(all: all, recents: active.recents);

  /// Every tool in home order, hidden ones included (the 116 editor).
  List<String> fullToolOrder(List<String> all) => active.layout.fullOrder(all: all, recents: active.recents);

  static MemberProfiles instance = MemberProfiles(MemoryProfileStore());

  static void install(MemberProfiles profiles) {
    instance = profiles;
  }
}
