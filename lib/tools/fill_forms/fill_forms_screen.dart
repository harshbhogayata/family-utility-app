import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../app/theme.dart';
import '../../app/widgets/result_bar.dart';
import '../../engines/pdf/pdf_form_filler.dart';
import '../../engines/pdf/pdf_signer.dart' show PageBox;
import '../../engines/records/autofill_profile.dart';
import '../../engines/share/share_engine.dart';
import '../../platform/pdf_surface.dart';

/// Picks and writes files for Fill forms. Fakes in tests.
abstract class FillFiles {
  Future<String?> pickPdf();

  Future<Uint8List> read(String path);

  Future<String> write(String name, Uint8List bytes);

  Future<void> remove(String path);
}

class SystemFillFiles implements FillFiles {
  const SystemFillFiles();

  @override
  Future<String?> pickPdf() async {
    final FilePickerResult? r =
        await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: <String>['pdf']);
    return r == null || r.files.isEmpty ? null : r.files.first.path;
  }

  @override
  Future<Uint8List> read(String path) => File(path).readAsBytes();

  @override
  Future<String> write(String name, Uint8List bytes) async {
    final Directory base = await getApplicationDocumentsDirectory();
    final Directory dir = Directory('${base.path}/filled');
    await dir.create(recursive: true);
    String path = '${dir.path}/$name';
    int i = 2;
    while (File(path).existsSync()) {
      path = '${dir.path}/${name.replaceAll('.pdf', '')} ($i).pdf';
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

typedef FillRunner = Future<Uint8List> Function(
    Uint8List pdf, Map<String, String> values, List<PlacedText> texts, bool flatten);
typedef FillPageView = Widget Function(BuildContext context, String path, int pageNumber);

class _FillJob {
  const _FillJob(this.pdf, this.values, this.texts, this.flatten);
  final Uint8List pdf;
  final Map<String, String> values;
  final List<PlacedText> texts;
  final bool flatten;
}

Uint8List _fillJob(_FillJob j) => PdfFormFiller.fill(j.pdf, values: j.values, texts: j.texts, flatten: j.flatten);

Future<Uint8List> fillInIsolate(Uint8List pdf, Map<String, String> values, List<PlacedText> texts, bool flatten) =>
    compute(_fillJob, _FillJob(pdf, values, texts, flatten));

Widget _pdfrxPage(BuildContext context, String path, int pageNumber) =>
    const PdfrxSurface().thumbnail(context, path, pageNumber);

/// Feature 009 — Fill forms.
class FillFormsScreen extends StatefulWidget {
  const FillFormsScreen({
    super.key,
    this.files = const SystemFillFiles(),
    this.runner = fillInIsolate,
    this.pageView = _pdfrxPage,
    this.profile,
    this.share,
  });

  final FillFiles files;
  final FillRunner runner;
  final FillPageView pageView;
  final AutofillProfileBook? profile;
  final ShareEngine? share;

  @override
  State<FillFormsScreen> createState() => _FillFormsScreenState();
}

class _FillFormsScreenState extends State<FillFormsScreen> {
  AutofillProfileBook get _profile => widget.profile ?? AutofillProfileBook.instance;

  String? _path;
  Uint8List? _pdf;
  FormInfo? _info;
  final Map<String, String> _values = <String, String>{};
  final Map<String, TextEditingController> _controllers = <String, TextEditingController>{};
  final List<PlacedText> _texts = <PlacedText>[];
  int _page = 0;
  bool _flatten = false;
  String? _output;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    if (!_profile.isLoaded) {
      unawaited(_profile.load().then((_) {
        if (mounted) {
          setState(() {});
        }
      }));
    }
  }

  @override
  void dispose() {
    for (final TextEditingController c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _toast(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(m)));
    }
  }

  Future<void> _pick() async {
    final String? path = await widget.files.pickPdf();
    if (path == null) {
      return;
    }
    final Uint8List bytes = await widget.files.read(path);
    try {
      final FormInfo info = PdfFormFiller.detect(bytes);
      for (final TextEditingController c in _controllers.values) {
        c.dispose();
      }
      _controllers.clear();
      setState(() {
        _path = path;
        _pdf = bytes;
        _info = info;
        _values.clear();
        _texts.clear();
        _page = 0;
        _output = null;
        for (final FormFieldInfo f in info.fields) {
          _values[f.name] = f.value;
          if (f.kind == FormFieldKind.text || (f.kind == FormFieldKind.choice && f.options.isEmpty)) {
            _controllers[f.name] = TextEditingController(text: f.value);
          }
        }
      });
      _toast(info.hasForm
          ? 'Found ${info.fields.length} field${info.fields.length == 1 ? '' : 's'}'
          : 'No form in this PDF. Tap the page to place text.');
    } on FormFillError catch (e) {
      _toast(e.message);
    }
  }

  void _set(String name, String value) {
    setState(() {
      _values[name] = value;
      _output = null;
    });
  }

  void _useSuggestion(FormFieldInfo f, String value) {
    _controllers[f.name]?.text = value;
    _set(f.name, value);
  }

  Future<void> _save() async {
    final Uint8List? pdf = _pdf;
    if (pdf == null) {
      _toast('Choose a PDF first');
      return;
    }
    if (_working) {
      return;
    }
    setState(() => _working = true);
    try {
      final Map<String, String> changed = <String, String>{};
      for (final FormFieldInfo f in _info!.fields) {
        final String? v = _values[f.name];
        if (v != null && v != f.value) {
          changed[f.name] = v;
        }
      }
      final Uint8List out = await widget.runner(pdf, changed, List<PlacedText>.of(_texts), _flatten);
      final String name = _path!.split('/').last.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '');
      final String path = await widget.files.write('$name-filled.pdf', out);
      setState(() => _output = path);
      _toast(_flatten ? 'Saved in Files › filled. Fields are flattened into the page.' : 'Saved in Files › filled');
    } on FormFillError catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast('Could not fill this PDF');
    } finally {
      if (mounted) {
        setState(() => _working = false);
      }
    }
  }

  Future<void> _share() async {
    if (_output == null) {
      await _save();
    }
    final String? out = _output;
    if (out != null) {
      await (widget.share ?? ShareEngine.instance).shareFiles(<String>[out]);
    }
  }

  Future<void> _undo() async {
    final String? out = _output;
    if (out != null) {
      await widget.files.remove(out);
      setState(() => _output = null);
      _toast('Removed the filled copy');
      return;
    }
    if (_texts.isNotEmpty) {
      setState(() => _texts.removeLast());
      _toast('Removed the last text box');
      return;
    }
    _toast('Nothing to undo');
  }

  /// Every profile value, for a text box placed by hand.
  List<AutofillSuggestion> _allProfileValues() {
    final List<AutofillSuggestion> out = <AutofillSuggestion>[];
    for (final String probe in <String>['name', 'dob', 'phone', 'email', 'address']) {
      out.addAll(_profile.suggestionsFor(probe));
    }
    return out;
  }

  Future<String?> _askText(String initial) {
    final TextEditingController c = TextEditingController(text: initial);
    final List<AutofillSuggestion> profile = _allProfileValues();
    return showDialog<String>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Text on the page'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              TextField(
                key: const Key('fill-box-text'),
                controller: c,
                autofocus: true,
                minLines: 1,
                maxLines: 4,
                decoration: const InputDecoration(labelText: 'Text'),
              ),
              if (profile.isNotEmpty) ...<Widget>[
                const SizedBox(height: 8),
                const Text('From My details'),
                Wrap(
                  spacing: 8,
                  children: <Widget>[
                    for (final AutofillSuggestion s in profile)
                      ActionChip(
                        label: Text(s.value, overflow: TextOverflow.ellipsis),
                        tooltip: s.label,
                        onPressed: () => c.text = s.value,
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          FilledButton(
            key: const Key('fill-box-ok'),
            onPressed: () => Navigator.of(context).pop(c.text),
            child: const Text('Place'),
          ),
        ],
      ),
    );
  }

  Future<void> _placeAt(double left, double top) async {
    final String? text = await _askText('');
    if (text == null || text.trim().isEmpty) {
      return;
    }
    setState(() {
      _texts.add(PlacedText(page: _page, left: left, top: top, text: text.trim()));
      _output = null;
    });
  }

  Future<void> _editBox(int i) async {
    final String? text = await _askText(_texts[i].text);
    if (text == null) {
      return;
    }
    setState(() {
      if (text.trim().isEmpty) {
        _texts.removeAt(i);
      } else {
        _texts[i] = _texts[i].copyWith(text: text.trim());
      }
      _output = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final FormInfo? info = _info;
    return Scaffold(
      appBar: AppBar(title: const Text('Fill forms')),
      bottomNavigationBar: info == null
          ? null
          : ResultBar(
              onShare: () => unawaited(_share()),
              onSave: () => unawaited(_save()),
              onUndo: () => unawaited(_undo()),
            ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          OutlinedButton.icon(
            key: const Key('fill-pick'),
            style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 48)),
            onPressed: () => unawaited(_pick()),
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: Text(_path == null ? 'Choose a PDF' : _path!.split('/').last),
          ),
          if (info == null) ...<Widget>[
            const SizedBox(height: 12),
            Text('Fill the boxes of a form, or type anywhere on any PDF. Works offline.', style: text.bodyMedium),
          ],
          if (info != null) ...<Widget>[
            const SizedBox(height: 12),
            if (info.hasForm) ...<Widget>[
              Text('Form fields', style: text.titleMedium),
              for (final FormFieldInfo f in info.fields) _field(f),
              SwitchListTile(
                key: const Key('fill-flatten'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Flatten on export'),
                subtitle: const Text('Fields become part of the page and can no longer be edited'),
                value: _flatten,
                onChanged: (bool v) => setState(() {
                  _flatten = v;
                  _output = null;
                }),
              ),
              const SizedBox(height: 8),
            ],
            Text('Text on the page', style: text.titleMedium),
            Text('Tap the page where the text should go.', style: text.bodySmall),
            const SizedBox(height: 8),
            _pager(info),
            _pageCanvas(info.pages[_page]),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const Key('fill-add-box'),
                style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                onPressed: () => unawaited(_placeAt(0.1, 0.1)),
                icon: const Icon(Icons.text_fields),
                label: const Text('Add text box'),
              ),
            ),
            if (_working) const LinearProgressIndicator(),
          ],
        ],
      ),
    );
  }

  Widget _pager(FormInfo info) {
    if (info.pages.length < 2) {
      return const SizedBox.shrink();
    }
    return Row(
      children: <Widget>[
        IconButton(
          tooltip: 'Previous page',
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          onPressed: _page == 0 ? null : () => setState(() => _page--),
          icon: const Icon(Icons.chevron_left),
        ),
        Text('Page ${_page + 1} of ${info.pages.length}'),
        IconButton(
          tooltip: 'Next page',
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          onPressed: _page >= info.pages.length - 1 ? null : () => setState(() => _page++),
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    );
  }

  Widget _pageCanvas(PageBox box) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 520),
      child: Center(
        child: AspectRatio(
          aspectRatio: box.width / box.height,
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints c) {
              final double w = c.maxWidth;
              final double h = c.maxHeight;
              final double scale = w / box.width;
              return GestureDetector(
                key: const Key('fill-page'),
                behavior: HitTestBehavior.opaque,
                onTapUp: (TapUpDetails d) =>
                    unawaited(_placeAt(
                    (d.localPosition.dx / w).clamp(0.0, 1.0).toDouble(),
                    (d.localPosition.dy / h).clamp(0.0, 1.0).toDouble(),
                  )),
                child: Stack(
                  children: <Widget>[
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: AppColors.line)),
                        child: widget.pageView(context, _path!, _page + 1),
                      ),
                    ),
                    for (int i = 0; i < _texts.length; i++)
                      if (_texts[i].page == _page)
                        Positioned(
                          left: _texts[i].left * w,
                          top: _texts[i].top * h,
                          child: Semantics(
                            button: true,
                            label: 'Text box: ${_texts[i].text}. Tap to edit',
                            child: GestureDetector(
                              key: Key('fill-box-$i'),
                              onTap: () => unawaited(_editBox(i)),
                              child: Container(
                                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                                decoration: BoxDecoration(border: Border.all(color: AppColors.accent)),
                                child: ExcludeSemantics(
                                  child: Text(
                                    _texts[i].text,
                                    style: TextStyle(fontSize: _texts[i].fontSize * scale, color: Colors.black, height: 1.2),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _field(FormFieldInfo f) {
    final String value = _values[f.name] ?? f.value;
    switch (f.kind) {
      case FormFieldKind.checkbox:
        return CheckboxListTile(
          key: Key('fill-field-${f.name}'),
          contentPadding: EdgeInsets.zero,
          title: Text(f.label),
          value: value != 'Off' && value.isNotEmpty,
          onChanged: f.editable
              ? (bool? v) => _set(f.name, v == true ? (f.options.isEmpty ? 'Yes' : f.options.first) : 'Off')
              : null,
        );
      case FormFieldKind.radio:
      case FormFieldKind.choice:
        if (f.options.isNotEmpty) {
          final List<String> items = <String>[if (f.kind == FormFieldKind.radio) 'Off', ...f.options];
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: DropdownButtonFormField<String>(
              key: Key('fill-field-${f.name}'),
              initialValue: items.contains(value) ? value : null,
              decoration: InputDecoration(labelText: f.label),
              items: <DropdownMenuItem<String>>[
                for (final String o in items)
                  DropdownMenuItem<String>(value: o, child: Text(o == 'Off' ? 'None' : o)),
              ],
              onChanged: f.editable ? (String? v) => _set(f.name, v ?? 'Off') : null,
            ),
          );
        }
        return _textField(f);
      case FormFieldKind.text:
        return _textField(f);
      case FormFieldKind.signature:
      case FormFieldKind.button:
        return ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(f.label),
          subtitle: Text(f.kind == FormFieldKind.signature ? 'Signature field: use Sign PDF' : 'Button'),
        );
    }
  }

  Widget _textField(FormFieldInfo f) {
    final List<AutofillSuggestion> suggestions = _profile.suggestionsFor(f.caption ?? f.name);
    if (suggestions.isEmpty && f.caption != null) {
      suggestions.addAll(_profile.suggestionsFor(f.name));
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          TextField(
            key: Key('fill-field-${f.name}'),
            controller: _controllers[f.name],
            enabled: f.editable,
            maxLength: f.maxLength,
            minLines: 1,
            maxLines: f.multiline ? 4 : 1,
            decoration: InputDecoration(labelText: f.label),
            onChanged: (String v) => _set(f.name, v),
          ),
          if (f.editable && suggestions.isNotEmpty)
            Wrap(
              spacing: 8,
              children: <Widget>[
                for (final AutofillSuggestion s in suggestions.take(3))
                  ActionChip(
                    key: Key('fill-suggest-${f.name}-${s.value}'),
                    avatar: const Icon(Icons.badge_outlined, size: 18),
                    label: Text(s.value, overflow: TextOverflow.ellipsis),
                    tooltip: 'Fill with ${s.label}',
                    onPressed: () => _useSuggestion(f, s.value),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
