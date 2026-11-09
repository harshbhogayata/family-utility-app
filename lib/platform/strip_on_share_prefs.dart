import 'package:shared_preferences/shared_preferences.dart';

import '../engines/image/exif_strip.dart';

/// Feature 046 — "always strip on share", kept on the phone.
class PrefsStripOnShareStore implements StripOnShareStore {
  const PrefsStripOnShareStore();

  static const String _key = 'strip_exif_on_share';

  @override
  Future<bool> read() async => (await SharedPreferences.getInstance()).getBool(_key) ?? false;

  @override
  Future<void> write(bool on) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, on);
  }
}
