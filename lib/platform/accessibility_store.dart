import 'package:shared_preferences/shared_preferences.dart';

import '../engines/platform/accessibility.dart';

/// Feature 109 — accessibility choices in the app's own preferences.
class PrefsAccessibilityStore implements AccessibilityStore {
  const PrefsAccessibilityStore();

  static const String _key = 'accessibility';

  @override
  Future<String?> read() async => (await SharedPreferences.getInstance()).getString(_key);

  @override
  Future<void> write(String value) async => (await SharedPreferences.getInstance()).setString(_key, value);
}
