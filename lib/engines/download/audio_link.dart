import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'download_queue.dart';
import 'mp4_audio.dart';
import 'video_link.dart';

/// Feature 124 — Download audio from a link.
///
/// Same links as 123 (Instagram, YouTube, Facebook, X, Pinterest, Threads,
/// any page with a video, or a direct link to a sound file). When the site
/// offers a sound-only file (YouTube does) that file is fetched; otherwise
/// the video is fetched and its sound is copied out on the phone into an
/// M4A, with no re-encoding. An optional start and end trim it before it is
/// saved. Everything goes through the download queue (127); nothing of the
/// person's is uploaded.

/// Sound file extensions saved as they are.
const List<String> directAudioExts = <String>['mp3', 'm4a', 'aac', 'opus', 'ogg', 'oga', 'wav', 'flac'];

/// One way to get the sound.
class AudioFormat {
  const AudioFormat({required this.url, required this.ext, this.bitrate, this.fromVideo = false});

  final Uri url;

  /// Extension of the saved file: m4a, mp3, webm, …
  final String ext;
  final int? bitrate;

  /// True when the sound is copied out of a video after download.
  final bool fromVideo;

  /// Only MP4/M4A sound can be trimmed on the phone.
  bool get canTrim => fromVideo || ext == 'm4a' || ext == 'mp4';

  String get label {
    final String kind = fromVideo ? 'M4A from the video' : ext.toUpperCase();
    final int? b = bitrate;
    return b == null ? kind : '$kind · ${(b / 1000).round()} kbps';
  }

  @override
  String toString() => '$label $url';
}

/// What a link resolved to.
class AudioLink {
  AudioLink({required this.page, required this.site, required this.title, required List<AudioFormat> formats, this.duration})
      : formats = sortAudio(formats);

  final Uri page;
  final String site;
  final String title;

  /// Best first.
  final List<AudioFormat> formats;

  /// Length when the site says it, else null.
  final Duration? duration;

  AudioFormat get best => formats.first;
}

/// Sound-only files first (M4A before others, higher bitrate first), then
/// sound copied from videos; duplicates dropped.
List<AudioFormat> sortAudio(List<AudioFormat> input) {
  final Set<String> seen = <String>{};
  final List<AudioFormat> out = <AudioFormat>[];
  for (final AudioFormat f in input) {
    if (seen.add('${f.fromVideo}${f.url}')) {
      out.add(f);
    }
  }
  int rank(AudioFormat f) => f.fromVideo ? 2 : (f.ext == 'm4a' || f.ext == 'mp3' ? 0 : 1);
  out.sort((AudioFormat a, AudioFormat b) {
    final int r = rank(a).compareTo(rank(b));
    if (r != 0) {
      return r;
    }
    return (b.bitrate ?? 0).compareTo(a.bitrate ?? 0);
  });
  return out;
}

/// Extension of a link that points straight at a sound file, or null.
String? directAudioExt(Uri url) {
  final String path = url.path.toLowerCase();
  for (final String e in directAudioExts) {
    if (path.endsWith('.$e')) {
      return e;
    }
  }
  return null;
}

/// The sound-only files in a YouTube player response.
List<AudioFormat> youTubeAudio(Map<String, Object?>? player) {
  final List<AudioFormat> out = <AudioFormat>[];
  final Object? streaming = player?['streamingData'];
  if (streaming is! Map<String, Object?>) {
    return out;
  }
  final Object? adaptive = streaming['adaptiveFormats'];
  if (adaptive is! List<Object?>) {
    return out;
  }
  for (final Object? f in adaptive) {
    if (f is! Map<String, Object?>) {
      continue;
    }
    final Object? mime = f['mimeType'];
    final Object? raw = f['url'];
    if (mime is! String || !mime.startsWith('audio/') || raw is! String) {
      continue; // Protected (signature-only) entries are skipped, not worked around.
    }
    final Uri? u = Uri.tryParse(raw);
    if (u == null || !(u.scheme == 'https' || u.scheme == 'http')) {
      continue;
    }
    out.add(AudioFormat(
      url: u,
      ext: mime.startsWith('audio/mp4') ? 'm4a' : (mime.contains('webm') ? 'webm' : 'm4a'),
      bitrate: f['bitrate'] is int ? f['bitrate']! as int : null,
    ));
  }
  return out;
}

