import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:family_utility_app/engines/download/download_queue.dart';
import 'package:family_utility_app/engines/download/shared_link.dart';
import 'package:family_utility_app/engines/download/video_link.dart';
import 'package:family_utility_app/engines/platform/background_jobs.dart';
import 'package:family_utility_app/tools/video_link/video_link_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Serves canned pages by URL and records what was asked for.
class FakePages implements PageFetcher {
  FakePages(this.pages);

  final Map<String, String> pages;
  final List<String> asked = <String>[];

  @override
  Future<String> getText(Uri url) async {
    asked.add(url.toString());
    final String? html = pages[url.toString()];
    if (html == null) {
      throw const VideoLinkError('The site answered 404. The post may be private or removed.');
    }
    return html;
  }
}

/// Serves the same bytes for any link.
class BytesFetcher implements DownloadFetcher {
  BytesFetcher(this.data);

  final Uint8List data;
  final List<String> urls = <String>[];

  @override
  Future<FetchResponse> open(Uri url, int from) async {
    urls.add(url.toString());
    return FetchResponse(
      statusCode: 200,
      totalLength: data.length,
      body: Stream<List<int>>.fromIterable(<List<int>>[data]),
    );
  }
}

/// A plugin with a bug: claims Instagram links and crashes.
class CrashingExtractor implements VideoExtractor {
  @override
  String get id => 'crashy';

  @override
  String get label => 'Crashy';

  @override
  bool handles(Uri url) => hostIs(url, <String>['instagram.com']);

  @override
  Future<VideoLink> extract(Uri url, PageFetcher pages) async {
    final List<int> empty = <int>[];
    return VideoLink(page: url, site: id, title: '${empty[3]}', formats: const <VideoFormat>[]);
  }
}

/// A plugin that never answers.
class HangingExtractor implements VideoExtractor {
  @override
  String get id => 'hangs';

  @override
  String get label => 'Hangs';

  @override
  bool handles(Uri url) => hostIs(url, <String>['facebook.com']);

  @override
  Future<VideoLink> extract(Uri url, PageFetcher pages) => Completer<VideoLink>().future;
}

/// A plugin whose matcher itself throws.
class BadMatcherExtractor implements VideoExtractor {
  @override
  String get id => 'badmatch';

  @override
  String get label => 'Bad matcher';

  @override
  bool handles(Uri url) => throw StateError('broken');

  @override
  Future<VideoLink> extract(Uri url, PageFetcher pages) => throw StateError('never');
}

const String igUrl = 'https://www.instagram.com/reel/Cabc123/';
const String igPage = '<html><head><meta property="og:title" content="Sunset &amp; waves"/>'
    '<meta property="og:video" content="https://cdn.example.com/ig/og.mp4?x=1&amp;y=2"></head>'
    '<script>{"video_versions":[{"width":720,"height":1280,"url":"https:\\/\\/cdn.example.com\\/ig\\/720.mp4?a=1\\u0026b=2"},'
    '{"width":360,"height":640,"url":"https:\\/\\/cdn.example.com\\/ig\\/360.mp4"}]}</script></html>';

const String ytId = 'dQw4w9WgXcQ';
const String ytWatch = 'https://www.youtube.com/watch?v=$ytId';
const String ytPage = '<html><title>x - YouTube</title><script>var ytInitialPlayerResponse = '
    '{"videoDetails":{"title":"Family trip {day 1}"},"streamingData":{"formats":['
    '{"itag":18,"url":"https://rr.example.com/videoplayback?itag=18","mimeType":"video/mp4; codecs=\\"avc1\\"","width":640,"height":360,"bitrate":500000},'
    '{"itag":22,"url":"https://rr.example.com/videoplayback?itag=22","mimeType":"video/mp4","width":1280,"height":720,"bitrate":1500000}'
    ']}};var other = {};</script></html>';
const String ytProtectedPage = '<script>var ytInitialPlayerResponse = {"videoDetails":{"title":"Song"},'
    '"streamingData":{"formats":[{"itag":18,"signatureCipher":"s=abc&url=https%3A%2F%2Fx"}]}};</script>';

const String fbUrl = 'https://www.facebook.com/watch/?v=123';
const String fbPage = '<meta property="og:title" content="Birthday">'
    '<script>{"browser_native_hd_url":"https:\\/\\/video.fb.example\\/hd.mp4","browser_native_sd_url":"https:\\/\\/video.fb.example\\/sd.mp4"}</script>';

