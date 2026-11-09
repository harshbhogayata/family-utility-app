import 'package:shared_preferences/shared_preferences.dart';

import '../engines/family/member_profiles.dart';

/// Keeps the member profiles in the app's own preferences file, on the phone.
class PrefsProfileStore implements ProfileStore {
  const PrefsProfileStore();

  static const String _key = 'member_profiles';

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
