import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../../app/theme.dart';
import '../../app/widgets/result_bar.dart';
import '../../engines/convert/convert_registry.dart';
import '../../engines/pdf/images_to_pdf.dart';
import '../../engines/share/share_engine.dart';

/// One picked image, in memory.
class PickedImage {
  const PickedImage({required this.name, required this.bytes});
  final String name;
  final Uint8List bytes;
}

/// Gallery, camera and the output folder, behind one interface for tests.
abstract class ImagesToPdfIo {
  Future<List<PickedImage>> pickFromGallery();
  Future<PickedImage?> takePhoto();
  Future<String> write(String name, Uint8List bytes);
  Future<void> remove(String path);
}

class SystemImagesToPdfIo implements ImagesToPdfIo {
  const SystemImagesToPdfIo();

  @override
  Future<List<PickedImage>> pickFromGallery() async {
    final FilePickerResult? r = await FilePicker.platform.pickFiles(type: FileType.image, allowMultiple: true);
    if (r == null) {
      return <PickedImage>[];
    }
    return <PickedImage>[
      for (final PlatformFile f in r.files)
        if (f.path != null) PickedImage(name: f.name, bytes: await File(f.path!).readAsBytes()),
    ];
  }

  @override
  Future<PickedImage?> takePhoto() async {
    final XFile? f = await ImagePicker().pickImage(source: ImageSource.camera);
    if (f == null) {
      return null;
    }
    return PickedImage(name: f.name, bytes: await f.readAsBytes());
  }

  @override
  Future<String> write(String name, Uint8List bytes) async {
    final Directory base = await getApplicationDocumentsDirectory();
    final Directory dir = Directory('${base.path}/pdf');
    await dir.create(recursive: true);
    String path = '${dir.path}/$name.pdf';
    int n = 2;
    while (File(path).existsSync()) {
      path = '${dir.path}/$name ($n).pdf';
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

/// Feature 021 — Images to PDF.
class ImagesToPdfScreen extends StatefulWidget {
  const ImagesToPdfScreen({super.key, this.io = const SystemImagesToPdfIo(), this.engine, this.share});

  final ImagesToPdfIo io;
  final ImagesToPdf? engine;
  final ShareEngine? share;

  @override
  State<ImagesToPdfScreen> createState() => _ImagesToPdfScreenState();
}

class _ImagesToPdfScreenState extends State<ImagesToPdfScreen> {
  late final ImagesToPdf _engine = widget.engine ?? ImagesToPdf();
  final List<PickedImage> _images = <PickedImage>[];
  PdfPageSize _size = PdfPageSize.a4;
  PdfOrientation _orientation = PdfOrientation.auto;
  double _marginMm = 10;
  String? _output;
  String? _status;
  bool _busy = false;

  void _toast(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(m)));
    }
  }

  Future<void> _gallery() async {
    final List<PickedImage> got = await widget.io.pickFromGallery();
    if (mounted && got.isNotEmpty) {
      setState(() => _images.addAll(got));
    }
  }

  Future<void> _camera() async {
    final PickedImage? got = await widget.io.takePhoto();
    if (mounted && got != null) {
      setState(() => _images.add(got));
    }
  }

