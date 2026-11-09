import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Feature 112 — home-screen widget and quick-settings tile.
///
/// The app writes a small flat snapshot (next medicine, speed-dial numbers)
/// that the native widget reads from the phone's own storage; nothing leaves
/// the phone. Taps on the widget or tile open the app with an action name.

/// What a widget, tile or lock-screen widget can start.
enum WidgetAction {
  scan('scan', 'Scan', 'document-scanner'),
  paste('paste', 'Paste', null),
  speedDial('speed-dial', 'Speed dial', null),
  nextMedicine('medicine', 'Next medicine', 'medicine-reminders');

  const WidgetAction(this.id, this.label, this.toolId);

  /// Stable name used in the launch link and by the native side.
  final String id;
  final String label;

  /// Tool opened in the app for this action, when one is registered.
  final String? toolId;

  static WidgetAction? byId(String? id) {
    for (final WidgetAction a in WidgetAction.values) {
      if (a.id == id) {
        return a;
      }
    }
    return null;
  }
}

/// Launch links: `familyapp://widget/<action>`. Native code passes either the
/// whole link or the bare action name.
class WidgetLaunch {
  WidgetLaunch._();

  static const String scheme = 'familyapp';
  static const String host = 'widget';

  static String linkFor(WidgetAction a) => '$scheme://$host/${a.id}';

  static WidgetAction? parse(String? raw) {
    if (raw == null) {
      return null;
    }
    final String s = raw.trim();
    if (s.isEmpty) {
      return null;
    }
    final WidgetAction? bare = WidgetAction.byId(s);
    if (bare != null) {
      return bare;
    }
    final Uri? u = Uri.tryParse(s);
    if (u == null) {
      return null;
    }
    if (u.scheme == scheme) {
      if (u.host != host || u.pathSegments.isEmpty) {
        return null;
      }
      return WidgetAction.byId(u.pathSegments.first);
    }
    // iOS deep links reach Flutter as a route: "/scan" (host dropped) or
    // "/widget/scan".
    if (u.hasScheme || !s.startsWith('/')) {
      return null;
    }
    final List<String> parts = u.pathSegments.where((String p) => p.isNotEmpty).toList();
    if (parts.length == 1) {
      return WidgetAction.byId(parts.first);
    }
    if (parts.length == 2 && parts.first == host) {
      return WidgetAction.byId(parts[1]);
    }
    return null;
  }
}

/// One planned dose, supplied by medicine reminders (088) when it lands.
@immutable
class MedicineDose {
  const MedicineDose({required this.name, required this.at, this.member = ''});

  final String name;
  final DateTime at;
  final String member;
}

/// One number on the speed-dial row.
@immutable
class SpeedDialEntry {
  const SpeedDialEntry({required this.label, required this.number});

  final String label;
  final String number;

  /// Digits and a leading + only, as the dialler wants.
  String get dialable {
    final StringBuffer b = StringBuffer();
    final String t = number.trim();
    for (int i = 0; i < t.length; i++) {
      final String c = t[i];
      if ((c == '+' && b.isEmpty) || '0123456789'.contains(c)) {
        b.write(c);
      }
    }
    return b.toString();
  }

  bool get isValid => label.trim().isNotEmpty && dialable.replaceAll('+', '').length >= 3;

  Map<String, String> toJson() => <String, String>{'label': label, 'number': number};

  static SpeedDialEntry? fromJson(Object? o) {
    if (o is! Map) {
      return null;
    }
    final Object? l = o['label'];
    final Object? n = o['number'];
    if (l is! String || n is! String) {
      return null;
    }
    return SpeedDialEntry(label: l, number: n);
  }

  @override
  bool operator ==(Object other) => other is SpeedDialEntry && other.label == label && other.number == number;

  @override
  int get hashCode => Object.hash(label, number);
}

/// What the widget shows. Flattened to string keys the native side reads.
@immutable
class WidgetSnapshot {
  const WidgetSnapshot({
    required this.medicineTitle,
    required this.medicineDetail,
    required this.speedDial,
    required this.updatedAt,
  });

  static const int maxSpeedDial = 3;

  final String medicineTitle;
  final String medicineDetail;
  final List<SpeedDialEntry> speedDial;
  final DateTime updatedAt;

