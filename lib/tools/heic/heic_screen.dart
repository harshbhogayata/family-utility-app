import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../app/widgets/result_bar.dart';
import '../../engines/image/heic_convert.dart';
import '../../engines/image/webp_convert.dart' show ImageTarget;
import '../../engines/platform/background_jobs.dart';
import '../../engines/share/share_engine.dart';
import '../../platform/heic_platform.dart';
import '../compress_images/compress_images_screen.dart' show ImageFiles;

/// Picks iPhone photos (and any other pictures) and keeps the results in
/// Files › converted.
class SystemHeicFiles implements ImageFiles {
  const SystemHeicFiles();

  @override
  Future<List<String>> pick() async {
    final FilePickerResult? r = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: <String>['heic', 'heif', 'jpg', 'jpeg', 'png', 'webp'],
      allowMultiple: true,
    );
    return r == null ? <String>[] : r.files.map((PlatformFile f) => f.path).whereType<String>().toList();
  }

  @override
  Future<Uint8List> read(String path) => File(path).readAsBytes();

  @override
  Future<String> write(String name, Uint8List bytes) async {
    final Directory base = await getApplicationDocumentsDirectory();
    final Directory dir = Directory('${base.path}/converted');
    await dir.create(recursive: true);
    String path = '${dir.path}/$name';
    int i = 2;
    while (File(path).existsSync()) {
      final int dot = name.lastIndexOf('.');
      path = '${dir.path}/${name.substring(0, dot)} ($i)${name.substring(dot)}';
      i++;
    }
    await File(path).writeAsBytes(bytes, flush: true);
    return path;
  }

  @override
  Future<void> remove(String path) async {
    final File f = File(path);
    if (f.existsSync()) {
      await f.delete();
    }
  }
}

/// Feature 025 — HEIC to JPG or PNG. Pick or share iPhone photos; they come
/// back upright as JPG (or PNG) in the same order.
class HeicScreen extends StatefulWidget {
  const HeicScreen({
    super.key,
    this.files = const SystemHeicFiles(),
    this.codec = const PlatformHeicCodec(),
    this.jobs,
    this.share,
    this.initialPaths,
  });

  final ImageFiles files;
  final HeicCodec codec;
  final BackgroundJobs? jobs;
  final ShareEngine? share;

  /// Pictures shared into the app; converted to JPG straight away.
  final List<String>? initialPaths;

  @override
  State<HeicScreen> createState() => _HeicScreenState();
}

class _HeicScreenState extends State<HeicScreen> {
  List<String> _paths = <String>[];
  ImageTarget _target = ImageTarget.jpg;
  List<PictureResult> _results = <PictureResult>[];
  int _done = 0;
  bool _working = false;
  String? _status;

  List<String> get _saved => <String>[
        for (final PictureResult r in _results)
          if (r.outputPath != null) r.outputPath!,
      ];

