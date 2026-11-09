import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../app/widgets/result_bar.dart';
import '../../engines/pdf/pdf_compressor.dart';
import '../../engines/share/share_engine.dart';
import '../compress_pdf/compress_pdf_screen.dart';

typedef PdfTargetRunner = Future<PdfTargetResult> Function(Uint8List input, int target);

Future<PdfTargetResult> targetInIsolate(Uint8List input, int target) => compute(_run, (input, target));

PdfTargetResult _run((Uint8List, int) job) => PdfCompressor.toTarget(job.$1, job.$2, format: formatBytes);

/// The limits people are asked for most (forms, email, portals).
const List<int> targetPresets = <int>[100 * 1024, 200 * 1024, 500 * 1024, 1024 * 1024, 2 * 1024 * 1024];

String presetLabel(int bytes) => bytes >= 1024 * 1024 ? '${bytes ~/ (1024 * 1024)} MB' : '${bytes ~/ 1024} KB';

/// Reads what the person typed: a number and KB or MB. Null when unusable.
int? parseTarget(String text, {required bool megabytes}) {
  final double? v = double.tryParse(text.trim().replaceAll(',', '.'));
  if (v == null || v <= 0 || v > 10240) {
    return null;
  }
  return (v * (megabytes ? 1024 * 1024 : 1024)).floor();
}

/// Feature 033 — PDF to target size: type a KB or MB limit; the app hits it
/// or says why it cannot.
class PdfTargetSizeScreen extends StatefulWidget {
  const PdfTargetSizeScreen({
    super.key,
    this.files = const SystemPdfFiles(),
    this.runner = targetInIsolate,
    this.share,
  });

  final PdfFiles files;
  final PdfTargetRunner runner;
  final ShareEngine? share;

  @override
  State<PdfTargetSizeScreen> createState() => _PdfTargetSizeScreenState();
}

class _PdfTargetSizeScreenState extends State<PdfTargetSizeScreen> {
  final TextEditingController _amount = TextEditingController(text: '500');
  bool _mb = false;
  String? _path;
  Uint8List? _input;
  PdfTargetResult? _result;
  String? _savedPath;
  String? _error;
  bool _working = false;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  String get _name => _path == null ? 'document.pdf' : _path!.split('/').last;

  String get _outName {
    final String n = _name.toLowerCase().endsWith('.pdf') ? _name.substring(0, _name.length - 4) : _name;
    return '$n-${presetLabel(_result?.target ?? 0).replaceAll(' ', '').toLowerCase()}.pdf';
  }

  int? get _target => parseTarget(_amount.text, megabytes: _mb);

