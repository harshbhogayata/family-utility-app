import 'package:shared_preferences/shared_preferences.dart';

import '../engines/download/video_link.dart';

/// Feature 123 — "the personal-use notice was shown", kept on the phone.
class PrefsNoticeStore implements NoticeStore {
  const PrefsNoticeStore();

  static const String _key = 'video_link_notice_shown';

  @override
  Future<bool> read() async => (await SharedPreferences.getInstance()).getBool(_key) ?? false;

  @override
  Future<void> write(bool shown) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, shown);
  }
}
