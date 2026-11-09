import 'dart:io';

import 'package:flutter/foundation.dart';

import 'share_engine.dart';

/// Feature 128 — Send at original quality.
///
/// WhatsApp recompresses anything shared as `image/*` or `video/*`. Shared as
/// a generic document type it is sent byte for byte, with its own file name,
/// exactly like WhatsApp's own "Document" attach option. This engine wraps a
/// photo or video that way and hands it to the system share sheet; nothing is
/// uploaded by the app and no copy is made unless the person taps Save.

/// A photo or video the person picked.
@immutable
class PickedMedia {
  const PickedMedia({required this.path, required this.name, required this.size});

  final String path;
  final String name;
  final int size;

  bool get isPhoto => MimeTypes.fromPath(name).startsWith('image/');

  bool get isVideo => MimeTypes.fromPath(name).startsWith('video/');
}

/// Pure rules for wrapping a file as a document.
abstract final class OriginalQuality {
  /// The type WhatsApp and other chat apps send without recompressing.
  static const String documentMime = 'application/octet-stream';

  /// WhatsApp's document size limit.
  static const int whatsappDocumentLimit = 2 * 1024 * 1024 * 1024;

  /// The file as a share entry that chat apps treat as a document, keeping
  /// the original name so the receiver sees `IMG_2041.HEIC`, not `file`.
  static ShareFile asDocument(PickedMedia media) {
    return ShareFile(media.path, mimeType: documentMime, name: media.name);
  }

  /// Files too big for a WhatsApp document.
  static List<PickedMedia> tooBig(List<PickedMedia> media) {
    return media.where((PickedMedia m) => m.size > whatsappDocumentLimit).toList();
  }

  static String formatSize(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) {
      return '${(bytes / 1024).round()} KB';
    }
    return '$bytes B';
  }
}

/// Keeps a copy of an original in the app's own folder (the Save action).
abstract class OriginalSaver {
  /// Returns the path of the saved copy.
  Future<String> save(PickedMedia media);

  Future<void> remove(String savedPath);
}

/// Saves into a folder, never overwriting an existing file.
class DirectoryOriginalSaver implements OriginalSaver {
  DirectoryOriginalSaver(this.folder);

  /// Resolved lazily so the platform folder is looked up only when needed.
  final Future<Directory> Function() folder;

  @override
  Future<String> save(PickedMedia media) async {
    final Directory dir = await folder();
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    final String name = _free(dir, media.name);
    final File copy = await File(media.path).copy('${dir.path}/$name');
    return copy.path;
  }

  @override
  Future<void> remove(String savedPath) async {
    final File f = File(savedPath);
    if (f.existsSync()) {
      await f.delete();
    }
  }

  static String _free(Directory dir, String name) {
    if (!File('${dir.path}/$name').existsSync()) {
      return name;
    }
    final int dot = name.lastIndexOf('.');
    final String stem = dot > 0 ? name.substring(0, dot) : name;
    final String ext = dot > 0 ? name.substring(dot) : '';
    int i = 2;
    while (File('${dir.path}/$stem ($i)$ext').existsSync()) {
      i++;
    }
    return '$stem ($i)$ext';
  }
}

/// What a send did.
@immutable
class SendOriginalResult {
  const SendOriginalResult({required this.sent, required this.count, this.target, this.skipped = const <PickedMedia>[]});

  final bool sent;
  final int count;
  final String? target;

  /// Files left out because WhatsApp would refuse them as documents.
  final List<PickedMedia> skipped;
}

/// Sends picked media through the share sheet as documents.
class SendOriginal {
  SendOriginal(this._share);

  final ShareEngine _share;

  Future<SendOriginalResult> send(List<PickedMedia> media) async {
    final List<PickedMedia> big = OriginalQuality.tooBig(media);
    final List<PickedMedia> ok = media.where((PickedMedia m) => !big.contains(m)).toList();
    if (ok.isEmpty) {
      return SendOriginalResult(sent: false, count: 0, skipped: big);
    }
    final ShareOutcome outcome = await _share.share(ShareRequest(
      files: ok.map(OriginalQuality.asDocument).toList(),
    ));
    return SendOriginalResult(
      sent: outcome.completed,
      count: outcome.completed ? ok.length : 0,
      target: outcome.target,
      skipped: big,
    );
  }
}
