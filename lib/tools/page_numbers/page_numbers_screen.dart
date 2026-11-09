import 'package:flutter/material.dart';

import '../../app/widgets/result_bar.dart';
import '../../engines/convert/convert_registry.dart';
import '../../engines/convert/file_kind.dart';
import '../../engines/pdf/page_numbers.dart';
import '../../engines/share/share_engine.dart';
import '../convert_anything/convert_anything_screen.dart';

/// Feature 014 — Page numbers. Pick a PDF, choose where the number goes, its
/// size, the first number and whether the cover is skipped, then stamp.
class PageNumbersScreen extends StatefulWidget {
  const PageNumbersScreen({
    super.key,
    this.chooser = const SystemConvertFileChooser(),
    this.sink = const FolderConvertSink(),
    this.share,
  });

  final ConvertFileChooser chooser;
  final ConvertSink sink;
  final ShareEngine? share;

  @override
  State<PageNumbersScreen> createState() => _PageNumbersScreenState();
}

class _PageNumbersScreenState extends State<PageNumbersScreen> {
  ConvertInput? _input;
  NumberPosition _position = NumberPosition.bottomCenter;
  double _size = 11;
  int _start = 1;
  bool _skipFirst = false;
  final List<String> _written = <String>[];
  String? _status;
  bool _busy = false;

  void _toast(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(m)));
    }
  }

  Future<void> _pick() async {
    final ConvertInput? input = await widget.chooser.pick();
    if (input == null || !mounted) {
      return;
    }
    if (sniffFileKind(input.bytes) != FileKind.pdf) {
      setState(() => _status = 'Pick a PDF. This one is ${sniffFileKind(input.bytes).label}.');
      return;
    }
    setState(() {
      _input = input;
      _status = null;
    });
  }

  Future<void> _run() async {
    final ConvertInput? input = _input;
    if (input == null || _busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      final PageNumberOptions o =
          PageNumberOptions(position: _position, fontSize: _size, start: _start, skipFirst: _skipFirst);
      final ConvertOutput out = ConvertOutput(
        name: '${input.stem}-numbered.pdf',
        bytes: PageNumberer.stamp(input.bytes, o),
        kind: FileKind.pdf,
      );
      final String path = await widget.sink.write(out);
      _written.add(path);
      setState(() => _status = 'Made ${out.name} in Files › converted');
    } on PageNumberError catch (e) {
      setState(() => _status = e.message);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _share() async {
    if (_written.isEmpty) {
      _toast('Add page numbers first');
      return;
    }
    await (widget.share ?? ShareEngine.instance).shareFiles(<String>[_written.last]);
  }

  void _save() => _toast(_written.isEmpty ? 'Nothing to save yet' : 'Saved in Files › converted');

  Future<void> _undo() async {
    if (_written.isEmpty) {
      Navigator.of(context).maybePop();
      return;
    }
    final String last = _written.removeLast();
    await widget.sink.remove(last);
    setState(() => _status = 'Removed ${last.substring(last.lastIndexOf('/') + 1)}');
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Page numbers')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          OutlinedButton.icon(
            key: const Key('pn-pick'),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: _busy ? null : _pick,
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: Text(_input?.name ?? 'Choose a PDF'),
          ),
          const SizedBox(height: 16),
          Text('Position', style: text.titleSmall),
          Wrap(spacing: 8, children: <Widget>[
            for (final NumberPosition p in NumberPosition.values)
              ChoiceChip(
                key: Key('pn-pos-${p.name}'),
                materialTapTargetSize: MaterialTapTargetSize.padded,
                label: Text(p.label),
                selected: _position == p,
                onSelected: (_) => setState(() => _position = p),
              ),
          ]),
          const SizedBox(height: 16),
          Text('Size ${_size.round()} pt', style: text.titleSmall),
          Slider(
            key: const Key('pn-size'),
            value: _size,
            min: 6,
            max: 36,
            divisions: 30,
            label: '${_size.round()} pt',
            semanticFormatterCallback: (double v) => '${v.round()} point numbers',
            onChanged: (double v) => setState(() => _size = v.roundToDouble()),
          ),
          Row(children: <Widget>[
            Expanded(child: Text('Start at', style: text.titleSmall)),
            IconButton(
              key: const Key('pn-start-down'),
              tooltip: 'Start one lower',
              onPressed: _start > 0 ? () => setState(() => _start--) : null,
              icon: const Icon(Icons.remove),
            ),
            Text('$_start', key: const Key('pn-start')),
            IconButton(
              key: const Key('pn-start-up'),
              tooltip: 'Start one higher',
              onPressed: () => setState(() => _start++),
              icon: const Icon(Icons.add),
            ),
          ]),
          SwitchListTile(
            key: const Key('pn-skip-first'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Skip the first page'),
            subtitle: const Text('Leave the cover unnumbered'),
            value: _skipFirst,
            onChanged: (bool v) => setState(() => _skipFirst = v),
          ),
          const SizedBox(height: 12),
          FilledButton(
            key: const Key('pn-run'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: _input == null || _busy ? null : _run,
            child: const Text('Add page numbers'),
          ),
          if (_status != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Semantics(
                liveRegion: true,
                child: Text(_status!, key: const Key('pn-status'), style: text.bodyMedium),
              ),
            ),
        ],
      ),
      bottomNavigationBar: ResultBar(onShare: _share, onSave: _save, onUndo: _undo),
    );
  }
}
