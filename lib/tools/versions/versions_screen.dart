import 'package:flutter/material.dart';

import '../../app/widgets/result_bar.dart';
import '../../engines/platform/action_history.dart';
import '../../engines/platform/versions.dart';
import '../../engines/share/share_engine.dart';

/// Feature 108 — Versions. Every file a tool made lists the originals it came
/// from; roll back any one of them, and undo the roll back.
class VersionsScreen extends StatefulWidget {
  const VersionsScreen({super.key, this.versions, this.share, this.initialFile});

  final Versions? versions;
  final ShareEngine? share;

  /// Opens straight on one file's version list.
  final String? initialFile;

  @override
  State<VersionsScreen> createState() => _VersionsScreenState();
}

class _VersionsScreenState extends State<VersionsScreen> {
  late final Versions _v = widget.versions ?? Versions.instance;
  late String? _file = widget.initialFile;

  /// Set after a roll back: what was put back, and the copy kept of what was there.
  FileVersion? _restored;
  FileVersion? _before;

  @override
  void initState() {
    super.initState();
    _v.addListener(_changed);
  }

  @override
  void dispose() {
    _v.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) {
      setState(() {});
    }
  }

  void _toast(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(m)));
    }
  }

  Future<void> _rollBack(FileVersion v) async {
    final FileVersion? before = await _v.rollBack(v.id);
    if (!mounted) {
      return;
    }
    setState(() {
      _restored = v;
      _before = before;
    });
    _toast('${baseName(v.filePath)} rolled back');
  }

  Future<void> _undo() async {
    final FileVersion? before = _before;
    if (before != null) {
      await _v.rollBack(before.id);
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _restored = null;
      _before = null;
    });
    _toast('Roll back undone');
  }

  Future<void> _share() async {
    final String? f = _file;
    if (f != null) {
      await (widget.share ?? ShareEngine.instance).shareFiles(<String>[f]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final String? file = _file;
    return PopScope(
      canPop: file == null || widget.initialFile != null,
      onPopInvokedWithResult: (bool didPop, Object? _) {
        if (!didPop) {
          setState(() {
            _file = null;
            _restored = null;
            _before = null;
          });
        }
      },
      child: Scaffold(
        appBar: AppBar(title: Text(file == null ? 'Versions' : baseName(file))),
        body: file == null ? _fileList(context) : _versionList(context, file),
        bottomNavigationBar: _restored == null
            ? null
            : ResultBar(
                onShare: _share,
                onSave: () => _toast('Saved in place: ${baseName(file ?? '')}'),
                onUndo: _undo,
              ),
      ),
    );
  }

  Widget _fileList(BuildContext context) {
    final List<String> files = _v.files;
    if (files.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No versions yet. When a tool makes a file, the original it came from is kept here until you empty the trash.',
            key: Key('versions-empty'),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ListView(
      children: <Widget>[
        for (final String f in files)
          ListTile(
            key: Key('versions-file-$f'),
            minTileHeight: 56,
            leading: const Icon(Icons.history_outlined),
            title: Text(baseName(f)),
            subtitle: Text('${_v.versionsOf(f).length} kept'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => setState(() => _file = f),
          ),
      ],
    );
  }

  Widget _versionList(BuildContext context, String file) {
    final TextTheme text = Theme.of(context).textTheme;
    final List<FileVersion> list = _v.versionsOf(file);
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: <Widget>[
        if (_restored != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Semantics(
              liveRegion: true,
              child: Text(
                'Rolled back to ${_restored!.sourceName} from ${ActionHistory.formatWhen(_restored!.at)}',
                key: const Key('versions-result'),
                style: text.titleSmall,
              ),
            ),
          ),
        for (final FileVersion v in list)
          ListTile(
            key: Key('version-${v.id}'),
            minTileHeight: 56,
            title: Text(v.label),
            subtitle: Text('${v.sourceName} · ${ActionHistory.formatWhen(v.at)} · ${Versions.formatSize(v.size)}'),
            trailing: Semantics(
              button: true,
              label: 'Roll back ${baseName(file)} to ${v.label}',
              excludeSemantics: true,
              child: TextButton(
                key: Key('rollback-${v.id}'),
                style: TextButton.styleFrom(minimumSize: const Size(64, 48)),
                onPressed: () => _rollBack(v),
                child: const Text('Roll back'),
              ),
            ),
          ),
      ],
    );
  }
}