  Future<void> _make() async {
    if (_images.isEmpty || _busy) {
      _toast('Add images first');
      return;
    }
    setState(() => _busy = true);
    try {
      final Uint8List pdf = await _engine.build(
        <Uint8List>[for (final PickedImage i in _images) i.bytes],
        ImagesToPdfOptions(pageSize: _size, orientation: _orientation, marginPt: _marginMm * 72 / 25.4),
      );
      final String first = _images.first.name;
      final int dot = first.lastIndexOf('.');
      final String name = _images.length == 1 && dot > 0 ? first.substring(0, dot) : 'Images';
      final String path = await widget.io.write(name, pdf);
      setState(() {
        _output = path;
        _status = 'Made a ${_images.length}-page PDF in Files › pdf';
      });
    } on ConvertException catch (e) {
      setState(() => _status = e.message);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _share() async {
    final String? out = _output;
    if (out == null) {
      _toast('Make the PDF first');
      return;
    }
    await (widget.share ?? ShareEngine.instance).shareFiles(<String>[out]);
  }

  void _save() {
    if (_output == null) {
      _toast('Make the PDF first');
      return;
    }
    _toast('Saved in Files › pdf');
  }

  Future<void> _undo() async {
    final String? out = _output;
    if (out != null) {
      await widget.io.remove(out);
      setState(() {
        _output = null;
        _status = 'Removed the PDF';
      });
      return;
    }
    if (_images.isNotEmpty) {
      setState(() {
        _images.removeLast();
        _status = null;
      });
      return;
    }
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Images to PDF')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton.icon(
                  key: const Key('i2p-gallery'),
                  onPressed: _gallery,
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Gallery'),
                ),
              ),
              const SizedBox(width: AppRadius.gridGap),
              Expanded(
                child: OutlinedButton.icon(
                  key: const Key('i2p-camera'),
                  onPressed: _camera,
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: const Text('Camera'),
                ),
              ),
            ],
          ),
          if (_status != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Semantics(
                liveRegion: true,
                child: Text(_status!,
                    key: const Key('i2p-status'), style: text.bodyMedium?.copyWith(color: AppColors.ink)),
              ),
            ),
          const SizedBox(height: 12),
          Text('Page size', style: text.titleSmall),
          const SizedBox(height: 6),
          SegmentedButton<PdfPageSize>(
            key: const Key('i2p-size'),
            segments: <ButtonSegment<PdfPageSize>>[
              for (final PdfPageSize s in PdfPageSize.values)
                ButtonSegment<PdfPageSize>(value: s, label: Text(s == PdfPageSize.fit ? 'Fit' : s.label)),
            ],
            selected: <PdfPageSize>{_size},
            onSelectionChanged: (Set<PdfPageSize> v) => setState(() => _size = v.first),
          ),
          const SizedBox(height: 12),
          Text('Orientation', style: text.titleSmall),
          const SizedBox(height: 6),
          SegmentedButton<PdfOrientation>(
            key: const Key('i2p-orientation'),
            segments: <ButtonSegment<PdfOrientation>>[
              for (final PdfOrientation s in PdfOrientation.values)
                ButtonSegment<PdfOrientation>(value: s, label: Text(s.label)),
            ],
            selected: <PdfOrientation>{_orientation},
            onSelectionChanged: _size == PdfPageSize.fit
                ? null
                : (Set<PdfOrientation> v) => setState(() => _orientation = v.first),
          ),
          const SizedBox(height: 12),
          Text('Margins: ${_marginMm.round()} mm', style: text.titleSmall),
          Slider(
            key: const Key('i2p-margin'),
            value: _marginMm,
            max: 30,
            divisions: 6,
            label: '${_marginMm.round()} mm',
            semanticFormatterCallback: (double v) => '${v.round()} millimetre margins',
            onChanged: (double v) => setState(() => _marginMm = v),
          ),
          if (_images.isNotEmpty)
            Card(
              child: ReorderableListView(
                key: const Key('i2p-list'),
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: true,
                onReorder: (int from, int to) => setState(() {
                  final PickedImage moved = _images.removeAt(from);
                  _images.insert(to > from ? to - 1 : to, moved);
                }),
                children: <Widget>[
                  for (int i = 0; i < _images.length; i++)
                    ListTile(
                      key: ValueKey<String>('i2p-item-$i-${_images[i].name}'),
                      leading: Text('${i + 1}', style: text.titleMedium),
                      title: Text(_images[i].name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text('Page ${i + 1}'),
                      trailing: IconButton(
                        tooltip: 'Remove ${_images[i].name}',
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(() => _images.removeAt(i)),
                      ),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const Key('i2p-make'),
            onPressed: _images.isEmpty || _busy ? null : _make,
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: Text(_images.isEmpty ? 'Make PDF' : 'Make ${_images.length}-page PDF'),
          ),
        ],
      ),
      bottomNavigationBar: ResultBar(onShare: _share, onSave: _save, onUndo: _undo),
    );
  }
}
