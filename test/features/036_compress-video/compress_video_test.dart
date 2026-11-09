import 'package:family_utility_app/app/theme.dart';
import 'package:family_utility_app/engines/platform/background_jobs.dart';
import 'package:family_utility_app/engines/video/video_compressor.dart';
import 'package:family_utility_app/tools/compress_video/compress_video_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const int mb = 1000 * 1000;

/// Pretends the hardware encoder spends each size's typical bitrate.
class FakeEncoder implements VideoEncoder {
  FakeEncoder({this.source = const VideoInfo(path: '/v/trip.mp4', bytes: 120 * mb, duration: Duration(seconds: 60), width: 1920, height: 1080), this.factor = 1.0});

  final VideoInfo source;
  final double factor;
  final Map<String, VideoInfo> outputs = <String, VideoInfo>{};
  final List<VideoSize> encoded = <VideoSize>[];
  bool cancelled = false;
  bool cancelOnStart = false;

  @override
  Future<VideoInfo> probe(String path) async => outputs[path] ?? source;

  @override
  Future<String?> encode(String path, VideoSize size, {required void Function(double fraction) onProgress}) async {
    encoded.add(size);
    onProgress(0.5);
    if (cancelled) {
      return null;
    }
    onProgress(1);
    final String out = '/tmp/out-${size.height}.mp4';
    final int bytes = ((size.typicalKbps + 128) * 1000 / 8 * source.duration.inSeconds * factor).round();
    outputs[out] = VideoInfo(path: out, bytes: bytes, duration: source.duration, width: size.height * 16 ~/ 9, height: size.height);
    return out;
  }

  @override
  Future<void> cancel() async => cancelled = true;
}

class FakeFiles implements VideoFiles {
  final List<String> kept = <String>[];

  @override
  Future<String?> pick() async => '/v/trip.mp4';

  @override
  Future<String> keep(String path, String name) async {
    kept.add('/videos/$name');
    return '/videos/$name';
  }

  @override
  Future<void> remove(String path) async => kept.remove(path);
}

void main() {
  const VideoInfo minute1080 = VideoInfo(path: '/v/a.mp4', bytes: 120 * mb, duration: Duration(seconds: 60), width: 1920, height: 1080);

  group('planner', () {
    test('WhatsApp 16 MB and email 25 MB pick a bitrate that fits', () {
      final VideoPlan wa = VideoPlanner.plan(minute1080, VideoPreset.whatsapp);
      expect(wa.targetBytes, 16 * mb);
      expect(VideoPlanner.estimateBytes(wa, minute1080), lessThanOrEqualTo(16 * mb));
      expect(wa.size, VideoSize.p540);

      final VideoPlan email = VideoPlanner.plan(minute1080, VideoPreset.email);
      expect(VideoPlanner.estimateBytes(email, minute1080), lessThanOrEqualTo(25 * mb));
      expect(email.videoKbps, greaterThan(wa.videoKbps));
    });

    test('720p and 480p never upscale; custom bitrate is used as given', () {
      expect(VideoPlanner.plan(minute1080, VideoPreset.p720).size, VideoSize.p720);
      expect(VideoPlanner.plan(minute1080, VideoPreset.p480).size, VideoSize.p480);
      const VideoInfo small = VideoInfo(path: '/v/s.mp4', bytes: 30 * mb, duration: Duration(seconds: 60), width: 640, height: 360);
      expect(VideoPlanner.plan(small, VideoPreset.p720).size, VideoSize.p360);
      final VideoPlan c = VideoPlanner.plan(minute1080, VideoPreset.custom(1200));
      expect(c.videoKbps, 1200);
      expect(c.size, VideoSize.p480);
      expect(VideoPreset.custom(5).customKbps, 100);
    });

    test('a file already under the limit is kept as it is', () {
      const VideoInfo tiny = VideoInfo(path: '/v/t.mp4', bytes: 5 * mb, duration: Duration(seconds: 10), width: 1280, height: 720);
      expect(VideoPlanner.plan(tiny, VideoPreset.whatsapp).keepOriginal, isTrue);
    });
  });

  group('compressor', () {
    test('runs as a background job with progress and hits the target', () async {
      final NoopJobHost host = NoopJobHost();
      final BackgroundJobs jobs = BackgroundJobs(host);
      final FakeEncoder enc = FakeEncoder();
      final VideoResult r = await VideoCompressor(enc, jobs: jobs).compress('/v/trip.mp4', VideoPreset.whatsapp);
      expect(r.outputBytes, lessThanOrEqualTo(16 * mb));
      expect(r.hitTarget, isTrue);
      expect(host.log.first, startsWith('start'));
      expect(host.log, contains('finished 1 done'));
      expect(jobs.jobs.single.outputPath, r.outputPath);
    });

    test('steps down a size when the encoder overshoots', () async {
      final FakeEncoder enc = FakeEncoder(factor: 1.6);
      final VideoResult r = await VideoCompressor(enc, jobs: BackgroundJobs(NoopJobHost())).compress('/v/trip.mp4', VideoPreset.whatsapp);
      expect(enc.encoded, <VideoSize>[VideoSize.p540, VideoSize.p480]);
      expect(r.size, VideoSize.p480);
      expect(r.outputBytes, lessThanOrEqualTo(16 * mb));
    });

    test('Cancel stops the encoder', () async {
      final NoopJobHost host = NoopJobHost();
      final BackgroundJobs jobs = BackgroundJobs(host);
      final FakeEncoder enc = FakeEncoder();
      final VideoCompressor c = VideoCompressor(enc, jobs: jobs);
      jobs.addListener(() {
        for (final JobRecord j in jobs.active) {
          if (j.percent >= 40) {
            jobs.cancel(j.id);
          }
        }
      });
      await expectLater(c.compress('/v/trip.mp4', VideoPreset.p480), throwsA(isA<JobCancelled>()));
      expect(enc.cancelled, isTrue);
      expect(jobs.jobs.single.state, JobState.cancelled);
    });
  });

  group('screen', () {
    testWidgets('pick, choose a preset, compress, save, undo', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final FakeFiles files = FakeFiles();
      final VideoCompressor c = VideoCompressor(FakeEncoder(), jobs: BackgroundJobs(NoopJobHost()));
      await tester.pumpWidget(MaterialApp(theme: buildAppTheme(), home: CompressVideoScreen(compressor: c, files: files)));

      await tester.tap(find.byKey(const Key('video-pick')));
      await tester.pump();
      expect(find.byKey(const Key('video-info')), findsOneWidget);
      expect(find.byKey(const Key('video-estimate')), findsOneWidget);

      await tester.tap(find.byKey(const Key('video-preset-email')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('video-go')));
      await tester.pump(const Duration(milliseconds: 10));
      await tester.pump(const Duration(milliseconds: 10));
      expect(find.textContaining('120.0 MB →'), findsOneWidget);

      await tester.tap(find.byKey(const Key('result-save')));
      await tester.pump();
      expect(files.kept, <String>['/videos/trip-small.mp4']);
      await tester.tap(find.byKey(const Key('result-undo')));
      await tester.pump();
      expect(files.kept, isEmpty);

      expect(tester.getSize(find.byKey(const Key('video-go'))).height, greaterThanOrEqualTo(44));
      expect(tester.getSize(find.byKey(const Key('video-pick'))).height, greaterThanOrEqualTo(44));
    });
  });
}
