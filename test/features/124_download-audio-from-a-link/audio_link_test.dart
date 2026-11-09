import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:family_utility_app/engines/download/audio_link.dart';
import 'package:family_utility_app/engines/download/download_queue.dart';
import 'package:family_utility_app/engines/download/mp4_audio.dart';
import 'package:family_utility_app/engines/download/video_link.dart';
import 'package:family_utility_app/engines/platform/background_jobs.dart';
import 'package:family_utility_app/tools/audio_link/audio_link_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// ---- tiny MP4 builder -------------------------------------------------------

List<int> u32(int v) => <int>[(v >> 24) & 0xff, (v >> 16) & 0xff, (v >> 8) & 0xff, v & 0xff];

List<int> box(String type, List<int> payload) => <int>[...u32(payload.length + 8), ...type.codeUnits, ...payload];

List<int> full(String type, List<int> payload, {int flags = 0}) => box(type, <int>[...u32(flags), ...payload]);

List<int> mvhd(int timescale, int duration) =>
    full('mvhd', <int>[...u32(0), ...u32(0), ...u32(timescale), ...u32(duration), ...List<int>.filled(80, 0)]);

List<int> tkhd(int id, int duration) =>
    full('tkhd', <int>[...u32(0), ...u32(0), ...u32(id), ...u32(0), ...u32(duration), ...List<int>.filled(60, 0)], flags: 3);

List<int> mdhd(int timescale, int duration) =>
    full('mdhd', <int>[...u32(0), ...u32(0), ...u32(timescale), ...u32(duration), 0x55, 0xc4, 0, 0]);

List<int> hdlr(String kind) => full('hdlr', <int>[...u32(0), ...kind.codeUnits, ...u32(0), ...u32(0), ...u32(0), 0]);

List<int> stsd(String codec) =>
    full('stsd', <int>[...u32(1), ...box(codec, <int>[0, 0, 0, 0, 0, 0, 0, 1, ...List<int>.filled(20, 0)])]);

List<int> table(String type, List<List<int>> rows, {List<int> prefix = const <int>[]}) => full(type, <int>[
      ...prefix,
      ...u32(rows.length),
      for (final List<int> r in rows)
        for (final int v in r) ...u32(v),
    ]);

List<int> trak({
  required int id,
  required String kind,
  required String codec,
  required int duration,
  required List<List<int>> stts,
  required List<int> sizes,
  required List<List<int>> stsc,
  required List<int> offsets,
}) {
  final List<int> stbl = box('stbl', <int>[
    ...stsd(codec),
    ...table('stts', stts),
    ...table('stsc', stsc),
    ...full('stsz', <int>[...u32(0), ...u32(sizes.length), for (final int s in sizes) ...u32(s)]),
    ...table('stco', <List<int>>[for (final int o in offsets) <int>[o]]),
  ]);
  return box('trak', <int>[
    ...tkhd(id, duration),
    ...box('edts', full('elst', <int>[...u32(0)])),
    ...box('mdia', <int>[
      ...mdhd(1000, duration),
      ...hdlr(kind),
      ...box('minf', <int>[
        ...(kind == 'soun' ? full('smhd', u32(0)) : full('vmhd', <int>[0, 0, 0, 0, 0, 0, 0, 0], flags: 1)),
        ...box('dinf', full('dref', <int>[...u32(1), ...full('url ', <int>[], flags: 1)])),
        ...stbl,
      ]),
    ]),
  ]);
}

/// Audio frames 0..4: sizes 3..7, each filled with 10+i.
List<List<int>> frames() => <List<int>>[for (int i = 0; i < 5; i++) List<int>.filled(3 + i, 10 + i)];

