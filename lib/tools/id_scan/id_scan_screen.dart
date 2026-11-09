import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';

import '../../app/widgets/result_bar.dart';
import '../../engines/image/id_card_page.dart';
import '../../engines/image/id_scan.dart';
import '../../engines/share/share_engine.dart';
import '../document_scanner/scan_camera.dart';
import '../id_card/id_card_screen.dart' show IdCardIo, SystemIdCardIo;

typedef IdPageBuilder = Future<IdCardPage> Function(Uint8List front, Uint8List back, IdPaper paper);

IdCardPage _buildOnDevice((Uint8List, Uint8List, IdPaper) a) => const IdCardEngine().build(a.$1, a.$2, a.$3);

/// Builds the page off the UI thread.
Future<IdCardPage> buildInBackground(Uint8List front, Uint8List back, IdPaper paper) =>
    compute(_buildOnDevice, (front, back, paper));

/// Builds on the calling thread (tests).
Future<IdCardPage> buildDirect(Uint8List front, Uint8List back, IdPaper paper) async =>
    const IdCardEngine().build(front, back, paper);

/// Feature 049 — ID scan: front, then back, then one page ready to print.
class IdScanScreen extends StatefulWidget {
  const IdScanScreen({
    super.key,
    this.camera,
    this.io = const SystemIdCardIo(),
    this.builder = buildInBackground,
    this.share,
  });

  /// Defaults to the phone's back camera.
  final ScanCamera? camera;
  final IdCardIo io;
  final IdPageBuilder builder;
  final ShareEngine? share;

  @override
  State<IdScanScreen> createState() => _IdScanScreenState();
}

