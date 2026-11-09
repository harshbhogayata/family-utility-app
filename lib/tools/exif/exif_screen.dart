import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../app/widgets/result_bar.dart';
import '../../engines/image/exif_strip.dart';
import '../../engines/share/share_engine.dart';
import '../../platform/strip_on_share_prefs.dart';
import '../compress_images/compress_images_screen.dart' show ImageFiles, SystemImageFiles;

class _Photo {
  _Photo(this.path, this.bytes, this.meta, this.error);
  final String path;
  final Uint8List bytes;
  final PhotoMeta? meta;
  final String? error;

  String get name => path.split('/').last;
}

/// Feature 046 — View and strip EXIF.
class ExifScreen extends StatefulWidget {
  const ExifScreen({
    super.key,
    this.files = const SystemImageFiles(),
    this.setting = const PrefsStripOnShareStore(),
    this.share,
  });

  final ImageFiles files;
  final StripOnShareStore setting;
  final ShareEngine? share;

  @override
  State<ExifScreen> createState() => _ExifScreenState();
}

class _ExifScreenState extends State<ExifScreen> {
  List<_Photo> _photos = <_Photo>[];
  final List<String> _saved = <String>[];
  bool _alwaysStrip = false;
  bool _working = false;
  String? _status;

  @override
  void initState() {
    super.initState();
    widget.setting.read().then((bool v) {
      if (mounted) {
        setState(() => _alwaysStrip = v);
      }
    });
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
    if (!mounted || paths.isEmpty) {
      return;
    }
    final List<_Photo> photos = <_Photo>[];
    for (final String p in paths) {
      final Uint8List b = await widget.files.read(p);
      try {
        photos.add(_Photo(p, b, ExifTool.read(b), null));
      } on ExifError catch (e) {
        photos.add(_Photo(p, b, null, e.message));
      }
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _photos = photos;
      _status = null;
    });
  }

  Future<void> _stripAll() async {
    if (_photos.isEmpty || _working) {
      return;
    }
    setState(() => _working = true);
    final List<String> saved = <String>[];
    for (final _Photo p in _photos) {
      if (p.meta == null) {
        continue;
      }
      saved.add(await widget.files.write(ExifTool.cleanName(p.path), ExifTool.strip(p.bytes)));
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _working = false;
      _saved
        ..clear()
        ..addAll(saved);
      _status = 'Cleaned ${saved.length} ${saved.length == 1 ? 'photo' : 'photos'}: '
          'no location, camera or date left';
    });
  }

  Future<void> _setAlways(bool v) async {
    setState(() => _alwaysStrip = v);
    await widget.setting.write(v);
  }

  Future<void> _share() async {
    if (_saved.isEmpty) {
      _toast('Strip the photos first');
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
      _status = 'Removed the cleaned copies; the originals were never changed';
    });
  }

  Widget _row(String label, String value, IconData icon, {bool warn = false}) => ListTile(
        dense: true,
        leading: Icon(icon, semanticLabel: label, color: warn ? Theme.of(context).colorScheme.error : null),
        title: Text(label),
        subtitle: Text(value),
      );

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Photo details (EXIF)')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          OutlinedButton.icon(
            key: const Key('exif-pick'),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: _working ? null : _pick,
            icon: const Icon(Icons.photo_library_outlined),
            label: Text(_photos.isEmpty ? 'Choose photos' : 'Choose again'),
          ),
          SwitchListTile(
            key: const Key('exif-always'),
            title: const Text('Always strip when sharing'),
            subtitle: const Text('Photos shared from this app go out without location, camera or date'),
            value: _alwaysStrip,
            onChanged: _setAlways,
          ),
          for (final _Photo p in _photos)
            Card(
              key: Key('exif-photo-${p.name}'),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Text(p.name, style: text.titleMedium),
                ),
                if (p.error != null)
                  _row('Cannot check', p.error!, Icons.info_outline)
                else ...<Widget>[
                  _row('Location', p.meta!.gpsLabel, Icons.location_on_outlined, warn: p.meta!.hasGps),
                  _row('Camera', p.meta!.camera ?? 'None', Icons.photo_camera_outlined),
                  _row('Taken', p.meta!.taken ?? 'None', Icons.schedule),
                  if (p.meta!.software != null) _row('Software', p.meta!.software!, Icons.apps),
                  if (p.meta!.otherBlocks > 0)
                    _row('Other details', '${p.meta!.otherBlocks} more blocks (XMP, IPTC, text)', Icons.notes),
                  if (p.meta!.isClean) _row('Status', 'Already clean', Icons.verified_outlined),
                ],
              ]),
            ),
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const Key('exif-strip'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: _photos.isEmpty || _working ? null : _stripAll,
            icon: const Icon(Icons.cleaning_services_outlined),
            label: Text(_photos.length > 1 ? 'Strip all ${_photos.length}' : 'Strip all'),
          ),
          if (_status != null)
            ListTile(
              key: const Key('exif-status'),
              leading: const Icon(Icons.check_circle, semanticLabel: 'Done'),
              title: Text(_status!),
            ),
        ],
      ),
      bottomNavigationBar: ResultBar(onShare: _share, onSave: _save, onUndo: _undo),
    );
  }
}
