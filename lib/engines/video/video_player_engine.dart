import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Feature 130 — Universal video player: the logic behind the screen.
///
/// Playback itself sits behind [VideoBackend] (libmpv through media_kit on
/// the phone), so this file stays pure and testable: which files play,
/// SRT parsing, the swipe-gesture maths, resume positions and the
/// picture-in-picture / brightness channel.

/// The containers the player promises to open.
abstract final class VideoFormats {
  static const Set<String> extensions = <String>{
    'mp4', 'm4v', 'mkv', 'avi', 'mov', 'webm', 'ts', 'm2ts', 'mts', '3gp', 'flv', 'wmv', 'mpg', 'mpeg', 'ogv',
  };

  static const Set<String> subtitleExtensions = <String>{'srt', 'vtt', 'ass', 'ssa'};

  static String extensionOf(String path) {
    final String name = path.split(RegExp(r'[/\\]')).last;
    final int dot = name.lastIndexOf('.');
    return dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
  }

  static bool isVideo(String path) => extensions.contains(extensionOf(path));

  static bool isSubtitle(String path) => subtitleExtensions.contains(extensionOf(path));

  /// Formats AVPlayer can show in iOS picture-in-picture.
  static bool iosPipCapable(String path) => const <String>{'mp4', 'm4v', 'mov'}.contains(extensionOf(path));
}

/// One line of subtitles on screen.
class SubtitleCue {
  const SubtitleCue({required this.start, required this.end, required this.text});

  final Duration start;
  final Duration end;
  final String text;

  @override
  String toString() => 'SubtitleCue($start-$end: $text)';
}

/// Reads SubRip (.srt) files, tolerant of BOMs, CRLF and missing numbers.
abstract final class SrtParser {
  static final RegExp _timing = RegExp(
    r'(\d{1,2}):(\d{2}):(\d{2})[,.](\d{1,3})\s*-->\s*(\d{1,2}):(\d{2}):(\d{2})[,.](\d{1,3})',
  );

  static Duration _at(Match m, int i) {
    final String ms = m.group(i + 3)!.padRight(3, '0');
    return Duration(
      hours: int.parse(m.group(i)!),
      minutes: int.parse(m.group(i + 1)!),
      seconds: int.parse(m.group(i + 2)!),
      milliseconds: int.parse(ms),
    );
  }

  static List<SubtitleCue> parse(String source) {
    String s = source.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    if (s.startsWith('﻿')) {
      s = s.substring(1);
    }
    final List<SubtitleCue> cues = <SubtitleCue>[];
    for (final String block in s.split(RegExp(r'\n\s*\n'))) {
      final List<String> lines = block.trim().split('\n');
      final int t = lines.indexWhere((String l) => _timing.hasMatch(l));
      if (t < 0) {
        continue;
      }
      final Match m = _timing.firstMatch(lines[t])!;
      final String text = lines
          .skip(t + 1)
          .map((String l) => l.replaceAll(RegExp(r'<[^>]+>'), '').trim())
          .where((String l) => l.isNotEmpty)
          .join('\n');
      if (text.isEmpty) {
        continue;
      }
      final Duration start = _at(m, 1);
      final Duration end = _at(m, 5);
      if (end <= start) {
        continue;
      }
      cues.add(SubtitleCue(start: start, end: end, text: text));
    }
    cues.sort((SubtitleCue a, SubtitleCue b) => a.start.compareTo(b.start));
    return cues;
  }

  /// The cue showing at [position], or null between lines.
  static SubtitleCue? cueAt(List<SubtitleCue> cues, Duration position) {
    for (final SubtitleCue c in cues) {
      if (c.start > position) {
        return null;
      }
      if (position < c.end) {
        return c;
      }
    }
    return null;
  }
}

/// Which setting a vertical swipe changes.
enum SwipeTarget { brightness, volume }

/// Swipe-gesture maths: left half is brightness, right half is volume.
abstract final class GestureMath {
  static SwipeTarget targetFor(double x, double width) => x < width / 2 ? SwipeTarget.brightness : SwipeTarget.volume;

  /// A full-height upward swipe raises the level from 0 to 1.
  static double adjust(double current, double dy, double height) {
    if (height <= 0) {
      return current.clamp(0.0, 1.0);
    }
    return (current - dy / height).clamp(0.0, 1.0);
  }

  /// Double-tap left half rewinds, right half skips ahead.
  static Duration doubleTapSeek(Duration position, Duration duration, double x, double width, {Duration step = const Duration(seconds: 10)}) {
    final Duration next = x < width / 2 ? position - step : position + step;
    if (next < Duration.zero) {
      return Duration.zero;
    }
    if (duration > Duration.zero && next > duration) {
      return duration;
    }
    return next;
  }

