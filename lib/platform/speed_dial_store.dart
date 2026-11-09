import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../engines/platform/home_widgets.dart';

/// Feature 112 — the widget's speed-dial numbers in the app's own preferences.
class PrefsSpeedDialStore implements SpeedDialStore {
  const PrefsSpeedDialStore();

  static const String _key = 'widget_speed_dial';

  @override
  Future<List<SpeedDialEntry>> load() async {
    final String? raw = (await SharedPreferences.getInstance()).getString(_key);
    if (raw == null) {
      return <SpeedDialEntry>[];
    }
    try {
      final Object? list = jsonDecode(raw);
      if (list is! List) {
        return <SpeedDialEntry>[];
      }
      final List<SpeedDialEntry> out = <SpeedDialEntry>[];
      for (final Object? o in list) {
        final SpeedDialEntry? e = SpeedDialEntry.fromJson(o);
        if (e != null) {
          out.add(e);
        }
      }
      return out;
    } catch (_) {
      return <SpeedDialEntry>[];
    }
  }

  @override
  Future<void> save(List<SpeedDialEntry> entries) async {
    final String raw = jsonEncode(entries.map((SpeedDialEntry e) => e.toJson()).toList());
    await (await SharedPreferences.getInstance()).setString(_key, raw);
  }
}
