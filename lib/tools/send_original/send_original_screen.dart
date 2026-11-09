import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../app/theme.dart';
import '../../app/widgets/result_bar.dart';
import '../../engines/share/original_quality.dart';
import '../../engines/share/share_engine.dart';

/// Picks photos and videos. Behind an interface so tests never open the
/// system picker.
abstract class MediaChooser {
  Future<List<PickedMedia>> pick();
}

class SystemMediaChooser implements MediaChooser {
  const SystemMediaChooser();

  @override
  Future<List<PickedMedia>> pick() async {
    final FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.media,
      allowMultiple: true,
    );
    if (result == null) {
      return <PickedMedia>[];
    }
    final List<PickedMedia> out = <PickedMedia>[];
    for (final PlatformFile f in result.files) {
      final String? path = f.path;
      if (path != null) {
        out.add(PickedMedia(path: path, name: f.name, size: f.size));
      }
    }
    return out;
  }
}

/// Feature 128 — Send at original quality. Pick photos or videos, tap
/// Send original, choose WhatsApp: they go as documents, not recompressed.
class SendOriginalScreen extends StatefulWidget {
  const SendOriginalScreen({super.key, this.chooser = const SystemMediaChooser(), this.saver, this.share});

  final MediaChooser chooser;

  /// Injected in tests; otherwise copies go to the app's Files › originals.
  final OriginalSaver? saver;

  /// Injected in tests; otherwise the app-wide share engine.
  final ShareEngine? share;

  @override
  State<SendOriginalScreen> createState() => _SendOriginalScreenState();
}

class _SendOriginalScreenState extends State<SendOriginalScreen> {
  List<PickedMedia> _picked = <PickedMedia>[];
  final List<String> _saved = <String>[];
  String? _status;
  bool _busy = false;

  late final OriginalSaver _saver = widget.saver ??
      DirectoryOriginalSaver(() async {
        final Directory base = await getApplicationDocumentsDirectory();
        return Directory('${base.path}/originals');
      });

  ShareEngine get _engine => widget.share ?? ShareEngine.instance;

  void _toast(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(m)));
    }
  }

  Future<void> _pick() async {
    final List<PickedMedia> got = await widget.chooser.pick();
    if (!mounted || got.isEmpty) {
      return;
    }
    setState(() {
      _picked = got;
      _status = null;
    });
  }

  Future<void> _send() async {
    if (_picked.isEmpty) {
      _toast('Choose a photo or video first');
      return;
    }
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    final SendOriginalResult r = await SendOriginal(_engine).send(_picked);
    if (!mounted) {
      return;
    }
    setState(() {
      _busy = false;
      final String skipped = r.skipped.isEmpty
          ? ''
          : ' ${r.skipped.length} over 2 GB left out: WhatsApp refuses larger documents.';
      if (r.sent) {
        _status = 'Sent ${r.count} as ${r.count == 1 ? 'a document' : 'documents'}, full quality.$skipped';
      } else if (r.count == 0 && r.skipped.length == _picked.length) {
        _status = 'Nothing sent.$skipped';
      } else {
        _status = 'Not sent. Tap Send original to try again.$skipped';
      }
    });
  }

  Future<void> _save() async {
    if (_picked.isEmpty) {
      _toast('Nothing to save yet');
      return;
    }
    for (final PickedMedia m in _picked) {
      _saved.add(await _saver.save(m));
    }
    _toast('Saved ${_picked.length} ${_picked.length == 1 ? 'original' : 'originals'} in Files › originals');
  }

  Future<void> _undo() async {
    if (_saved.isNotEmpty) {
      final int n = _saved.length;
      for (final String p in _saved) {
        await _saver.remove(p);
      }
      _saved.clear();
      _toast('Removed $n saved ${n == 1 ? 'copy' : 'copies'}');
      return;
    }
    if (_picked.isNotEmpty) {
      setState(() {
        _picked = <PickedMedia>[];
        _status = null;
      });
      return;
    }
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Send at original quality')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text('No compression on WhatsApp', style: text.titleMedium),
                  const SizedBox(height: 6),
                  Text(
                    'Photos and videos go as documents, so the other person gets the exact file, '
                    'with its name. Nothing passes through this app\'s servers; there are none.',
                    style: text.bodyMedium,
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    key: const Key('original-pick'),
                    onPressed: _pick,
                    icon: const Icon(Icons.photo_library_outlined),
                    label: Text(_picked.isEmpty ? 'Choose photos or videos' : 'Choose again'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (_picked.isNotEmpty)
            Card(
              child: Column(
                children: <Widget>[
                  for (final PickedMedia m in _picked)
                    ListTile(
                      leading: Icon(
                        m.isVideo ? Icons.movie_outlined : Icons.image_outlined,
                        semanticLabel: m.isVideo ? 'Video' : 'Photo',
                      ),
                      title: Text(m.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                        m.size > OriginalQuality.whatsappDocumentLimit
                            ? '${OriginalQuality.formatSize(m.size)} · over WhatsApp\'s 2 GB limit'
                            : '${OriginalQuality.formatSize(m.size)} · goes as a document',
                      ),
                    ),
                ],
              ),
            ),
          if (_picked.isNotEmpty) const SizedBox(height: 16),
          FilledButton.icon(
            key: const Key('original-send'),
            onPressed: _picked.isEmpty || _busy ? null : _send,
            icon: const Icon(Icons.send_outlined),
            label: const Text('Send original'),
          ),
          if (_status != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  _status!,
                  key: const Key('original-status'),
                  style: text.bodyMedium?.copyWith(color: AppColors.ink),
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: ResultBar(onShare: _send, onSave: _save, onUndo: _undo),
    );
  }
}
