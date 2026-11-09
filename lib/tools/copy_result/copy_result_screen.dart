import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import '../../app/widgets/result_bar.dart';
import '../../engines/share/copy_result.dart';
import '../../engines/share/share_engine.dart';

/// Picking a picture and writing the Save copy, behind an interface so tests
/// need neither the picker nor the disk.
abstract class CopyFiles {
  /// PNG bytes of a picked picture, or null if cancelled.
  Future<Uint8List?> pickImage();
  Future<String> write(String name, Uint8List bytes);
  Future<void> remove(String path);
}

class SystemCopyFiles implements CopyFiles {
  const SystemCopyFiles();

  @override
  Future<Uint8List?> pickImage() async {
    final FilePickerResult? r = await FilePicker.platform.pickFiles(type: FileType.image);
    final String? path = r?.files.single.path;
    if (path == null) {
      return null;
    }
    return CopyResultScreen.toPng(await File(path).readAsBytes());
  }

  @override
  Future<String> write(String name, Uint8List bytes) async {
    final Directory dir = Directory('${(await getApplicationDocumentsDirectory()).path}/copied');
    await dir.create(recursive: true);
    final int dot = name.lastIndexOf('.');
    String path = '${dir.path}/$name';
    int n = 2;
    while (File(path).existsSync()) {
      path = '${dir.path}/${name.substring(0, dot)} ($n)${name.substring(dot)}';
      n++;
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

/// A copy button any tool can drop next to its result.
class CopyResultButton extends StatefulWidget {
  const CopyResultButton({super.key, required this.content, this.engine});

  final CopyContent Function() content;
  final CopyResult? engine;

  @override
  State<CopyResultButton> createState() => _CopyResultButtonState();
}

class _CopyResultButtonState extends State<CopyResultButton> {
  Future<void> _copy() async {
    final CopyOutcome out = await (widget.engine ?? CopyResult.instance).copy(widget.content());
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(out.message)));
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: const Key('copy-result-button'),
      tooltip: 'Copy',
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      onPressed: _copy,
      icon: const Icon(Icons.copy),
    );
  }
}

/// Feature 066 — Copy result.
class CopyResultScreen extends StatefulWidget {
  const CopyResultScreen({super.key, this.engine, this.files = const SystemCopyFiles(), this.share});

  final CopyResult? engine;
  final CopyFiles files;
  final ShareEngine? share;

  /// Re-encodes any picture the image package reads as PNG.
  static Uint8List? toPng(Uint8List bytes) {
    final img.Image? decoded = img.decodeImage(bytes);
    return decoded == null ? null : img.encodePng(decoded);
  }

  @override
  State<CopyResultScreen> createState() => _CopyResultScreenState();
}

class _CopyResultScreenState extends State<CopyResultScreen> {
  final TextEditingController _text = TextEditingController();
  Uint8List? _image;
  bool? _sensitiveChoice;
  CopyOutcome? _outcome;
  String? _status;
  final List<String> _saved = <String>[];
  Timer? _tick;
  int _secondsLeft = 0;

  CopyResult get _engine => widget.engine ?? CopyResult.instance;

  bool get _autoSensitive => _image == null && SensitiveText.looksSensitive(_text.text);
  bool get _sensitive => _sensitiveChoice ?? _autoSensitive;

  CopyContent? get _content {
    final Uint8List? im = _image;
    if (im != null) {
      return CopyImage(im, sensitive: _sensitive);
    }
    if (_text.text.isEmpty) {
      return null;
    }
    return CopyText(_text.text, sensitive: _sensitive);
  }

  @override
  void dispose() {
    _tick?.cancel();
    _text.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final Uint8List? png = await widget.files.pickImage();
    if (!mounted) {
      return;
    }
    if (png == null) {
      setState(() => _status = 'No picture picked');
      return;
    }
    setState(() {
      _image = png;
      _status = null;
    });
  }

  Future<void> _copy() async {
    final CopyContent? c = _content;
    if (c == null) {
      setState(() => _status = 'Type or paste something, or pick a picture');
      return;
    }
    final CopyOutcome out = await _engine.copy(c);
    if (!mounted) {
      return;
    }
    _tick?.cancel();
    setState(() {
      _outcome = out;
      _status = out.message;
      _secondsLeft = out.willClear ? CopyResult.clearAfter.inSeconds : 0;
    });
    if (out.willClear) {
      _tick = Timer.periodic(const Duration(seconds: 1), (Timer t) {
        if (!mounted) {
          t.cancel();
          return;
        }
        setState(() {
          _secondsLeft--;
          if (_secondsLeft <= 0) {
            t.cancel();
            _status = 'Clipboard cleared';
          }
        });
      });
    }
  }

