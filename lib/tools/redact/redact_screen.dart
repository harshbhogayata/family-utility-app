import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import '../../app/theme.dart';
import '../../app/widgets/result_bar.dart';
import '../../engines/image/redact.dart';
import '../../engines/platform/action_history.dart' show baseName;
import '../../engines/share/share_engine.dart';
import '../../platform/face_platform.dart';
import '../../platform/mlkit_text_platform.dart';

/// Picks one photo, reads it and writes the covered copy. Behind an
/// interface so tests need neither the picker nor the disk.
abstract class RedactFiles {
  Future<String?> pick();

  Future<Uint8List> read(String path);

  Future<String> write(String name, Uint8List bytes);

  Future<void> remove(String path);
}

class SystemRedactFiles implements RedactFiles {
  const SystemRedactFiles();

  @override
  Future<String?> pick() async {
    final FilePickerResult? r = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: <String>['jpg', 'jpeg', 'png', 'webp'],
    );
    return r == null || r.files.isEmpty ? null : r.files.first.path;
  }

  @override
  Future<Uint8List> read(String path) => File(path).readAsBytes();

  @override
  Future<String> write(String name, Uint8List bytes) async {
    final Directory base = await getApplicationDocumentsDirectory();
    final Directory dir = Directory('${base.path}/covered');
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

/// "photo.jpg" -> "photo-covered.jpg".
String coveredName(String path) {
  final String name = baseName(path);
  final int dot = name.lastIndexOf('.');
  return '${dot > 0 ? name.substring(0, dot) : name}-covered.jpg';
}

/// Feature 045 — Blur faces, plates and Aadhaar numbers.
class RedactScreen extends StatefulWidget {
  const RedactScreen({
    super.key,
    this.files = const SystemRedactFiles(),
    this.redactor = const Redactor(faces: MlKitFaceFinder(), text: MlKitTextRecognizer()),
    this.share,
  });

  final RedactFiles files;
  final Redactor redactor;
  final ShareEngine? share;

  @override
  State<RedactScreen> createState() => _RedactScreenState();
}

class _RedactScreenState extends State<RedactScreen> {
  String? _path;
  Uint8List? _bytes;
  img.Image? _image;
  final List<RedactRegion> _regions = <RedactRegion>[];
  RedactStyle _style = RedactStyle.blur;
  bool _busy = false;
  Offset? _dragStart;
  Rect? _dragRect;
  Uint8List? _output;
  String? _savedPath;

  void _toast(String m) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _pick() async {
    final String? p = await widget.files.pick();
    if (p == null || !mounted) {
      return;
    }
    setState(() => _busy = true);
    try {
      final Uint8List b = await widget.files.read(p);
      final img.Image? im = img.decodeImage(b);
      if (im == null) {
        throw const FormatException('not an image');
      }
      final img.Image upright = img.bakeOrientation(im);
      setState(() {
        _path = p;
        _bytes = Uint8List.fromList(img.encodeJpg(upright, quality: 90));
        _image = upright;
        _regions.clear();
        _output = null;
        _savedPath = null;
      });
      await _detect();
    } catch (_) {
      _toast('Could not open this picture');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _detect() async {
    final String? p = _path;
    final img.Image? im = _image;
    final Uint8List? b = _bytes;
    if (p == null || im == null || b == null) {
      return;
    }
    setState(() => _busy = true);
    final List<RedactRegion> found = await widget.redactor.detect(
      p,
      im,
      b,
      const RedactTargets(),
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _regions
        ..removeWhere((RedactRegion r) => r.kind != RedactKind.manual)
        ..addAll(found);
      _busy = false;
    });
    _toast(found.isEmpty ? 'Nothing found. Drag on the picture to cover a part.' : 'Found ${found.length} to cover');
  }

  Future<void> _apply() async {
    final img.Image? im = _image;
    final String? p = _path;
    if (im == null || p == null) {
      _toast('Choose a picture first');
      return;
    }
    if (_regions.isEmpty) {
      _toast('Nothing to cover yet');
      return;
    }
    setState(() => _busy = true);
    final Uint8List out = Redactor.encode(Redactor.apply(im, _regions, _style));
    final String saved = await widget.files.write(coveredName(p), out);
    if (!mounted) {
      return;
    }
    setState(() {
      _output = out;
      _savedPath = saved;
      _busy = false;
    });
  }

  Future<void> _share() async {
    final String? s = _savedPath;
    if (s == null) {
      _toast('Cover the picture first');
      return;
    }
    await (widget.share ?? ShareEngine.instance).shareFiles(<String>[s]);
  }

  void _save() {
    final String? s = _savedPath;
    _toast(s == null ? 'Cover the picture first' : 'Saved ${baseName(s)} in Files › covered');
  }

  Future<void> _undo() async {
    final String? s = _savedPath;
    if (s != null) {
      await widget.files.remove(s);
      setState(() {
        _savedPath = null;
        _output = null;
      });
      _toast('Removed the covered copy');
      return;
    }
    if (_regions.isNotEmpty) {
      setState(() => _regions.removeLast());
      return;
    }
    if (mounted) {
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final img.Image? im = _image;
    final TextTheme text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Blur faces and numbers')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Text(
            'Finds faces, number plates and Aadhaar numbers on this phone. '
            'The cover is baked into a new picture; nothing is uploaded.',
            style: text.bodyMedium,
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            key: const Key('redact-pick'),
            onPressed: _busy ? null : _pick,
            icon: const Icon(Icons.add_photo_alternate_outlined),
            label: Text(_path == null ? 'Choose a picture' : baseName(_path!), overflow: TextOverflow.ellipsis),
          ),
          if (_busy) const Padding(padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator()),
          if (im != null) ...<Widget>[
            const SizedBox(height: 12),
            _picture(im),
            const SizedBox(height: 8),
            Text('Drag on the picture to add your own box.', style: text.bodySmall),
            const SizedBox(height: 12),
            SegmentedButton<RedactStyle>(
              key: const Key('redact-style'),
              segments: <ButtonSegment<RedactStyle>>[
                for (final RedactStyle s in RedactStyle.values) ButtonSegment<RedactStyle>(value: s, label: Text(s.label)),
              ],
              selected: <RedactStyle>{_style},
              onSelectionChanged: (Set<RedactStyle> s) => setState(() => _style = s.first),
            ),
            const SizedBox(height: 8),
            for (int i = 0; i < _regions.length; i++)
              ListTile(
                key: ValueKey<String>('redact-region-$i'),
                minTileHeight: 48,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.crop_square),
                title: Text(_regions[i].kind.label),
                trailing: IconButton(
                  tooltip: 'Remove ${_regions[i].kind.label.toLowerCase()} ${i + 1}',
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(() => _regions.removeAt(i)),
                ),
              ),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton.icon(
                    key: const Key('redact-detect'),
                    onPressed: _busy ? null : _detect,
                    icon: const Icon(Icons.auto_fix_high),
                    label: const Text('Find again'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    key: const Key('redact-apply'),
                    onPressed: _busy ? null : _apply,
                    icon: const Icon(Icons.blur_on),
                    label: Text('Cover ${_regions.length}'),
                  ),
                ),
              ],
            ),
          ],
          if (_output != null) ...<Widget>[
            const SizedBox(height: 16),
            Semantics(
              label: 'Covered picture',
              image: true,
              child: Image.memory(_output!, key: const Key('redact-output'), height: 200, fit: BoxFit.contain),
            ),
            Text('Saved ${baseName(_savedPath!)}', key: const Key('redact-saved'), style: text.bodySmall),
          ],
        ],
      ),
      bottomNavigationBar: ResultBar(onShare: _share, onSave: _save, onUndo: _undo),
    );
  }

  /// The picture with the boxes drawn on it; dragging adds a box.
  Widget _picture(img.Image im) {
    return AspectRatio(
      aspectRatio: im.width / im.height,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints c) {
          final double scale = im.width / c.maxWidth;
          return Semantics(
            label: 'Picture with ${_regions.length} covered ${_regions.length == 1 ? 'part' : 'parts'}. '
                'Drag to cover another part.',
            child: GestureDetector(
              key: const Key('redact-canvas'),
              // Boxes start where the finger went down, not after the slop.
              dragStartBehavior: DragStartBehavior.down,
              onPanStart: (DragStartDetails d) => setState(() {
                _dragStart = d.localPosition;
                _dragRect = Rect.fromPoints(d.localPosition, d.localPosition);
              }),
              onPanUpdate: (DragUpdateDetails d) {
                final Offset? s = _dragStart;
                if (s != null) {
                  setState(() => _dragRect = Rect.fromPoints(s, d.localPosition));
                }
              },
              onPanEnd: (_) {
                final Rect? r = _dragRect;
                setState(() {
                  if (r != null && r.width > 4 && r.height > 4) {
                    _regions.add(RedactRegion(
                      RedactKind.manual,
                      r.left * scale,
                      r.top * scale,
                      r.width * scale,
                      r.height * scale,
                    ));
                  }
                  _dragStart = null;
                  _dragRect = null;
                });
              },
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  Image.memory(_bytes!, fit: BoxFit.fill, gaplessPlayback: true),
                  for (final RedactRegion r in _regions)
                    Positioned(
                      left: r.left / scale,
                      top: r.top / scale,
                      width: r.width / scale,
                      height: r.height / scale,
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.35),
                            border: Border.all(color: AppColors.accent, width: 2),
                          ),
                        ),
                      ),
                    ),
                  if (_dragRect != null)
                    Positioned.fromRect(
                      rect: _dragRect!,
                      child: IgnorePointer(
                        child: DecoratedBox(decoration: BoxDecoration(border: Border.all(color: Colors.white, width: 2))),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
