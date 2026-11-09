import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../../app/widgets/result_bar.dart';
import '../../engines/convert/convert_registry.dart';
import '../../engines/image/id_card_page.dart';
import '../../engines/share/share_engine.dart';
import '../images_to_pdf/images_to_pdf_screen.dart' show PickedImage;

/// Gallery, camera and the output folder, behind one interface for tests.
abstract class IdCardIo {
  Future<PickedImage?> pickImage();
  Future<PickedImage?> takePhoto();

  /// [name] includes the extension. Returns the saved path.
  Future<String> write(String name, Uint8List bytes);
  Future<void> remove(String path);
}

class SystemIdCardIo implements IdCardIo {
  const SystemIdCardIo();

  @override
  Future<PickedImage?> pickImage() async {
    final FilePickerResult? r = await FilePicker.platform.pickFiles(type: FileType.image);
    final String? path = r == null || r.files.isEmpty ? null : r.files.first.path;
    if (path == null) {
      return null;
    }
    return PickedImage(name: r!.files.first.name, bytes: await File(path).readAsBytes());
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
    String path = '${dir.path}/$name';
    int n = 2;
    while (File(path).existsSync()) {
      final int dot = name.lastIndexOf('.');
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

/// Feature 044 — ID card to A4.
class IdCardScreen extends StatefulWidget {
  const IdCardScreen({super.key, this.io = const SystemIdCardIo(), this.engine = const IdCardEngine(), this.share});

  final IdCardIo io;
  final IdCardEngine engine;
  final ShareEngine? share;

  @override
  State<IdCardScreen> createState() => _IdCardScreenState();
}

class _IdCardScreenState extends State<IdCardScreen> {
  PickedImage? _front;
  PickedImage? _back;
  IdPaper _paper = IdPaper.a4;
  IdCardPage? _result;
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

  Future<void> _get(bool front, bool camera) async {
    final PickedImage? p = camera ? await widget.io.takePhoto() : await widget.io.pickImage();
    if (!mounted || p == null) {
      return;
    }
    setState(() {
      if (front) {
        _front = p;
      } else {
        _back = p;
      }
      _result = null;
    });
  }

  Future<void> _make() async {
    final PickedImage? f = _front;
    if (f == null || _working) {
      return;
    }
    setState(() => _working = true);
    try {
      final IdCardPage r = widget.engine.build(f.bytes, _back?.bytes, _paper);
      final String stem = 'id-card-${_paper.name}';
      final String pdf = await widget.io.write('$stem.pdf', r.pdf);
      final String jpg = await widget.io.write('$stem.jpg', r.jpg);
      final bool edges = r.front.foundEdges && (r.back?.foundEdges ?? true);
      setState(() {
        _result = r;
        _saved
          ..clear()
          ..addAll(<String>[pdf, jpg]);
        _status = 'Saved as PDF and JPG at actual size on ${_paper.label}'
            '${edges ? '' : '. A card edge was not found, so the whole picture was used'}';
      });
    } on ConvertException catch (e) {
      setState(() => _status = e.message);
    } finally {
      if (mounted) {
        setState(() => _working = false);
      }
    }
  }

  Future<void> _share() async {
    if (_saved.isEmpty) {
      _toast('Make the page first');
      return;
    }
    await (widget.share ?? ShareEngine.instance).shareFiles(List<String>.of(_saved));
  }

  void _save() => _toast(_saved.isEmpty ? 'Nothing to save yet' : 'Saved in Files › pdf');

  Future<void> _undo() async {
    if (_saved.isEmpty) {
      Navigator.of(context).maybePop();
      return;
    }
    for (final String p in _saved) {
      await widget.io.remove(p);
    }
    setState(() {
      _saved.clear();
      _result = null;
      _status = 'Removed the page';
    });
  }

  Widget _slot(String label, bool front, PickedImage? picked) {
    final String side = front ? 'front' : 'back';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(picked == null ? Icons.credit_card_outlined : Icons.check_circle,
                    semanticLabel: picked == null ? '$label not added' : '$label added'),
                const SizedBox(width: 8),
                Expanded(child: Text(picked == null ? label : '$label: ${picked.name}')),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton.icon(
                    key: Key('id-$side-pick'),
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                    onPressed: () => _get(front, false),
                    icon: const Icon(Icons.photo_outlined),
                    label: const Text('Choose'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    key: Key('id-$side-camera'),
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                    onPressed: () => _get(front, true),
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: const Text('Take photo'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final IdCardPage? r = _result;
    return Scaffold(
      appBar: AppBar(title: const Text('ID card to A4')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          _slot('Front of the card', true, _front),
          _slot('Back of the card (optional)', false, _back),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: <Widget>[
              for (final IdPaper p in IdPaper.values)
                ChoiceChip(
                  key: Key('id-paper-${p.name}'),
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                  label: Text(p.label),
                  selected: _paper == p,
                  onSelected: (_) => setState(() {
                    _paper = p;
                    _result = null;
                  }),
                ),
            ],
          ),
          const SizedBox(height: 12),
          FilledButton(
            key: const Key('id-make'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: _front == null || _working ? null : _make,
            child: const Text('Make printable page'),
          ),
          if (r != null) ...<Widget>[
            const SizedBox(height: 16),
            Center(
              child: Semantics(
                label: 'Page preview with the card at actual size',
                image: true,
                child: Container(
                  key: const Key('id-preview'),
                  decoration: BoxDecoration(border: Border.all(color: Colors.black26)),
                  child: Image.memory(r.jpg, height: 280, excludeFromSemantics: true),
                ),
              ),
            ),
          ],
          if (_status != null)
            ListTile(
              key: const Key('id-status'),
              leading: Icon(r != null ? Icons.check_circle : Icons.info_outline,
                  semanticLabel: r != null ? 'Done' : 'Note'),
              title: Text(_status!),
            ),
        ],
      ),
      bottomNavigationBar: ResultBar(onShare: _share, onSave: _save, onUndo: _undo),
    );
  }
}
