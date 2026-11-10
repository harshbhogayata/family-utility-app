import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/widgets/result_bar.dart';
import '../../engines/pdf/text_to_pdf.dart';
import '../../engines/records/autofill_profile.dart';
import '../../engines/records/templates.dart';
import '../../engines/share/share_engine.dart';
import '../../tools/text_to_pdf/text_to_pdf_screen.dart' show SystemTextPdfFiles, TextPdfFiles;

/// Feature 101 — pick one of ten templates.
class TemplatesScreen extends StatelessWidget {
  const TemplatesScreen({super.key, this.profile, this.files, this.maker, this.share, this.today});

  final AutofillProfile Function()? profile;
  final TextPdfFiles? files;
  final TextPdfMaker? maker;
  final ShareEngine? share;
  final DateTime Function()? today;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Templates')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: <Widget>[
          for (final DocTemplate t in Templates.all)
            ListTile(
              key: Key('template-${t.id}'),
              minTileHeight: 56,
              leading: const Icon(Icons.description_outlined),
              title: Text(t.titleEn),
              subtitle: Text(t.titleHi),
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (BuildContext context) => TemplateEditorScreen(
                    template: t,
                    profile: profile,
                    files: files,
                    maker: maker,
                    share: share,
                    today: today,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Fill one template (prefilled from the saved profile), preview, and make
/// the PDF. Share, Save and Undo at the bottom.
class TemplateEditorScreen extends StatefulWidget {
  const TemplateEditorScreen({super.key, required this.template, this.profile, this.files, this.maker, this.share, this.today});

  final DocTemplate template;
  final AutofillProfile Function()? profile;
  final TextPdfFiles? files;
  final TextPdfMaker? maker;
  final ShareEngine? share;
  final DateTime Function()? today;

  @override
  State<TemplateEditorScreen> createState() => _TemplateEditorScreenState();
}

class _TemplateEditorScreenState extends State<TemplateEditorScreen> {
  TemplateLang _lang = TemplateLang.en;
  final Map<String, TextEditingController> _c = <String, TextEditingController>{};
  String? _path;
  bool _working = false;
  String _status = '';
  Map<String, String>? _beforeClear;

  DocTemplate get _t => widget.template;
  TextPdfFiles get _files => widget.files ?? const SystemTextPdfFiles();

  AutofillProfile _profile() {
    final AutofillProfile Function()? p = widget.profile;
    return p != null ? p() : AutofillProfileBook.instance.profile;
  }

  @override
  void initState() {
    super.initState();
    final Map<String, String> start = Templates.prefill(_t, _profile(), (widget.today ?? DateTime.now)());
    for (final TemplateField f in _t.fields) {
      _c[f.key] = TextEditingController(text: start[f.key] ?? '')..addListener(_edited);
    }
    final int filled = start.values.where((String v) => v.isNotEmpty).length;
    _status = filled == 0 ? 'Fill in the fields; add your details in the saved profile to skip this next time.' : 'Filled $filled from your saved profile.';
  }

  void _edited() {
    if (_path != null && mounted) {
      setState(() => _path = null); // the saved PDF no longer matches
    } else if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    for (final TextEditingController c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, String> get _values => <String, String>{for (final MapEntry<String, TextEditingController> e in _c.entries) e.key: e.value.text};

  void _toast(String s) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
    }
  }

  Future<void> _save() async {
    if (_working) {
      return;
    }
    if (_path != null) {
      _toast('Saved in Files › converted');
      return;
    }
    setState(() {
      _working = true;
      _status = 'Making the PDF…';
    });
    try {
      final TextPdfResult r = await Templates.toPdf(_t, _lang, _values, maker: widget.maker ?? const TextPdfMaker());
      final String path = await _files.write(r.name, r.bytes);
      if (!mounted) {
        return;
      }
      setState(() {
        _path = path;
        _status = 'Saved ${r.name} in Files › converted. Made on this phone.';
      });
    } on TextPdfError catch (e) {
      if (mounted) {
        setState(() => _status = e.message);
      }
    } finally {
      if (mounted) {
        setState(() => _working = false);
      }
    }
  }

  Future<void> _share() async {
    if (_path == null) {
      await _save();
    }
    final String? path = _path;
    if (path != null) {
      await (widget.share ?? ShareEngine.instance).shareFiles(<String>[path]);
    }
  }

  Future<void> _undo() async {
    final String? path = _path;
    if (path != null) {
      await _files.remove(path);
      if (mounted) {
        setState(() {
          _path = null;
          _status = 'Removed the PDF; your entries are still here';
        });
      }
      return;
    }
    final Map<String, String>? before = _beforeClear;
    if (before != null) {
      _beforeClear = null;
      _setAll(before);
      setState(() => _status = 'Fields back');
      return;
    }
    _toast('Nothing to undo');
  }

  void _setAll(Map<String, String> v) {
    for (final MapEntry<String, TextEditingController> e in _c.entries) {
      e.value.text = v[e.key] ?? '';
    }
  }

  void _clear() {
    _beforeClear = _values;
    _setAll(const <String, String>{});
    setState(() => _status = 'Cleared. Undo brings the entries back.');
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(_t.title(_lang)),
        actions: <Widget>[
          IconButton(
            key: const Key('template-clear'),
            tooltip: 'Clear all fields',
            onPressed: _clear,
            icon: const Icon(Icons.clear_all),
          ),
        ],
      ),
      bottomNavigationBar: ResultBar(
        onShare: () => unawaited(_share()),
        onSave: () => unawaited(_save()),
        onUndo: () => unawaited(_undo()),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: <Widget>[
          SegmentedButton<TemplateLang>(
            key: const Key('template-lang'),
            segments: <ButtonSegment<TemplateLang>>[
              for (final TemplateLang l in TemplateLang.values) ButtonSegment<TemplateLang>(value: l, label: Text(l.label)),
            ],
            selected: <TemplateLang>{_lang},
            onSelectionChanged: (Set<TemplateLang> s) => setState(() {
              _lang = s.first;
              _path = null;
            }),
          ),
          const SizedBox(height: 8),
          Semantics(liveRegion: true, child: Text(_status, key: const Key('template-status'), style: text.bodySmall)),
          for (final TemplateField f in _t.fields)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: TextField(
                key: Key('template-field-${f.key}'),
                controller: _c[f.key],
                minLines: f.multiline ? 2 : 1,
                maxLines: f.multiline ? 5 : 1,
                decoration: InputDecoration(labelText: f.label(_lang), border: const OutlineInputBorder()),
              ),
            ),
          const SizedBox(height: 16),
          Text(_lang == TemplateLang.en ? 'Preview' : 'पूर्वावलोकन', style: text.titleMedium),
          const SizedBox(height: 4),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: SelectableText(Templates.fill(_t, _lang, _values), key: const Key('template-preview')),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const Key('template-make'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: _working ? null : () => unawaited(_save()),
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: const Text('Make PDF'),
          ),
        ],
      ),
    );
  }
}
