import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'video_player_engine.dart';

/// Feature 130 — libmpv on the phone (via media_kit): MKV, AVI, MOV, WebM,
/// TS and the rest, with embedded and SRT subtitles. Plays local files only.
class MediaKitBackend implements VideoBackend {
  MediaKitBackend() {
    MediaKit.ensureInitialized();
    _player = Player();
    _controller = VideoController(_player);
  }

  late final Player _player;
  late final VideoController _controller;

  @override
  Future<void> open(String path, {Duration? start}) async {
    await _player.open(Media(Uri.file(path).toString()), play: false);
    if (start != null && start > Duration.zero) {
      try {
        await _player.stream.duration.firstWhere((Duration d) => d > Duration.zero).timeout(const Duration(seconds: 5));
      } on TimeoutException {
        // Seek anyway; mpv queues it.
      }
      await _player.seek(start);
    }
    await _player.play();
  }

  @override
  Future<void> playOrPause() => _player.playOrPause();

  @override
  Future<void> seek(Duration to) => _player.seek(to);

  @override
  Future<void> setVolume(double level) => _player.setVolume((level * 100).clamp(0.0, 100.0));

  @override
  Future<void> loadSubtitle(String path) {
    final String name = path.split(Platform.pathSeparator).last;
    return _player.setSubtitleTrack(SubtitleTrack.uri(Uri.file(path).toString(), title: name));
  }

  @override
  Future<void> selectSubtitle(String? id) async {
    if (id == null) {
      await _player.setSubtitleTrack(SubtitleTrack.no());
      return;
    }
    for (final SubtitleTrack t in _player.state.tracks.subtitle) {
      if (t.id == id) {
        await _player.setSubtitleTrack(t);
        return;
      }
    }
  }

  static List<MediaTrack> _tracks(Tracks t) => t.subtitle
      .where((SubtitleTrack s) => s.id != 'auto' && s.id != 'no')
      .map((SubtitleTrack s) => MediaTrack(id: s.id, title: s.title, language: s.language))
      .toList();

  @override
  Stream<Duration> get position => _player.stream.position;

  @override
  Stream<Duration> get duration => _player.stream.duration;

  @override
  Stream<bool> get playing => _player.stream.playing;

  @override
  Stream<List<MediaTrack>> get subtitles => _player.stream.tracks.map(_tracks);

  @override
  Duration get currentPosition => _player.state.position;

  @override
  Duration get currentDuration => _player.state.duration;

  @override
  bool get isPlaying => _player.state.playing;

  @override
  Widget view() => Video(controller: _controller, controls: NoVideoControls);

  @override
  Future<void> dispose() => _player.dispose();
}