const String xUrl = 'https://x.com/someone/status/1';
const String xPage = '<meta property="og:title" content="A clip">'
    '<script>{"variants":[{"bitrate":632000,"content_type":"video/mp4","url":"https:\\/\\/video.twimg.example\\/vid\\/320x568\\/a.mp4"},'
    '{"bitrate":2176000,"content_type":"video/mp4","url":"https:\\/\\/video.twimg.example\\/vid\\/720x1280\\/b.mp4"}]}</script>';

const String pinUrl = 'https://in.pinterest.com/pin/42/';
const String pinPage = '<meta property="og:title" content="Craft idea">'
    '<script>{"videos":{"video_list":{"V_720P":{"width":720,"height":1280,"url":"https://v.pinimg.example/720.mp4"},'
    '"V_HLSV4":{"url":"https://v.pinimg.example/hls.m3u8"}}}}</script>';

const String threadsUrl = 'https://www.threads.net/@a/post/xyz';
const String threadsPage = '<meta property="og:title" content="Thread video">'
    '<script>{"video_versions":[{"width":1080,"height":1920,"url":"https://cdn.threads.example/1080.mp4"}]}</script>';

const String genericUrl = 'https://blog.example.com/post';
const String genericPage = '<meta property="og:title" content="Blog clip">'
    '<meta content="https://blog.example.com/clip.webm" property="og:video:secure_url">'
    '<meta property="og:video:width" content="1920"><meta property="og:video:height" content="1080">';

Map<String, String> allPages() => <String, String>{
      igUrl: igPage,
      ytWatch: ytPage,
      fbUrl: fbPage,
      xUrl: xPage,
      pinUrl: pinPage,
      threadsUrl: threadsPage,
      genericUrl: genericPage,
    };

