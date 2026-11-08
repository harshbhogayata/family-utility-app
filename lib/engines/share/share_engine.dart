import 'package:flutter/foundation.dart';

/// Feature 060 — Share to any app.
///
/// Every tool's Share button goes through [ShareEngine]: it works out the
/// right MIME type for each file, hands the request to the system share sheet
/// (behind [ShareSheet], so tests never touch the platform), and remembers
/// which apps the person shared to last. Nothing is uploaded by the app
/// itself; the share sheet only sends what the person picks.

/// MIME types for the file kinds the app produces or receives. Pure table.
abstract final class MimeTypes {
  static const String fallback = 'application/octet-stream';

  static const Map<String, String> _byExtension = <String, String>{
    'pdf': 'application/pdf',
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'webp': 'image/webp',
    'gif': 'image/gif',
    'bmp': 'image/bmp',
    'heic': 'image/heic',
    'heif': 'image/heif',
    'avif': 'image/avif',
    'svg': 'image/svg+xml',
    'tif': 'image/tiff',
    'tiff': 'image/tiff',
    'mp4': 'video/mp4',
    'mov': 'video/quicktime',
    'mkv': 'video/x-matroska',
    'webm': 'video/webm',
    'avi': 'video/x-msvideo',
    '3gp': 'video/3gpp',
    'mp3': 'audio/mpeg',
    'm4a': 'audio/mp4',
    'aac': 'audio/aac',
    'wav': 'audio/wav',
    'ogg': 'audio/ogg',
    'opus': 'audio/opus',
    'flac': 'audio/flac',
    'txt': 'text/plain',
    'md': 'text/markdown',
    'csv': 'text/csv',
    'json': 'application/json',
    'xml': 'application/xml',
    'html': 'text/html',
    'vcf': 'text/vcard',
    'ics': 'text/calendar',
    'doc': 'application/msword',
    'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'xls': 'application/vnd.ms-excel',
    'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'ppt': 'application/vnd.ms-powerpoint',
    'pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    'odt': 'application/vnd.oasis.opendocument.text',
    'ods': 'application/vnd.oasis.opendocument.spreadsheet',
    'odp': 'application/vnd.oasis.opendocument.presentation',
    'epub': 'application/epub+zip',
    'zip': 'application/zip',
    '7z': 'application/x-7z-compressed',
    'rar': 'application/vnd.rar',
    'tar': 'application/x-tar',
    'gz': 'application/gzip',
    'apk': 'application/vnd.android.package-archive',
  };

  /// The extension after the last dot, lower-case, or empty.
  static String extensionOf(String path) {
    final String name = path.split('/').last.split(r'\').last;
    final int dot = name.lastIndexOf('.');
    if (dot < 0 || dot == name.length - 1) {
      return '';
    }
    return name.substring(dot + 1).toLowerCase();
  }

  static String fromPath(String path) => _byExtension[extensionOf(path)] ?? fallback;

  static bool isKnown(String path) => _byExtension.containsKey(extensionOf(path));
}

/// One file in a share request, with the MIME type already worked out.
class ShareFile {
  ShareFile(this.path, {String? mimeType, String? name})
      : mimeType = mimeType ?? MimeTypes.fromPath(path),
        name = name ?? path.split('/').last;

  final String path;
  final String mimeType;
  final String name;

  @override
  bool operator ==(Object other) =>
      other is ShareFile && other.path == path && other.mimeType == mimeType && other.name == name;

  @override
  int get hashCode => Object.hash(path, mimeType, name);
}

/// What the tool asks the sheet to send.
@immutable
class ShareRequest {
  const ShareRequest({this.files = const <ShareFile>[], this.text, this.subject});

  final List<ShareFile> files;
  final String? text;
  final String? subject;

  bool get hasFiles => files.isNotEmpty;

  /// The single MIME type the sheet should advertise: the files' common type,
  /// or `image/*` / `video/*` when they agree on a family, else `*/*`.
  String get mimeType {
    if (!hasFiles) {
      return 'text/plain';
    }
    final Set<String> types = files.map((ShareFile f) => f.mimeType).toSet();
    if (types.length == 1) {
      return types.first;
    }
    final Set<String> families = types.map((String t) => t.split('/').first).toSet();
    if (families.length == 1) {
      return '${families.first}/*';
    }
    return '*/*';
  }
}

/// What came back from the sheet.
@immutable
class ShareOutcome {
  const ShareOutcome({required this.completed, this.target});

  const ShareOutcome.dismissed() : this(completed: false);

  /// True when the sheet reported the share went through.
  final bool completed;

  /// The app it went to, as the platform names it (Android component name or
  /// iOS activity type), when the platform tells us. Null otherwise.
  final String? target;
}

/// The system share sheet. The platform implementation lives in lib/platform.
abstract class ShareSheet {
  Future<ShareOutcome> share(ShareRequest request);
}

/// Where the recent targets are remembered.
abstract class ShareTargetStore {
  Future<List<String>> read();

  Future<void> write(List<String> rawTargets);
}

class MemoryShareTargetStore implements ShareTargetStore {
  MemoryShareTargetStore([List<String>? initial]) : _value = List<String>.of(initial ?? <String>[]);

  List<String> _value;

  @override
  Future<List<String>> read() async => List<String>.unmodifiable(_value);