  void _toast(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(m)));
    }
  }

  void _usePreset(int bytes) {
    setState(() {
      _mb = bytes >= 1024 * 1024;
      _amount.text = _mb ? '${bytes ~/ (1024 * 1024)}' : '${bytes ~/ 1024}';
      _result = null;
    });
  }

  Future<void> _pick() async {
    final String? path = await widget.files.pick();
    if (path == null) {
      return;
    }
    final Uint8List bytes = await widget.files.read(path);
    if (!mounted) {
      return;
    }
    setState(() {
      _path = path;
      _input = bytes;
      _result = null;
      _savedPath = null;
      _error = null;
    });
  }

  Future<void> _go() async {
    final Uint8List? input = _input;
    final int? target = _target;
    if (input == null) {
      return;
    }
    if (target == null) {
      setState(() => _error = 'Type a size, like 500 KB or 2 MB.');
      return;
    }
    setState(() {
      _working = true;
      _error = null;
      _result = null;
    });
    try {
      final PdfTargetResult r = await widget.runner(input, target);
      if (mounted) {
        setState(() => _result = r);
      }
    } on PdfCompressError catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Something in this PDF could not be compressed. The original is untouched.');
    } finally {
      if (mounted) {
        setState(() => _working = false);
      }
    }
  }

  bool get _savable {
    final PdfTargetResult? r = _result;
    return r != null && r.reached && r.result.smaller;
  }

  Future<void> _save() async {
    final PdfTargetResult? r = _result;
    if (!_savable || r == null) {
      _toast(r == null ? 'Pick a PDF and a size first' : 'Nothing new to save');
      return;
    }
    if (_savedPath != null) {
      _toast('Already saved');
      return;
    }
    final String where = await widget.files.write(_outName, r.result.bytes);
    setState(() => _savedPath = where);
    _toast('Saved ${where.split('/').last} in Files');
  }

  Future<void> _share() async {
    final PdfTargetResult? r = _result;
    if (!_savable || r == null) {
      _toast('Nothing to share yet');
      return;
    }
    final String path = _savedPath ?? await widget.files.write(_outName, r.result.bytes);
    if (mounted) {
      setState(() => _savedPath = path);
    }
    await (widget.share ?? ShareEngine.instance).shareFiles(<String>[path]);
  }

  Future<void> _undo() async {
    final String? saved = _savedPath;
    if (saved != null) {
      await widget.files.remove(saved);
      setState(() => _savedPath = null);
      _toast('Saved copy removed. The original is untouched.');
      return;
    }
    if (_result != null) {
      setState(() => _result = null);
      return;
    }
    if (mounted) {
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final PdfTargetResult? r = _result;
    return Scaffold(
      appBar: AppBar(title: const Text('PDF to target size')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          SizedBox(
            height: 48,
            child: FilledButton.tonalIcon(
              key: const Key('target-pick'),
              onPressed: _working ? null : _pick,
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: Text(_input == null ? 'Pick a PDF' : 'Pick another PDF'),
            ),
          ),
          if (_input != null) ...<Widget>[
            const SizedBox(height: 12),
            Text('$_name · ${formatBytes(_input!.length)}', style: text.titleMedium),
          ],
          const SizedBox(height: 16),
          Text('Size limit', style: text.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final int t in targetPresets)
                ChoiceChip(
                  key: Key('target-${presetLabel(t).replaceAll(' ', '')}'),
                  label: Text(presetLabel(t)),
                  selected: _target == t,
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                  onSelected: (bool _) => _usePreset(t),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  key: const Key('target-amount'),
                  controller: _amount,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Limit'),
                  onChanged: (String _) => setState(() => _result = null),
                ),
              ),
              const SizedBox(width: 8),
              SegmentedButton<bool>(
                key: const Key('target-unit'),
                segments: const <ButtonSegment<bool>>[
                  ButtonSegment<bool>(value: false, label: Text('KB')),
                  ButtonSegment<bool>(value: true, label: Text('MB')),
                ],
                selected: <bool>{_mb},
                onSelectionChanged: (Set<bool> s) => setState(() {
                  _mb = s.first;
                  _result = null;
                }),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 48,
            child: FilledButton(
              key: const Key('target-run'),
              onPressed: _working || _input == null ? null : _go,
              child: const Text('Make it fit'),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_error!, key: const Key('target-error'), style: text.bodyMedium?.copyWith(color: Colors.red[800])),
            ),
          if (_working)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator(semanticsLabel: 'Trying sizes')),
            ),
          if (r != null)
            Card(
              margin: const EdgeInsets.only(top: 16),
              color: r.reached ? AppColors.accentTint : null,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Semantics(
                  liveRegion: true,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Icon(
                        r.reached ? Icons.check_circle_outline : Icons.error_outline,
                        color: r.reached ? AppColors.accentDark : Colors.red[800],
                        semanticLabel: r.reached ? 'Fits' : 'Does not fit',
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(r.message, key: const Key('target-message'), style: text.bodyLarge),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: ResultBar(
        onShare: _share,
        onSave: _save,
        onUndo: _undo,
        saveLabel: _savedPath == null ? 'Save' : 'Saved',
      ),
    );
  }
}
