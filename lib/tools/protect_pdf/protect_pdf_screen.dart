import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../app/widgets/result_bar.dart';
import '../../engines/pdf/pdf_compressor.dart';
import '../../engines/pdf/pdf_protector.dart';
import '../../engines/share/share_engine.dart';

class ProtectInput {
  const ProtectInput(this.name, this.bytes);
  final String name;
  final Uint8List bytes;
}

/// Picks the PDF and keeps the protected copy. Behind an interface for tests.
abstract class ProtectFiles {
  Future<ProtectInput?> pick();
  Future<String> write(String name, Uint8List bytes);
  Future<void> remove(String path);
}

class SystemProtectFiles implements ProtectFiles {
  const SystemProtectFiles();

  @override
  Future<ProtectInput?> pick() async {
    final FilePickerResult? r = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: <String>['pdf'],
    );
    final List<PlatformFile> files = r?.files ?? const <PlatformFile>[];
    final String? p = files.isEmpty ? null : files.first.path;
    if (p == null) {
      return null;
    }
    return ProtectInput(files.first.name, await File(p).readAsBytes());
  }

  @override
  Future<String> write(String name, Uint8List bytes) async {
    final Directory base = await getApplicationDocumentsDirectory();
    final Directory dir = Directory('${base.path}/protected');
    await dir.create(recursive: true);
    String path = '${dir.path}/$name';
    int i = 2;
    while (File(path).existsSync()) {
      path = '${dir.path}/${name.substring(0, name.length - 4)} ($i).pdf';
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

/// Everything protect needs, sendable to an isolate.
class ProtectJob {
  const ProtectJob(this.bytes, this.options);
  final Uint8List bytes;
  final PdfProtectOptions options;
}

PdfProtectResult _protect(ProtectJob job) => PdfProtector.protect(job.bytes, job.options);

typedef ProtectRunner = Future<PdfProtectResult> Function(ProtectJob job);

Future<PdfProtectResult> protectInIsolate(ProtectJob job) => compute(_protect, job);

/// Feature 011 — Protect with password.
class ProtectPdfScreen extends StatefulWidget {
  const ProtectPdfScreen({super.key, this.files = const SystemProtectFiles(), this.runner = protectInIsolate, this.share});

  final ProtectFiles files;
  final ProtectRunner runner;
  final ShareEngine? share;

  @override
  State<ProtectPdfScreen> createState() => _ProtectPdfScreenState();
}

class _ProtectPdfScreenState extends State<ProtectPdfScreen> {
  final TextEditingController _pw = TextEditingController();
  final TextEditingController _confirm = TextEditingController();
  ProtectInput? _input;
  bool _show = false;
  bool _allowPrint = true;
  bool _allowCopy = true;
  bool _working = false;
  String? _saved;
  String? _status;

  @override
  void initState() {
    super.initState();
    _pw.addListener(_changed);
    _confirm.addListener(_changed);
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    _pw.dispose();
    _confirm.dispose();
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
    final ProtectInput? p = await widget.files.pick();
    if (!mounted || p == null) {
      return;
    }
    setState(() {
      _input = p;
      _saved = null;
      _status = null;
    });
  }

  String? get _problem {
    if (_input == null) {
      return 'Choose a PDF first';
    }
    if (_pw.text.isEmpty) {
      return 'Type a password';
    }
    if (_confirm.text != _pw.text) {
      return 'The two passwords do not match';
    }
    return null;
  }

  Future<void> _run() async {
    final ProtectInput? input = _input;
    if (input == null || _problem != null || _working) {
      return;
    }
    setState(() => _working = true);
    try {
      final PdfProtectResult r = await widget.runner(ProtectJob(
        input.bytes,
        PdfProtectOptions(password: _pw.text, allowPrint: _allowPrint, allowCopy: _allowCopy),
      ));
      final String stem = input.name.toLowerCase().endsWith('.pdf') ? input.name.substring(0, input.name.length - 4) : input.name;
      final String path = await widget.files.write('$stem protected.pdf', r.bytes);
      // The password is not kept: the fields are cleared once it is used.
      _pw.clear();
      _confirm.clear();
      final List<String> limits = <String>[
        if (!_allowPrint) 'no printing',
        if (!_allowCopy) 'no copying',
      ];
      setState(() {
        _saved = path;
        _status = 'Protected with AES-256${limits.isEmpty ? '' : ' · ${limits.join(', ')}'}. '
            'Keep the password safe: it cannot be recovered.';
      });
    } on PdfCompressError catch (e) {
      setState(() => _status = e.message);
    } finally {
      if (mounted) {
        setState(() => _working = false);
      }
    }
  }

  Future<void> _share() async {
    final String? p = _saved;
    if (p == null) {
      _toast('Protect a PDF first');
      return;
    }
    await (widget.share ?? ShareEngine.instance).shareFiles(<String>[p]);
  }

  void _save() => _toast(_saved == null ? 'Nothing to save yet' : 'Saved in Files › protected');

  Future<void> _undo() async {
    final String? p = _saved;
    if (p != null) {
      await widget.files.remove(p);
      setState(() {
        _saved = null;
        _status = 'Removed the protected copy. The original was never changed.';
      });
      return;
    }
    if (_input != null) {
      setState(() => _input = null);
      return;
    }
    if (mounted) {
      await Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final PasswordStrength strength = PasswordStrength.of(_pw.text);
    final Color meter = strength.level <= 1
        ? scheme.error
        : strength.level == 2
            ? Colors.orange.shade700
            : Colors.green.shade700;
    final String? problem = _problem;
    return Scaffold(
      appBar: AppBar(title: const Text('Protect with password')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          OutlinedButton.icon(
            key: const Key('protect-pick'),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: _working ? null : _pick,
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: Text(_input == null ? 'Choose a PDF' : _input!.name),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('protect-password'),
            controller: _pw,
            obscureText: !_show,
            enableSuggestions: false,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: 'Password to open the file',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                key: const Key('protect-show'),
                tooltip: _show ? 'Hide password' : 'Show password',
                onPressed: () => setState(() => _show = !_show),
                icon: Icon(_show ? Icons.visibility_off : Icons.visibility),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Semantics(
            label: 'Password strength: ${strength.label}',
            child: ExcludeSemantics(
              child: Row(children: <Widget>[
                Expanded(
                  child: LinearProgressIndicator(
                    key: const Key('protect-strength-bar'),
                    value: strength.level / 4,
                    color: meter,
                    minHeight: 6,
                  ),
                ),
                const SizedBox(width: 12),
                Text(strength.label, key: const Key('protect-strength')),
              ]),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('protect-confirm'),
            controller: _confirm,
            obscureText: !_show,
            enableSuggestions: false,
            autocorrect: false,
            decoration: const InputDecoration(labelText: 'Type it again', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            key: const Key('protect-print'),
            title: const Text('Allow printing'),
            value: _allowPrint,
            onChanged: (bool v) => setState(() => _allowPrint = v),
          ),
          SwitchListTile(
            key: const Key('protect-copy'),
            title: const Text('Allow copying text'),
            subtitle: const Text('Screen readers can always read it'),
            value: _allowCopy,
            onChanged: (bool v) => setState(() => _allowCopy = v),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            key: const Key('protect-run'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: problem == null && !_working ? _run : null,
            icon: const Icon(Icons.lock_outline),
            label: Text(_working ? 'Protecting…' : (problem ?? 'Protect PDF')),
          ),
          const SizedBox(height: 8),
          const Text('The password is used once on this phone and is not stored anywhere. '
              'If it is forgotten, the protected copy cannot be opened.'),
          if (_status != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Semantics(liveRegion: true, child: Text(_status!, key: const Key('protect-status'))),
            ),
        ],
      ),
      bottomNavigationBar: ResultBar(onShare: _share, onSave: _save, onUndo: _undo),
    );
  }
}