  static String percent(double v) => '${(v * 100).round()}%';
}

/// Where the person stopped, per file; kept only on this phone.
abstract class ResumeStore {
  Future<int?> read(String key);
  Future<void> write(String key, int millis);
  Future<void> clear(String key);
}

class MemoryResumeStore implements ResumeStore {
  final Map<String, int> values = <String, int>{};

  @override
  Future<int?> read(String key) async => values[key];

  @override
  Future<void> write(String key, int millis) async => values[key] = millis;

  @override
  Future<void> clear(String key) async => values.remove(key);
}

/// Decides when to offer "resume" and when to forget a position.
class ResumePolicy {
  const ResumePolicy({this.store, this.minimum = const Duration(seconds: 5), this.tail = const Duration(seconds: 10)});

  final ResumeStore? store;
  final Duration minimum;
  final Duration tail;

  /// One key per file and size, so a replaced file starts fresh.
  static String keyFor(String path, int bytes) => 'video_resume:$path:$bytes';

  /// The position worth resuming from, or null to start at the beginning.
  Duration? resumeFrom(Duration saved, Duration duration) {
    if (saved < minimum) {
      return null;
    }
    if (duration > Duration.zero && saved >= duration - tail) {
      return null;
    }
    return saved;
  }

  Future<Duration?> load(String key, Duration duration) async {
    final ResumeStore? s = store;
    if (s == null) {
      return null;
    }
    final int? ms = await s.read(key);
    return ms == null ? null : resumeFrom(Duration(milliseconds: ms), duration);
  }

  /// Saves [position]; finished or barely-started files are forgotten.
  Future<void> save(String key, Duration position, Duration duration) async {
    final ResumeStore? s = store;
    if (s == null) {
      return;
    }
    if (resumeFrom(position, duration) == null) {
      await s.clear(key);
    } else {
      await s.write(key, position.inMilliseconds);
    }
  }
}

/// A subtitle or audio track the file carries.
class MediaTrack {
  const MediaTrack({required this.id, this.title, this.language});

  final String id;
  final String? title;
  final String? language;

  String get label {
    final List<String> parts = <String>[
      if (title != null && title!.isNotEmpty) title!,
      if (language != null && language!.isNotEmpty) language!,
    ];
    return parts.isEmpty ? 'Track $id' : parts.join(' · ');
  }
}

/// The playback engine; media_kit on device, a fake in tests.
abstract class VideoBackend {
  Future<void> open(String path, {Duration? start});
  Future<void> playOrPause();
  Future<void> seek(Duration to);

  /// 0..1.
  Future<void> setVolume(double level);
  Future<void> loadSubtitle(String path);
  Future<void> selectSubtitle(String? id);

  Stream<Duration> get position;
  Stream<Duration> get duration;
  Stream<bool> get playing;
  Stream<List<MediaTrack>> get subtitles;

  Duration get currentPosition;
  Duration get currentDuration;
  bool get isPlaying;

  /// The picture itself, with embedded or loaded subtitles drawn on it.
  Widget view();
  Future<void> dispose();
}

/// Screen brightness and picture-in-picture on the native side.
class PlayerPlatform {
  PlayerPlatform({MethodChannel? channel}) : _channel = channel ?? const MethodChannel('app.family/video_player');

  static final PlayerPlatform instance = PlayerPlatform();

  final MethodChannel _channel;

  /// The window's brightness, 0..1; null when the system decides.
  Future<double?> brightness() async {
    try {
      final Object? v = await _channel.invokeMethod<Object?>('getBrightness');
      return v is num ? v.toDouble().clamp(0.0, 1.0) : null;
    } on Object {
      return null;
    }
  }

  /// Changes only this app's window, never the system setting.
  Future<void> setBrightness(double? level) async {
    try {
      await _channel.invokeMethod<void>('setBrightness', <String, Object?>{'level': level});
    } on Object {
      // No native side (tests, desktop): ignore.
    }
  }

  Future<bool> pipSupported() async {
    try {
      return await _channel.invokeMethod<bool>('pipSupported') ?? false;
    } on Object {
      return false;
    }
  }

  /// Android: the whole app shrinks into a pop-up window. iOS: AVPlayer
  /// carries on from [position] in the system pop-up.
  Future<bool> enterPip({required String path, required Duration position, required double aspect}) async {
    try {
      return await _channel.invokeMethod<bool>('enterPip', <String, Object?>{
            'path': path,
            'positionMs': position.inMilliseconds,
            'aspect': aspect,
          }) ??
          false;
    } on Object {
      return false;
    }
  }
}

String formatPlayerTime(Duration d) {
  final int h = d.inHours;
  final String m = (d.inMinutes % 60).toString().padLeft(h > 0 ? 2 : 1, '0');
  final String s = (d.inSeconds % 60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}
