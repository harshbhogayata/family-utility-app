import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../app/theme.dart';
import '../../app/widgets/result_bar.dart';
import '../../engines/share/share_engine.dart';
import '../../engines/transfer/lan_transfer.dart';

/// Picks files to offer. Behind an interface so tests never open the system
/// picker.
abstract class FileChooser {
  Future<List<String>> pickPaths();
}

class SystemFileChooser implements FileChooser {
  const SystemFileChooser();

  @override
  Future<List<String>> pickPaths() async {
    final FilePickerResult? result = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (result == null) {
      return <String>[];
    }
    return result.files.map((PlatformFile f) => f.path).whereType<String>().toList();
  }
}

/// Feature 062 — Phone to laptop. Start the server, scan the QR on the
/// laptop, drag files either way. Ends in Share / Save / Undo for what came in.
class PhoneToLaptopScreen extends StatefulWidget {
  const PhoneToLaptopScreen({
    super.key,
    this.server,
    this.chooser = const SystemFileChooser(),
    this.addresses,
  });

  /// Injected in tests; otherwise one is made with the app's inbox folder.
  final LanTransferServer? server;
  final FileChooser chooser;

  /// Injected in tests; otherwise the phone's Wi-Fi addresses are looked up.
  final Future<List<String>> Function()? addresses;

  @override
  State<PhoneToLaptopScreen> createState() => _PhoneToLaptopScreenState();
}

class _PhoneToLaptopScreenState extends State<PhoneToLaptopScreen> {
  LanTransferServer? _server;
  bool _ownsServer = false;
  List<String> _urls = <String>[];
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final LanTransferServer? given = widget.server;
    if (given != null) {
      _server = given;
      given.addListener(_onServer);
    } else {
      _ownsServer = true;
      _makeServer();
    }
  }

  Future<void> _makeServer() async {
    try {
      final Directory base = await getApplicationDocumentsDirectory();
      final LanTransferServer s = LanTransferServer(inbox: Directory('${base.path}/received'));
      if (!mounted) {
        return;
      }
      setState(() => _server = s);
      s.addListener(_onServer);
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Could not prepare a folder for received files: $e');
      }
    }
  }

  void _onServer() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    final LanTransferServer? s = _server;
    s?.removeListener(_onServer);
    if (_ownsServer) {
      s?.dispose(); // stops the server: nothing keeps running after the screen closes
    }
    super.dispose();
  }

  Future<void> _toggle() async {
    final LanTransferServer? s = _server;
    if (s == null || _busy) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (s.isRunning) {
        await s.stop();
        _urls = <String>[];
      } else {
        await s.start();
        final List<String> hosts = await (widget.addresses?.call() ?? LanTransferServer.localAddresses());
        _urls = hosts.map(s.urlFor).toList();
        if (_urls.isEmpty) {
          _error = 'No Wi-Fi address found. Join the same Wi-Fi as the laptop and try again.';
        }
      }
    } catch (e) {
      _error = 'Could not start: $e';
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _addFiles() async {
    final LanTransferServer? s = _server;
    if (s == null) {
      return;
    }
    for (final String p in await widget.chooser.pickPaths()) {
      await s.offer(p);
    }
  }

  void _toast(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(m)));
    }
  }

  Future<void> _share() async {
    final List<ReceivedFile> got = _server?.received ?? const <ReceivedFile>[];
    if (got.isEmpty) {
      _toast('Nothing received yet');
      return;
    }
    await ShareEngine.instance.shareFiles(got.map((ReceivedFile r) => r.path).toList());
  }

  void _save() {
    final List<ReceivedFile> got = _server?.received ?? const <ReceivedFile>[];
    if (got.isEmpty) {
      _toast('Nothing received yet');
      return;
    }
    _server?.forgetReceived();
    _toast('Kept ${got.length} ${got.length == 1 ? 'file' : 'files'} in Files › received');
  }

  Future<void> _undo() async {
    final LanTransferServer? s = _server;
    if (s == null || s.received.isEmpty) {
      Navigator.of(context).maybePop();
      return;
    }
    final int n = s.received.length;
    await s.discardReceived();
    _toast('Removed $n received ${n == 1 ? 'file' : 'files'}');
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final LanTransferServer? s = _server;
    final bool running = s?.isRunning ?? false;
    return Scaffold(
      appBar: AppBar(title: const Text('Phone to laptop')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    running ? 'Scan this on the laptop' : 'Move files over home Wi-Fi',
                    style: text.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    running
                        ? 'Open the camera on the laptop browser, or type the address. The link works once, on this Wi-Fi only.'
                        : 'Both devices on the same Wi-Fi. No internet needed; nothing leaves your home network.',
                    style: text.bodyMedium,
                  ),
                  const SizedBox(height: 12),
                  if (running && _urls.isNotEmpty) ...<Widget>[
                    Center(
                      child: Semantics(
                        label: 'QR code for ${_urls.first}',
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(AppRadius.input),
                            border: Border.all(color: AppColors.line),
                          ),
                          child: QrImageView(
                            key: const Key('transfer-qr'),
                            data: _urls.first,
                            size: 220,
                            backgroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    for (final String u in _urls)
                      Center(
                        child: SelectableText(
                          u,
                          key: ValueKey<String>('transfer-url-$u'),
                          style: text.bodyMedium,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    const SizedBox(height: 12),
                  ],
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(_error!, style: text.bodyMedium?.copyWith(color: const Color(0xFFB45309))),
                    ),
                  FilledButton.icon(
                    key: const Key('transfer-toggle'),
                    onPressed: s == null || _busy ? null : _toggle,
                    icon: Icon(running ? Icons.stop_circle_outlined : Icons.wifi_tethering),
                    label: Text(running ? 'Stop' : 'Start'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: <Widget>[
              Expanded(child: Text('Offer to the laptop', style: text.titleMedium)),
              TextButton.icon(
                key: const Key('transfer-add'),
                onPressed: s == null ? null : _addFiles,
                icon: const Icon(Icons.add),
                label: const Text('Add files'),
              ),
            ],
          ),
          if (s == null || s.offered.isEmpty)
            Text('Files you add here show up on the laptop page with a Download link.', style: text.bodyMedium)
          else
            Card(
              child: Column(
                children: <Widget>[
                  for (final OfferedFile f in s.offered)
                    ListTile(
                      leading: const Icon(Icons.insert_drive_file_outlined),
                      title: Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(_fmt(f.size)),
                      trailing: IconButton(
                        tooltip: 'Remove ${f.name}',
                        onPressed: () => s.withdraw(f.path),
                        icon: const Icon(Icons.close),
                      ),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 16),
          Text('Received from the laptop', style: text.titleMedium),
          const SizedBox(height: 4),
          if (s == null || s.received.isEmpty)
            Text('Files dropped on the laptop page land here.', style: text.bodyMedium)
          else
            Card(
              child: Column(
                children: <Widget>[
                  for (final ReceivedFile r in s.received)
                    ListTile(
                      leading: const Icon(Icons.download_done_outlined, color: AppColors.accent),
                      title: Text(r.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(_fmt(r.size)),
                    ),
                ],
              ),
            ),
          if (s != null && s.downloads > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('${s.downloads} downloaded by the laptop', style: text.bodySmall),
            ),
        ],
      ),
      bottomNavigationBar: ResultBar(onShare: _share, onSave: _save, onUndo: _undo),
    );
  }

  static String _fmt(int n) {
    if (n > 1024 * 1024) {
      return '${(n / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (n > 1024) {
      return '${(n / 1024).round()} KB';
    }
    return '$n B';
  }
}
