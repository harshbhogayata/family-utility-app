import 'package:shared_preferences/shared_preferences.dart';

import '../engines/privacy/on_device_mode.dart';

/// Remembers the on-device switch in the app's own preferences file.
class PrefsOnDeviceModeStore implements OnDeviceModeStore {
  const PrefsOnDeviceModeStore();

  static const String _key = 'on_device_mode';

  @override
  Future<bool?> read() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key);
  }

  @override
  Future<void> write(bool on) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, on);
  }
}
