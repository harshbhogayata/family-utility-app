import 'dart:async';

import 'package:family_utility_app/engines/video/video_player_engine.dart';
import 'package:family_utility_app/tools/compress_video/compress_video_screen.dart';
import 'package:family_utility_app/tools/video_player/video_player_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeBackend implements VideoBackend {
  final StreamController<Duration> pos = StreamController<Duration>.broadcast();
  final StreamController<Duration> dur = StreamController<Duration>.broadcast();
  final StreamController<bool> play = StreamController<bool>.broadcast();
  final StreamController<List<MediaTrack>> subs = StreamController<List<MediaTrack>>.broadcast();
  String? opened;
  Duration? openedAt;
  final List<Duration> seeks = <Duration>[];
  double volume = 1;
  String? selected = 'none-yet';
  String? loaded;
  bool playingNow = false;

  @override
  Future<void> open(String path, {Duration? start}) async {
    opened = path;
    openedAt = start;
    playingNow = true;
    play.add(true);
  }

  @override
  Future<void> playOrPause() async {
    playingNow = !playingNow;
    play.add(playingNow);
  }

  @override
  Future<void> seek(Duration to) async => seeks.add(to);

  @override
  Future<void> setVolume(double level) async => volume = level;

  @override
  Future<void> loadSubtitle(String path) async => loaded = path;

  @override
  Future<void> selectSubtitle(String? id) async => selected = id;

  @override
  Stream<Duration> get position => pos.stream;

  @override
  Stream<Duration> get duration => dur.stream;

  @override
  Stream<bool> get playing => play.stream;

  @override
  Stream<List<MediaTrack>> get subtitles => subs.stream;

  @override
  Duration get currentPosition => Duration.zero;

  @override
  Duration get currentDuration => Duration.zero;

  @override
  bool get isPlaying => playingNow;

  @override
  Widget view() => const ColoredBox(color: Colors.black, child: SizedBox.expand());

  @override
  Future<void> dispose() async {}
}

class FakePlatform extends PlayerPlatform {
  double? brightnessSet;
  bool pipEntered = false;

  @override
  Future<double?> brightness() async => 0.5;

  @override
  Future<void> setBrightness(double? level) async => brightnessSet = level;

  @override
  Future<bool> pipSupported() async => true;

  @override
  Future<bool> enterPip({required String path, required Duration position, required double aspect}) async {
    pipEntered = true;
    return true;
  }
}

class FakeFiles implements PlayerFiles {
  FakeFiles(this.video, {this.subtitle});
  final String video;
  final String? subtitle;

  @override
  Future<String?> pickVideo() async => video;

  @override
  Future<String?> pickSubtitle() async => subtitle;
}

class FakeKeeper implements VideoFiles {
  final List<String> kept = <String>[];

  @override
  Future<String?> pick() async => null;

  @override
  Future<String> keep(String path, String name) async {
    kept.add('/videos/$name');
    return '/videos/$name';
  }

  @override
  Future<void> remove(String path) async => kept.remove(path);
}

const String srt = '﻿1\r\n00:00:01,000 --> 00:00:03,500\r\nHello <i>there</i>\r\n\r\n'
    '2\r\n00:00:04,000 --> 00:00:06,000\r\nSecond line\r\nwraps here\r\n\r\n'
    'junk block\r\n\r\n'
    '00:01:00.250 --> 00:01:02.000\r\nNo number\r\n';

