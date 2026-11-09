import 'package:flutter/material.dart';

import '../../app/widgets/result_bar.dart';
import '../../engines/image/webp_convert.dart';
import '../../engines/share/share_engine.dart';
import '../../platform/webp_platform.dart';
import '../compress_images/compress_images_screen.dart' show ImageFiles, SystemImageFiles;

/// Feature 026 — WebP to JPG or PNG and back.
class WebpScreen extends StatefulWidget {
  const WebpScreen({
    super.key,
    this.files = const SystemImageFiles(),
    this.encoder = const PlatformWebpEncoder(),
    this.share,
  });

  final ImageFiles files;
  final WebpEncoder encoder;
  final ShareEngine? share;

  @override
  State<WebpScreen> createState() => _WebpScreenState();
}

class _WebpScreenState extends State<WebpScreen> {
  List<String> _paths = <String>[];
  ImageTarget _target = ImageTarget.png;
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
      _target = WebpConverter.defaultTarget(p.first);
      _status = null;
    });
  }

  Future<void> _run() async {
    if (_paths.isEmpty || _working) {
      return;
    }
    setState(() => _working = true);
    final WebpConverter c = WebpConverter(widget.encoder);
    final List<String> saved = <String>[];
    int lostAlpha = 0;
    String? error;
    for (final String path in _paths) {
      try {
        final WebpConverted r = await c.convert(await widget.files.read(path), path.split('/').last, _target);
        saved.add(await widget.files.write(r.name, r.bytes));
        if (r.hadAlpha && !r.keptAlpha) {
          lostAlpha++;
        }
      } on WebpConvertError catch (e) {
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
      final String n = '${saved.length} ${saved.length == 1 ? 'picture' : 'pictures'} saved as ${_target.label}';
      _status = <String>[
        n,
        if (lostAlpha > 0) 'see-through parts filled with white (JPG has no transparency)',
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
      appBar: AppBar(title: const Text('WebP converter')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          OutlinedButton.icon(
            key: const Key('webp-pick'),
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
            for (final ImageTarget t in ImageTarget.values)
              ChoiceChip(
                key: Key('webp-to-${t.extension}'),
                materialTapTargetSize: MaterialTapTargetSize.padded,
                label: Text(t.label),
                selected: _target == t,
                onSelected: (_) => setState(() => _target = t),
              ),
          ]),
          if (_target == ImageTarget.jpg)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('JPG has no transparency: see-through parts become white. Pick PNG to keep them.'),
            ),
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('webp-run'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: _paths.isEmpty || _working ? null : _run,
            child: const Text('Convert'),
          ),
          if (_status != null)
            ListTile(
              key: const Key('webp-status'),
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
