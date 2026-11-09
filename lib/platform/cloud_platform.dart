import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../engines/share/cloud_bridge.dart';

/// The system document picker through file_picker (Storage Access Framework
/// on Android, UIDocumentPicker on iOS): cloud providers show up there.
class SystemDocumentPicker implements DocumentPicker {
  const SystemDocumentPicker();

  @override
  Future<List<PickedDocument>> open({bool multiple = true}) async {
    final FilePickerResult? r = await FilePicker.platform.pickFiles(allowMultiple: multiple, withData: true);
    final List<PickedDocument> out = <PickedDocument>[];
    for (final PlatformFile f in r?.files ?? const <PlatformFile>[]) {
      final Uint8List? data = f.bytes ?? (f.path == null ? null : await File(f.path!).readAsBytes());
      if (data != null) {
        out.add(PickedDocument(f.name, data));
      }
    }
    return out;
  }

  @override
  Future<String?> saveAs(String name, Uint8List bytes) =>
      FilePicker.platform.saveFile(dialogTitle: 'Save to', fileName: name, bytes: bytes);
}

class FolderImportSink implements ImportSink {
  const FolderImportSink();

  @override
  Future<String> write(String name, Uint8List bytes) async {
    final Directory base = await getApplicationDocumentsDirectory();
    final Directory dir = Directory('${base.path}/imported');
    await dir.create(recursive: true);
    String path = '${dir.path}/$name';
    int i = 2;
    while (File(path).existsSync()) {
      final int dot = name.lastIndexOf('.');
      path = dot > 0 ? '${dir.path}/${name.substring(0, dot)} ($i)${name.substring(dot)}' : '${dir.path}/$name ($i)';
      i++;
    }
    await File(path).writeAsBytes(bytes, flush: true);
    return path;
  }

  @override
  Future<void> remove(String path) async {
    final File f = File(path);
    if (f.existsSync()) {
      await f.delete();
    }
  }
}

class PrefsCloudStore implements CloudPrefsStore {
  const PrefsCloudStore();

  static const String _key = 'cloud_bridge';

  @override
  Future<String?> read() async => (await SharedPreferences.getInstance()).getString(_key);

  @override
  Future<void> write(String value) async {
    await (await SharedPreferences.getInstance()).setString(_key, value);
  }
}
