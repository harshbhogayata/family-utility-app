import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/widgets/result_bar.dart';
import '../../engines/share/share_engine.dart';
import '../../engines/video/media_kit_backend.dart';
import '../../engines/video/video_player_engine.dart';
import '../compress_video/compress_video_screen.dart' show SystemVideoFiles, VideoFiles;

/// Resume positions in this phone's preferences; nothing leaves the phone.
class PrefsResumeStore implements ResumeStore {
  const PrefsResumeStore();

  @override
  Future<int?> read(String key) async => (await SharedPreferences.getInstance()).getInt(key);

  @override
  Future<void> write(String key, int millis) async => (await SharedPreferences.getInstance()).setInt(key, millis);

  @override
  Future<void> clear(String key) async => (await SharedPreferences.getInstance()).remove(key);
}

/// Picks a video, or a subtitle file to go with it.
abstract class PlayerFiles {
  Future<String?> pickVideo();
  Future<String?> pickSubtitle();
}

class SystemPlayerFiles implements PlayerFiles {
  const SystemPlayerFiles();

  @override
  Future<String?> pickVideo() async {
    final FilePickerResult? r = await FilePicker.platform.pickFiles(type: FileType.any);
    return r?.files.single.path;
  }

  @override
  Future<String?> pickSubtitle() async {
    final FilePickerResult? r = await FilePicker.platform.pickFiles(type: FileType.any);
    return r?.files.single.path;
  }
}

/// Feature 130 — Universal video player.
class VideoPlayerScreen extends StatefulWidget {
  const VideoPlayerScreen({
    super.key,
    this.path,
    this.backendFactory,
    this.platform,
    this.resume,
    this.files,
    this.keeper,
    this.share,
  });

  /// A file opened from elsewhere (065); otherwise the person picks one.
  final String? path;
  final VideoBackend Function()? backendFactory;
  final PlayerPlatform? platform;
  final ResumeStore? resume;
  final PlayerFiles? files;
  final VideoFiles? keeper;
  final ShareEngine? share;

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  VideoBackend? _backend;
  final List<StreamSubscription<Object?>> _subs = <StreamSubscription<Object?>>[];
  String? _path;
  String? _resumeKey;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _playing = false;
  List<MediaTrack> _tracks = <MediaTrack>[];
  String? _subtitleName;
  bool _controls = true;
  double _brightness = 0.5;
  double _volume = 1;
  String? _hud;
  Timer? _hudTimer;
  SwipeTarget? _swipe;
  Offset? _lastTap;
  String? _savedTo;
  DateTime _lastSaved = DateTime.fromMillisecondsSinceEpoch(0);

  late final ResumePolicy _policy = ResumePolicy(store: widget.resume ?? const PrefsResumeStore());
  PlayerPlatform get _platform => widget.platform ?? PlayerPlatform.instance;

  @override
  void initState() {
    super.initState();
    unawaited(_initBrightness());
    final String? p = widget.path;
    if (p != null) {
      unawaited(_open(p));
    }
  }

  Future<void> _initBrightness() async {
    final double? b = await _platform.brightness();
    if (b != null && mounted) {
      setState(() => _brightness = b);
    }
  }

