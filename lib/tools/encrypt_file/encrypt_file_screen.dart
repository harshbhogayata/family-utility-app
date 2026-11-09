import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../app/widgets/result_bar.dart';
import '../../engines/security/file_crypt.dart';
import '../../engines/share/share_engine.dart';

class CryptInput {
  const CryptInput(this.name, this.bytes);
  final String name;
  final Uint8List bytes;
}

/// Picks the file and keeps the result. Behind an interface for tests.
abstract class CryptFiles {
  Future<CryptInput?> pick();
  Future<String> write(String folder, String name, Uint8List bytes);
  Future<void> remove(String path);
}

class SystemCryptFiles implements CryptFiles {
  const SystemCryptFiles();

  @override
  Future<CryptInput?> pick() async {
    final FilePickerResult? r = await FilePicker.platform.pickFiles();
    final List<PlatformFile> files = r?.files ?? const <PlatformFile>[];
    final String? p = files.isEmpty ? null : files.first.path;
    if (p == null) {
      return null;
    }
    return CryptInput(files.first.name, await File(p).readAsBytes());
  }

  @override
  Future<String> write(String folder, String name, Uint8List bytes) async {
    final Directory base = await getApplicationDocumentsDirectory();
    final Directory dir = Directory('${base.path}/$folder');
    await dir.create(recursive: true);
    final int dot = name.lastIndexOf('.');
    final String stem = dot > 0 ? name.substring(0, dot) : name;
    final String ext = dot > 0 ? name.substring(dot) : '';
    String path = '${dir.path}/$name';
    int i = 2;
    while (File(path).existsSync()) {
      path = '${dir.path}/$stem ($i)$ext';
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

/// One lock or unlock, sendable to an isolate.
class CryptJob {
  const CryptJob(this.bytes, this.name, this.password, {required this.lock});
  final Uint8List bytes;
  final String name;
  final String password;
  final bool lock;
}

Future<DecryptedFile> _runJob(CryptJob j) async {
  if (j.lock) {
    return DecryptedFile(FileCrypt.lockedName(j.name), await FileCrypt.encrypt(j.bytes, j.name, j.password));
  }
  return FileCrypt.decrypt(j.bytes, j.password);
}

typedef CryptRunner = Future<DecryptedFile> Function(CryptJob job);

Future<DecryptedFile> cryptInIsolate(CryptJob job) => compute(_runJob, job);

/// Feature 058 — Encrypt any file.
class EncryptFileScreen extends StatefulWidget {
  const EncryptFileScreen({super.key, this.files = const SystemCryptFiles(), this.runner = cryptInIsolate, this.share});

  final CryptFiles files;
  final CryptRunner runner;
  final ShareEngine? share;

  @override
  State<EncryptFileScreen> createState() => _EncryptFileScreenState();
}

class _EncryptFileScreenState extends State<EncryptFileScreen> {
  final TextEditingController _pw = TextEditingController();
  final TextEditingController _again = TextEditingController();
  CryptInput? _input;
  bool _show = false;
  bool _working = false;
  bool _error = false;
  String? _saved;
  String? _status;

  bool get _locked => _input != null && FileCrypt.isEncrypted(_input!.bytes);

  @override
  void initState() {
    super.initState();
    _pw.addListener(_changed);
    _again.addListener(_changed);
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    _pw.dispose();
    _again.dispose();
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
    final CryptInput? p = await widget.files.pick();
    if (!mounted || p == null) {
      return;
    }
    _pw.clear();
    _again.clear();
    setState(() {
      _input = p;
      _saved = null;
      _error = false;
      _status = FileCrypt.isEncrypted(p.bytes)
          ? 'This file is locked. Type its password to open it.'
          : 'Choose a password. Without it the file cannot be opened again, not even by this app.';
    });
  }

  String? get _problem {
    if (_input == null) {
      return 'Choose a file first';
    }
    if (_locked) {
      return _pw.text.isEmpty ? 'Type its password' : null;
    }
    return FileCrypt.passwordProblem(_pw.text, _again.text);
  }

  Future<void> _run() async {
    final CryptInput? input = _input;
    if (input == null || _problem != null || _working) {
      return;
    }
    final bool lock = !_locked;
    setState(() => _working = true);
    try {
      final DecryptedFile out = await widget.runner(CryptJob(input.bytes, input.name, _pw.text, lock: lock));
      final String path = await widget.files.write(lock ? 'locked' : 'unlocked', out.name, out.bytes);
      _pw.clear();
      _again.clear();
      setState(() {
        _saved = path;
        _error = false;
        _status = lock
            ? 'Locked as ${out.name} with AES-256. Open it in this app on any phone with the same password.'
            : 'Opened ${out.name}. Anyone with this copy can read it, so share it with care.';
      });
    } on FileCryptError catch (e) {
      setState(() {
        _error = true;
        _status = e.message;
      });
    } finally {
      if (mounted) {
        setState(() => _working = false);
      }
    }
  }

  Future<void> _share() async {
    final String? p = _saved;
    if (p == null) {
      _toast('Lock or open a file first');
      return;
    }
    await (widget.share ?? ShareEngine.instance).shareFiles(<String>[p]);
  }

  void _save() => _toast(_saved == null ? 'Nothing to save yet' : 'Saved in Files › ${_locked ? 'unlocked' : 'locked'}');

  Future<void> _undo() async {
    final String? p = _saved;
    if (p != null) {
      await widget.files.remove(p);
      setState(() {
        _saved = null;
        _status = 'Removed the new copy. The original is unchanged.';
      });
      return;
    }
    if (_input != null) {
      setState(() {
        _input = null;
        _status = null;
        _error = false;
      });
      return;
    }
    if (mounted) {
      await Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final String? problem = _problem;
    final bool locked = _locked;
    return Scaffold(
      appBar: AppBar(title: const Text('Encrypt any file')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          OutlinedButton.icon(
            key: const Key('crypt-pick'),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: _working ? null : _pick,
            icon: const Icon(Icons.insert_drive_file_outlined),
            label: Text(_input == null ? 'Choose any file' : _input!.name),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('crypt-password'),
            controller: _pw,
            obscureText: !_show,
            enableSuggestions: false,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: locked ? 'Password of the file' : 'Password',
              helperText: locked ? null : 'At least ${FileCrypt.minPassword} characters. It cannot be recovered.',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                key: const Key('crypt-show'),
                tooltip: _show ? 'Hide password' : 'Show password',
                onPressed: () => setState(() => _show = !_show),
                icon: Icon(_show ? Icons.visibility_off : Icons.visibility),
              ),
            ),
          ),
          if (!locked) ...<Widget>[
            const SizedBox(height: 12),
            TextField(
              key: const Key('crypt-again'),
              controller: _again,
              obscureText: !_show,
              enableSuggestions: false,
              autocorrect: false,
              decoration: const InputDecoration(labelText: 'Type it again', border: OutlineInputBorder()),
            ),
          ],
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const Key('crypt-run'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: problem == null && !_working ? _run : null,
            icon: Icon(locked ? Icons.lock_open_outlined : Icons.lock_outline),
            label: Text(_working
                ? (locked ? 'Opening…' : 'Locking…')
                : (problem ?? (locked ? 'Open the file' : 'Lock the file'))),
          ),
          if (_status != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  _status!,
                  key: const Key('crypt-status'),
                  style: _error ? TextStyle(color: scheme.error) : null,
                ),
              ),
            ),
          const SizedBox(height: 16),
          Text(
            'Works with any file: photos, PDFs, documents, archives. The locked copy is one '
            '.${FileCrypt.extension} file. Everything happens on this phone and nothing is uploaded; '
            'the password is never stored.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      bottomNavigationBar: ResultBar(onShare: _share, onSave: _save, onUndo: _undo),
    );
  }
}