/// A plain MP4: video track + audio track, audio split over two chunks
/// with a video frame between them.
Uint8List plainMp4() {
  final List<int> ftyp = box('ftyp', <int>[...'isom'.codeUnits, ...u32(0), ...'isom'.codeUnits]);
  final List<List<int>> a = frames();
  final List<int> video = List<int>.filled(9, 99);
  final List<int> mdatPayload = <int>[...a[0], ...a[1], ...video, ...a[2], ...a[3], ...a[4]];
  final int dataStart = ftyp.length + 8;
  final int chunk1 = dataStart;
  final int videoAt = chunk1 + 3 + 4;
  final int chunk2 = videoAt + 9;
  final List<int> moov = box('moov', <int>[
    ...mvhd(600, 600),
    ...trak(
        id: 1,
        kind: 'vide',
        codec: 'avc1',
        duration: 1000,
        stts: <List<int>>[<int>[1, 1000]],
        sizes: <int>[9],
        stsc: <List<int>>[<int>[1, 1, 1]],
        offsets: <int>[videoAt]),
    ...trak(
        id: 2,
        kind: 'soun',
        codec: 'mp4a',
        duration: 1000,
        stts: <List<int>>[<int>[5, 200]],
        sizes: <int>[3, 4, 5, 6, 7],
        stsc: <List<int>>[<int>[1, 2, 1], <int>[2, 3, 1]],
        offsets: <int>[chunk1, chunk2]),
  ]);
  return Uint8List.fromList(<int>[...ftyp, ...box('mdat', mdatPayload), ...moov]);
}

/// A fragmented MP4 (as streaming sites serve): empty tables, one moof.
Uint8List fragmentedMp4() {
  final List<int> ftyp = box('ftyp', <int>[...'dash'.codeUnits, ...u32(0), ...'iso6'.codeUnits]);
  final List<int> moov = box('moov', <int>[
    ...mvhd(1000, 0),
    ...trak(id: 1, kind: 'soun', codec: 'mp4a', duration: 0, stts: <List<int>>[], sizes: <int>[], stsc: <List<int>>[], offsets: <int>[]),
    ...box('mvex', full('trex', <int>[...u32(1), ...u32(1), ...u32(200), ...u32(0), ...u32(0)])),
  ]);
  final List<List<int>> a = frames();
  List<int> moof(int dataOffset) => box('moof', <int>[
        ...full('mfhd', u32(1)),
        ...box('traf', <int>[
          ...full('tfhd', u32(1), flags: 0x20000),
          ...full('trun', <int>[...u32(5), ...u32(dataOffset), for (final List<int> f in a) ...u32(f.length)], flags: 0x201),
        ]),
      ]);
  final int moofSize = moof(0).length;
  return Uint8List.fromList(<int>[
    ...ftyp,
    ...moov,
    ...moof(moofSize + 8),
    ...box('mdat', <int>[for (final List<int> f in a) ...f]),
  ]);
}

List<String> topTypes(Uint8List b) {
  final MemoryByteSource s = MemoryByteSource(b);
  return readBoxes(s, 0, b.length).map((Mp4Box x) => x.type).toList();
}

// ---- fakes ------------------------------------------------------------------

class FakePages implements PageFetcher {
  FakePages(this.pages);

  final Map<String, String> pages;
  final List<String> asked = <String>[];

  @override
  Future<String> getText(Uri url) async {
    asked.add(url.toString());
    final String? html = pages[url.toString()];
    if (html == null) {
      throw const VideoLinkError('The site answered 404.');
    }
    return html;
  }
}

class BytesFetcher implements DownloadFetcher {
  BytesFetcher(this.data);

  final Uint8List data;
  final List<String> urls = <String>[];

  @override
  Future<FetchResponse> open(Uri url, int from) async {
    urls.add(url.toString());
    return FetchResponse(statusCode: 200, totalLength: data.length, body: Stream<List<int>>.fromIterable(<List<int>>[data]));
  }
}

const String ytId = 'abcdefghijk';
const String pageUrl = 'https://example.com/post/1';

Map<String, String> allPages() {
  final Map<String, Object?> player = <String, Object?>{
    'videoDetails': <String, Object?>{'title': 'Lullaby', 'lengthSeconds': '95'},
    'streamingData': <String, Object?>{
      'formats': <Object?>[
        <String, Object?>{'url': 'https://yt.example/v360.mp4', 'mimeType': 'video/mp4', 'width': 640, 'height': 360},
      ],
      'adaptiveFormats': <Object?>[
        <String, Object?>{'url': 'https://yt.example/v1080.mp4', 'mimeType': 'video/mp4; codecs="avc1"', 'bitrate': 4000000},
        <String, Object?>{'url': 'https://yt.example/a140.m4a', 'mimeType': 'audio/mp4; codecs="mp4a.40.2"', 'bitrate': 130000},
        <String, Object?>{'url': 'https://yt.example/a251.webm', 'mimeType': 'audio/webm; codecs="opus"', 'bitrate': 160000},
        <String, Object?>{'signatureCipher': 's=abc', 'mimeType': 'audio/mp4', 'bitrate': 50000},
      ],
    },
  };
  return <String, String>{
    'https://www.youtube.com/watch?v=$ytId':
        '<html><script>var ytInitialPlayerResponse = ${jsonEncode(player)};</script></html>',
    pageUrl: '<html><head><meta property="og:title" content="Garden party">'
        '<meta property="og:video" content="https://cdn.example.com/party.mp4"></head></html>',
  };
}

