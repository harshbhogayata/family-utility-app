import 'package:shared_preferences/shared_preferences.dart';

import '../engines/platform/first_run.dart';

class PrefsFirstRunStore implements FirstRunStore {
  const PrefsFirstRunStore();

  static const String _key = 'welcome_done';

  @override
  Future<bool> readWelcomeDone() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key) ?? false;
  }

  @override
  Future<void> writeWelcomeDone() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, true);
  }
}
