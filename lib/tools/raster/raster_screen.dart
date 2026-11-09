import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../app/widgets/result_bar.dart';
import '../../engines/image/raster_convert.dart';
import '../../engines/share/share_engine.dart';
import '../compress_images/compress_images_screen.dart' show ImageFiles, SystemImageFiles;

/// Picks PNG, JPG, GIF, BMP, TIFF (and WebP) from the phone.
class SystemRasterFiles extends SystemImageFiles {
  const SystemRasterFiles();

  @override
  Future<List<String>> pick() async {
    final FilePickerResult? r = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: RasterFormat.readable,
      allowMultiple: true,
    );
    return r == null ? <String>[] : r.files.map((PlatformFile f) => f.path).whereType<String>().toList();
  }
}

/// Feature 027 — Raster any to any.
class RasterScreen extends StatefulWidget {
  const RasterScreen({super.key, this.files = const SystemRasterFiles(), this.share});

  final ImageFiles files;
  final ShareEngine? share;

  @override
  State<RasterScreen> createState() => _RasterScreenState();
}

class _RasterScreenState extends State<RasterScreen> {
  List<String> _paths = <String>[];
  RasterFormat _target = RasterFormat.png;
  double _quality = RasterConverter.defaultQuality.toDouble();
  final List<String> _saved = <String>[];
  String? _status;
  bool _working = false;

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
      _target = RasterConverter.defaultTarget(p.first);
      _status = null;
    });
  }

  Future<void> _run() async {
    if (_paths.isEmpty || _working) {
      return;
    }
    setState(() => _working = true);
    const RasterConverter c = RasterConverter();
    final List<String> saved = <String>[];
    int lostAlpha = 0;
    String? error;
    for (final String path in _paths) {
      try {
        final RasterResult r =
            c.convert(await widget.files.read(path), path.split('/').last, _target, quality: _quality.round());
        for (final RasterPage page in r.pages) {
          saved.add(await widget.files.write(page.name, page.bytes));
        }
        if (r.hadAlpha && !r.keptAlpha) {
          lostAlpha++;
        }
      } on RasterConvertError catch (e) {
        error = e.message;
      }
    }
    if (!mounted) {
      return;
    }
    final String? err = error;
    setState(() {
      _working = false;
      _saved
        ..clear()
        ..addAll(saved);
      _status = <String>[
        '${saved.length} ${saved.length == 1 ? 'picture' : 'pictures'} saved as ${_target.label}',
        if (lostAlpha > 0) 'see-through parts filled with white (${_target.label} has no transparency here)',
        if (err != null) err,
      ].join('. ');
    });
  }

  Future<void> _share() async {
    if (_saved.isEmpty) {
      _toast('Convert first');
      return;
    }
    await (widget.share ?? ShareEngine.instance).shareFiles(List<String>.of(_saved));
  }

  void _save() => _toast(_saved.isEmpty ? 'Nothing to save yet' : 'Saved in Files › compressed');

  Future<void> _undo() async {
    if (_saved.isEmpty) {
      Navigator.of(context).maybePop();
      return;
    }
    for (final String p in _saved) {
      await widget.files.remove(p);
    }
    setState(() {
      _saved.clear();
      _status = 'Removed the converted copies';
    });
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Convert pictures')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          OutlinedButton.icon(
            key: const Key('raster-pick'),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: _working ? null : _pick,
            icon: const Icon(Icons.photo_library_outlined),
            label: Text(_paths.isEmpty
                ? 'Choose pictures'
                : _paths.length == 1
                    ? _paths.first.split('/').last
                    : '${_paths.length} pictures'),
          ),
          const SizedBox(height: 16),
          Text('Convert to', style: text.titleSmall),
          Wrap(spacing: 8, children: <Widget>[
            for (final RasterFormat t in RasterFormat.values)
              ChoiceChip(
                key: Key('raster-to-${t.extension}'),
                materialTapTargetSize: MaterialTapTargetSize.padded,
                label: Text(t.label),
                selected: _target == t,
                onSelected: (_) => setState(() => _target = t),
              ),
          ]),
          if (_target.lossy) ...<Widget>[
            const SizedBox(height: 8),
            Text('Quality ${_quality.round()}', style: text.titleSmall),
            Slider(
              key: const Key('raster-quality'),
              min: 10,
              max: 100,
              divisions: 18,
              value: _quality,
              label: '${_quality.round()}',
              semanticFormatterCallback: (double v) => 'Quality ${v.round()}',
              onChanged: (double v) => setState(() => _quality = v),
            ),
          ],
          if (!_target.keepsAlpha)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('${_target.label} here has no transparency: see-through parts become white.'),
            ),
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('A TIFF with several pages becomes one picture per page.'),
          ),
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('raster-run'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: _paths.isEmpty || _working ? null : _run,
            child: const Text('Convert'),
          ),
          if (_status != null)
            ListTile(
              key: const Key('raster-status'),
              leading: Icon(_saved.isEmpty ? Icons.info_outline : Icons.check_circle,
                  semanticLabel: _saved.isEmpty ? 'Note' : 'Done'),
              title: Text(_status!),
            ),
        ],
      ),
      bottomNavigationBar: ResultBar(onShare: _share, onSave: _save, onUndo: _undo),
    );
  }
}
