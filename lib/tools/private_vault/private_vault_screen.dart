import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../../app/theme.dart';
import '../../app/widgets/result_bar.dart';
import '../../engines/security/private_vault.dart';
import '../../engines/share/share_engine.dart';

/// One file picked to go into the vault.
class VaultPick {
  const VaultPick(this.name, this.bytes);
  final String name;
  final Uint8List bytes;
}

/// Picks files and writes plain copies out when the person asks (Share or
/// Save). Behind an interface for tests.
abstract class VaultFiles {
  Future<List<VaultPick>> pick({required bool photos});

  /// A plain copy for the share sheet, in the temp folder.
  Future<String> writeTemp(String name, Uint8List bytes);

  /// A plain copy in Files › Vault exports. Returns the path.
  Future<String> save(String name, Uint8List bytes);

  Future<void> remove(String path);
}

class SystemVaultFiles implements VaultFiles {
  const SystemVaultFiles();

  @override
  Future<List<VaultPick>> pick({required bool photos}) async {
    final FilePickerResult? r = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: photos ? FileType.media : FileType.any,
    );
    final List<VaultPick> out = <VaultPick>[];
    for (final PlatformFile f in r?.files ?? const <PlatformFile>[]) {
      final String? p = f.path;
      if (p != null) {
        out.add(VaultPick(f.name, await File(p).readAsBytes()));
      }
    }
    return out;
  }

  Future<String> _write(Directory dir, String name, Uint8List bytes) async {
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
  Future<String> writeTemp(String name, Uint8List bytes) async {
    final Directory t = await getTemporaryDirectory();
    return _write(Directory('${t.path}/vault_share'), name, bytes);
  }

  @override
  Future<String> save(String name, Uint8List bytes) async {
    final Directory base = await getApplicationDocumentsDirectory();
    return _write(Directory('${base.path}/Vault exports'), name, bytes);
  }

  @override
  Future<void> remove(String path) async {
    final File f = File(path);
    if (f.existsSync()) {
      await f.delete();
    }
  }
}

