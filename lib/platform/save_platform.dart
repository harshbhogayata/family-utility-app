import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../engines/share/save_anywhere.dart';

/// Real folders for feature 064. Writes with dart:io; nothing leaves the phone.
class SystemSavePlatform implements SavePlatform {
  const SystemSavePlatform();

  @override
  Future<String> filesFolder() async {
    final Directory base = await getApplicationDocumentsDirectory();
    return '${base.path}/Saved';
  }

  @override
  Future<String> downloadsFolder() async {
    if (Platform.isAndroid) {
      const String shared = '/storage/emulated/0/Download';
      if (Directory(shared).existsSync()) {
        return shared;
      }
    }
    // iOS has no shared Downloads: the app's Documents show in the Files app.
    final Directory? d = await getDownloadsDirectory();
    if (d != null) {
      return d.path;
    }
    return (await getApplicationDocumentsDirectory()).path;
  }

  @override
  Future<String?> pickFolder({String? initialFolder}) {
    return FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Save to this folder',
      initialDirectory: initialFolder,
    );
  }

  @override
  Future<bool> exists(String path) async => File(path).existsSync();

  @override
  Future<void> write(String path, Uint8List bytes) async {
    final File f = File(path);
    await f.parent.create(recursive: true);
    await f.writeAsBytes(bytes, flush: true);
  }
}

class PrefsSaveChoiceStore implements SaveChoiceStore {
  const PrefsSaveChoiceStore();

  static const String _key = 'save_anywhere_choices';

  @override
  Future<String?> read() async => (await SharedPreferences.getInstance()).getString(_key);

  @override
  Future<void> write(String json) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, json);
  }
}
