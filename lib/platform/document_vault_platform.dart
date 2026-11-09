import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:image/image.dart' as img;

import '../engines/family/document_vault.dart';
import '../engines/image/redact.dart';

/// Feature 074 — encrypted document files in an app-private folder.
class FileDocumentBlobStore implements DocumentBlobStore {
  const FileDocumentBlobStore(this.folder);

  final Future<Directory> Function() folder;

  Future<File> _file(String id) async {
    final Directory d = await folder();
    if (!await d.exists()) {
      await d.create(recursive: true);
    }
    return File('${d.path}/${id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')}.bin');
  }

  @override
  Future<Uint8List?> read(String id) async {
    final File f = await _file(id);
    return await f.exists() ? f.readAsBytes() : null;
  }

  @override
  Future<void> write(String id, Uint8List data) async => (await _file(id)).writeAsBytes(data, flush: true);

  @override
  Future<void> delete(String id) async {
    final File f = await _file(id);
    if (await f.exists()) {
      await f.delete();
    }
  }
}

/// Last reminder check, as a timestamp in a small file.
class FileDocumentReminderMarks implements DocumentReminderMarks {
  const FileDocumentReminderMarks(this.folder);

  final Future<Directory> Function() folder;

  Future<File> _file() async {
    final Directory d = await folder();
    if (!await d.exists()) {
      await d.create(recursive: true);
    }
    return File('${d.path}/document_reminders.txt');
  }

  @override
  Future<DateTime?> read() async {
    final File f = await _file();
    return await f.exists() ? DateTime.tryParse((await f.readAsString()).trim()) : null;
  }

  @override
  Future<void> write(DateTime at) async => (await _file()).writeAsString(at.toIso8601String(), flush: true);
}

/// Reminders as local notifications (plugin set up by feature 067).
class NotificationDocumentReminders implements DocumentReminderSink {
  NotificationDocumentReminders({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  static const int idBase = 740000;

  @override
  Future<void> remind(DocumentReminder reminder) async {
    await _plugin.show(
      idBase + ((reminder.document.id.hashCode + reminder.days) & 0xFFFF),
      reminder.text,
      'Renew it before it runs out. Open Family > Documents for details.',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'family_documents',
          'Document expiry',
          channelDescription: 'Reminders 30, 7 and 1 day before a family document expires',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
    );
  }
}

/// Covers Aadhaar numbers (all but the last four digits) and number plates
/// with on-device ML Kit text recognition, then re-encodes from pixels.
class RedactorDocumentMasker implements DocumentMasker {
  const RedactorDocumentMasker(this.redactor);

  final Redactor redactor;

  @override
  Future<Uint8List> mask(Uint8List image) async {
    final img.Image? decoded = img.decodeImage(image);
    if (decoded == null) {
      throw const DocumentVaultException('This file is not a photo the phone can read.');
    }
    final img.Image upright = img.bakeOrientation(decoded);
    final Uint8List jpeg = Uint8List.fromList(img.encodeJpg(upright, quality: 92));
    final List<RedactRegion> regions =
        await redactor.detect('', upright, jpeg, const RedactTargets(faces: false, plates: true, aadhaar: true));
    if (regions.isEmpty) {
      throw const DocumentVaultException('No ID number found to cover. Use Blur faces, plates and Aadhaar to cover it by hand.');
    }
    return Redactor.encode(Redactor.apply(upright, regions, RedactStyle.box));
  }
}
