import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Feature 065 — Open-with for all file types.
///
/// The app is registered for the types below (Android intent filters in
/// `AndroidManifest.xml`, iOS document types in `Info.plist`). A file opened
/// from another app arrives here as a local path and the app shows the tools
/// that apply to it (feature 106). The file is copied into the app's own
/// storage on the phone and never uploaded.
abstract final class OpenWithTypes {
  /// MIME types the Android VIEW / SEND filters accept.
  static const List<String> androidMimeTypes = <String>[
    'application/pdf',
    'image/jpeg',
    'image/png',
    'image/gif',
    'image/webp',
    'image/bmp',
    'image/tiff',
    'image/heic',
    'image/heif',
    'image/avif',
    'image/svg+xml',
    'image/x-icon',
    'image/*',
    'video/mp4',
    'video/quicktime',
    'video/x-matroska',
    'video/webm',
    'video/3gpp',
    'video/x-msvideo',
    'video/*',
    'audio/mpeg',
    'audio/mp4',
    'audio/aac',
    'audio/wav',
    'audio/x-wav',
    'audio/ogg',
    'audio/opus',
    'audio/flac',
    'audio/amr',
    'audio/*',
    'application/zip',
    'application/x-zip-compressed',
    'application/vnd.rar',
    'application/x-rar-compressed',
    'application/x-7z-compressed',
    'application/gzip',
    'application/x-tar',
    'application/msword',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'application/vnd.ms-excel',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'application/vnd.ms-powerpoint',
    'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    'application/vnd.oasis.opendocument.text',
    'application/vnd.oasis.opendocument.spreadsheet',
    'application/vnd.oasis.opendocument.presentation',
    'application/rtf',
    'text/plain',
    'text/csv',
    'text/comma-separated-values',
    'text/markdown',
    'application/json',
    'application/epub+zip',
  ];

  /// Uniform type identifiers listed under `CFBundleDocumentTypes` on iOS.
  static const List<String> iosTypes = <String>[
    'com.adobe.pdf',
    'public.image',
    'public.jpeg',
    'public.png',
    'public.heic',
    'public.heif',
    'org.webmproject.webp',
    'com.compuserve.gif',
    'public.tiff',
    'com.microsoft.bmp',
    'public.avif',
    'public.movie',
    'public.mpeg-4',
    'com.apple.quicktime-movie',
    'public.audio',
    'public.mp3',
    'public.mpeg-4-audio',
    'com.microsoft.waveform-audio',
    'public.zip-archive',
    'com.rarlab.rar-archive',
    'org.7-zip.7-zip-archive',
    'org.gnu.gnu-zip-archive',
    'public.tar-archive',
    'com.microsoft.word.doc',
    'org.openxmlformats.wordprocessingml.document',
    'com.microsoft.excel.xls',
    'org.openxmlformats.spreadsheetml.sheet',
    'com.microsoft.powerpoint.ppt',
    'org.openxmlformats.presentationml.presentation',
    'org.oasis-open.opendocument.text',
    'org.oasis-open.opendocument.spreadsheet',
    'org.oasis-open.opendocument.presentation',
    'public.rtf',
    'public.plain-text',
    'public.comma-separated-values-text',
    'net.daringfireball.markdown',
    'public.json',
    'org.idpf.epub-container',
  ];

  /// File extensions the app knows how to route (for the Files tab and iOS
  /// inbox). Over fifty, across every family of types above.
  static const List<String> extensions = <String>[
    'pdf', 'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'tif', 'tiff', 'heic', //
    'heif', 'avif', 'svg', 'ico', 'mp4', 'mov', 'mkv', 'webm', '3gp', 'avi', //
    'm4v', 'mp3', 'm4a', 'aac', 'wav', 'ogg', 'opus', 'flac', 'amr', 'zip', //
    'rar', '7z', 'gz', 'tar', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', //
    'odt', 'ods', 'odp', 'rtf', 'txt', 'csv', 'md', 'json', 'epub', 'vcf', //
    'ics',
  ];
}

/// Files opened into the app from another app ("Open with", "Open in").
///
/// Android: MainActivity copies the file behind an `ACTION_VIEW` (or a
/// non-picture `ACTION_SEND`) into the cache and passes the path over
/// `app.family/open_with` — `initialFiles` for the file that started the app
/// and a `files` call while it runs. iOS: the system copies the file into
/// `Documents/Inbox`; [scanInbox] picks new ones up when the app starts or
/// comes back to the front.
class OpenWithInbox extends ChangeNotifier {
  OpenWithInbox();

