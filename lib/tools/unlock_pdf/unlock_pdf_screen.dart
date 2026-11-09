import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../app/widgets/result_bar.dart';
import '../../engines/pdf/pdf_compressor.dart';
import '../../engines/pdf/pdf_unlocker.dart';
import '../../engines/share/share_engine.dart';

class UnlockInput {
  const UnlockInput(this.name, this.bytes);
  final String name;
  final Uint8List bytes;
}

/// Picks the locked PDF and keeps the unlocked copy. Behind an interface for tests.
abstract class UnlockFiles {
  Future<UnlockInput?> pick();
  Future<String> write(String name, Uint8List bytes);
  Future<void> remove(String path);
}

class SystemUnlockFiles implements UnlockFiles {
  const SystemUnlockFiles();

  @override
  Future<UnlockInput?> pick() async {
    final FilePickerResult? r = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: <String>['pdf'],
    );
    final List<PlatformFile> files = r?.files ?? const <PlatformFile>[];
    final String? p = files.isEmpty ? null : files.first.path;
    if (p == null) {
      return null;
    }
    return UnlockInput(files.first.name, await File(p).readAsBytes());
  }

  @override
  Future<String> write(String name, Uint8List bytes) async {
    final Directory base = await getApplicationDocumentsDirectory();
    final Directory dir = Directory('${base.path}/unlocked');
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

/// Everything unlock needs, sendable to an isolate.
class UnlockJob {
  const UnlockJob(this.bytes, this.password);
  final Uint8List bytes;
  final String password;
}

PdfUnlockResult _unlock(UnlockJob job) => PdfUnlocker.unlock(job.bytes, job.password);

typedef UnlockRunner = Future<PdfUnlockResult> Function(UnlockJob job);

Future<PdfUnlockResult> unlockInIsolate(UnlockJob job) => compute(_unlock, job);

/// Feature 012 — Unlock a known password.
class UnlockPdfScreen extends StatefulWidget {
  const UnlockPdfScreen({super.key, this.files = const SystemUnlockFiles(), this.runner = unlockInIsolate, this.share});

  final UnlockFiles files;
  final UnlockRunner runner;
  final ShareEngine? share;

  @override
  State<UnlockPdfScreen> createState() => _UnlockPdfScreenState();
}

class _UnlockPdfScreenState extends State<UnlockPdfScreen> {
  final TextEditingController _pw = TextEditingController();
  final TextEditingController _name = TextEditingController();
  final TextEditingController _year = TextEditingController();
  UnlockInput? _input;
  bool _show = false;
  bool _working = false;
  bool _wrong = false;
  String? _saved;
  String? _status;

  @override
  void initState() {
    super.initState();
    _pw.addListener(_changed);
    _name.addListener(_changed);
    _year.addListener(_changed);
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    _pw.dispose();
    _name.dispose();
    _year.dispose();
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
    final UnlockInput? p = await widget.files.pick();
    if (!mounted || p == null) {
      return;
    }
    setState(() {
      _input = p;
      _saved = null;
      _wrong = false;
      _status = PdfUnlocker.isProtected(p.bytes) ? null : 'This PDF has no password to remove.';
    });
  }

  String? get _aadhaar {
    final int? year = int.tryParse(_year.text.trim());
    if (_name.text.trim().isEmpty || year == null || year < 1900 || year > 2100) {
      return null;
    }
    return PdfUnlocker.aadhaarPassword(_name.text, year);
  }

  String? get _problem {
    if (_input == null) {
      return 'Choose a PDF first';
    }
    if (_pw.text.isEmpty) {
      return 'Type its password';
    }
    return null;
  }

  Future<void> _run() async {
    final UnlockInput? input = _input;
    if (input == null || _problem != null || _working) {
      return;
    }
    setState(() => _working = true);
    try {
      final PdfUnlockResult r = await widget.runner(UnlockJob(input.bytes, _pw.text));
      final String stem = input.name.toLowerCase().endsWith('.pdf') ? input.name.substring(0, input.name.length - 4) : input.name;
      final String path = await widget.files.write('$stem unlocked.pdf', r.bytes);
      // The password is used once and not kept.
      _pw.clear();
      setState(() {
        _saved = path;
        _wrong = false;
        _status = 'Password removed (${r.method}) · ${r.pages} ${r.pages == 1 ? 'page' : 'pages'}. '
            'Anyone with this copy can open it, so share it with care.';
      });
    } on PdfWrongPasswordError catch (e) {
      setState(() {
        _wrong = true;
        _status = e.message;
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
      _toast('Unlock a PDF first');
      return;
    }
    await (widget.share ?? ShareEngine.instance).shareFiles(<String>[p]);
  }

  void _save() => _toast(_saved == null ? 'Nothing to save yet' : 'Saved in Files › unlocked');

  Future<void> _undo() async {
    final String? p = _saved;
    if (p != null) {
      await widget.files.remove(p);
      setState(() {
        _saved = null;
        _status = 'Removed the unlocked copy. The original still has its password.';
      });
      return;
    }
    if (_input != null) {
      setState(() {
        _input = null;
        _status = null;
        _wrong = false;
      });
      return;
    }
    if (mounted) {
      await Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final String? problem = _problem;
    final String? aadhaar = _aadhaar;
    return Scaffold(
      appBar: AppBar(title: const Text('Unlock a known password')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          OutlinedButton.icon(
            key: const Key('unlock-pick'),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: _working ? null : _pick,
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: Text(_input == null ? 'Choose a locked PDF' : _input!.name),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('unlock-password'),
            controller: _pw,
            obscureText: !_show,
            enableSuggestions: false,
            autocorrect: false,
            onSubmitted: (_) => _run(),
            decoration: InputDecoration(
              labelText: 'Password of the file',
              helperText: 'Capitals matter. The owner password works too.',
              errorText: _wrong ? 'Wrong password' : null,
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                key: const Key('unlock-show'),
                tooltip: _show ? 'Hide password' : 'Show password',
                onPressed: () => setState(() => _show = !_show),
                icon: Icon(_show ? Icons.visibility_off : Icons.visibility),
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const Key('unlock-run'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: problem == null && !_working ? _run : null,
            icon: const Icon(Icons.lock_open_outlined),
            label: Text(_working ? 'Unlocking…' : (problem ?? 'Remove password')),
          ),
          if (_status != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  _status!,
                  key: const Key('unlock-status'),
                  style: _wrong ? TextStyle(color: scheme.error) : null,
                ),
              ),
            ),
          const SizedBox(height: 20),
          Text('Common password formats', style: text.titleMedium),
          const SizedBox(height: 8),
          for (final PdfPasswordHint h in PdfUnlocker.hints)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(h.title, style: text.titleSmall),
                    const SizedBox(height: 4),
                    Text(h.format),
                    const SizedBox(height: 4),
                    Text('Example: ${h.example}', style: text.bodySmall),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 12),
          Text('Make the e-Aadhaar password', style: text.titleSmall),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                flex: 3,
                child: TextField(
                  key: const Key('unlock-aadhaar-name'),
                  controller: _name,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(labelText: 'Name as on Aadhaar', border: OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: TextField(
                  key: const Key('unlock-aadhaar-year'),
                  controller: _year,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  decoration: const InputDecoration(
                    labelText: 'Birth year',
                    counterText: '',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            key: const Key('unlock-aadhaar-use'),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: aadhaar == null
                ? null
                : () {
                    _pw.text = aadhaar;
                    setState(() => _wrong = false);
                  },
            child: Text(aadhaar == null ? 'Type name and year' : 'Use $aadhaar'),
          ),
          const SizedBox(height: 12),
          const Text('Everything happens on this phone. The file and its password are never uploaded '
              'or stored, and the original keeps its password.'),
        ],
      ),
      bottomNavigationBar: ResultBar(onShare: _share, onSave: _save, onUndo: _undo),
    );
  }
}
