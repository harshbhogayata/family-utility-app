import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../app/widgets/result_bar.dart';
import '../../engines/convert/convert_registry.dart';
import '../../engines/convert/file_kind.dart';
import '../../engines/share/share_engine.dart';

/// Picks one file and reads it. Behind an interface so tests need no picker.
abstract class ConvertFileChooser {
  Future<ConvertInput?> pick();
}

class SystemConvertFileChooser implements ConvertFileChooser {
  const SystemConvertFileChooser();

  @override
  Future<ConvertInput?> pick() async {
    final FilePickerResult? r = await FilePicker.platform.pickFiles();
    final PlatformFile? f = r?.files.single;
    if (f == null || f.path == null) {
      return null;
    }
    return ConvertInput(name: f.name, bytes: await File(f.path!).readAsBytes());
  }
}

/// Where converted files are kept. Behind an interface for tests.
abstract class ConvertSink {
  Future<String> write(ConvertOutput out);
  Future<void> remove(String path);
}

class FolderConvertSink implements ConvertSink {
  const FolderConvertSink();

  @override
  Future<String> write(ConvertOutput out) async {
    final Directory base = await getApplicationDocumentsDirectory();
    final Directory dir = Directory('${base.path}/converted');
    await dir.create(recursive: true);
    final int dot = out.name.lastIndexOf('.');
    final String stem = dot > 0 ? out.name.substring(0, dot) : out.name;
    final String ext = dot > 0 ? out.name.substring(dot) : '';
    String path = '${dir.path}/${out.name}';
    int n = 2;
    while (File(path).existsSync()) {
      path = '${dir.path}/$stem ($n)$ext';
      n++;
    }
    await File(path).writeAsBytes(out.bytes, flush: true);
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

/// Feature 030 — Convert anything. Pick a file; see every format it can
/// become, worked out from its real type, not its name.
class ConvertAnythingScreen extends StatefulWidget {
  const ConvertAnythingScreen({
    super.key,
    this.chooser = const SystemConvertFileChooser(),
    this.sink = const FolderConvertSink(),
    this.registry,
    this.share,
  });

  final ConvertFileChooser chooser;
  final ConvertSink sink;
  final ConvertRegistry? registry;
  final ShareEngine? share;

  @override
  State<ConvertAnythingScreen> createState() => _ConvertAnythingScreenState();
}

class _ConvertAnythingScreenState extends State<ConvertAnythingScreen> {
  ConvertRegistry get _registry => widget.registry ?? ConvertRegistry.instance;

  ConvertInput? _input;
  FileKind? _kind;
  List<Converter> _targets = <Converter>[];
  final List<String> _written = <String>[];
  String? _status;
  String? _busyId;

  void _toast(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(m)));
    }
  }

  String _claimed(String name) {
    final int dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(dot + 1).toLowerCase() : '';
  }

  Future<void> _pick() async {
    final ConvertInput? input = await widget.chooser.pick();
    if (input == null || !mounted) {
      return;
    }
    final Uint8List bytes = input.bytes;
    final FileKind kind = sniffFileKind(bytes);
    setState(() {
      _input = input;
      _kind = kind;
      _targets = _registry.targetsFor(kind);
      final String claimed = _claimed(input.name);
      final bool mismatch = claimed.isNotEmpty &&
          kind != FileKind.unknown &&
          claimed != kind.extension &&
          !(kind == FileKind.jpeg && claimed == 'jpeg') &&
          !(kind == FileKind.tiff && claimed == 'tif');
      _status = mismatch ? 'Named .$claimed, but it is really a ${kind.label} file.' : null;
    });
  }

  Future<void> _convert(Converter c) async {
    final ConvertInput? input = _input;
    if (input == null || _busyId != null) {
      return;
    }
    setState(() => _busyId = c.id);
    try {
      final ConvertOutput out = await _registry.convert(input, c.id);
      final String path = await widget.sink.write(out);
      _written.add(path);
      setState(() => _status = 'Made ${out.name} in Files › converted');
    } on ConvertException catch (e) {
      setState(() => _status = e.message);
    } on FormatException {
      setState(() => _status = 'This file could not be read as ${_kind?.label ?? 'expected'}.');
    } finally {
      if (mounted) {
        setState(() => _busyId = null);
      }
    }
  }

  Future<void> _share() async {
    if (_written.isEmpty) {
      _toast('Convert something first');
      return;
    }
    await (widget.share ?? ShareEngine.instance).shareFiles(<String>[_written.last]);
  }

  void _save() {
    if (_written.isEmpty) {
      _toast('Nothing to save yet');
      return;
    }
    _toast('Saved in Files › converted');
  }

  Future<void> _undo() async {
    if (_written.isNotEmpty) {
      final String last = _written.removeLast();
      await widget.sink.remove(last);
      setState(() => _status = 'Removed ${last.substring(last.lastIndexOf('/') + 1)}');
      return;
    }
    if (_input != null) {
      setState(() {
        _input = null;
        _kind = null;
        _targets = <Converter>[];
        _status = null;
      });
      return;
    }
    Navigator.of(context).maybePop();
  }

  IconData _icon(FileKind k) {
    if (k.isImage) {
      return Icons.image_outlined;
    }
    if (k.isText) {
      return Icons.notes_outlined;
    }
    if (k == FileKind.zip) {
      return Icons.folder_zip_outlined;
    }
    return Icons.insert_drive_file_outlined;
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ConvertInput? input = _input;
    final FileKind? kind = _kind;
    return Scaffold(
      appBar: AppBar(title: const Text('Convert anything')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(input == null ? 'Pick a file' : input.name,
                      style: text.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 6),
                  Text(
                    kind == null
                        ? 'The app reads what the file really is and lists every format it can become.'
                        : 'Real type: ${kind.label}',
                    key: const Key('convert-kind'),
                    style: text.bodyMedium,
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    key: const Key('convert-pick'),
                    onPressed: _pick,
                    icon: const Icon(Icons.file_open_outlined),
                    label: Text(input == null ? 'Choose a file' : 'Choose another'),
                  ),
                ],
              ),
            ),
          ),
          if (_status != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  _status!,
                  key: const Key('convert-status'),
                  style: text.bodyLarge?.copyWith(fontSize: 13),
                ),
              ),
            ),
          if (input != null) ...<Widget>[
            const SizedBox(height: 12),
            Text('Can become', style: text.titleSmall),
            const SizedBox(height: 8),
            if (_targets.isEmpty)
              Text('No converter on this phone takes ${kind?.label ?? 'this'} files yet.',
                  style: text.bodyMedium)
            else
              Card(
                child: Column(
                  children: <Widget>[
                    for (final Converter c in _targets)
                      ListTile(
                        key: Key('convert-to-${c.id}'),
                        minVerticalPadding: 12,
                        leading: Icon(_icon(c.target), semanticLabel: c.target.label),
                        title: Text(c.label),
                        subtitle: Text('.${c.target.extension}'),
                        trailing: _busyId == c.id
                            ? const SizedBox(
                                width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.chevron_right),
                        onTap: _busyId == null ? () => _convert(c) : null,
                      ),
                  ],
                ),
              ),
          ],
        ],
      ),
      bottomNavigationBar: ResultBar(onShare: _share, onSave: _save, onUndo: _undo),
    );
  }
}