  static const String channelName = 'app.family/open_with';
  static const MethodChannel channel = MethodChannel(channelName);

  List<String>? _pending;
  final Set<String> _seen = <String>{};

  /// Called for each open, with the local paths.
  void Function(List<String> paths)? onFiles;

  void receive(List<String> paths) {
    final List<String> fresh = paths.where((String p) => p.isNotEmpty && _seen.add(p)).toList();
    if (fresh.isEmpty) {
      return;
    }
    _pending = List<String>.unmodifiable(fresh);
    notifyListeners();
    onFiles?.call(_pending!);
  }

  /// Hands the pending paths over once.
  List<String>? take() {
    final List<String>? p = _pending;
    _pending = null;
    return p;
  }

  static List<String> _paths(Object? args) =>
      args is List<Object?> ? args.whereType<String>().toList() : <String>[];

  Future<Object?> handle(MethodCall call) async {
    if (call.method == 'files') {
      receive(_paths(call.arguments));
      return null;
    }
    throw MissingPluginException('No handler for ${call.method}');
  }

  /// Does nothing where there is no platform side (tests).
  Future<void> attach() async {
    try {
      channel.setMethodCallHandler(handle);
      receive(_paths(await channel.invokeMethod<Object?>('initialFiles')));
    } catch (_) {
      // No binding or no platform side.
    }
  }

  /// iOS: new files in [inboxDir] (the system's `Documents/Inbox`), oldest
  /// first. Each path is handed over once.
  Future<void> scanInbox(String inboxDir) async {
    try {
      final Directory dir = Directory(inboxDir);
      if (!dir.existsSync()) {
        return;
      }
      final List<File> files = dir.listSync().whereType<File>().toList()
        ..sort((File a, File b) => a.statSync().modified.compareTo(b.statSync().modified));
      receive(files.map((File f) => f.path).toList());
    } catch (_) {
      // Unreadable inbox: nothing to open.
    }
  }

  /// Android: opens the app's "Open by default" page (Android 12+), or the
  /// default apps page, or the app's details page. False when none opened.
  Future<bool> openDefaultAppSettings() async {
    try {
      return await channel.invokeMethod<bool>('openDefaultsSettings') ?? false;
    } catch (_) {
      return false;
    }
  }

  static OpenWithInbox? _instance;

  static OpenWithInbox get instance => _instance ??= OpenWithInbox();

  static void install(OpenWithInbox inbox) => _instance = inbox;
}

/// Remembers whether the default-app prompt was already answered.
abstract class DefaultAppPromptStore {
  Future<bool> readDismissed();
  Future<void> writeDismissed();
}

class MemoryDefaultAppPromptStore implements DefaultAppPromptStore {
  MemoryDefaultAppPromptStore({this.dismissed = false});

  bool dismissed;

  @override
  Future<bool> readDismissed() async => dismissed;

  @override
  Future<void> writeDismissed() async => dismissed = true;
}

/// The one-time Android card "Make this your PDF and image app?".
///
/// Shown only on Android, only after a file opened successfully, and never
/// again once the person taps either button.
class DefaultAppPrompt extends ChangeNotifier {
  DefaultAppPrompt(this._store);

  final DefaultAppPromptStore _store;
  bool _dismissed = false;
  bool _loaded = false;

  bool get dismissed => _dismissed;

  Future<void> load() async {
    try {
      _dismissed = await _store.readDismissed();
    } catch (_) {
      _dismissed = false;
    }
    _loaded = true;
    notifyListeners();
  }

  bool shouldShow({required bool isAndroid, required bool openedOk}) =>
      _loaded && isAndroid && openedOk && !_dismissed;

  Future<void> dismiss() async {
    if (_dismissed) {
      return;
    }
    _dismissed = true;
    notifyListeners();
    try {
      await _store.writeDismissed();
    } catch (_) {
      // Best effort; the card stays hidden for this run.
    }
  }

  static DefaultAppPrompt instance = DefaultAppPrompt(MemoryDefaultAppPromptStore());

  static void install(DefaultAppPrompt p) => instance = p;
}
