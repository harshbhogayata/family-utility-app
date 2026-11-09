import 'package:shared_preferences/shared_preferences.dart';

import '../engines/share/open_with.dart';

/// Feature 065: the default-app card is answered once, then never shown.
class PrefsDefaultAppPromptStore implements DefaultAppPromptStore {
  const PrefsDefaultAppPromptStore();

  static const String _key = 'default_app_prompt_done';

  @override
  Future<bool> readDismissed() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key) ?? false;
  }

  @override
  Future<void> writeDismissed() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, true);
  }
}