  Future<void> _clearNow() async {
    _tick?.cancel();
    await _engine.clearNow();
    if (!mounted) {
      return;
    }
    setState(() {
      _secondsLeft = 0;
      _status = 'Clipboard cleared';
    });
  }

  Future<String?> _save() async {
    final Uint8List? im = _image;
    final String path;
    if (im != null) {
      path = await widget.files.write('copied.png', im);
    } else if (_text.text.isNotEmpty) {
      path = await widget.files.write('copied.txt', Uint8List.fromList(utf8.encode(_text.text)));
    } else {
      setState(() => _status = 'Nothing to save');
      return null;
    }
    if (!mounted) {
      return path;
    }
    setState(() {
      _saved.add(path);
      _status = 'Saved ${path.substring(path.lastIndexOf('/') + 1)} in Files › copied';
    });
    return path;
  }

  Future<void> _share() async {
    final ShareEngine share = widget.share ?? ShareEngine.instance;
    if (_image == null) {
      if (_text.text.isEmpty) {
        setState(() => _status = 'Nothing to share');
        return;
      }
      await share.shareText(_text.text);
      return;
    }
    final String? path = _saved.isNotEmpty ? _saved.last : await _save();
    if (path != null) {
      await share.shareFiles(<String>[path]);
    }
  }

  Future<void> _undo() async {
    if (_engine.canUndo) {
      _tick?.cancel();
      await _engine.undo();
      if (!mounted) {
        return;
      }
      setState(() {
        _outcome = null;
        _secondsLeft = 0;
        _status = 'Clipboard put back as it was';
      });
      return;
    }
    if (_saved.isNotEmpty) {
      final String last = _saved.removeLast();
      await widget.files.remove(last);
      if (!mounted) {
        return;
      }
      setState(() => _status = 'Removed ${last.substring(last.lastIndexOf('/') + 1)}');
      return;
    }
    if (mounted) {
      await Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final Uint8List? im = _image;
    return Scaffold(
      appBar: AppBar(title: const Text('Copy result')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          if (im == null)
            TextField(
              key: const Key('copy-text'),
              controller: _text,
              minLines: 3,
              maxLines: 8,
              decoration: const InputDecoration(labelText: 'Text to copy'),
              onChanged: (_) => setState(() => _sensitiveChoice = null),
            )
          else
            Stack(children: <Widget>[
              Semantics(
                label: 'Picture to copy',
                image: true,
                child: Image.memory(im, key: const Key('copy-image'), height: 200, fit: BoxFit.contain, excludeFromSemantics: true),
              ),
              Positioned(
                right: 0,
                top: 0,
                child: IconButton(
                  key: const Key('copy-image-remove'),
                  tooltip: 'Remove picture',
                  constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                  onPressed: () => setState(() {
                    _image = null;
                    _sensitiveChoice = null;
                  }),
                  icon: const Icon(Icons.close),
                ),
              ),
            ]),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const Key('copy-pick-image'),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: _pickImage,
            icon: const Icon(Icons.image_outlined),
            label: Text(im == null ? 'Copy a picture instead' : 'Pick another picture'),
          ),
          SwitchListTile(
            key: const Key('copy-sensitive'),
            title: const Text('Sensitive'),
            subtitle: Text(_autoSensitive && _sensitiveChoice == null
                ? 'Looks like a code or number; clears after 60 s'
                : 'Clear the clipboard after 60 s'),
            value: _sensitive,
            onChanged: (bool v) => setState(() => _sensitiveChoice = v),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            key: const Key('copy-go'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: _copy,
            icon: const Icon(Icons.copy),
            label: const Text('Copy'),
          ),
          if (_status != null)
            Semantics(
              liveRegion: true,
              child: ListTile(
                key: const Key('copy-status'),
                leading: Icon(_outcome?.ok ?? false ? Icons.check_circle_outline : Icons.info_outline, semanticLabel: 'Note'),
                title: Text(_status!),
                subtitle: _secondsLeft > 0 ? Text('Clears in $_secondsLeft s', key: const Key('copy-countdown')) : null,
                trailing: _secondsLeft > 0
                    ? TextButton(
                        key: const Key('copy-clear-now'),
                        style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                        onPressed: _clearNow,
                        child: const Text('Clear now'),
                      )
                    : null,
              ),
            ),
        ],
      ),
      bottomNavigationBar: ResultBar(onShare: _share, onSave: _save, onUndo: _undo),
    );
  }
}