  @override
  void initState() {
    super.initState();
    final List<String>? shared = widget.initialPaths;
    if (shared != null && shared.isNotEmpty) {
      _paths = List<String>.of(shared);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(_run());
        }
      });
    }
  }

  void _toast(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(m)));
    }
  }

  Future<void> _pick() async {
    final List<String> p = await widget.files.pick();
    if (!mounted || p.isEmpty) {
      return;
    }
    setState(() {
      _paths = p;
      _results = <PictureResult>[];
      _done = 0;
      _status = null;
    });
  }

  Future<void> _run() async {
    if (_paths.isEmpty || _working) {
      return;
    }
    setState(() {
      _working = true;
      _done = 0;
      _results = <PictureResult>[];
      _status = 'Converting…';
    });
    final List<String> paths = List<String>.of(_paths);
    final ImageTarget target = _target;
    List<PictureResult> results = <PictureResult>[];
    final List<String> written = <String>[];
    try {
      results = await (widget.jobs ?? BackgroundJobs.instance).run<List<PictureResult>>(
        'Convert ${paths.length} ${paths.length == 1 ? 'photo' : 'photos'} to ${target.label}',
        (JobContext ctx) => PictureConverter(widget.codec).convertAll(
          paths,
          target,
          read: widget.files.read,
          write: (String name, Uint8List bytes) async {
            final String path = await widget.files.write(name, bytes);
            written.add(path);
            return path;
          },
          cancelled: () => ctx.cancelled,
          progress: (int done, int total) {
            if (!ctx.cancelled) {
              ctx.report(done / total, '$done of $total');
            }
            if (mounted) {
              setState(() => _done = done);
            }
          },
        ),
      );
    } on JobCancelled {
      // Keep what was made so Share and Undo still see it.
      results = <PictureResult>[
        for (int i = 0; i < written.length; i++) PictureResult(source: paths[i], outputPath: written[i]),
      ];
    }
    if (!mounted) {
      return;
    }
    final int ok = results.where((PictureResult r) => r.ok).length;
    final int bad = results.length - ok;
    setState(() {
      _working = false;
      _results = results;
      _status = <String>[
        '$ok ${ok == 1 ? 'photo' : 'photos'} saved as ${target.label} in Files › converted',
        if (bad > 0) '$bad could not be converted',
      ].join('. ');
    });
  }

  Future<void> _share() async {
    final List<String> saved = _saved;
    if (saved.isEmpty) {
      _toast('Convert first');
      return;
    }
    // Same order as shared or picked.
    await (widget.share ?? ShareEngine.instance).shareFiles(saved);
  }

  void _save() => _toast(_saved.isEmpty ? 'Nothing to save yet' : 'Saved in Files › converted');

  Future<void> _undo() async {
    final List<String> saved = _saved;
    if (saved.isEmpty) {
      unawaited(Navigator.of(context).maybePop());
      return;
    }
    for (final String p in saved) {
      await widget.files.remove(p);
    }
    if (mounted) {
      setState(() {
        _results = <PictureResult>[];
        _status = 'Removed the converted copies';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('HEIC to JPG or PNG')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          const Text('iPhone photos (HEIC) become JPG or PNG that every phone and computer opens, turned upright. '
              'Share them here from Photos or Gallery, or pick them.'),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            key: const Key('heic-pick'),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: _working ? null : _pick,
            icon: const Icon(Icons.photo_library_outlined),
            label: Text(_paths.isEmpty
                ? 'Choose photos'
                : _paths.length == 1
                    ? _paths.first.split('/').last
                    : '${_paths.length} photos'),
          ),
          const SizedBox(height: 16),
          Text('Convert to', style: text.titleSmall),
          Wrap(spacing: 8, children: <Widget>[
            for (final ImageTarget t in <ImageTarget>[ImageTarget.jpg, ImageTarget.png])
              ChoiceChip(
                key: Key('heic-to-${t.extension}'),
                materialTapTargetSize: MaterialTapTargetSize.padded,
                label: Text(t.label),
                selected: _target == t,
                onSelected: _working ? null : (_) => setState(() => _target = t),
              ),
          ]),
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('heic-run'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: _paths.isEmpty || _working ? null : _run,
            child: Text('Convert to ${_target.label}'),
          ),
          if (_working && _paths.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: _done / _paths.length,
              semanticsLabel: 'Converted $_done of ${_paths.length} photos',
            ),
          ],
          if (_status != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Semantics(liveRegion: true, child: Text(_status!, key: const Key('heic-status'))),
            ),
          for (int i = 0; i < _results.length; i++)
            ListTile(
              key: Key('heic-result-$i'),
              contentPadding: EdgeInsets.zero,
              leading: Icon(_results[i].ok ? Icons.check_circle_outline : Icons.error_outline,
                  semanticLabel: _results[i].ok ? 'Converted' : 'Failed'),
              title: Text(_results[i].source.split('/').last, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(_results[i].ok ? _results[i].outputPath!.split('/').last : _results[i].error ?? ''),
            ),
        ],
      ),
      bottomNavigationBar: ResultBar(onShare: _share, onSave: _save, onUndo: () => unawaited(_undo())),
    );
  }
}