String _size(int bytes) {
  if (bytes < 1024) {
    return '$bytes B';
  }
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

/// Feature 056 — Private vault.
class PrivateVaultScreen extends StatefulWidget {
  const PrivateVaultScreen({super.key, PrivateVault? vault, this.files = const SystemVaultFiles(), this.share})
      : _vault = vault;

  final PrivateVault? _vault;
  final VaultFiles files;
  final ShareEngine? share;

  @override
  State<PrivateVaultScreen> createState() => _PrivateVaultScreenState();
}

class _PrivateVaultScreenState extends State<PrivateVaultScreen> {
  PrivateVault get vault => widget._vault ?? PrivateVault.instance;

  final TextEditingController _pin = TextEditingController();
  final TextEditingController _confirm = TextEditingController();
  String? _pinError;
  bool _busy = false;
  VaultItem? _selected;
  final List<String> _tempPaths = <String>[];

  @override
  void initState() {
    super.initState();
    if (!vault.isLoaded) {
      vault.load();
    }
  }

  @override
  void dispose() {
    _pin.dispose();
    _confirm.dispose();
    // Lock again on the way out and drop plain share copies.
    vault.close();
    for (final String p in _tempPaths) {
      widget.files.remove(p);
    }
    super.dispose();
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _setPin() async {
    if (_pin.text != _confirm.text) {
      setState(() => _pinError = 'The two PINs do not match.');
      return;
    }
    setState(() => _busy = true);
    try {
      await vault.setPin(_pin.text);
      _pin.clear();
      _confirm.clear();
      _pinError = null;
    } on VaultPinError catch (e) {
      _pinError = e.message;
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _open() async {
    setState(() => _busy = true);
    final VaultOpenFailure? f = await vault.open(_pin.text);
    if (!mounted) {
      return;
    }
    setState(() {
      _busy = false;
      _pin.clear();
      _pinError = switch (f) {
        null => null,
        VaultOpenFailure.notSetUp => 'Set a vault PIN first.',
        VaultOpenFailure.wrongPin => 'Wrong PIN.',
        VaultOpenFailure.lockedOut => 'Too many tries. Wait ${vault.lockoutSecondsLeft} s.',
      };
    });
  }

  Future<void> _add({required bool photos}) async {
    final List<VaultPick> picks = await widget.files.pick(photos: photos);
    if (picks.isEmpty || !mounted) {
      return;
    }
    setState(() => _busy = true);
    VaultItem? last;
    for (final VaultPick p in picks) {
      last = await vault.add(p.name, p.bytes);
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _busy = false;
      _selected = last;
    });
    _toast(
      picks.length == 1
          ? 'Locked ${picks.first.name} in the vault. Delete the original from your gallery to hide it.'
          : 'Locked ${picks.length} files in the vault. Delete the originals from your gallery to hide them.',
    );
  }

  Future<void> _remove(VaultItem item) async {
    await vault.remove(item);
    if (!mounted) {
      return;
    }
    setState(() {
      if (_selected?.id == item.id) {
        _selected = null;
      }
    });
    _toast('Removed ${item.name}. Undo puts it back.');
  }

  Future<void> _share() async {
    final VaultItem? item = _selected;
    if (item == null) {
      _toast('Pick a file in the vault first');
      return;
    }
    final String path = await widget.files.writeTemp(item.name, await vault.read(item));
    _tempPaths.add(path);
    await (widget.share ?? ShareEngine.instance).shareFiles(<String>[path]);
  }

  Future<void> _save() async {
    final VaultItem? item = _selected;
    if (item == null) {
      _toast('Pick a file in the vault first');
      return;
    }
    await widget.files.save(item.name, await vault.read(item));
    if (mounted) {
      _toast('Saved an unlocked copy in Files › Vault exports');
    }
  }

  Future<void> _undo() async {
    final String? msg = await vault.undo();
    if (!mounted) {
      return;
    }
    setState(() {
      if (_selected != null && !vault.items.any((VaultItem i) => i.id == _selected!.id)) {
        _selected = null;
      }
    });
    _toast(msg ?? 'Nothing to undo');
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (BuildContext _) => VaultSettingsScreen(vault: vault)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: vault,
      builder: (BuildContext context, Widget? _) {
        final bool open = vault.isOpen;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Private vault'),
            actions: <Widget>[
              if (open)
                IconButton(
                  key: const Key('vault-settings'),
                  tooltip: 'Vault settings',
                  onPressed: _openSettings,
                  icon: const Icon(Icons.tune),
                ),
              if (open)
                IconButton(
                  key: const Key('vault-lock'),
                  tooltip: 'Lock the vault',
                  onPressed: () {
                    setState(() => _selected = null);
                    vault.close();
                  },
                  icon: const Icon(Icons.lock_outline),
                ),
            ],
          ),
          body: !vault.isLoaded
              ? const Center(child: CircularProgressIndicator())
              : open
                  ? _contents(context)
                  : _pinPad(context),
          bottomNavigationBar:
              open ? ResultBar(onShare: _share, onSave: _save, onUndo: _undo, saveLabel: 'Save copy') : null,
        );
      },
    );
  }

  Widget _pinField(TextEditingController c, String label, Key key) {
    return TextField(
      key: key,
      controller: c,
      obscureText: true,
      keyboardType: TextInputType.number,
      inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly],
      maxLength: 6,
      decoration: InputDecoration(labelText: label, counterText: ''),
    );
  }

  Widget _pinPad(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final bool setUp = !vault.hasPin;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: <Widget>[
        const Icon(Icons.shield_outlined, size: 44, color: AppColors.accent),
        const SizedBox(height: 12),
        Text(
          setUp ? 'Set a vault PIN' : 'Enter your vault PIN',
          style: text.titleLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 6),
        Text(
          setUp
              ? 'Photos and files you add are encrypted on this phone, kept out of the gallery and out of backups.'
              : 'Files stay encrypted until you open the vault.',
          style: text.bodyMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        _pinField(_pin, setUp ? 'New PIN (4–6 digits)' : 'PIN', const Key('vault-pin')),
        if (setUp) ...<Widget>[
          const SizedBox(height: 12),
          _pinField(_confirm, 'Type it again', const Key('vault-pin-confirm')),
        ],
        if (_pinError != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Semantics(
              liveRegion: true,
              child: Text(_pinError!, style: text.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.error)),
            ),
          ),
        const SizedBox(height: 16),
        SizedBox(
          height: 48,
          child: FilledButton.icon(
            key: Key(setUp ? 'vault-set-pin' : 'vault-open'),
            onPressed: _busy ? null : (setUp ? _setPin : _open),
            icon: const Icon(Icons.lock_open_outlined),
            label: Text(setUp ? 'Set PIN and open' : 'Open vault'),
          ),
        ),
      ],
    );
  }

  Widget _contents(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final List<VaultItem> items = vault.items;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: SizedBox(
                height: 48,
                child: FilledButton.icon(
                  key: const Key('vault-add-photos'),
                  onPressed: _busy ? null : () => _add(photos: true),
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  label: const Text('Add photos'),
                ),
              ),
            ),
            const SizedBox(width: AppRadius.gridGap),
            Expanded(
              child: SizedBox(
                height: 48,
                child: OutlinedButton.icon(
                  key: const Key('vault-add-files'),
                  onPressed: _busy ? null : () => _add(photos: false),
                  icon: const Icon(Icons.note_add_outlined),
                  label: const Text('Add files'),
                ),
              ),
            ),
          ],
        ),
        if (_busy) const Padding(padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator()),
        if (vault.indexError != null)
          Card(
            child: Padding(padding: const EdgeInsets.all(16), child: Text(vault.indexError!, style: text.bodyMedium)),
          ),
        const SizedBox(height: 16),
        if (items.isEmpty)
          Padding(
            key: const Key('vault-empty'),
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Column(
              children: <Widget>[
                const Icon(Icons.inventory_2_outlined, size: 40, color: AppColors.accent),
                const SizedBox(height: 12),
                Text('The vault is empty', style: text.titleMedium),
                const SizedBox(height: 4),
                Text(
                  'Add photos or files. They are encrypted on this phone and never uploaded.',
                  style: text.bodyMedium,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        for (final VaultItem i in items)
          Card(
            child: ListTile(
              key: ValueKey<String>('vault-item-${i.name}'),
              minVerticalPadding: 12,
              selected: _selected?.id == i.id,
              onTap: () => setState(() => _selected = i),
              leading: Icon(i.kind == VaultItemKind.photo ? Icons.image_outlined : Icons.insert_drive_file_outlined),
              title: Text(i.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(_size(i.size)),
              trailing: IconButton(
                key: ValueKey<String>('vault-remove-${i.name}'),
                tooltip: 'Remove ${i.name} from the vault',
                onPressed: () => _remove(i),
                icon: const Icon(Icons.delete_outline),
              ),
            ),
          ),
      ],
    );
  }
}

/// Decoy PIN and backups. Opened only from the open vault; in the decoy
/// vault it shows just the backup switch, so nothing hints at the real one.
class VaultSettingsScreen extends StatefulWidget {
  const VaultSettingsScreen({super.key, required this.vault});

  final PrivateVault vault;

  @override
  State<VaultSettingsScreen> createState() => _VaultSettingsScreenState();
}

class _VaultSettingsScreenState extends State<VaultSettingsScreen> {
  final TextEditingController _decoy = TextEditingController();
  String? _msg;

  @override
  void dispose() {
    _decoy.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() f, String ok) async {
    try {
      await f();
      _decoy.clear();
      setState(() => _msg = ok);
    } on VaultPinError catch (e) {
      setState(() => _msg = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final PrivateVault vault = widget.vault;
    final TextTheme text = Theme.of(context).textTheme;
    final bool real = vault.openSpace == VaultSpace.real;
    return Scaffold(
      appBar: AppBar(title: const Text('Vault settings')),
      body: ListenableBuilder(
        listenable: vault,
        builder: (BuildContext context, Widget? _) => ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            SwitchListTile(
              key: const Key('vault-backups'),
              value: vault.includeInBackups,
              onChanged: real ? (bool on) => _run(() => vault.setIncludeInBackups(on), on ? 'Vault included in backups' : 'Vault kept out of backups') : null,
              title: const Text('Include in phone backups'),
              subtitle: const Text('Off by default. Backed-up files stay encrypted and open only with this phone\'s key.'),
            ),
            if (real) ...<Widget>[
              const Divider(height: 32),
              Text('Decoy PIN', style: text.titleMedium),
              const SizedBox(height: 4),
              Text(
                vault.hasDecoy
                    ? 'A decoy PIN is set. It opens a separate, empty vault.'
                    : 'If someone makes you open the vault, this PIN opens a separate, empty one.',
                style: text.bodyMedium,
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('vault-decoy-pin'),
                controller: _decoy,
                obscureText: true,
                keyboardType: TextInputType.number,
                inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly],
                maxLength: 6,
                decoration: const InputDecoration(labelText: 'Decoy PIN (4–6 digits)', counterText: ''),
              ),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: FilledButton(
                        key: const Key('vault-save-decoy'),
                        onPressed: () => _run(() => vault.setDecoyPin(_decoy.text), 'Decoy PIN set'),
                        child: const Text('Set decoy PIN'),
                      ),
                    ),
                  ),
                  if (vault.hasDecoy) ...<Widget>[
                    const SizedBox(width: AppRadius.gridGap),
                    Expanded(
                      child: SizedBox(
                        height: 48,
                        child: OutlinedButton(
                          key: const Key('vault-clear-decoy'),
                          onPressed: () => _run(vault.clearDecoyPin, 'Decoy PIN removed'),
                          child: const Text('Remove'),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
            if (_msg != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Semantics(liveRegion: true, child: Text(_msg!, style: text.bodyMedium)),
              ),
          ],
        ),
      ),
    );
  }
}
