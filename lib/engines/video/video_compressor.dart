import 'dart:async';

import '../platform/background_jobs.dart';

/// Feature 036 — Compress video.
///
/// [VideoPlanner] turns a preset (WhatsApp 16 MB, email 25 MB, 720p, 480p or
/// a custom bitrate) into an encode plan; [VideoCompressor] runs the plan on
/// the phone's hardware encoder through a [VideoEncoder], as a background
/// job with progress and Cancel, and steps down a size if the file still
/// comes out too big.

enum VideoPresetKind { whatsapp, email, p720, p480, custom }

class VideoPreset {
  const VideoPreset._(this.kind, this.label, {this.targetBytes, this.maxHeight, this.customKbps});

  static const VideoPreset whatsapp = VideoPreset._(VideoPresetKind.whatsapp, 'WhatsApp (16 MB)', targetBytes: 16 * 1000 * 1000);
  static const VideoPreset email = VideoPreset._(VideoPresetKind.email, 'Email (25 MB)', targetBytes: 25 * 1000 * 1000);
  static const VideoPreset p720 = VideoPreset._(VideoPresetKind.p720, '720p', maxHeight: 720);
  static const VideoPreset p480 = VideoPreset._(VideoPresetKind.p480, '480p', maxHeight: 480);

  /// Video bitrate in kilobits per second, chosen by the person.
  factory VideoPreset.custom(int kbps) =>
      VideoPreset._(VideoPresetKind.custom, 'Custom ($kbps kbps)', customKbps: kbps.clamp(100, 50000).toInt());

  static const List<VideoPreset> fixed = <VideoPreset>[whatsapp, email, p720, p480];

  final VideoPresetKind kind;
  final String label;
  final int? targetBytes;
  final int? maxHeight;
  final int? customKbps;
}

/// The encoder sizes the phone's hardware encoders handle well.
enum VideoSize {
  p360(360, 600),
  p480(480, 1200),
  p540(540, 1800),
  p720(720, 2500),
  p1080(1080, 5000);

  const VideoSize(this.height, this.typicalKbps);

  final int height;

  /// Roughly what the platform encoder spends per second at this size.
  final int typicalKbps;

  VideoSize? get smaller {
    final int i = VideoSize.values.indexOf(this);
    return i == 0 ? null : VideoSize.values[i - 1];
  }
}

class VideoInfo {
  const VideoInfo({required this.path, required this.bytes, required this.duration, required this.width, required this.height});

  final String path;
  final int bytes;
  final Duration duration;
  final int width;
  final int height;

  int get shortSide => width < height ? width : height;
}

class VideoPlan {
  const VideoPlan({required this.size, required this.videoKbps, this.targetBytes, this.keepOriginal = false});

  final VideoSize size;
  final int videoKbps;
  final int? targetBytes;

  /// The source already fits; nothing to do.
  final bool keepOriginal;
}

abstract final class VideoPlanner {
  static const int audioKbps = 128;

  /// Keeps 5 % headroom for the container.
  static int bitrateForTarget(int targetBytes, Duration duration) {
    final double seconds = duration.inMilliseconds / 1000.0;
    if (seconds <= 0) {
      return 2500;
    }
    final double totalKbps = targetBytes * 8 * 0.95 / 1000 / seconds;
    return (totalKbps - audioKbps).floor().clamp(100, 50000).toInt();
  }

  /// Largest size whose typical bitrate fits [kbps] and that does not upscale.
  static VideoSize sizeFor(int kbps, int sourceShortSide, {int? maxHeight}) {
    VideoSize pick = VideoSize.p360;
    for (final VideoSize s in VideoSize.values) {
      if (s.typicalKbps <= kbps && s.height <= sourceShortSide && (maxHeight == null || s.height <= maxHeight)) {
        pick = s;
      }
    }
    return pick;
  }