class _IdScanScreenState extends State<IdScanScreen> {
  late final ScanCamera _camera = widget.camera ?? DeviceScanCamera();
  final IdScanFlow _flow = IdScanFlow();
  bool _cameraReady = false;
  bool _busy = false;
  IdPaper _paper = IdPaper.a4;
  IdCardPage? _page;
  final List<String> _saved = <String>[];
  String? _status;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    final bool ok = await _camera.start((_) {});
    if (!mounted) {
      return;
    }
    setState(() {
      _cameraReady = ok;
      if (!ok) {
        _status = 'No camera available. Allow camera access in Settings to scan.';
      }
    });
  }

  @override
  void dispose() {
    unawaited(_camera.dispose());
    super.dispose();
  }

  void _toast(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(m)));
    }
  }

  Future<void> _shoot() async {
    if (_busy || !_cameraReady || _flow.step == IdScanStep.review) {
      return;
    }
    setState(() => _busy = true);
    try {
      final Uint8List photo = await _camera.takePicture();
      final IdScanStep was = _flow.step;
      _flow.capture(photo);
      _status = was == IdScanStep.front ? 'Front captured' : 'Back captured';
      if (_flow.step == IdScanStep.review) {
        await _build();
      }
    } catch (_) {
      _status = 'Could not take the photo. Try again.';
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _build() async {
    final IdCardPage page = await widget.builder(_flow.front!, _flow.back!, _paper);
    if (!mounted) {
      return;
    }
    final bool edges = page.front.foundEdges && (page.back?.foundEdges ?? true);
    setState(() {
      _page = page;
      _status = edges
          ? 'Both sides aligned at actual size on ${_paper.label}'
          : 'A card edge was not found, so the whole photo was used. Retake for a cleaner page.';
    });
  }

  Future<void> _paperChanged(IdPaper p) async {
    setState(() {
      _paper = p;
      _busy = true;
    });
    try {
      await _build();
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _retake(IdScanStep side) {
    setState(() {
      _flow.retake(side);
      _page = null;
      _status = null;
    });
  }

  Future<void> _saveFiles() async {
    final IdCardPage? p = _page;
    if (p == null) {
      _toast('Photograph both sides first');
      return;
    }
    if (_saved.isNotEmpty) {
      _toast('Saved in Files › pdf');
      return;
    }
    final String stem = 'id-scan-${_paper.name}';
    final String pdf = await widget.io.write('$stem.pdf', p.pdf);
    final String jpg = await widget.io.write('$stem.jpg', p.jpg);
    setState(() {
      _saved.addAll(<String>[pdf, jpg]);
      _status = 'Saved as PDF and JPG, ready to print on ${_paper.label}';
    });
  }

  Future<void> _share() async {
    if (_page == null) {
      _toast('Photograph both sides first');
      return;
    }
    if (_saved.isEmpty) {
      await _saveFiles();
    }
    await (widget.share ?? ShareEngine.instance).shareFiles(List<String>.of(_saved));
  }

  Future<void> _undo() async {
    if (_saved.isNotEmpty) {
      for (final String p in _saved) {
        await widget.io.remove(p);
      }
      setState(() {
        _saved.clear();
        _status = 'Removed the saved page';
      });
      return;
    }
    if (_flow.step == IdScanStep.review) {
      _retake(IdScanStep.back);
      return;
    }
    if (_flow.step == IdScanStep.back && _flow.hasFront) {
      _retake(IdScanStep.front);
      return;
    }
    Navigator.of(context).maybePop();
  }

  Widget _cameraView() {
    return AspectRatio(
      aspectRatio: 3 / 4,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            if (_cameraReady) _camera.preview(context) else const ColoredBox(color: Colors.black),
            // Card-shaped guide (ID-1 is 85.6 × 53.98 mm).
            Center(
              child: FractionallySizedBox(
                widthFactor: 0.86,
                child: AspectRatio(
                  aspectRatio: idCardWidthMm / idCardHeightMm,
                  child: Semantics(
                    key: const Key('ids-guide'),
                    label: 'Card frame. ${_flow.step.hint}',
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.white, width: 3),
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _review(IdCardPage p) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Center(
          child: Semantics(
            label: 'Page preview: front above back at actual size',
            image: true,
            child: Container(
              key: const Key('ids-preview'),
              decoration: BoxDecoration(border: Border.all(color: Colors.black26)),
              child: Image.memory(p.jpg, height: 320, excludeFromSemantics: true),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: <Widget>[
            for (final IdPaper paper in IdPaper.values)
              ChoiceChip(
                key: Key('ids-paper-${paper.name}'),
                materialTapTargetSize: MaterialTapTargetSize.padded,
                label: Text(paper.label),
                selected: _paper == paper,
                onSelected: _busy || _saved.isNotEmpty ? null : (_) => _paperChanged(paper),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            Expanded(
              child: OutlinedButton(
                key: const Key('ids-retake-front'),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                onPressed: _busy ? null : () => _retake(IdScanStep.front),
                child: const Text('Retake front'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                key: const Key('ids-retake-back'),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                onPressed: _busy ? null : () => _retake(IdScanStep.back),
                child: const Text('Retake back'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final IdCardPage? page = _page;
    final IdScanStep step = _flow.step;
    return Scaffold(
      appBar: AppBar(title: const Text('ID scan')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Semantics(
            header: true,
            child: Text(step.title, key: const Key('ids-step'), style: text.titleMedium),
          ),
          Text(step.hint),
          const SizedBox(height: 12),
          if (step == IdScanStep.review && page != null)
            _review(page)
          else if (step == IdScanStep.review)
            const Center(child: CircularProgressIndicator(semanticsLabel: 'Making the page'))
          else ...<Widget>[
            _cameraView(),
            const SizedBox(height: 12),
            Center(
              child: SizedBox(
                width: 72,
                height: 72,
                child: FilledButton(
                  key: const Key('ids-shutter'),
                  style: FilledButton.styleFrom(shape: const CircleBorder(), padding: EdgeInsets.zero),
                  onPressed: _cameraReady && !_busy ? _shoot : null,
                  child: Icon(Icons.camera_alt,
                      semanticLabel: step == IdScanStep.front ? 'Photograph the front' : 'Photograph the back'),
                ),
              ),
            ),
          ],
          if (_status != null)
            ListTile(
              key: const Key('ids-status'),
              leading: const Icon(Icons.info_outline, semanticLabel: 'Note'),
              title: Text(_status!),
            ),
        ],
      ),
      bottomNavigationBar: ResultBar(onShare: _share, onSave: _saveFiles, onUndo: _undo),
    );
  }
}
