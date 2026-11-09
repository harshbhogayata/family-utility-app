import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../engines/download/clipboard_watch.dart';

/// Feature 126 — the system clipboard, read only while the watch is on and
/// the app is in front (Android 10+ allows nothing else).
class SystemClipboardTextSource implements ClipboardTextSource {
  const SystemClipboardTextSource();

  @override
  Future<String?> readText() async {
    if (!await Clipboard.hasStrings()) {
      return null;
    }
    final ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
    return data?.text;
  }
}

class PrefsClipboardWatchStore implements ClipboardWatchStore {
  const PrefsClipboardWatchStore();

  static const String _key = 'clipboard_link_watch_on';

  @override
  Future<bool> readEnabled() async => (await SharedPreferences.getInstance()).getBool(_key) ?? false;

  @override
  Future<void> writeEnabled(bool enabled) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, enabled);
  }
}