  /// The first dose at or after [now], else a quiet "nothing due".
  static WidgetSnapshot build({
    required DateTime now,
    List<MedicineDose> doses = const <MedicineDose>[],
    List<SpeedDialEntry> speedDial = const <SpeedDialEntry>[],
  }) {
    MedicineDose? next;
    for (final MedicineDose d in doses) {
      if (d.at.isBefore(now)) {
        continue;
      }
      if (next == null || d.at.isBefore(next.at)) {
        next = d;
      }
    }
    final List<SpeedDialEntry> dial =
        speedDial.where((SpeedDialEntry e) => e.isValid).take(maxSpeedDial).toList(growable: false);
    if (next == null) {
      return WidgetSnapshot(
        medicineTitle: 'No medicine due',
        medicineDetail: '',
        speedDial: dial,
        updatedAt: now,
      );
    }
    final String who = next.member.trim().isEmpty ? '' : ' · ${next.member.trim()}';
    return WidgetSnapshot(
      medicineTitle: next.name,
      medicineDetail: '${whenText(next.at, now)}$who',
      speedDial: dial,
      updatedAt: now,
    );
  }

  /// "8:05 am", "Tomorrow 8:05 am" or "12 Nov 8:05 am".
  static String whenText(DateTime at, DateTime now) {
    final int h12 = at.hour % 12 == 0 ? 12 : at.hour % 12;
    final String time = '$h12:${at.minute.toString().padLeft(2, '0')} ${at.hour < 12 ? 'am' : 'pm'}';
    final DateTime today = DateTime(now.year, now.month, now.day);
    final DateTime day = DateTime(at.year, at.month, at.day);
    final int diff = day.difference(today).inDays;
    if (diff == 0) {
      return time;
    }
    if (diff == 1) {
      return 'Tomorrow $time';
    }
    const List<String> months = <String>[
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${at.day} ${months[at.month - 1]} $time';
  }

  Map<String, String> toMap() {
    final Map<String, String> m = <String, String>{
      'medicine_title': medicineTitle,
      'medicine_detail': medicineDetail,
      'dial_count': '${speedDial.length}',
      'updated_at': updatedAt.toIso8601String(),
    };
    for (int i = 0; i < maxSpeedDial; i++) {
      final SpeedDialEntry? e = i < speedDial.length ? speedDial[i] : null;
      m['dial_${i}_label'] = e?.label ?? '';
      m['dial_${i}_number'] = e?.dialable ?? '';
    }
    return m;
  }

  /// Plain text for Share / Save.
  String describe() {
    final StringBuffer b = StringBuffer()
      ..writeln('Home widget')
      ..writeln('Next medicine: $medicineTitle${medicineDetail.isEmpty ? '' : ' ($medicineDetail)'}');
    if (speedDial.isEmpty) {
      b.writeln('Speed dial: none');
    } else {
      for (final SpeedDialEntry e in speedDial) {
        b.writeln('Speed dial: ${e.label} ${e.dialable}');
      }
    }
    b.writeln('Buttons: Scan, Paste');
    return b.toString();
  }
}

/// The native widget/tile side.
abstract class WidgetBridge {
  /// Hands the snapshot to the widget and asks it to redraw.
  Future<bool> publish(Map<String, String> data);

  /// The action the app was opened with, once.
  Future<String?> initialAction();

  /// Called when a widget or tile is tapped while the app runs.
  set onAction(void Function(String raw)? f);
}

/// `app.family/home_widget`: `publish`, `initialAction`, and `action` calls
/// from the platform. Quietly does nothing where there is no platform side.
class ChannelWidgetBridge implements WidgetBridge {
  ChannelWidgetBridge();

  static const String channelName = 'app.family/home_widget';
  static const MethodChannel channel = MethodChannel(channelName);

  void Function(String raw)? _onAction;

  @override
  set onAction(void Function(String raw)? f) {
    _onAction = f;
    try {
      channel.setMethodCallHandler((MethodCall call) async {
        if (call.method == 'action' && call.arguments is String) {
          _onAction?.call(call.arguments as String);
          return null;
        }
        throw MissingPluginException('No handler for ${call.method}');
      });
    } catch (_) {
      // No binding (tests).
    }
  }

