import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../app/widgets/result_bar.dart';
import '../../engines/platform/background_jobs.dart';
import '../../engines/share/share_engine.dart';
import '../../engines/video/video_compressor.dart';
import '../../platform/video_encoder_platform.dart';

/// Picking and keeping videos, behind an interface for tests.
abstract class VideoFiles {
  Future<String?> pick();

  /// Copies the result into the app's Files › videos; returns the new path.
  Future<String> keep(String path, String name);
  Future<void> remove(String path);
}

class SystemVideoFiles implements VideoFiles {
  const SystemVideoFiles();

  @override
  Future<String?> pick() async {
    final FilePickerResult? r = await FilePicker.platform.pickFiles(type: FileType.video);
    return r?.files.single.path;
  }

  @override
  Future<String> keep(String path, String name) async {
    final Directory dir = Directory('${(await getApplicationDocumentsDirectory()).path}/videos');
    await dir.create(recursive: true);
    final int dot = name.lastIndexOf('.');
    String out = '${dir.path}/$name';
    int n = 2;
    while (File(out).existsSync()) {
      out = '${dir.path}/${name.substring(0, dot)} ($n)${name.substring(dot)}';
      n++;
    }
    await File(path).copy(out);
    return out;
  }

  @override
  Future<void> remove(String path) async {
    final File f = File(path);
    if (f.existsSync()) {
      await f.delete();
    }
  }
}

String formatBytes(int bytes) {
  if (bytes >= 1000 * 1000) {
    return '${(bytes / 1000 / 1000).toStringAsFixed(1)} MB';
  }
  return '${(bytes / 1000).round()} KB';
}

/// Feature 036 — Compress video.
class CompressVideoScreen extends StatefulWidget {
  const CompressVideoScreen({super.key, this.compressor, this.files = const SystemVideoFiles(), this.share});

  final VideoCompressor? compressor;
  final VideoFiles files;
  final ShareEngine? share;

  @override
  State<CompressVideoScreen> createState() => _CompressVideoScreenState();
}

class _CompressVideoScreenState extends State<CompressVideoScreen> {
  late final VideoCompressor _compressor = widget.compressor ?? VideoCompressor(const PlatformVideoEncoder());
  final TextEditingController _kbps = TextEditingController(text: '1500');
  String? _source;
  VideoInfo? _info;
  VideoPreset _preset = VideoPreset.whatsapp;
  bool _custom = false;
  bool _busy = false;
  VideoResult? _result;
  final List<String> _kept = <String>[];
  String? _status;

  VideoPreset get _chosen => _custom ? VideoPreset.custom(int.tryParse(_kbps.text) ?? 1500) : _preset;

  @override
  void dispose() {
    _kbps.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final String? p = await widget.files.pick();
    if (p == null) {
      return;
    }
    final VideoInfo info = await _compressor.encoder.probe(p);
    if (!mounted) {
      return;
    }
    setState(() {
      _source = p;
      _info = info;
      _result = null;
      _status = null;
    });
  }

