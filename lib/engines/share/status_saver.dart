import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Feature 125 — WhatsApp status saver.
///
/// WhatsApp keeps the statuses a phone has viewed in a hidden `.Statuses`
/// folder for about a day. This lists the photos and videos there (with the
/// person's permission) so they can be kept or shared. Nothing is uploaded.

@immutable
class StatusItem {
  const StatusItem({required this.id, required this.name, required this.modified, required this.size});

  /// A path on Android 10 and older, a content URI through the folder grant.
  final String id;
  final String name;
  final DateTime modified;
  final int size;

  String get extension {
    final int dot = name.lastIndexOf('.');
    return dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
  }

  bool get isVideo => const <String>{'mp4', '3gp', 'mkv', 'webm'}.contains(extension);
  bool get isPhoto => const <String>{'jpg', 'jpeg', 'png', 'webp', 'gif'}.contains(extension);
}

enum StatusAccess { granted, needsGrant, unsupported, noWhatsApp }

/// Where statuses come from. Behind an interface so tests need no phone.
abstract class StatusSource {
  Future<StatusAccess> access();

  /// Asks for the statuses folder (Android's folder picker opens there).
  Future<StatusAccess> requestAccess();

  /// Raw entries in the folder(s), unfiltered.
  Future<List<StatusItem>> entries();

  Future<Uint8List> read(StatusItem item);
}

/// Where kept statuses go. Behind an interface for tests.
abstract class StatusSink {
  Future<String> write(String name, Uint8List bytes);
  Future<void> remove(String path);
}

class StatusSaver {
  StatusSaver(this.source, this.sink);

  final StatusSource source;
  final StatusSink sink;

  /// Photos and videos, newest first, without duplicates (the same status
  /// can sit in both WhatsApp and WhatsApp Business folders).
  Future<List<StatusItem>> list() async {
    final List<StatusItem> all = await source.entries();
    final Map<String, StatusItem> byKey = <String, StatusItem>{};
    for (final StatusItem s in all) {
      if (s.name.startsWith('.') || !(s.isPhoto || s.isVideo) || s.size == 0) {
        continue;
      }
      byKey.putIfAbsent('${s.name}:${s.size}', () => s);
    }
    final List<StatusItem> out = byKey.values.toList()
      ..sort((StatusItem a, StatusItem b) => b.modified.compareTo(a.modified));
    return out;
  }

  /// Copies a status into the app's Statuses folder; returns the saved path.
  Future<String> save(StatusItem item) async => sink.write(savedName(item), await source.read(item));

  static String savedName(StatusItem item) {
    final DateTime t = item.modified;
    String two(int v) => v.toString().padLeft(2, '0');
    return 'Status ${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}.${two(t.minute)}.${two(t.second)}.${item.extension}';
  }
}

/// Android: the folder grant (Android 11+) through a platform channel, or
/// the folder itself on Android 10 and older. Other systems: unsupported.
class PhoneStatusSource implements StatusSource {
  const PhoneStatusSource();

  static const MethodChannel _channel = MethodChannel('app.family/statuses');

  /// Folders used by WhatsApp and WhatsApp Business over the years.
  static const List<String> legacyFolders = <String>[
    '/storage/emulated/0/Android/media/com.whatsapp/WhatsApp/Media/.Statuses',
    '/storage/emulated/0/Android/media/com.whatsapp.w4b/WhatsApp Business/Media/.Statuses',
    '/storage/emulated/0/WhatsApp/Media/.Statuses',
    '/storage/emulated/0/WhatsApp Business/Media/.Statuses',
  ];

  @override
  Future<StatusAccess> access() async {
    if (!Platform.isAndroid) {
      return StatusAccess.unsupported;
    }
    try {
      final String? s = await _channel.invokeMethod<String>('access');
      return StatusAccess.values.firstWhere((StatusAccess a) => a.name == s, orElse: () => StatusAccess.needsGrant);
    } on MissingPluginException {
      return _legacyFolders().isEmpty ? StatusAccess.noWhatsApp : StatusAccess.granted;
    }
  }

  @override
  Future<StatusAccess> requestAccess() async {
    if (!Platform.isAndroid) {
      return StatusAccess.unsupported;
    }
    try {
      await _channel.invokeMethod<void>('requestAccess');
    } on MissingPluginException {
      // Older builds read the folder directly.
    } on PlatformException {
      return StatusAccess.needsGrant;
    }
    return access();
  }

  List<Directory> _legacyFolders() =>
      legacyFolders.map(Directory.new).where((Directory d) => d.existsSync()).toList();

  @override
  Future<List<StatusItem>> entries() async {
    try {
      final List<Object?>? raw = await _channel.invokeListMethod<Object?>('list');
      return <StatusItem>[
        for (final Object? e in raw ?? const <Object?>[])
          if (e is Map)
            StatusItem(
              id: '${e['uri']}',
              name: '${e['name']}',
              modified: DateTime.fromMillisecondsSinceEpoch((e['modified'] as num?)?.toInt() ?? 0),
              size: (e['size'] as num?)?.toInt() ?? 0,
            ),
      ];
    } on MissingPluginException {
      final List<StatusItem> out = <StatusItem>[];
      for (final Directory d in _legacyFolders()) {
        for (final FileSystemEntity f in d.listSync()) {
          if (f is File) {
            final FileStat st = f.statSync();
            out.add(StatusItem(id: f.path, name: f.uri.pathSegments.last, modified: st.modified, size: st.size));
          }
        }
      }
      return out;
    }
  }

  @override
  Future<Uint8List> read(StatusItem item) async {
    if (item.id.startsWith('/')) {
      return File(item.id).readAsBytes();
    }
    final Uint8List? bytes = await _channel.invokeMethod<Uint8List>('read', <String, String>{'uri': item.id});
    if (bytes == null) {
      throw const FileSystemException('This status has expired');
    }
    return bytes;
  }
}