Duration? youTubeDuration(Map<String, Object?>? player) {
  final Object? details = player?['videoDetails'];
  if (details is Map<String, Object?>) {
    final int? s = int.tryParse('${details['lengthSeconds']}');
    if (s != null && s > 0) {
      return Duration(seconds: s);
    }
  }
  return null;
}

/// Reads `m:ss`, `h:mm:ss` or plain seconds; null for empty, throws on junk.
Duration? parseClock(String text) {
  final String t = text.trim();
  if (t.isEmpty) {
    return null;
  }
  final List<String> parts = t.split(':');
  if (parts.length > 3) {
    throw const FormatException('Use m:ss, like 1:30');
  }
  double total = 0;
  for (int i = 0; i < parts.length; i++) {
    final double? v = double.tryParse(parts[i]);
    if (v == null || v < 0 || (i > 0 && v >= 60)) {
      throw const FormatException('Use m:ss, like 1:30');
    }
    total = total * 60 + v;
  }
  return Duration(milliseconds: (total * 1000).round());
}

String formatClock(Duration d) {
  final int s = d.inSeconds;
  final String ss = (s % 60).toString().padLeft(2, '0');
  if (s >= 3600) {
    return '${s ~/ 3600}:${((s % 3600) ~/ 60).toString().padLeft(2, '0')}:$ss';
  }
  return '${s ~/ 60}:$ss';
}

/// A start/end pair the person typed; checked before anything downloads.
class TrimRange {
  const TrimRange({this.start, this.end});

  final Duration? start;
  final Duration? end;

  bool get isEmpty => start == null && end == null;

  /// Null when fine, else what is wrong.
  String? problem(Duration? length) {
    final Duration? s = start;
    final Duration? e = end;
    if (s != null && e != null && e <= s) {
      return 'The end must come after the start.';
    }
    if (length != null && s != null && s >= length) {
      return 'The start is past the end of the audio (${formatClock(length)}).';
    }
    return null;
  }
}

/// Runs the copy-out step; the app runs it in a background isolate.
typedef AudioExtractRunner = Future<void> Function(String input, String output, Duration? start, Duration? end);

Future<void> _isolateExtract(String input, String output, Duration? start, Duration? end) {
  return compute<List<Object?>, void>(_extractEntry, <Object?>[input, output, start?.inMicroseconds, end?.inMicroseconds]);
}

void _extractEntry(List<Object?> a) {
  final int? s = a[2] as int?;
  final int? e = a[3] as int?;
  extractAudioFile(a[0]! as String, a[1]! as String,
      start: s == null ? null : Duration(microseconds: s), end: e == null ? null : Duration(microseconds: e));
}

/// Glue between a pasted link, the 123 plugins, the queue and the extractor.
class AudioLinkDownloader {
  AudioLinkDownloader({required this.video, AudioExtractRunner? extract}) : extract = extract ?? _isolateExtract;

  final VideoLinkDownloader video;
  final AudioExtractRunner extract;

  /// Finds the sound behind a pasted or shared text.
  Future<AudioLink> resolve(String text) async {
    final Uri? url = findLink(text);
    if (url == null) {
      throw const VideoLinkError('Paste a link that starts with http:// or https://');
    }
    final String? why = video.blockedReason?.call();
    if (why != null) {
      throw VideoLinkError(why);
    }
    final String? ext = directAudioExt(url);
    if (ext != null) {
      final String name = url.pathSegments.isEmpty ? 'audio' : url.pathSegments.last;
      final int dot = name.lastIndexOf('.');
      return AudioLink(
          page: url,
          site: 'direct',
          title: dot > 0 ? name.substring(0, dot) : name,
          formats: <AudioFormat>[AudioFormat(url: url, ext: ext)]);
    }
    final List<AudioFormat> formats = <AudioFormat>[];
    Duration? length;
    if (const YouTubeExtractor().handles(url)) {
      final String? id = YouTubeExtractor.videoId(url);
      if (id != null) {
        try {
          final Map<String, Object?>? player = YouTubeExtractor.playerResponse(
              await video.pages.getText(Uri.https('www.youtube.com', '/watch', <String, String>{'v': id})));
          formats.addAll(youTubeAudio(player));
          length = youTubeDuration(player);
        } catch (_) {
          // Fall back to the video plugins below.
        }
      }
    }
    VideoLink? v;
    try {
      v = await video.registry.resolve(url, video.pages);
    } on VideoLinkError {
      if (formats.isEmpty) {
        rethrow;
      }
    }
    if (v != null) {
      for (final VideoFormat f in v.formats.where((VideoFormat f) => f.hasAudio && f.ext == 'mp4')) {
        formats.add(AudioFormat(url: f.url, ext: 'm4a', bitrate: f.bitrate, fromVideo: true));
        break; // The best one with sound is enough; the sound is the same.
      }
    }
    if (formats.isEmpty) {
      throw const VideoLinkError('This link has no sound that can be saved.');
    }
    return AudioLink(page: v?.page ?? url, site: v?.site ?? 'youtube', title: v?.title ?? 'audio', formats: formats, duration: length);
  }