  Future<void> _go() async {
    final String? src = _source;
    if (src == null) {
      setState(() => _status = 'Pick a video first');
      return;
    }
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      final VideoResult r = await _compressor.compress(src, _chosen);
      if (!mounted) {
        return;
      }
      setState(() {
        _result = r;
        if (r.outputPath == r.input.path) {
          _status = 'Already small enough: ${formatBytes(r.input.bytes)}';
        } else {
          _status = '${formatBytes(r.input.bytes)} → ${formatBytes(r.outputBytes)} at ${r.size.height}p'
              '${r.hitTarget ? '' : ' (still over the limit; try a shorter clip)'}';
        }
      });
    } on JobCancelled {
      if (mounted) {
        setState(() => _status = 'Cancelled');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _status = 'Could not compress: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _cancel() {
    for (final JobRecord j in _compressor.jobs.active) {
      _compressor.jobs.cancel(j.id);
    }
  }

  String get _outName {
    final String src = _source ?? 'video.mp4';
    final String base = src.substring(src.lastIndexOf('/') + 1);
    final int dot = base.lastIndexOf('.');
    return '${dot > 0 ? base.substring(0, dot) : base}-small.mp4';
  }

  Future<void> _save() async {
    final VideoResult? r = _result;
    if (r == null) {
      setState(() => _status = 'Compress a video first');
      return;
    }
    final String p = await widget.files.keep(r.outputPath, _outName);
    if (!mounted) {
      return;
    }
    setState(() {
      _kept.add(p);
      _status = 'Saved ${p.substring(p.lastIndexOf('/') + 1)} in Files › videos';
    });
  }

  Future<void> _share() async {
    final VideoResult? r = _result;
    if (r == null) {
      setState(() => _status = 'Compress a video first');
      return;
    }
    await (widget.share ?? ShareEngine.instance).shareFiles(<String>[r.outputPath]);
  }

  Future<void> _undo() async {
    if (_kept.isNotEmpty) {
      final String p = _kept.removeLast();
      await widget.files.remove(p);
      if (mounted) {
        setState(() => _status = 'Removed ${p.substring(p.lastIndexOf('/') + 1)}');
      }
      return;
    }
    if (_result != null) {
      setState(() {
        _result = null;
        _status = 'Back to the original';
      });
      return;
    }
    if (mounted) {
      await Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final VideoInfo? info = _info;
    return Scaffold(
      appBar: AppBar(title: const Text('Compress video')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          OutlinedButton.icon(
            key: const Key('video-pick'),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: _busy ? null : _pick,
            icon: const Icon(Icons.video_library_outlined),
            label: Text(info == null ? 'Pick a video' : 'Pick another video'),
          ),
          if (info != null)
            ListTile(
              key: const Key('video-info'),
              title: Text(_source!.substring(_source!.lastIndexOf('/') + 1)),
              subtitle: Text('${formatBytes(info.bytes)} · ${info.width}×${info.height} · ${info.duration.inSeconds} s'),
            ),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
            for (final VideoPreset p in VideoPreset.fixed)
              ChoiceChip(
                key: Key('video-preset-${p.kind.name}'),
                materialTapTargetSize: MaterialTapTargetSize.padded,
                label: Text(p.label),
                selected: !_custom && _preset.kind == p.kind,
                onSelected: (_) => setState(() {
                  _custom = false;
                  _preset = p;
                }),
              ),
            ChoiceChip(
              key: const Key('video-preset-custom'),
              materialTapTargetSize: MaterialTapTargetSize.padded,
              label: const Text('Custom bitrate'),
              selected: _custom,
              onSelected: (_) => setState(() => _custom = true),
            ),
          ]),
          if (_custom)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: TextField(
                key: const Key('video-kbps'),
                controller: _kbps,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Video bitrate (kbps)'),
                onChanged: (_) => setState(() {}),
              ),
            ),
          if (info != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'About ${formatBytes(VideoPlanner.estimateBytes(VideoPlanner.plan(info, _chosen), info))} '
                'at ${VideoPlanner.plan(info, _chosen).size.height}p',
                key: const Key('video-estimate'),
              ),
            ),
          const SizedBox(height: 12),
          if (!_busy)
            FilledButton.icon(
              key: const Key('video-go'),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              onPressed: _go,
              icon: const Icon(Icons.compress),
              label: const Text('Compress'),
            )
          else
            ListenableBuilder(
              listenable: _compressor.jobs,
              builder: (BuildContext context, Widget? _) {
                final List<JobRecord> active = _compressor.jobs.active;
                final JobRecord? j = active.isEmpty ? null : active.first;
                return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
                  LinearProgressIndicator(
                    key: const Key('video-progress'),
                    value: j?.fraction,
                    semanticsLabel: 'Compression progress',
                    semanticsValue: '${j?.percent ?? 0}%',
                  ),
                  const SizedBox(height: 4),
                  Text(j?.statusLine ?? 'Starting…'),
                  const Text('You can leave the app; it keeps going in the background.'),
                  TextButton(
                    key: const Key('video-cancel'),
                    style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                    onPressed: _cancel,
                    child: const Text('Cancel'),
                  ),
                ]);
              },
            ),
          if (_status != null)
            ListTile(
              key: const Key('video-status'),
              leading: const Icon(Icons.info_outline, semanticLabel: 'Note'),
              title: Text(_status!),
            ),
        ],
      ),
      bottomNavigationBar: ResultBar(onShare: _share, onSave: _save, onUndo: _undo),
    );
  }
}
