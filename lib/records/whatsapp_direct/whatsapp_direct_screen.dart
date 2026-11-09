import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/widgets/result_bar.dart';
import '../../engines/records/whatsapp_direct.dart';
import '../../engines/share/share_engine.dart';

/// Feature 102 — message a number without saving it.
class WhatsAppDirectScreen extends StatefulWidget {
  const WhatsAppDirectScreen({super.key, this.direct, this.share, this.copy});

  final WhatsAppDirect? direct;

  /// Shares the chat link; defaults to the share sheet.
  final Future<void> Function(String link)? share;

  /// Copies the link; defaults to the clipboard.
  final Future<void> Function(String link)? copy;

  @override
  State<WhatsAppDirectScreen> createState() => _WhatsAppDirectScreenState();
}

class _WhatsAppDirectScreenState extends State<WhatsAppDirectScreen> {
  WhatsAppDirect get _w => widget.direct ?? WhatsAppDirect.instance;
  final TextEditingController _number = TextEditingController();
  final TextEditingController _message = TextEditingController();

  @override
  void dispose() {
    _number.dispose();
    _message.dispose();
    super.dispose();
  }

  void _snack(String s) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
    }
  }

  String? get _link => _w.link(_number.text, message: _message.text)?.toString();

  Future<void> _open() async {
    if (_w.normalise(_number.text) == null) {
      _snack('Type the number with its country code, like +91 98765 43210');
      return;
    }
    bool ok = false;
    try {
      ok = await _w.openChat(_number.text, message: _message.text);
    } catch (_) {
      ok = false;
    }
    if (!ok) {
      _snack('Could not open WhatsApp');
    }
  }

  Future<void> _share() async {
    final String? l = _link;
    if (l == null) {
      _snack('Type a number first');
      return;
    }
    _w.remember(_number.text);
    final Future<void> Function(String)? s = widget.share;
    if (s != null) {
      await s(l);
      return;
    }
    await ShareEngine.instance.shareText(l);
  }

  Future<void> _copy() async {
    final String? l = _link;
    if (l == null) {
      _snack('Type a number first');
      return;
    }
    _w.remember(_number.text);
    await (widget.copy ?? (String t) => Clipboard.setData(ClipboardData(text: t)))(l);
    _snack('Link copied');
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('WhatsApp direct')),
      bottomNavigationBar: ResultBar(
        onShare: () => unawaited(_share()),
        onSave: () => unawaited(_copy()),
        onUndo: () => _snack(_w.undo() ? 'Undone' : 'Nothing to undo'),
        saveLabel: 'Copy link',
      ),
      body: ListenableBuilder(
        listenable: _w,
        builder: (BuildContext context, Widget? _) => ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            Text('Message a number without saving it to contacts.', style: text.bodyMedium),
            const SizedBox(height: 12),
            TextField(
              key: const Key('wa-number'),
              controller: _number,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Phone number', hintText: '+91 98765 43210'),
            ),
            TextField(
              key: const Key('wa-message'),
              controller: _message,
              decoration: const InputDecoration(labelText: 'Message (optional)'),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const Key('wa-open'),
              style: FilledButton.styleFrom(minimumSize: const Size(88, 48)),
              onPressed: () => unawaited(_open()),
              icon: const Icon(Icons.chat_outlined),
              label: const Text('Open chat'),
            ),
            const SizedBox(height: 16),
            if (_w.recent.isNotEmpty) Text('Recent', style: text.titleMedium),
            for (final String n in _w.recent)
              ListTile(
                key: Key('wa-recent-$n'),
                contentPadding: EdgeInsets.zero,
                minTileHeight: 56,
                leading: const Icon(Icons.history),
                title: Text(WhatsAppDirect.pretty(n)),
                onTap: () => _number.text = '+$n',
                trailing: IconButton(
                  tooltip: 'Forget this number',
                  onPressed: () => _w.forget(n),
                  icon: const Icon(Icons.close),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
