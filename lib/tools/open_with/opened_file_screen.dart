import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../app/widgets/result_bar.dart';
import '../../app/widgets/save_anywhere_sheet.dart';
import '../../engines/platform/smart_suggestions.dart';
import '../../engines/share/open_with.dart';
import '../../engines/share/save_anywhere.dart';
import '../../engines/share/share_engine.dart';
import '../smart_suggestions/suggestions_bar.dart';
import '../video_player/video_player_screen.dart';

/// Feature 065 — where a file opened from another app lands.
///
/// Shows the file, the tools that apply to it (feature 106), and on Android
/// the one-time "Make this your PDF and image app?" card.
class OpenedFileScreen extends StatefulWidget {
  const OpenedFileScreen({
    super.key,
    required this.paths,
    this.prompt,
    this.inbox,
    this.share,
    this.saver,
    this.isAndroid,
  });

  final List<String> paths;
  final DefaultAppPrompt? prompt;
  final OpenWithInbox? inbox;
  final ShareEngine? share;
  final SaveAnywhere? saver;

  /// Injected in tests; otherwise the platform the app runs on.
  final bool? isAndroid;

  @override
  State<OpenedFileScreen> createState() => _OpenedFileScreenState();
}

class _OpenedFileScreenState extends State<OpenedFileScreen> {
  late final DefaultAppPrompt _prompt = widget.prompt ?? DefaultAppPrompt.instance;
  String? _savedTo;

  bool get _android => widget.isAndroid ?? defaultTargetPlatform == TargetPlatform.android;

  String get _path => widget.paths.first;

  String _name(String p) => p.split(RegExp(r'[/\\]')).last;

  void _toast(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(m)));
    }
  }

  Future<void> _share() async {
    await (widget.share ?? ShareEngine.instance).shareFiles(widget.paths);
  }

  Future<void> _save() async {
    final SaveAnywhere? saver = widget.saver ?? SaveAnywhere.maybeInstance;
    if (saver == null) {
      _toast('Saving is not set up on this phone yet');
      return;
    }
    final Uint8List bytes;
    try {
      bytes = await File(_path).readAsBytes();
    } catch (_) {
      _toast('Could not read ${_name(_path)}');
      return;
    }
    if (!mounted) {
      return;
    }
    final String? to = await showSaveAnywhereSheet(
      context,
      saver: saver,
      toolId: 'open-with',
      fileName: _name(_path),
      bytes: bytes,
    );
    if (to != null) {
      setState(() => _savedTo = to);
      _toast('Saved to ${SaveAnywhere.shortPath(to)}');
    }
  }

  Future<void> _undo() async {
    final String? s = _savedTo;
    if (s == null) {
      _toast('Nothing to undo');
      return;
    }
    try {
      await File(s).delete();
    } catch (_) {
      // Already gone.
    }
    setState(() => _savedTo = null);
    _toast('Saved copy removed');
  }

  Future<void> _openSettings() async {
    // Answered either way: the card never comes back.
    await _prompt.dismiss();
    final bool ok = await (widget.inbox ?? OpenWithInbox.instance).openDefaultAppSettings();
    if (!ok) {
      _toast('Open Settings > Apps > Default apps to choose this app');
    }
  }

  Widget _promptCard(TextTheme text) {
    return Card(
      key: const Key('default-app-card'),
      color: AppColors.accentTint,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Make this your PDF and image app?', style: text.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Then tapping a PDF or photo anywhere on the phone opens it here, with the tools for it.',
              style: text.bodyMedium,
            ),
            Row(
              children: <Widget>[
                TextButton(
                  key: const Key('default-app-settings'),
                  onPressed: _openSettings,
                  child: const Text('Open settings'),
                ),
                const Spacer(),
                TextButton(
                  key: const Key('default-app-dismiss'),
                  onPressed: _prompt.dismiss,
                  child: const Text('Not now'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final SuggestKind kind = SmartSuggestions.kindForName(_path);
    final int more = widget.paths.length - 1;
    return Scaffold(
      appBar: AppBar(title: const Text('Opened file')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          ListTile(
            key: const Key('opened-file'),
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              kind == SuggestKind.pdf
                  ? Icons.picture_as_pdf_outlined
                  : (kind == SuggestKind.image || kind == SuggestKind.heic)
                      ? Icons.image_outlined
                      : Icons.insert_drive_file_outlined,
              semanticLabel: SmartSuggestions.label(kind),
            ),
            title: Text(_name(_path), maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: Text(more > 0 ? 'and $more more · kept on this phone' : 'Kept on this phone'),
          ),
          if (kind == SuggestKind.video)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: FilledButton.icon(
                key: const Key('play-opened-video'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (BuildContext context) => VideoPlayerScreen(path: _path)),
                ),
                icon: const Icon(Icons.play_arrow),
                label: const Text('Play'),
              ),
            ),
          const SizedBox(height: 8),
          SuggestionsBar(path: _path, limit: 8),
          ListenableBuilder(
            listenable: _prompt,
            builder: (BuildContext context, Widget? _) =>
                _prompt.shouldShow(isAndroid: _android, openedOk: true) ? _promptCard(text) : const SizedBox.shrink(),
          ),
        ],
      ),
      bottomNavigationBar: ResultBar(onShare: _share, onSave: _save, onUndo: _undo),
    );
  }
}