AudioLinkDownloader downloader({String? Function()? blocked, AudioExtractRunner? extract}) {
  return AudioLinkDownloader(
    video: VideoLinkDownloader(pages: FakePages(allPages()), notice: MemoryNoticeStore(), blockedReason: blocked),
    extract: extract ?? (String i, String o, Duration? s, Duration? e) async => extractAudioFile(i, o, start: s, end: e),
  );
}

void main() {
  group('MP4 sound extraction', () {
    test('copies only the sound track, frames in order, as M4A', () {
      final Uint8List src = plainMp4();
      final AudioTrack t = const Mp4AudioReader().read(MemoryByteSource(src));
      expect(t.codec, 'mp4a');
      expect(t.timescale, 1000);
      expect(t.samples.length, 5);
      expect(t.duration, const Duration(seconds: 1));

      final Uint8List out = const M4aWriter().toBytes(MemoryByteSource(src), t);
      expect(topTypes(out), <String>['ftyp', 'moov', 'mdat']);
      expect(String.fromCharCodes(out.sublist(8, 12)), 'M4A ');
      expect(out.sublist(out.length - 25), <int>[for (final List<int> f in frames()) ...f]);
      expect(out.length, const M4aWriter().header(t, t.samples).length + 25, reason: 'no video bytes');

      final AudioTrack back = const Mp4AudioReader().read(MemoryByteSource(out));
      expect(back.samples.map((AudioSample s) => s.size).toList(), <int>[3, 4, 5, 6, 7]);
      expect(back.duration, const Duration(seconds: 1));
      for (int i = 0; i < 5; i++) {
        expect(out.sublist(back.samples[i].offset, back.samples[i].offset + back.samples[i].size), frames()[i]);
      }
    });

    test('trims to whole frames between start and end', () {
      final Uint8List src = plainMp4();
      final AudioTrack t = const Mp4AudioReader().read(MemoryByteSource(src));
      final Uint8List out = const M4aWriter()
          .toBytes(MemoryByteSource(src), t, start: const Duration(milliseconds: 200), end: const Duration(milliseconds: 600));
      final AudioTrack back = const Mp4AudioReader().read(MemoryByteSource(out));
      expect(back.samples.length, 2);
      expect(back.duration, const Duration(milliseconds: 400));
      expect(out.sublist(out.length - 9), <int>[...frames()[1], ...frames()[2]]);
      expect(
        () => const M4aWriter().toBytes(MemoryByteSource(src), t, start: const Duration(seconds: 5)),
        throwsA(isA<AudioExtractError>()),
      );
    });

    test('reads fragmented files too', () {
      final Uint8List src = fragmentedMp4();
      final AudioTrack t = const Mp4AudioReader().read(MemoryByteSource(src));
      expect(t.samples.length, 5);
      expect(t.duration, const Duration(seconds: 1));
      final Uint8List out = const M4aWriter().toBytes(MemoryByteSource(src), t, end: const Duration(milliseconds: 400));
      expect(topTypes(out), <String>['ftyp', 'moov', 'mdat']);
      expect(out.sublist(out.length - 7), <int>[...frames()[0], ...frames()[1]]);
    });

    test('files without sound or not MP4 are reported', () {
      expect(() => const Mp4AudioReader().read(MemoryByteSource(Uint8List.fromList(utf8.encode('hello world, not a video')))),
          throwsA(isA<AudioExtractError>()));
      final List<int> silent = box('moov', <int>[
        ...mvhd(1000, 1000),
        ...trak(
            id: 1,
            kind: 'vide',
            codec: 'avc1',
            duration: 1000,
            stts: <List<int>>[<int>[1, 1000]],
            sizes: <int>[1],
            stsc: <List<int>>[<int>[1, 1, 1]],
            offsets: <int>[0]),
      ]);
      expect(() => const Mp4AudioReader().read(MemoryByteSource(Uint8List.fromList(silent))),
          throwsA(isA<AudioExtractError>().having((AudioExtractError e) => e.message, 'message', contains('no sound'))));
    });

    test('works on files on disk', () {
      final Directory dir = Directory.systemTemp.createTempSync('aud_');
      try {
        final File input = File('${dir.path}/in.mp4')..writeAsBytesSync(plainMp4());
        extractAudioFile(input.path, '${dir.path}/out.m4a', start: const Duration(milliseconds: 400));
        final Uint8List out = File('${dir.path}/out.m4a').readAsBytesSync();
        expect(out.sublist(out.length - 18), <int>[...frames()[2], ...frames()[3], ...frames()[4]]);
      } finally {
        dir.deleteSync(recursive: true);
      }
    });
  });

  group('finding the sound', () {
    test('YouTube: sound-only files first, protected ones skipped, video as fallback', () async {
      final AudioLink a = await downloader().resolve('listen https://youtu.be/$ytId');
      expect(a.title, 'Lullaby');
      expect(a.duration, const Duration(seconds: 95));
      expect(a.formats.map((AudioFormat f) => f.url.toString()).toList(), <String>[
        'https://yt.example/a140.m4a',
        'https://yt.example/a251.webm',
        'https://yt.example/v360.mp4',
      ]);
      expect(a.best.ext, 'm4a');
      expect(a.best.label, 'M4A · 130 kbps');
      expect(a.formats[1].canTrim, isFalse);
      expect(a.formats.last.fromVideo, isTrue);
    });

    test('any page with a video: the sound is copied from the video', () async {
      final AudioLink a = await downloader().resolve(pageUrl);
      expect(a.title, 'Garden party');
      expect(a.formats.single.fromVideo, isTrue);
      expect(a.formats.single.label, 'M4A from the video');
      expect(AudioLinkDownloader.fileName(a, a.best), 'Garden party.m4a');
      expect(AudioLinkDownloader.fileName(a, a.best, trimmed: true), 'Garden party (clip).m4a');
    });

    test('direct sound links need no page; bad links and on-device mode are refused', () async {
      final AudioLink a = await downloader().resolve('https://files.example.com/songs/Rain%20song.mp3');
      expect(a.title, 'Rain song');
      expect(a.best.ext, 'mp3');
      expect(a.best.canTrim, isFalse);
      await expectLater(downloader().resolve('no link here'), throwsA(isA<VideoLinkError>()));
      await expectLater(downloader(blocked: () => 'On-device mode is on').resolve(pageUrl),
          throwsA(isA<VideoLinkError>().having((VideoLinkError e) => e.message, 'm', 'On-device mode is on')));
      await expectLater(downloader().resolve('https://example.com/missing'), throwsA(isA<VideoLinkError>()));
    });

    test('times typed as m:ss', () {
      expect(parseClock(''), isNull);
      expect(parseClock('1:30'), const Duration(seconds: 90));
      expect(parseClock('1:02:03'), const Duration(hours: 1, minutes: 2, seconds: 3));
      expect(parseClock('45'), const Duration(seconds: 45));
      expect(() => parseClock('1:75'), throwsFormatException);
      expect(() => parseClock('abc'), throwsFormatException);
      expect(formatClock(const Duration(seconds: 95)), '1:35');
      expect(const TrimRange(start: Duration(seconds: 5), end: Duration(seconds: 2)).problem(null), isNotNull);
      expect(const TrimRange(start: Duration(seconds: 100)).problem(const Duration(seconds: 95)), isNotNull);
      expect(const TrimRange(start: Duration(seconds: 1)).problem(const Duration(seconds: 95)), isNull);
    });
  });

  group('saving', () {
    late Directory dir;
    late DownloadQueue q;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('audq_');
      q = DownloadQueue(
        fetcher: BytesFetcher(plainMp4()),
        store: MemoryDownloadQueueStore(),
        defaultFolder: () async => dir.path,
        jobs: BackgroundJobs(NoopJobHost()),
      );
    });

    tearDown(() {
      if (dir.existsSync()) {
        dir.deleteSync(recursive: true);
      }
    });

    test('from a video: downloads, copies the trimmed sound out, removes the video', () async {
      final AudioLinkDownloader d = downloader();
      final AudioLink a = await d.resolve(pageUrl);
      const TrimRange trim = TrimRange(start: Duration(milliseconds: 200));
      final DownloadTask t = await d.start(q, a, a.best, trim);
      expect(t.name, 'Garden party (source).mp4');
      final DownloadTask done = await AudioLinkDownloader.whenDone(q, t);
      final String path = await d.finish(done, a, a.best, trim);
      expect(path, '${dir.path}/Garden party (clip).m4a');
      expect(File(done.path).existsSync(), isFalse);
      final Uint8List out = File(path).readAsBytesSync();
      expect(out.sublist(out.length - 22), <int>[...frames()[1], ...frames()[2], ...frames()[3], ...frames()[4]]);
    });

    test('a sound-only file without trim is saved as it is', () async {
      final AudioLinkDownloader d = downloader();
      final AudioLink a = await d.resolve('https://youtu.be/$ytId');
      final DownloadTask t = await d.start(q, a, a.best, const TrimRange());
      final DownloadTask done = await AudioLinkDownloader.whenDone(q, t);
      final String path = await d.finish(done, a, a.best, const TrimRange());
      expect(path, '${dir.path}/Lullaby.m4a');
      expect(File(path).readAsBytesSync(), plainMp4());
      await expectLater(d.start(q, a, a.formats[1], const TrimRange(end: Duration(seconds: 3))), throwsA(isA<VideoLinkError>()));
    });
  });

  group('screen', () {
    late Directory dir;
    late DownloadQueue q;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('auds_');
      q = DownloadQueue(
        fetcher: BytesFetcher(plainMp4()),
        store: MemoryDownloadQueueStore(),
        defaultFolder: () async => dir.path,
        jobs: BackgroundJobs(NoopJobHost()),
      );
    });

    tearDown(() {
      if (dir.existsSync()) {
        dir.deleteSync(recursive: true);
      }
    });

    Future<void> io(WidgetTester tester) async {
      for (int i = 0; i < 10; i++) {
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

    testWidgets('find, trim, save as M4A, undo', (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(home: AudioLinkScreen(downloader: downloader(), queue: q)));
      await io(tester);

      await tester.enterText(find.byKey(const Key('audio-link')), pageUrl);
      await tap(tester, 'audio-find');
      expect(find.byKey(const Key('audio-notice')), findsOneWidget);
      await tap(tester, 'audio-notice-ok');
      expect(find.text('Garden party'), findsOneWidget);
      expect(find.text('M4A from the video'), findsOneWidget);

      for (final String k in <String>['audio-find', 'audio-download', 'audio-change-folder', 'audio-trim']) {
        final Size s = tester.getSize(find.byKey(Key(k)));
        expect(s.height, greaterThanOrEqualTo(44), reason: k);
        expect(s.width, greaterThanOrEqualTo(44), reason: k);
      }
      expect(find.byWidgetPredicate((Widget w) => w is Icon && w.semanticLabel == 'Folder'), findsOneWidget);

      await tap(tester, 'audio-trim');
      await tester.enterText(find.byKey(const Key('audio-start')), '0:00.4');
      await tester.enterText(find.byKey(const Key('audio-end')), '0:00.2');
      await tap(tester, 'audio-download');
      expect(find.text('The end must come after the start.'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('audio-end')), '');
      await tap(tester, 'audio-download');
      await io(tester);
      expect(find.text('Saved Garden party (clip).m4a'), findsOneWidget);
      final String saved = '${dir.path}/Garden party (clip).m4a';
      await tester.runAsync(() async {
        expect(File(saved).existsSync(), isTrue);
        expect(File('${dir.path}/Garden party (source).mp4').existsSync(), isFalse);
      });
      expect(q.tasks, isEmpty);

      await tap(tester, 'result-undo');
      await io(tester);
      await tester.runAsync(() async {
        expect(File(saved).existsSync(), isFalse);
      });
      expect(find.textContaining('Removed'), findsOneWidget);
    });
  });
}
