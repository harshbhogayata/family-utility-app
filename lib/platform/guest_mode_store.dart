import 'package:shared_preferences/shared_preferences.dart';

import '../engines/platform/guest_mode.dart';

class PrefsGuestModeStore implements GuestModeStore {
  const PrefsGuestModeStore();

  static const String _key = 'guest_mode';

  @override
  Future<String?> read() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key);
  }

  @override
  Future<void> write(String json) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, json);
  }
}
