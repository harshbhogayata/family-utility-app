import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../app/widgets/result_bar.dart';
import '../../engines/family/family_identity.dart';
import '../../engines/family/family_space.dart';
import '../../engines/share/share_engine.dart';
import '../../engines/transfer/nearby_share.dart';
import '../../platform/network/nearby_share_net.dart';

typedef NearbyServiceBuilder = Future<NearbyShareService> Function(FamilyIdentity identity);
typedef NearbyFilePick = Future<List<String>> Function();

Future<NearbyShareService> _defaultService(FamilyIdentity identity) async {
  final Directory base = await getApplicationDocumentsDirectory();
  final NearbyShareService s = NearbyShareService(
    identity: identity,
    inbox: NearbyInbox(Directory('${base.path}/received/nearby')),
  );
  await s.start();
  return s;
}

Future<List<String>> _pickFiles() async {
  final FilePickerResult? r = await FilePicker.platform.pickFiles(allowMultiple: true);
  return r?.files.map((PlatformFile f) => f.path).whereType<String>().toList() ?? <String>[];
}

/// Feature 061 — Nearby share: pick a family phone by name, send a file
/// straight across the Wi-Fi or hotspot; files sent here land in the list.
class NearbyShareScreen extends StatefulWidget {
  const NearbyShareScreen({super.key, this.space, this.serviceBuilder, this.pick});

  final FamilySpace? space;
  final NearbyServiceBuilder? serviceBuilder;
  final NearbyFilePick? pick;

  @override
  State<NearbyShareScreen> createState() => _NearbyShareScreenState();
}

class _NearbyShareScreenState extends State<NearbyShareScreen> {
  NearbyShareService? _service;
  String? _status;
  double? _progress;
  bool _ownsService = false;

  @override
  void initState() {
    super.initState();
    final FamilyIdentity? id = (widget.space ?? FamilySpace.instance).identity;
    if (id != null) {
      unawaited(_open(id));
    }
  }

  Future<void> _open(FamilyIdentity id) async {
    try {
      final NearbyShareService s = await (widget.serviceBuilder ?? _defaultService)(id);
      if (!mounted) {
        await s.stop();
        return;
      }
      _ownsService = widget.serviceBuilder == null;
      s.addListener(_changed);
      setState(() => _service = s);
    } catch (_) {
      if (mounted) {
        setState(() => _status = 'Could not start on this Wi-Fi');
      }
    }
  }

  void _changed() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    final NearbyShareService? s = _service;
    s?.removeListener(_changed);
    if (s != null && _ownsService) {
      unawaited(s.stop());
    }
    super.dispose();
  }

  Future<void> _send(NearbyDevice to) async {
    final NearbyShareService? s = _service;
    if (s == null) {
      return;
    }
    final List<String> paths = await (widget.pick ?? _pickFiles)();
    if (paths.isEmpty || !mounted) {
      return;
    }
    try {
      int resumed = 0;
      double speed = 0;
      for (int i = 0; i < paths.length; i++) {
        setState(() {
          _status = 'Sending ${i + 1} of ${paths.length} to ${to.name}…';
          _progress = 0;
        });
        final NearbySendResult r = await s.send(to, paths[i], onProgress: (int sent, int total) {
          if (mounted) {
            setState(() => _progress = total == 0 ? 1 : sent / total);
          }
        });
        resumed += r.attempts - 1;
        speed = r.megabytesPerSecond;
        if (!mounted) {
          return;
        }
      }
      setState(() {
        _progress = null;
        _status = 'Sent ${paths.length} to ${to.name} at ${speed.toStringAsFixed(1)} MB/s'
            '${resumed > 0 ? ' (resumed $resumed×)' : ''}';
      });
    } on NearbyShareException catch (e) {
      if (mounted) {
        setState(() {
          _progress = null;
          _status = e.message;
        });
      }
    }
  }

  void _toast(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _share() async {
    final List<NearbyReceived> got = _service?.received ?? const <NearbyReceived>[];
    if (got.isEmpty) {
      _toast('Nothing received yet');
      return;
    }
    await ShareEngine.instance.shareFiles(got.map((NearbyReceived r) => r.path).toList());
  }

  void _save() {
    final List<NearbyReceived> got = _service?.received ?? const <NearbyReceived>[];
    if (got.isEmpty) {
      _toast('Nothing received yet');
      return;
    }
    final int n = got.length;
    setState(got.clear);
    _toast('Kept $n ${n == 1 ? 'file' : 'files'} in Files › received');
  }

  Future<void> _undo() async {
    final List<NearbyReceived> got = _service?.received ?? <NearbyReceived>[];
    if (got.isEmpty) {
      await Navigator.of(context).maybePop();
      return;
    }
    final int n = got.length;
    for (final NearbyReceived r in got) {
      try {
        await File(r.path).delete();
      } catch (_) {}
    }
    if (!mounted) {
      return;
    }
    setState(got.clear);
    _toast('Removed $n received ${n == 1 ? 'file' : 'files'}');
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final bool inFamily = (widget.space ?? FamilySpace.instance).inFamily;
    final NearbyShareService? s = _service;
    return Scaffold(
      appBar: AppBar(title: const Text('Nearby share')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Text(
            'Phone to phone on the same Wi-Fi or a phone hotspot. No internet needed; '
            'a dropped link picks up where it stopped.',
            style: text.bodyMedium,
          ),
          const SizedBox(height: 16),
          if (!inFamily)
            Text('Start or join a family space in the Family tab to see your family\'s phones.',
                style: text.bodyMedium)
          else if (s == null)
            Text(_status ?? 'Starting…', style: text.bodyMedium)
          else ...<Widget>[
            Text('Family phones nearby', style: text.titleMedium),
            if (s.devices.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text('Looking… open Nearby share on the other phone too.', style: text.bodySmall),
              ),
            for (final NearbyDevice d in s.devices)
              ListTile(
                contentPadding: EdgeInsets.zero,
                minTileHeight: 48,
                leading: const Icon(Icons.smartphone),
                title: Text(d.name),
                subtitle: const Text('Tap to send a file'),
                onTap: () => unawaited(_send(d)),
              ),
            if (_progress != null)
              Semantics(
                label: 'Sending, ${((_progress ?? 0) * 100).round()} percent',
                excludeSemantics: true,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: LinearProgressIndicator(value: _progress),
                ),
              ),
            if (_status != null) Text(_status!, style: text.bodySmall),
            const SizedBox(height: 16),
            Text('Received', style: text.titleMedium),
            if (s.received.isEmpty) Text('Nothing yet', style: text.bodySmall),
            for (final NearbyReceived r in s.received)
              ListTile(
                contentPadding: EdgeInsets.zero,
                minTileHeight: 48,
                leading: const Icon(Icons.download_done),
                title: Text(r.path.split(Platform.pathSeparator).last),
                subtitle: Text('from ${r.from}'),
              ),
          ],
        ],
      ),
      bottomNavigationBar: ResultBar(onShare: () => unawaited(_share()), onSave: _save, onUndo: () => unawaited(_undo())),
    );
  }
}
