import 'dart:async';

import 'package:flutter/material.dart';

import '../../engines/download/clipboard_watch.dart';
import '../../engines/share/share_engine.dart';

/// Feature 126 — the opt-in switch, and the link on offer with Save, Share
/// and Undo. [onSave] opens the 123 screen with the link.
class ClipboardWatchScreen extends StatefulWidget {
  const ClipboardWatchScreen({super.key, this.watch, this.share, this.onSave});

  final ClipboardLinkWatch? watch;
  final ShareEngine? share;
  final void Function(BuildContext context, Uri url)? onSave;

  @override
  State<ClipboardWatchScreen> createState() => _ClipboardWatchScreenState();
}

class _ClipboardWatchScreenState extends State<ClipboardWatchScreen> {
  ClipboardLinkWatch get _watch => widget.watch ?? ClipboardLinkWatch.instance;
  LinkOffer? _lastAction;
  String? _message;

  @override
  void initState() {
    super.initState();
    _watch.addListener(_changed);
  }

  @override
  void dispose() {
    _watch.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _checkNow() async {
    final LinkOffer? found = await _watch.check();
    if (!mounted) {
      return;
    }
    setState(() {
      _message = found == null && _watch.offer == null ? 'No supported link on the clipboard.' : null;
    });
  }

  void _save(LinkOffer offer) {
    _watch.accept();
    setState(() {
      _lastAction = offer;
      _message = 'Opened ${offer.site} link to save.';
    });
    widget.onSave?.call(context, offer.url);
  }

  void _dismiss(LinkOffer offer) {
    _watch.dismiss();
    setState(() {
      _lastAction = offer;
      _message = 'Dismissed.';
    });
  }

  void _undo() {
    final LinkOffer? o = _lastAction;
    if (o == null) {
      return;
    }
    _watch.restore(o);
    setState(() {
      _lastAction = null;
      _message = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final LinkOffer? offer = _watch.offer;
    return Scaffold(
      appBar: AppBar(title: const Text('Clipboard link watch')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          SwitchListTile(
            key: const Key('clipboard-watch-switch'),
            title: const Text('Offer to save copied links'),
            subtitle: const Text(
              'When you come back to the app, it checks for a copied Instagram, YouTube, '
              'Facebook, X, Pinterest or Threads link. Anything else on the clipboard is '
              'ignored and never kept or sent.',
            ),
            value: _watch.enabled,
            onChanged: (bool v) => unawaited(_watch.setEnabled(v)),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const Key('clipboard-watch-check'),
            style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
            onPressed: _watch.enabled ? _checkNow : null,
            icon: const Icon(Icons.content_paste_search),
            label: const Text('Check now'),
          ),
          const SizedBox(height: 16),
          if (offer != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('Copied ${offer.site} link', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(offer.url.toString(), key: const Key('clipboard-watch-offer')),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: <Widget>[
                        FilledButton.icon(
                          key: const Key('clipboard-watch-save'),
                          style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
                          onPressed: () => _save(offer),
                          icon: const Icon(Icons.download_outlined),
                          label: const Text('Save'),
                        ),
                        OutlinedButton.icon(
                          key: const Key('clipboard-watch-share'),
                          style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
                          onPressed: () =>
                              unawaited((widget.share ?? ShareEngine.instance).shareText(offer.url.toString())),
                          icon: const Icon(Icons.share_outlined),
                          label: const Text('Share'),
                        ),
                        TextButton(
                          key: const Key('clipboard-watch-dismiss'),
                          style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                          onPressed: () => _dismiss(offer),
                          child: const Text('Not now'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: <Widget>[
                  Expanded(child: Text(_message!)),
                  if (_lastAction != null)
                    TextButton(
                      key: const Key('clipboard-watch-undo'),
                      style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                      onPressed: _undo,
                      child: const Text('Undo'),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Shows the bubble (a snack bar with a Save action) for a new offer.
void showLinkOfferBubble(ScaffoldMessengerState messenger, LinkOffer offer, VoidCallback onSave) {
  messenger.showSnackBar(SnackBar(
    behavior: SnackBarBehavior.floating,
    duration: const Duration(seconds: 8),
    content: Text('Copied ${offer.site} link. Save it?'),
    action: SnackBarAction(label: 'Save', onPressed: onSave),
  ));
}