  @override
  Future<void> write(List<String> rawTargets) async => _value = List<String>.of(rawTargets);
}

/// A remembered destination with a plain-words label.
@immutable
class ShareTarget {
  const ShareTarget(this.raw);

  final String raw;

  static const Map<String, String> _labels = <String, String>{
    'com.whatsapp': 'WhatsApp',
    'com.whatsapp.w4b': 'WhatsApp Business',
    'com.google.android.gm': 'Gmail',
    'com.google.android.apps.docs': 'Drive',
    'org.telegram.messenger': 'Telegram',
    'org.telegram.plus': 'Telegram',
    'com.android.bluetooth': 'Bluetooth',
    'com.google.android.apps.nbu.files': 'Files',
    'com.google.android.apps.messaging': 'Messages',
    'com.google.android.apps.photos': 'Photos',
    'com.google.android.apps.tachyon': 'Meet',
    'com.microsoft.office.outlook': 'Outlook',
    'com.microsoft.teams': 'Teams',
    'com.slack': 'Slack',
    'com.instagram.android': 'Instagram',
    'com.facebook.orca': 'Messenger',
    'com.dropbox.android': 'Dropbox',
    'com.google.android.apps.dynamite': 'Chat',
    'com.paytm': 'Paytm',
    'net.one97.paytm': 'Paytm',
    'com.phonepe.app': 'PhonePe',
    // iOS activity types
    'net.whatsapp.WhatsApp.ShareExtension': 'WhatsApp',
    'com.apple.UIKit.activity.Mail': 'Mail',
    'com.apple.UIKit.activity.Message': 'Messages',
    'com.apple.UIKit.activity.AirDrop': 'AirDrop',
    'com.apple.UIKit.activity.CopyToPasteboard': 'Copy',
    'com.apple.UIKit.activity.SaveToCameraRoll': 'Photos',
    'com.apple.CloudDocsUI.AddToiCloudDrive': 'iCloud Drive',
    'com.google.Gmail.ShareExtension': 'Gmail',
    'com.google.Drive.ShareExtension': 'Drive',
    'ph.telegra.Telegraph.Share': 'Telegram',
  };

  /// Android gives "package/activity"; iOS gives the activity type.
  String get packageName => raw.split('/').first;

  String get label {
    final String known = _labels[packageName] ?? _labels[raw] ?? '';
    if (known.isNotEmpty) {
      return known;
    }
    // Fall back to the last meaningful segment, capitalised.
    final List<String> parts = packageName.split('.').where((String p) => p.isNotEmpty).toList();
    if (parts.isEmpty) {
      return raw;
    }
    String tail = parts.last;
    if (<String>{'android', 'app', 'apps', 'messenger', 'mobile'}.contains(tail.toLowerCase()) && parts.length > 1) {
      tail = parts[parts.length - 2];
    }
    return tail.isEmpty ? raw : tail[0].toUpperCase() + tail.substring(1);
  }

  @override
  bool operator ==(Object other) => other is ShareTarget && other.raw == raw;

  @override
  int get hashCode => raw.hashCode;
}

/// Sends requests to the sheet and remembers where they went.
class ShareEngine {
  ShareEngine(this._sheet, this._store);

  final ShareSheet _sheet;
  final ShareTargetStore _store;

  static const int keep = 5;

  /// Most recent first. Listen to it to show "Last shared to …".
  final ValueNotifier<List<ShareTarget>> recents = ValueNotifier<List<ShareTarget>>(<ShareTarget>[]);

  Future<void> load() async {
    try {
      final List<String> raws = await _store.read();
      recents.value = raws.map(ShareTarget.new).toList();
    } catch (_) {
      // Keep whatever is in memory.
    }
  }

  Future<ShareOutcome> share(ShareRequest request) async {
    final ShareOutcome outcome = await _sheet.share(request);
    final String? target = outcome.target;
    if (outcome.completed && target != null && target.isNotEmpty) {
      await remember(ShareTarget(target));
    }
    return outcome;
  }

  Future<ShareOutcome> shareFiles(List<String> paths, {String? text, String? subject}) {
    return share(ShareRequest(
      files: paths.map((String p) => ShareFile(p)).toList(),
      text: text,
      subject: subject,
    ));
  }

  Future<ShareOutcome> shareText(String text, {String? subject}) {
    return share(ShareRequest(text: text, subject: subject));
  }

  /// Moves [target] to the front, drops duplicates, keeps the last [keep].
  Future<void> remember(ShareTarget target) async {
    final List<ShareTarget> next = <ShareTarget>[
      target,
      ...recents.value.where((ShareTarget t) => t != target),
    ].take(keep).toList();
    recents.value = next;
    try {
      await _store.write(next.map((ShareTarget t) => t.raw).toList());
    } catch (_) {
      // Memory still holds it for this launch.
    }
  }

  Future<void> forgetAll() async {
    recents.value = <ShareTarget>[];
    try {
      await _store.write(<String>[]);
    } catch (_) {
      // Nothing more to do.
    }
  }

  /// One shared engine; bootstrap installs the platform sheet and store.
  static ShareEngine instance = ShareEngine(_NoopSheet(), MemoryShareTargetStore());

  static void install(ShareEngine engine) {
    instance = engine;
  }
}

class _NoopSheet implements ShareSheet {
  @override
  Future<ShareOutcome> share(ShareRequest request) async => const ShareOutcome.dismissed();
}