  void _toast(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(m)));
    }
  }

  String _name(String p) => p.split(RegExp(r'[/\\]')).last;

  Future<void> _pick() async {
    final String? p = await (widget.files ?? const SystemPlayerFiles()).pickVideo();
    if (p == null) {
      return;
    }
    if (!VideoFormats.isVideo(p)) {
      _toast('${_name(p)} is not a video this player knows');
      return;
    }
    await _open(p);
  }

  Future<void> _open(String path) async {
    await _close();
    final VideoBackend b = (widget.backendFactory ?? MediaKitBackend.new)();
    int bytes = 0;
    try {
      bytes = File(path).lengthSync();
    } catch (_) {
      // Size unknown: the path alone keys the resume position.
    }
    final String key = ResumePolicy.keyFor(path, bytes);
    _subs
      ..add(b.position.listen(_onPosition))
      ..add(b.duration.listen((Duration d) => _update(() => _duration = d)))
      ..add(b.playing.listen((bool v) => _update(() => _playing = v)))
      ..add(b.subtitles.listen((List<MediaTrack> t) => _update(() => _tracks = t)));
    _update(() {
      _backend = b;
      _path = path;
      _resumeKey = key;
      _subtitleName = null;
      _position = Duration.zero;
    });
    // Duration is not known yet; the stored position is checked only
    // against the "barely started" rule here and the tail rule on save.
    final Duration? from = await _policy.load(key, Duration.zero);
    await b.open(path, start: from);
    if (from != null) {
      _toast('Resumed from ${formatPlayerTime(from)}');
    }
  }

  void _update(VoidCallback f) {
    if (mounted) {
      setState(f);
    }
  }

  void _onPosition(Duration p) {
    if (!mounted) {
      return;
    }
    setState(() => _position = p);
    final DateTime now = DateTime.now();
    if (now.difference(_lastSaved) > const Duration(seconds: 5)) {
      _lastSaved = now;
      unawaited(_rememberPosition());
    }
  }

  Future<void> _rememberPosition() async {
    final String? key = _resumeKey;
    if (key != null) {
      await _policy.save(key, _position, _duration);
    }
  }

  Future<void> _close() async {
    await _rememberPosition();
    for (final StreamSubscription<Object?> s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    await _backend?.dispose();
    _backend = null;
  }

  @override
  void dispose() {
    _hudTimer?.cancel();
    unawaited(_close());
    unawaited(_platform.setBrightness(null));
    super.dispose();
  }

  void _showHud(String text) {
    _hudTimer?.cancel();
    setState(() => _hud = text);
    _hudTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) {
        setState(() => _hud = null);
      }
    });
  }

  void _dragStart(DragStartDetails d, double width) {
    _swipe = GestureMath.targetFor(d.localPosition.dx, width);
  }

  void _dragUpdate(DragUpdateDetails d, double height) {
    final SwipeTarget? t = _swipe;
    if (t == null) {
      return;
    }
    if (t == SwipeTarget.brightness) {
      _brightness = GestureMath.adjust(_brightness, d.delta.dy, height);
      unawaited(_platform.setBrightness(_brightness));
      _showHud('Brightness ${GestureMath.percent(_brightness)}');
    } else {
      _volume = GestureMath.adjust(_volume, d.delta.dy, height);
      unawaited(_backend?.setVolume(_volume));
      _showHud('Volume ${GestureMath.percent(_volume)}');
    }
  }

  void _doubleTap(double width) {
    final VideoBackend? b = _backend;
    final Offset? at = _lastTap;
    if (b == null || at == null) {
      return;
    }
    final Duration to = GestureMath.doubleTapSeek(_position, _duration, at.dx, width);
    unawaited(b.seek(to));
    _showHud(at.dx < width / 2 ? '− 10 s' : '+ 10 s');
  }

  Future<void> _subtitleMenu() async {
    final VideoBackend? b = _backend;
    if (b == null) {
      return;
    }
    final String? choice = await showModalBottomSheet<String>(
      context: context,
      builder: (BuildContext context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: <Widget>[
            ListTile(
              key: const Key('subtitle-off'),
              leading: const Icon(Icons.subtitles_off_outlined),
              title: const Text('Subtitles off'),
              onTap: () => Navigator.pop(context, '\u0000off'),
            ),
            for (final MediaTrack t in _tracks)
              ListTile(
                leading: const Icon(Icons.subtitles_outlined),
                title: Text(t.label),
                onTap: () => Navigator.pop(context, t.id),
              ),
            ListTile(
              key: const Key('subtitle-load'),
              leading: const Icon(Icons.file_open_outlined),
              title: const Text('Load SRT file…'),
              onTap: () => Navigator.pop(context, '\u0000load'),
            ),
          ],
        ),
      ),
    );
    if (choice == null) {
      return;
    }
    if (choice == '\u0000off') {
      await b.selectSubtitle(null);
      setState(() => _subtitleName = null);
    } else if (choice == '\u0000load') {
      await _loadSrt(b);
    } else {
      await b.selectSubtitle(choice);
      setState(() => _subtitleName = _tracks.firstWhere((MediaTrack t) => t.id == choice).label);
    }
  }

  Future<void> _loadSrt(VideoBackend b) async {
    final String? p = await (widget.files ?? const SystemPlayerFiles()).pickSubtitle();
    if (p == null) {
      return;
    }
    if (!VideoFormats.isSubtitle(p)) {
      _toast('Pick an .srt, .vtt or .ass file');
      return;
    }
    if (VideoFormats.extensionOf(p) == 'srt') {
      String text;
      try {
        text = await File(p).readAsString();
      } catch (_) {
        text = '';
      }
      if (SrtParser.parse(text).isEmpty) {
        _toast('No subtitle lines found in ${_name(p)}');
        return;
      }
    }
    await b.loadSubtitle(p);
    setState(() => _subtitleName = _name(p));
  }

  Future<void> _pip() async {
    final String? p = _path;
    if (p == null) {
      return;
    }
    if (Platform.isIOS && !VideoFormats.iosPipCapable(p)) {
      _toast('Pop-up window on iPhone plays MP4 and MOV');
      return;
    }
    if (Platform.isIOS && _playing) {
      // AVPlayer takes over in the pop-up from the same position.
      await _backend?.playOrPause();
    }
    final bool ok = await _platform.enterPip(path: p, position: _position, aspect: 16 / 9);
    if (!ok) {
      _toast('Pop-up window is not available on this phone');
    }
  }

  Future<void> _share() async {
    final String? p = _path;
    if (p == null) {
      _toast('Open a video first');
      return;
    }
    await (widget.share ?? ShareEngine.instance).shareFiles(<String>[p]);
  }

  Future<void> _save() async {
    final String? p = _path;
    if (p == null) {
      _toast('Open a video first');
      return;
    }
    final String to = await (widget.keeper ?? const SystemVideoFiles()).keep(p, _name(p));
    setState(() => _savedTo = to);
    _toast('Saved to Files › videos');
  }

  Future<void> _undo() async {
    final String? s = _savedTo;
    if (s == null) {
      _toast('Nothing to undo');
      return;
    }
    await (widget.keeper ?? const SystemVideoFiles()).remove(s);
    setState(() => _savedTo = null);
    _toast('Saved copy removed');
  }

  Widget _player(VideoBackend b) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) => GestureDetector(
        key: const Key('player-surface'),
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _controls = !_controls),
        onDoubleTapDown: (TapDownDetails d) => _lastTap = d.localPosition,
        onDoubleTap: () => _doubleTap(c.maxWidth),
        onVerticalDragStart: (DragStartDetails d) => _dragStart(d, c.maxWidth),
        onVerticalDragUpdate: (DragUpdateDetails d) => _dragUpdate(d, c.maxHeight),
        onVerticalDragEnd: (_) => _swipe = null,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            ColoredBox(color: Colors.black, child: Center(child: b.view())),
            if (_hud != null)
              Center(
                child: DecoratedBox(
                  decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: Text(_hud!, key: const Key('player-hud'), style: const TextStyle(color: Colors.white, fontSize: 18)),
                  ),
                ),
              ),
            if (_controls) Align(alignment: Alignment.bottomCenter, child: _controlBar(b)),
          ],
        ),
      ),
    );
  }

  Widget _controlBar(VideoBackend b) {
    final double max = _duration.inMilliseconds.toDouble();
    final double value = _position.inMilliseconds.toDouble().clamp(0.0, max <= 0 ? 0.0 : max);
    return ColoredBox(
      color: Colors.black45,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: <Widget>[
            IconButton(
              key: const Key('play-pause'),
              color: Colors.white,
              iconSize: 32,
              tooltip: _playing ? 'Pause' : 'Play',
              icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
              onPressed: b.playOrPause,
            ),
            Text(formatPlayerTime(_position), style: const TextStyle(color: Colors.white)),
            Expanded(
              child: Semantics(
                label: 'Seek',
                child: Slider(
                  value: value,
                  max: max <= 0 ? 1 : max,
                  onChanged: max <= 0 ? null : (double v) => b.seek(Duration(milliseconds: v.round())),
                ),
              ),
            ),
            Text(formatPlayerTime(_duration), style: const TextStyle(color: Colors.white)),
            IconButton(
              key: const Key('subtitles'),
              color: Colors.white,
              tooltip: 'Subtitles',
              icon: const Icon(Icons.subtitles_outlined),
              onPressed: _subtitleMenu,
            ),
            IconButton(
              key: const Key('pip'),
              color: Colors.white,
              tooltip: 'Pop-up window',
              icon: const Icon(Icons.picture_in_picture_alt_outlined),
              onPressed: _pip,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final VideoBackend? b = _backend;
    final String? p = _path;
    return Scaffold(
      appBar: AppBar(
        title: Text(p == null ? 'Video player' : _name(p), maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: <Widget>[
          IconButton(
            key: const Key('open-video'),
            tooltip: 'Open a video',
            icon: const Icon(Icons.folder_open_outlined),
            onPressed: _pick,
          ),
        ],
      ),
      body: b == null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Text(
                      'Plays MP4, MKV, AVI, MOV, WebM, TS and more, with subtitles. '
                      'Swipe left side for brightness, right side for volume; double-tap to skip 10 s.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      key: const Key('pick-video'),
                      onPressed: _pick,
                      icon: const Icon(Icons.video_library_outlined),
                      label: const Text('Open a video'),
                    ),
                  ],
                ),
              ),
            )
          : Column(
              children: <Widget>[
                Expanded(child: _player(b)),
                if (_subtitleName != null)
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text('Subtitles: $_subtitleName', key: const Key('subtitle-name')),
                  ),
              ],
            ),
      bottomNavigationBar: ResultBar(onShare: _share, onSave: _save, onUndo: _undo),
    );
  }
}
