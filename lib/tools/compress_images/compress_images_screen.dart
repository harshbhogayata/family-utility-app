import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../app/widgets/result_bar.dart';
import '../../engines/image/image_compressor.dart';
import '../../engines/share/share_engine.dart';

/// Reads picked images and writes the compressed copies. Behind an interface
/// so tests need neither the picker nor the disk.
abstract class ImageFiles {
  /// Paths of the picked images (a gallery selection in batch mode).
  Future<List<String>> pick();

  Future<Uint8List> read(String path);

  /// Saves next to the app's other outputs. Returns the saved path.
  Future<String> write(String name, Uint8List bytes);

  Future<void> remove(String path);
}

class SystemImageFiles implements ImageFiles {
  const SystemImageFiles();

  @override
  Future<List<String>> pick() async {
    final FilePickerResult? r = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: <String>['jpg', 'jpeg', 'png', 'webp'],
      allowMultiple: true,
    );
    return r == null ? <String>[] : r.files.map((PlatformFile f) => f.path).whereType<String>().toList();
  }

  @override
  Future<Uint8List> read(String path) => File(path).readAsBytes();

  @override
  Future<String> write(String name, Uint8List bytes) async {
    final Directory base = await getApplicationDocumentsDirectory();
    final Directory dir = Directory('${base.path}/compressed');
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

typedef CompressRunner = Future<CompressResult> Function(Uint8List input, CompressSettings settings);

Future<CompressResult> compressInIsolate(Uint8List input, CompressSettings settings) {
  return compute(_run, _Job(input, settings));
}

class _Job {
  const _Job(this.input, this.settings);
  final Uint8List input;
  final CompressSettings settings;
}

CompressResult _run(_Job j) => ImageCompressor.compress(j.input, j.settings);

class _Item {
  _Item(this.path, this.bytes);
  final String path;
  final Uint8List bytes;
  CompressResult? result;
  String? error;

  String get name => path.split('/').last;
}

/// Feature 034 — Compress images.
class CompressImagesScreen extends StatefulWidget {
  const CompressImagesScreen({
    super.key,
    this.files = const SystemImageFiles(),
    this.runner = compressInIsolate,
    this.share,
    this.debounce = const Duration(milliseconds: 250),
  });

  final ImageFiles files;
  final CompressRunner runner;
  final ShareEngine? share;
  final Duration debounce;

  @override
  State<CompressImagesScreen> createState() => _CompressImagesScreenState();
}

class _CompressImagesScreenState extends State<CompressImagesScreen> {
  List<_Item> _items = <_Item>[];
  double _quality = 75;
  bool _shrink = false;
  bool _working = false;
  Timer? _timer;
  int _run = 0;
  final List<String> _saved = <String>[];

  CompressSettings get _settings => CompressSettings(quality: _quality.round(), maxSide: _shrink ? 2048 : null);

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _toast(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(m)));
    }
  }

  Future<void> _pick() async {
    final List<String> paths = await widget.files.pick();
    if (paths.isEmpty) {
      return;
    }
    final List<_Item> items = <_Item>[];
    for (final String p in paths) {
      items.add(_Item(p, await widget.files.read(p)));
    }
    if (!mounted) {
      return;
    }
    setState(() => _items = items);
    await _estimate();
  }

  void _changed() {
    _timer?.cancel();
    _timer = Timer(widget.debounce, _estimate);
  }

  Future<void> _estimate() async {
    final int run = ++_run;
    setState(() => _working = true);
    final CompressSettings s = _settings;
    for (final _Item it in _items) {
      try {
        it.result = await widget.runner(it.bytes, s);
        it.error = null;
      } catch (e) {
        it.result = null;
        it.error = '$e';
      }
      if (run != _run || !mounted) {
        return; // a newer slider value took over
      }
    }
    setState(() => _working = false);
  }

  int get _before => _items.fold<int>(0, (int a, _Item i) => a + i.bytes.length);

  int get _after => _items.fold<int>(
      0, (int a, _Item i) => a + ((i.result?.noGain ?? true) ? i.bytes.length : i.result!.size));

  Future<void> _save() async {
    if (_items.isEmpty || _working) {
      _toast(_items.isEmpty ? 'Choose images first' : 'Still working…');
      return;
    }
    int kept = 0;
    for (final _Item it in _items) {
      final CompressResult? r = it.result;
      if (r == null || r.noGain) {
        continue; // keep the original: the copy would not be smaller
      }
      _saved.add(await widget.files.write(ImageCompressor.outputName(it.path, r.format), r.bytes));
      kept++;
    }
    _toast(kept == 0 ? 'Already as small as it gets' : 'Saved $kept in Files › compressed');
  }

  Future<void> _share() async {
    if (_saved.isEmpty) {
      await _save();
    }
    if (_saved.isNotEmpty) {
      await (widget.share ?? ShareEngine.instance).shareFiles(List<String>.of(_saved));
    }
  }

  Future<void> _undo() async {
    if (_saved.isNotEmpty) {
      final int n = _saved.length;
      for (final String p in _saved) {
        await widget.files.remove(p);
      }
      _saved.clear();
      _toast('Removed $n compressed ${n == 1 ? 'copy' : 'copies'}');
      return;
    }
    if (_items.isNotEmpty) {
      setState(() => _items = <_Item>[]);
      return;
    }
    if (mounted) {
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Compress images')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          OutlinedButton.icon(
            key: const Key('compress-pick'),
            onPressed: _pick,
            icon: const Icon(Icons.photo_library_outlined),
            label: Text(_items.isEmpty ? 'Choose images' : 'Choose again'),
          ),
          const SizedBox(height: 16),
          Text('Quality ${_quality.round()}', style: text.titleMedium),
          Slider(
            key: const Key('compress-quality'),
            value: _quality,
            min: 10,
            max: 95,
            divisions: 17,
            label: '${_quality.round()}',
            semanticFormatterCallback: (double v) => 'Quality ${v.round()}',
            onChanged: (double v) {
              setState(() => _quality = v);
              _changed();
            },
          ),
          SwitchListTile(
            key: const Key('compress-shrink'),
            title: const Text('Also shrink to 2048 px'),
            subtitle: const Text('Never makes an image bigger'),
            value: _shrink,
            onChanged: (bool v) {
              setState(() => _shrink = v);
              _changed();
            },
          ),
          if (_items.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  _working
                      ? 'Working out the size…'
                      : '${ImageCompressor.formatSize(_before)} → ${ImageCompressor.formatSize(_after)}',
                  key: const Key('compress-total'),
                  style: text.titleMedium,
                ),
              ),
            ),
          for (final _Item it in _items)
            ListTile(
              leading: const Icon(Icons.image_outlined, semanticLabel: 'Image'),
              title: Text(it.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                it.error ??
                    (it.result == null
                        ? ImageCompressor.formatSize(it.bytes.length)
                        : it.result!.noGain
                            ? 'Already small: original kept'
                            : '${ImageCompressor.formatSize(it.bytes.length)} → '
                                '${ImageCompressor.formatSize(it.result!.size)} '
                                '(${it.result!.extension.toUpperCase()}, ${it.result!.width}×${it.result!.height})'),
              ),
            ),
        ],
      ),
      bottomNavigationBar: ResultBar(onShare: _share, onSave: _save, onUndo: _undo),
    );
  }
}
