import 'package:shared_preferences/shared_preferences.dart';

import '../engines/image/scan_namer.dart';

/// 053: the scan name pattern in the app's preferences.
class PrefsScanNamePatternStore implements ScanNamePatternStore {
  const PrefsScanNamePatternStore();

  static const String _key = 'scan_name_pattern';

  @override
  Future<String?> read() async => (await SharedPreferences.getInstance()).getString(_key);

  @override
  Future<void> write(String pattern) async => (await SharedPreferences.getInstance()).setString(_key, pattern);
}