  static VideoPlan plan(VideoInfo info, VideoPreset preset) {
    final int? target = preset.targetBytes;
    if (target != null) {
      if (info.bytes <= target) {
        return VideoPlan(size: sizeFor(1 << 30, info.shortSide), videoKbps: 0, targetBytes: target, keepOriginal: true);
      }
      final int kbps = bitrateForTarget(target, info.duration);
      return VideoPlan(size: sizeFor(kbps, info.shortSide), videoKbps: kbps, targetBytes: target);
    }
    if (preset.kind == VideoPresetKind.custom) {
      final int kbps = preset.customKbps!;
      return VideoPlan(size: sizeFor(kbps, info.shortSide), videoKbps: kbps);
    }
    final int h = preset.maxHeight!;
    final VideoSize size = sizeFor(1 << 30, info.shortSide, maxHeight: h);
    return VideoPlan(size: size, videoKbps: size.typicalKbps);
  }

  /// Expected output bytes for a plan, for the screen's estimate.
  static int estimateBytes(VideoPlan plan, VideoInfo info) {
    if (plan.keepOriginal) {
      return info.bytes;
    }
    final double seconds = info.duration.inMilliseconds / 1000.0;
    return ((plan.videoKbps + audioKbps) * 1000 / 8 * seconds).round();
  }
}

/// The phone's encoder (MediaCodec on Android, AVFoundation on iOS).
abstract class VideoEncoder {
  Future<VideoInfo> probe(String path);

  /// Encodes [path] at [size]; reports 0..1 on [onProgress]. Returns the new
  /// file's path, or null if cancelled.
  Future<String?> encode(String path, VideoSize size, {required void Function(double fraction) onProgress});

  Future<void> cancel();
}

class VideoResult {
  const VideoResult({required this.input, required this.outputPath, required this.outputBytes, required this.size, this.hitTarget = true});

  final VideoInfo input;
  final String outputPath;
  final int outputBytes;
  final VideoSize size;

  /// False when even the smallest size stayed over the preset's limit.
  final bool hitTarget;

  int get savedBytes => input.bytes - outputBytes;
}

class VideoCompressor {
  VideoCompressor(this.encoder, {BackgroundJobs? jobs}) : _jobs = jobs;

  final VideoEncoder encoder;
  final BackgroundJobs? _jobs;

  BackgroundJobs get jobs => _jobs ?? BackgroundJobs.instance;

  /// Throws [JobCancelled] when the person cancels.
  Future<VideoResult> compress(String path, VideoPreset preset) async {
    final VideoInfo info = await encoder.probe(path);
    final VideoPlan plan = VideoPlanner.plan(info, preset);
    if (plan.keepOriginal) {
      return VideoResult(input: info, outputPath: info.path, outputBytes: info.bytes, size: plan.size);
    }
    final String name = path.substring(path.lastIndexOf('/') + 1);
    return jobs.run<VideoResult>('Compressing $name', (JobContext ctx) async {
      VideoSize size = plan.size;
      int attempt = 0;
      while (true) {
        ctx.throwIfCancelled();
        final int pass = attempt;
        final String? out = await encoder.encode(path, size, onProgress: (double f) {
          if (ctx.cancelled) {
            unawaited(encoder.cancel());
            return;
          }
          ctx.report(((pass + f) / (pass + 1)).clamp(0.0, 0.99).toDouble(), '${size.height}p');
        });
        if (out == null || ctx.cancelled) {
          throw const JobCancelled();
        }
        final VideoInfo result = await encoder.probe(out);
        final int? target = plan.targetBytes;
        final VideoSize? next = size.smaller;
        if (target == null || result.bytes <= target || next == null) {
          return VideoResult(
            input: info,
            outputPath: out,
            outputBytes: result.bytes,
            size: size,
            hitTarget: target == null || result.bytes <= target,
          );
        }
        size = next;
        attempt++;
      }
    }, outputOf: (VideoResult r) => r.outputPath);
  }
}