void main() {
  group('formats', () {
    test('plays the promised containers and nothing else', () {
      for (final String ext in <String>['mkv', 'avi', 'mov', 'webm', 'ts', 'mp4', 'MKV']) {
        expect(VideoFormats.isVideo('/d/clip.$ext'), isTrue, reason: ext);
      }
      expect(VideoFormats.isVideo('/d/notes.pdf'), isFalse);
      expect(VideoFormats.isVideo('/d/noext'), isFalse);
      expect(VideoFormats.isSubtitle('/d/film.en.srt'), isTrue);
      expect(VideoFormats.iosPipCapable('/d/a.mov'), isTrue);
      expect(VideoFormats.iosPipCapable('/d/a.mkv'), isFalse);
    });
  });

  group('SRT', () {
    final List<SubtitleCue> cues = SrtParser.parse(srt);

    test('parses BOM, CRLF, tags, multi-line and unnumbered cues', () {
      expect(cues.length, 3);
      expect(cues[0].text, 'Hello there');
      expect(cues[0].start, const Duration(seconds: 1));
      expect(cues[0].end, const Duration(seconds: 3, milliseconds: 500));
      expect(cues[1].text, 'Second line\nwraps here');
      expect(cues[2].start, const Duration(minutes: 1, milliseconds: 250));
    });

    test('finds the cue on screen', () {
      expect(SrtParser.cueAt(cues, const Duration(seconds: 2))?.text, 'Hello there');
      expect(SrtParser.cueAt(cues, const Duration(milliseconds: 3700)), isNull);
      expect(SrtParser.cueAt(cues, const Duration(seconds: 5))?.text, startsWith('Second'));
      expect(SrtParser.cueAt(cues, const Duration(hours: 1)), isNull);
    });

    test('empty or broken files give no cues', () {
      expect(SrtParser.parse(''), isEmpty);
      expect(SrtParser.parse('00:00:05,000 --> 00:00:01,000\nbackwards'), isEmpty);
    });
  });

  group('gestures', () {
    test('left half brightness, right half volume', () {
      expect(GestureMath.targetFor(10, 400), SwipeTarget.brightness);
      expect(GestureMath.targetFor(300, 400), SwipeTarget.volume);
    });

    test('swipe up raises, clamps to 0..1', () {
      expect(GestureMath.adjust(0.5, -100, 400), closeTo(0.75, 1e-9));
      expect(GestureMath.adjust(0.5, 1000, 400), 0);
      expect(GestureMath.adjust(0.9, -1000, 400), 1);
      expect(GestureMath.adjust(0.4, 10, 0), 0.4);
    });

    test('double-tap skips 10 s within the file', () {
      const Duration len = Duration(minutes: 2);
      expect(GestureMath.doubleTapSeek(const Duration(seconds: 30), len, 350, 400), const Duration(seconds: 40));
      expect(GestureMath.doubleTapSeek(const Duration(seconds: 5), len, 10, 400), Duration.zero);
      expect(GestureMath.doubleTapSeek(const Duration(seconds: 115), len, 350, 400), len);
    });
  });

  group('resume', () {
    test('skips barely-started and nearly-finished positions', () {
      const ResumePolicy p = ResumePolicy();
      const Duration len = Duration(minutes: 10);
      expect(p.resumeFrom(const Duration(seconds: 2), len), isNull);
      expect(p.resumeFrom(const Duration(minutes: 4), len), const Duration(minutes: 4));
      expect(p.resumeFrom(const Duration(minutes: 9, seconds: 55), len), isNull);
    });

    test('saves, loads and forgets per file', () async {
      final MemoryResumeStore store = MemoryResumeStore();
      final ResumePolicy p = ResumePolicy(store: store);
      final String key = ResumePolicy.keyFor('/d/film.mkv', 1234);
      await p.save(key, const Duration(minutes: 3), const Duration(minutes: 90));
      expect(await p.load(key, const Duration(minutes: 90)), const Duration(minutes: 3));
      expect(ResumePolicy.keyFor('/d/film.mkv', 999), isNot(key));
      await p.save(key, const Duration(minutes: 89, seconds: 58), const Duration(minutes: 90));
      expect(store.values, isEmpty);
    });

    test('formats times', () {
      expect(formatPlayerTime(const Duration(seconds: 65)), '1:05');
      expect(formatPlayerTime(const Duration(hours: 1, minutes: 2, seconds: 3)), '1:02:03');
    });
  });

  group('screen', () {
    late FakeBackend backend;
    late FakePlatform platform;
    late MemoryResumeStore store;
    late FakeKeeper keeper;

    Widget app({String? subtitle}) => MaterialApp(
          home: VideoPlayerScreen(
            backendFactory: () => backend,
            platform: platform,
            resume: store,
            files: FakeFiles('/d/film.mkv', subtitle: subtitle),
            keeper: keeper,
          ),
        );

    setUp(() {
      backend = FakeBackend();
      platform = FakePlatform();
      store = MemoryResumeStore();
      keeper = FakeKeeper();
    });

    testWidgets('opens an MKV, resumes, gestures, PiP, save and undo', (WidgetTester tester) async {
      store.values[ResumePolicy.keyFor('/d/film.mkv', 0)] = const Duration(minutes: 2).inMilliseconds;
      await tester.pumpWidget(app());
      expect(find.byKey(const Key('pick-video')), findsOneWidget);
      await tester.tap(find.byKey(const Key('pick-video')));
      await tester.pumpAndSettle();
      expect(backend.opened, '/d/film.mkv');
      expect(backend.openedAt, const Duration(minutes: 2));
      expect(find.text('Resumed from 2:00'), findsOneWidget);

      backend.dur.add(const Duration(minutes: 30));
      await tester.pump();

      final Rect r = tester.getRect(find.byKey(const Key('player-surface')));
      await tester.dragFrom(Offset(r.left + 20, r.center.dy), const Offset(0, -150));
      await tester.pump();
      expect(platform.brightnessSet, greaterThan(0.5));
      await tester.dragFrom(Offset(r.right - 20, r.center.dy), const Offset(0, 150));
      await tester.pump();
      expect(backend.volume, lessThan(1));
      expect(find.byKey(const Key('player-hud')), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));

      await tester.tap(find.byKey(const Key('pip')));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(platform.pipEntered, isTrue);

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(keeper.kept, <String>['/videos/film.mkv']);
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(keeper.kept, isEmpty);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });

    testWidgets('embedded subtitle tracks can be chosen and turned off', (WidgetTester tester) async {
      await tester.pumpWidget(app());
      await tester.tap(find.byKey(const Key('pick-video')));
      await tester.pumpAndSettle();
      backend.subs.add(const <MediaTrack>[MediaTrack(id: '2', title: 'English', language: 'eng')]);
      await tester.pump();

      await tester.tap(find.byKey(const Key('subtitles')));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      await tester.tap(find.text('English · eng'));
      await tester.pumpAndSettle();
      expect(backend.selected, '2');
      expect(find.text('Subtitles: English · eng'), findsOneWidget);

      await tester.tap(find.byKey(const Key('subtitles')));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('subtitle-off')));
      await tester.pumpAndSettle();
      expect(backend.selected, isNull);
      expect(find.byKey(const Key('subtitle-name')), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });

    testWidgets('controls are labelled and at least 44 px', (WidgetTester tester) async {
      final SemanticsHandle h = tester.ensureSemantics();
      await tester.pumpWidget(app());
      await tester.tap(find.byKey(const Key('pick-video')));
      await tester.pumpAndSettle();
      for (final String k in <String>['play-pause', 'subtitles', 'pip', 'open-video']) {
        final Size s = tester.getSize(find.byKey(Key(k)));
        expect(s.width, greaterThanOrEqualTo(44), reason: k);
        expect(s.height, greaterThanOrEqualTo(44), reason: k);
      }
      expect(find.byTooltip('Pop-up window'), findsOneWidget);
      expect(find.byTooltip('Subtitles'), findsOneWidget);
      h.dispose();
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  });
}