  /// A file name from the title, e.g. `Sunset at the beach.m4a`.
  static String fileName(AudioLink link, AudioFormat format, {bool trimmed = false}) {
    String base = link.title.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f#%]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    if (base.length > 80) {
      base = base.substring(0, 80).trim();
    }
    if (base.isEmpty) {
      base = '${link.site} audio';
    }
    return trimmed ? '$base (clip).${format.ext}' : '$base.${format.ext}';
  }

  /// Queues the download. Sound copied from a video, or a trim, is
  /// downloaded under a temporary name and finished by [finish].
  Future<DownloadTask> start(DownloadQueue queue, AudioLink link, AudioFormat format, TrimRange trim) async {
    if (!trim.isEmpty && !format.canTrim) {
      throw const VideoLinkError('This sound file cannot be trimmed on the phone. Save it without a start and end.');
    }
    final bool convert = format.fromVideo || !trim.isEmpty;
    final String plain = fileName(link, format);
    final String name = convert ? '${plain.substring(0, plain.lastIndexOf('.'))} (source).mp4' : plain;
    return queue.add(format.url.toString(), name: name);
  }

  /// Waits for [task] to finish downloading.
  static Future<DownloadTask> whenDone(DownloadQueue queue, DownloadTask task) {
    final Completer<DownloadTask> done = Completer<DownloadTask>();
    void check() {
      final DownloadTask? t = queue.byId(task.id);
      if (done.isCompleted) {
        return;
      }
      if (t == null) {
        done.completeError(const VideoLinkError('The download was removed.'));
      } else if (t.state == DownloadState.done) {
        done.complete(t);
      } else if (t.state == DownloadState.failed) {
        done.completeError(VideoLinkError(t.error ?? 'The download failed.'));
      }
    }

    queue.addListener(check);
    check();
    return done.future.whenComplete(() => queue.removeListener(check));
  }

  /// Turns a finished download into the saved sound file and returns its
  /// path. A plain download is already the result.
  Future<String> finish(DownloadTask task, AudioLink link, AudioFormat format, TrimRange trim) async {
    final bool convert = format.fromVideo || !trim.isEmpty;
    if (!convert) {
      return task.path;
    }
    final String folder = task.folder.endsWith('/') ? task.folder.substring(0, task.folder.length - 1) : task.folder;
    final String name = fileName(link, AudioFormat(url: format.url, ext: 'm4a'), trimmed: !trim.isEmpty);
    String out = '$folder/$name';
    int n = 2;
    while (File(out).existsSync()) {
      out = '$folder/${name.substring(0, name.length - 4)} ($n).m4a';
      n++;
    }
    try {
      await extract(task.path, out, trim.start, trim.end);
    } on AudioExtractError catch (e) {
      throw VideoLinkError(e.message);
    } finally {
      try {
        await File(task.path).delete();
      } catch (_) {
        // The temporary copy is gone already.
      }
    }
    return out;
  }
}

/// App-wide instance.
abstract final class AudioLinks {
  static AudioLinkDownloader? _instance;

  static AudioLinkDownloader get instance => _instance ??= AudioLinkDownloader(video: VideoLinks.instance);

  static void install(AudioLinkDownloader d) => _instance = d;
}
