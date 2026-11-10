import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../engines/security/secure_notes.dart';

/// 097: the encrypted Wi-Fi and devices list, in the app's private folder.
class FileWifiDevicesBlobStore implements NoteBlobStore {
  const FileWifiDevicesBlobStore();

  Future<File> _file() async {
    final Directory dir = await getApplicationSupportDirectory();
    return File('${dir.path}${Platform.pathSeparator}wifi_devices.enc');
  }

  @override
  Future<String?> read() async {
    final File f = await _file();
    if (!await f.exists()) {
      return null;
    }
    return f.readAsString();
  }

  @override
  Future<void> write(String blob) async {
    final File f = await _file();
    await f.writeAsString(blob, flush: true);
  }
}
