import 'dart:io';

import 'package:video_compress/video_compress.dart';

import '../engines/video/video_compressor.dart';

/// Hardware encode through `video_compress` (MediaCodec / AVFoundation).
class PlatformVideoEncoder implements VideoEncoder {
  const PlatformVideoEncoder();

  static VideoQuality _quality(VideoSize size) {
    switch (size) {
      case VideoSize.p360:
        return VideoQuality.LowQuality;
      case VideoSize.p480:
        return VideoQuality.Res640x480Quality;
      case VideoSize.p540:
        return VideoQuality.Res960x540Quality;
      case VideoSize.p720:
        return VideoQuality.Res1280x720Quality;
      case VideoSize.p1080:
        return VideoQuality.Res1920x1080Quality;
    }
  }

  @override
  Future<VideoInfo> probe(String path) async {
    final MediaInfo m = await VideoCompress.getMediaInfo(path);
    return VideoInfo(
      path: path,
      bytes: m.filesize ?? File(path).lengthSync(),
      duration: Duration(milliseconds: (m.duration ?? 0).round()),
      width: m.width ?? 0,
      height: m.height ?? 0,
    );
  }

  @override
  Future<String?> encode(String path, VideoSize size, {required void Function(double fraction) onProgress}) async {
    final Subscription sub = VideoCompress.compressProgress$.subscribe((double percent) => onProgress(percent / 100));
    try {
      final MediaInfo? out = await VideoCompress.compressVideo(
        path,
        quality: _quality(size),
        deleteOrigin: false,
        includeAudio: true,
      );
      return out?.path;
    } finally {
      sub.unsubscribe();
    }
  }

  @override
  Future<void> cancel() => VideoCompress.cancelCompression();
}