  @override
  Future<bool> publish(Map<String, String> data) async {
    try {
      return await channel.invokeMethod<bool>('publish', data) ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<String?> initialAction() async {
    try {
      return await channel.invokeMethod<String>('initialAction');
    } catch (_) {
      return null;
    }
  }
}

/// In-memory bridge for tests.
class MemoryWidgetBridge implements WidgetBridge {
  MemoryWidgetBridge({this.initial});

  String? initial;
  final List<Map<String, String>> published = <Map<String, String>>[];
  void Function(String raw)? handler;

  @override
  set onAction(void Function(String raw)? f) => handler = f;

  @override
  Future<bool> publish(Map<String, String> data) async {
    published.add(Map<String, String>.of(data));
    return true;
  }

  @override
  Future<String?> initialAction() async {
    final String? s = initial;
    initial = null;
    return s;
  }

  void tap(WidgetAction a) => handler?.call(WidgetLaunch.linkFor(a));
}

/// Where the speed-dial list is kept.
abstract class SpeedDialStore {
  Future<List<SpeedDialEntry>> load();
  Future<void> save(List<SpeedDialEntry> entries);
}

class MemorySpeedDialStore implements SpeedDialStore {
  List<SpeedDialEntry> saved = <SpeedDialEntry>[];

  @override
  Future<List<SpeedDialEntry>> load() async => List<SpeedDialEntry>.of(saved);

  @override
  Future<void> save(List<SpeedDialEntry> entries) async => saved = List<SpeedDialEntry>.of(entries);
}

/// Supplies upcoming doses; medicine reminders (088) plugs in here.
typedef DoseSource = Future<List<MedicineDose>> Function();

/// Keeps the widget in step with the app and routes taps.
class HomeWidgets extends ChangeNotifier {
  HomeWidgets({
    required this.bridge,
    required this.store,
    DoseSource? doses,
    DateTime Function()? clock,
  })  : _doses = doses,
        _clock = clock ?? DateTime.now;

  final WidgetBridge bridge;
  final SpeedDialStore store;
  DoseSource? _doses;
  final DateTime Function() _clock;

  List<SpeedDialEntry> _dial = <SpeedDialEntry>[];
  WidgetSnapshot? _last;
  bool _published = false;

  List<SpeedDialEntry> get speedDial => List<SpeedDialEntry>.unmodifiable(_dial);
  WidgetSnapshot? get snapshot => _last;

  /// True once the platform accepted a snapshot (false in tests / web).
  bool get published => _published;

  /// Called with each action from a widget or tile.
  void Function(WidgetAction action)? onAction;

  set doseSource(DoseSource? s) {
    _doses = s;
  }

  Future<void> load() async {
    try {
      _dial = (await store.load()).where((SpeedDialEntry e) => e.isValid).toList();
    } catch (_) {
      _dial = <SpeedDialEntry>[];
    }
    await refresh();
  }

  /// Rebuilds the snapshot and hands it to the widget.
  Future<WidgetSnapshot> refresh() async {
    List<MedicineDose> doses = const <MedicineDose>[];
    final DoseSource? s = _doses;
    if (s != null) {
      try {
        doses = await s();
      } catch (_) {
        doses = const <MedicineDose>[];
      }
    }
    final WidgetSnapshot snap = WidgetSnapshot.build(now: _clock(), doses: doses, speedDial: _dial);
    _last = snap;
    _published = await bridge.publish(snap.toMap());
    notifyListeners();
    return snap;
  }

  /// Adds a number; false when invalid, a duplicate, or the row is full.
  Future<bool> addSpeedDial(SpeedDialEntry e) async {
    if (!e.isValid || _dial.length >= WidgetSnapshot.maxSpeedDial) {
      return false;
    }
    if (_dial.any((SpeedDialEntry x) => x.dialable == e.dialable)) {
      return false;
    }
    return setSpeedDial(<SpeedDialEntry>[..._dial, e]);
  }

  Future<bool> removeSpeedDial(int index) async {
    if (index < 0 || index >= _dial.length) {
      return false;
    }
    final List<SpeedDialEntry> next = List<SpeedDialEntry>.of(_dial)..removeAt(index);
    return setSpeedDial(next);
  }

  Future<bool> setSpeedDial(List<SpeedDialEntry> entries) async {
    _dial = entries.where((SpeedDialEntry e) => e.isValid).take(WidgetSnapshot.maxSpeedDial).toList();
    await store.save(_dial);
    await refresh();
    return true;
  }

  /// Hooks the bridge up and delivers the action the app was opened with.
  Future<void> attach() async {
    bridge.onAction = handleRaw;
    final String? first = await bridge.initialAction();
    if (first != null) {
      handleRaw(first);
    }
  }

  /// iOS: widget taps arrive as deep links pushed to the app as routes.
  /// Returns true when [route] was a widget link and has been handled.
  bool handleRoute(String route) => handleRaw(route) != null;

  WidgetAction? handleRaw(String raw) {
    final WidgetAction? a = WidgetLaunch.parse(raw);
    if (a != null) {
      onAction?.call(a);
    }
    return a;
  }

  static HomeWidgets? _instance;

  static HomeWidgets get instance =>
      _instance ??= HomeWidgets(bridge: MemoryWidgetBridge(), store: MemorySpeedDialStore());

  static void install(HomeWidgets w) => _instance = w;
}