void main() {
  group('links', () {
    test('finds the link inside shared text', () {
      expect(findLink('Watch this! https://www.instagram.com/reel/Cabc123/?igsh=x).').toString(),
          'https://www.instagram.com/reel/Cabc123/?igsh=x');
      expect(findLink('no link here'), isNull);
    });

    test('YouTube ids from watch, Shorts, youtu.be and embed links', () {
      for (final String l in <String>[
        'https://www.youtube.com/watch?v=$ytId&t=3',
        'https://youtube.com/shorts/$ytId?feature=share',
        'https://youtu.be/$ytId',
        'https://m.youtube.com/embed/$ytId',
      ]) {
        expect(YouTubeExtractor.videoId(Uri.parse(l)), ytId, reason: l);
      }
      expect(YouTubeExtractor.videoId(Uri.parse('https://www.youtube.com/feed/library')), isNull);
    });
  });

  group('site plugins', () {
    late FakePages pages;
    late VideoExtractorRegistry reg;

    setUp(() {
      pages = FakePages(allPages());
      reg = VideoExtractorRegistry();
    });

    test('Instagram reels: every size the page offers, best first', () async {
      final VideoLink v = await reg.resolve(Uri.parse(igUrl), pages);
      expect(v.site, 'instagram');
      expect(v.title, 'Sunset & waves');
      expect(v.best.url.toString(), 'https://cdn.example.com/ig/720.mp4?a=1&b=2');
      expect(v.formats.map((VideoFormat f) => f.label).toList(), <String>['720p', '360p', 'Best available']);
    });

    test('YouTube and Shorts read the open formats', () async {
      final VideoLink v = await reg.resolve(Uri.parse('https://youtube.com/shorts/$ytId'), pages);
      expect(v.site, 'youtube');
      expect(v.title, 'Family trip {day 1}');
      expect(v.formats.map((VideoFormat f) => f.label).toList(), <String>['720p', '360p']);
      expect(pages.asked, <String>[ytWatch]);
    });

    test('YouTube videos the site protects are reported, not worked around', () async {
      pages.pages[ytWatch] = ytProtectedPage;
      await expectLater(
        reg.resolve(Uri.parse(ytWatch), pages),
        throwsA(isA<VideoLinkError>().having((VideoLinkError e) => e.message, 'message', contains('protects'))),
      );
    });

    test('Facebook, X, Pinterest and Threads', () async {
      final VideoLink fb = await reg.resolve(Uri.parse(fbUrl), pages);
      expect(fb.site, 'facebook');
      expect(fb.formats.map((VideoFormat f) => f.url.toString()).toList(),
          <String>['https://video.fb.example/hd.mp4', 'https://video.fb.example/sd.mp4']);

      final VideoLink x = await reg.resolve(Uri.parse(xUrl), pages);
      expect(x.site, 'x');
      expect(x.formats.map((VideoFormat f) => f.label).toList(), <String>['720p', '320p']);

      final VideoLink pin = await reg.resolve(Uri.parse(pinUrl), pages);
      expect(pin.site, 'pinterest');
      expect(pin.formats.single.url.toString(), 'https://v.pinimg.example/720.mp4');

      final VideoLink th = await reg.resolve(Uri.parse(threadsUrl), pages);
      expect(th.site, 'threads');
      expect(th.best.label, '1080p');
    });

    test('any other page: Open Graph video, or a direct file link without a fetch', () async {
      final VideoLink g = await reg.resolve(Uri.parse(genericUrl), pages);
      expect(g.site, 'generic');
      expect(g.best.label, '1080p');
      expect(g.best.ext, 'webm');

      final int before = pages.asked.length;
      final VideoLink d = await reg.resolve(Uri.parse('https://files.example.com/clips/beach.mp4'), pages);
      expect(d.title, 'beach');
      expect(pages.asked.length, before);
    });

    test('a private post explains itself', () async {
      await expectLater(
        reg.resolve(Uri.parse('https://www.instagram.com/p/private/'), pages),
        throwsA(isA<VideoLinkError>().having((VideoLinkError e) => e.message, 'message', contains('private'))),
      );
    });
  });

  group('plugins are isolated', () {
    test('a crashing plugin fails only itself; the generic reader still finds the video', () async {
      final FakePages pages = FakePages(allPages());
      final VideoExtractorRegistry reg = VideoExtractorRegistry(
        plugins: <VideoExtractor>[BadMatcherExtractor(), CrashingExtractor(), const XExtractor()],
      );
      final VideoLink v = await reg.resolve(Uri.parse(igUrl), pages);
      expect(v.site, 'generic');
      expect(v.best.url.toString(), 'https://cdn.example.com/ig/og.mp4?x=1&y=2');
      expect(reg.lastFailures.single.extractor, 'crashy');
      expect(reg.lastFailures.single.message, contains('stopped working'));

      // Other sites are untouched by the broken plugin.
      final VideoLink x = await reg.resolve(Uri.parse(xUrl), pages);
      expect(x.site, 'x');
      expect(reg.lastFailures, isEmpty);
    });

    test('a plugin that hangs times out and the rest carry on', () async {
      final FakePages pages = FakePages(<String, String>{fbUrl: '<p>no video</p>'});
      final VideoExtractorRegistry reg = VideoExtractorRegistry(
        plugins: <VideoExtractor>[HangingExtractor()],
        timeout: const Duration(milliseconds: 50),
      );
      await expectLater(reg.resolve(Uri.parse(fbUrl), pages), throwsA(isA<VideoLinkError>()));
      expect(reg.lastFailures.map((ExtractorFailure f) => f.extractor).toList(), <String>['hangs', 'generic']);
      expect(reg.lastFailures.first.message, contains('too long'));
    });

    test('a switched-off plugin is skipped', () async {
      final FakePages pages = FakePages(allPages());
      final VideoExtractorRegistry reg = VideoExtractorRegistry()..disabled.add('instagram');
      final VideoLink v = await reg.resolve(Uri.parse(igUrl), pages);
      expect(v.site, 'generic');
    });
  });

  group('downloader', () {
    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('vid_'));
    tearDown(() {
      if (dir.existsSync()) {
        dir.deleteSync(recursive: true);
      }
    });

    test('personal-use notice is needed once', () async {
      final VideoLinkDownloader d = VideoLinkDownloader(pages: FakePages(allPages()), notice: MemoryNoticeStore());
      expect(await d.needsNotice(), isTrue);
      await d.noticeSeen();
      expect(await d.needsNotice(), isFalse);
    });

    test('on-device mode blocks the page fetch', () async {
      final FakePages pages = FakePages(allPages());
      final VideoLinkDownloader d = VideoLinkDownloader(
        pages: pages,
        notice: MemoryNoticeStore(),
        blockedReason: () => 'On-device mode is on.',
      );
      await expectLater(d.resolve(igUrl), throwsA(isA<VideoLinkError>()));
      expect(pages.asked, isEmpty);
      await expectLater(d.resolve('just words'), throwsA(isA<VideoLinkError>()));
    });

    test('the chosen quality is saved into the chosen folder through the queue', () async {
      final Uint8List data = Uint8List.fromList(List<int>.generate(500, (int i) => i % 251));
      final BytesFetcher fetcher = BytesFetcher(data);
      final DownloadQueue q = DownloadQueue(
        fetcher: fetcher,
        store: MemoryDownloadQueueStore(),
        defaultFolder: () async => dir.path,
        jobs: BackgroundJobs(NoopJobHost()),
      );
      await q.setFolder('${dir.path}/Videos');
      final VideoLinkDownloader d = VideoLinkDownloader(pages: FakePages(allPages()), notice: MemoryNoticeStore());
      final VideoLink v = await d.resolve('look https://www.instagram.com/reel/Cabc123/');
      final VideoFormat small = v.formats[1];
      final DownloadTask t = await d.save(q, v, small);
      expect(t.name, 'Sunset & waves 360p.mp4');
      for (int i = 0; i < 200 && t.state != DownloadState.done; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(t.state, DownloadState.done);
      expect(fetcher.urls, <String>['https://cdn.example.com/ig/360.mp4']);
      expect(File('${dir.path}/Videos/Sunset & waves 360p.mp4').readAsBytesSync(), data);
    });
  });

  group('shared links', () {
    test('the inbox hands shared text over once', () async {
      final SharedLinkInbox inbox = SharedLinkInbox();
      final List<String> seen = <String>[];
      inbox.onLink = seen.add;
      await inbox.handle(const MethodCall('link', 'see https://x.com/a/status/1'));
      expect(seen, <String>['see https://x.com/a/status/1']);
      expect(inbox.take(), 'see https://x.com/a/status/1');
      expect(inbox.take(), isNull);
    });
  });

  group('screen', () {
    late Directory dir;
    late DownloadQueue q;
    late MemoryNoticeStore notice;
    late VideoLinkDownloader d;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('vids_');
      q = DownloadQueue(
        fetcher: BytesFetcher(Uint8List.fromList(List<int>.filled(300, 7))),
        store: MemoryDownloadQueueStore(),
        defaultFolder: () async => dir.path,
        jobs: BackgroundJobs(NoopJobHost()),
      );
      notice = MemoryNoticeStore();
      d = VideoLinkDownloader(pages: FakePages(allPages()), notice: notice);
    });

    tearDown(() {
      if (dir.existsSync()) {
        dir.deleteSync(recursive: true);
      }
    });

    Future<void> io(WidgetTester tester) async {
      for (int i = 0; i < 8; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump();
      }
    }

    Future<void> tap(WidgetTester tester, String key) async {
      await tester.ensureVisible(find.byKey(Key(key)));
      await tester.pump();
      await tester.tap(find.byKey(Key(key)));
      await io(tester);
    }

    testWidgets('notice once, pick a quality, save to the folder, undo', (WidgetTester tester) async {
      final String picked = '${dir.path}/Chosen';
      await tester.pumpWidget(MaterialApp(
        home: VideoLinkScreen(downloader: d, queue: q, pickFolder: () async => picked, inbox: SharedLinkInbox()),
      ));
      await io(tester);
      expect(find.text(dir.path), findsOneWidget);

      await tap(tester, 'video-change-folder');
      expect(q.chosenFolder, picked);

      await tester.enterText(find.byKey(const Key('video-link')), igUrl);
      await tap(tester, 'video-find');
      expect(find.byKey(const Key('video-notice')), findsOneWidget);
      await tap(tester, 'video-notice-ok');
      expect(notice.shown, isTrue);
      expect(find.text('Sunset & waves'), findsOneWidget);
      expect(find.text('720p'), findsOneWidget);
      expect(find.text('360p'), findsOneWidget);

      for (final String k in <String>['video-find', 'video-download', 'video-change-folder']) {
        final Size s = tester.getSize(find.byKey(Key(k)));
        expect(s.height, greaterThanOrEqualTo(44), reason: k);
        expect(s.width, greaterThanOrEqualTo(44), reason: k);
      }

      await tap(tester, 'video-format-1');
      await tap(tester, 'video-download');
      await io(tester);
      expect(find.byKey(const Key('video-task')), findsOneWidget);
      expect(q.tasks.single.folder, picked);
      expect(q.tasks.single.name, 'Sunset & waves 360p.mp4');
      expect(find.textContaining('Done'), findsOneWidget);
      await tester.runAsync(() async {
        expect(File('$picked/Sunset & waves 360p.mp4').existsSync(), isTrue);
      });

      // A second link: the notice is not shown again.
      await tester.enterText(find.byKey(const Key('video-link')), xUrl);
      await tap(tester, 'video-find');
      expect(find.byKey(const Key('video-notice')), findsNothing);
      expect(find.text('A clip'), findsOneWidget);

      await tap(tester, 'result-undo');
      expect(q.tasks, isEmpty);
      expect(find.textContaining('Removed'), findsOneWidget);
    });

    testWidgets('a shared link opens straight into the result', (WidgetTester tester) async {
      notice.shown = true;
      await tester.pumpWidget(MaterialApp(
        home: VideoLinkScreen(downloader: d, queue: q, initialText: 'check https://youtu.be/$ytId'),
      ));
      await io(tester);
      expect(find.text('Family trip {day 1}'), findsOneWidget);
      expect(find.byWidgetPredicate((Widget w) => w is Icon && w.semanticLabel == 'Folder'), findsOneWidget);
    });
  });
}
