import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../app/widgets/result_bar.dart';
import '../../engines/qr/qr_actions.dart';
import '../../engines/qr/qr_payload.dart';

/// The safe preview of a scanned code, with one primary action for its kind
/// and the Share / Save / Undo bar every tool result ends with.
class QrResultScreen extends StatefulWidget {
  const QrResultScreen({
    super.key,
    required this.payload,
    required this.actions,
  });

  final QrPayload payload;
  final QrActions actions;

  @override
  State<QrResultScreen> createState() => _QrResultScreenState();
}

class _QrResultScreenState extends State<QrResultScreen> {
  String? _savedPath;
  bool _busy = false;
  bool _showPassword = false;

  QrPayload get payload => widget.payload;
  QrActions get actions => widget.actions;

  void _toast(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _run(Future<void> Function() job) async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      await job();
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  // ---- bar actions -------------------------------------------------------

  Future<void> _share() => _run(() => actions.shareText(payload.raw));

  Future<void> _save() => _run(() async {
        final String path = await actions.saveText(_fileName(), payload.raw);
        if (!mounted) {
          return;
        }
        setState(() => _savedPath = path);
        _toast('Saved to Files › scans');
      });

  Future<void> _undo() => _run(() async {
        final String? saved = _savedPath;
        if (saved != null) {
          await actions.deleteSaved(saved);
          if (!mounted) {
            return;
          }
          setState(() => _savedPath = null);
          _toast('Removed the saved copy');
          return;
        }
        if (mounted) {
          Navigator.of(context).maybePop();
        }
      });

  String _fileName() {
    final DateTime n = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return 'qr-${n.year}${two(n.month)}${two(n.day)}-${two(n.hour)}${two(n.minute)}${two(n.second)}.txt';
  }

  // ---- primary actions ---------------------------------------------------

  Future<void> _openUri(Uri uri, String failure) => _run(() async {
        final bool ok = await actions.openUri(uri);
        if (!ok) {
          _toast(failure);
        }
      });

  Future<void> _joinWifi(WifiPayload wifi) => _run(() async {
        final bool ok = await actions.joinWifi(wifi);
        if (ok) {
          _toast('Joined ${wifi.ssid}');
          return;
        }
        if (wifi.password.isNotEmpty) {
          await actions.copyText(wifi.password);
          _toast('Could not join automatically. Password copied, paste it in Wi-Fi settings.');
        } else {
          _toast('Could not join automatically. Pick ${wifi.ssid} in Wi-Fi settings.');
        }
      });

  Future<void> _saveContact(VCardPayload card) => _run(() async {
        final bool ok = await actions.saveContact(card);
        _toast(ok ? 'Saved ${card.headline} to contacts' : 'Contacts permission was not given');
      });

  Future<void> _addEvent(EventPayload event) => _run(() async {
        final bool ok = await actions.addEvent(event);
        if (!ok) {
          _toast('No calendar app could take this event');
        }
      });

  Future<void> _copy(String text, String message) => _run(() async {
        await actions.copyText(text);
        _toast(message);
      });

  // ---- build -------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Scan result')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _KindChip(label: payload.kindLabel, icon: _iconFor(payload)),
                  const SizedBox(height: 12),
                  Text(
                    payload.headline,
                    style: text.titleLarge,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 12),
                  ..._details(context),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          ..._primaryButtons(),
          const SizedBox(height: 12),
          Text(
            'Nothing you scan leaves this phone.',
            style: text.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
      bottomNavigationBar: ResultBar(
        onShare: _share,
        onSave: _save,
        onUndo: _undo,
        saveLabel: _savedPath == null ? 'Save' : 'Saved',
      ),
    );
  }

  static IconData _iconFor(QrPayload p) {
    return switch (p) {
      UrlPayload() => Icons.link,
      WifiPayload() => Icons.wifi,
      UpiPayload() => Icons.currency_rupee,
      VCardPayload() => Icons.person_outline,
      EventPayload() => Icons.event_outlined,
      TextPayload() => Icons.notes,
    };
  }

  List<Widget> _details(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final QrPayload p = payload;
    switch (p) {
      case UrlPayload():
        return <Widget>[
          _RawBox(text: p.uri.toString(), semanticsLabel: 'Full address'),
          const SizedBox(height: 8),
          if (p.isWeb)
            _Note(
              icon: p.isSecure ? Icons.lock_outline : Icons.lock_open,
              text: p.isSecure
                  ? 'Secure link. Check the address above before opening.'
                  : 'Not a secure (https) link. Open only if you trust it.',
              warn: !p.isSecure,
            ),
          if (p.looksSuspicious)
            const _Note(
              icon: Icons.warning_amber_outlined,
              text: 'This address is unusual (a bare IP or look-alike name). Be careful.',
              warn: true,
            ),
        ];
      case WifiPayload():
        return <Widget>[
          _Row(label: 'Security', value: p.securityLabel),
          if (p.hidden) const _Row(label: 'Network', value: 'Hidden'),
          if (p.password.isNotEmpty)
            Row(
              children: <Widget>[
                Expanded(
                  child: _Row(
                    label: 'Password',
                    value: _showPassword ? p.password : '•' * p.password.length.clamp(4, 16).toInt(),
                  ),
                ),
                IconButton(
                  tooltip: _showPassword ? 'Hide password' : 'Show password',
                  onPressed: () => setState(() => _showPassword = !_showPassword),
                  icon: Icon(_showPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                ),
              ],
            ),
        ];
      case UpiPayload():
        return <Widget>[
          _Row(label: 'UPI ID', value: p.payeeAddress),
          if (p.amountLabel.isNotEmpty) _Row(label: 'Amount', value: p.amountLabel),
          if (p.note != null) _Row(label: 'Note', value: p.note!),
          const SizedBox(height: 4),
          const _Note(
            icon: Icons.info_outline,
            text: 'Your UPI app will ask you to confirm before anything is paid.',
          ),
        ];
      case VCardPayload():
        return <Widget>[
          if (p.organisation != null) _Row(label: 'Organisation', value: p.organisation!),
          for (final String phone in p.phones) _Row(label: 'Phone', value: phone),
          for (final String email in p.emails) _Row(label: 'Email', value: email),
          for (final String url in p.urls) _Row(label: 'Website', value: url),
        ];
      case EventPayload():
        return <Widget>[
          if (p.start != null) _Row(label: 'Starts', value: formatDateTime(p.start!)),
          if (p.end != null) _Row(label: 'Ends', value: formatDateTime(p.end!)),
          if (p.location != null) _Row(label: 'Where', value: p.location!),
          if (p.description != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(p.description!, style: text.bodyMedium),
            ),
        ];
      case TextPayload():
        return <Widget>[_RawBox(text: p.text, semanticsLabel: 'Scanned text')];
    }
  }

  List<Widget> _primaryButtons() {
    final QrPayload p = payload;
    final bool enabled = !_busy;
    Widget primary(String label, IconData icon, Future<void> Function() run) {
      return FilledButton.icon(
        key: const Key('primary-action'),
        onPressed: enabled ? () => run() : null,
        icon: Icon(icon),
        label: Text(label),
      );
    }

    Widget secondary(String label, IconData icon, Future<void> Function() run) {
      return OutlinedButton.icon(
        onPressed: enabled ? () => run() : null,
        icon: Icon(icon),
        label: Text(label),
      );
    }

    switch (p) {
      case UrlPayload():
        final String label = switch (p.uri.scheme) {
          'tel' => 'Call',
          'mailto' => 'Write email',
          'sms' || 'smsto' => 'Send message',
          'geo' => 'Open in maps',
          _ => 'Open ${p.host}',
        };
        return <Widget>[
          primary(label, Icons.open_in_new, () => _openUri(p.uri, 'No app can open this link')),
          const SizedBox(height: AppRadius.gridGap),
          secondary('Copy address', Icons.copy_outlined, () => _copy(p.uri.toString(), 'Address copied')),
        ];
      case WifiPayload():
        return <Widget>[
          primary('Join ${p.ssid}', Icons.wifi, () => _joinWifi(p)),
          if (p.password.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppRadius.gridGap),
            secondary('Copy password', Icons.copy_outlined, () => _copy(p.password, 'Password copied')),
          ],
        ];
      case UpiPayload():
        return <Widget>[
          primary('Pay with UPI app', Icons.currency_rupee, () => _openUri(p.uri, 'No UPI app found on this phone')),
          const SizedBox(height: AppRadius.gridGap),
          secondary('Copy UPI ID', Icons.copy_outlined, () => _copy(p.payeeAddress, 'UPI ID copied')),
        ];
      case VCardPayload():
        return <Widget>[
          primary('Save to contacts', Icons.person_add_alt_outlined, () => _saveContact(p)),
          if (p.phones.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppRadius.gridGap),
            secondary('Call ${p.phones.first}', Icons.call_outlined,
                () => _openUri(Uri(scheme: 'tel', path: p.phones.first), 'No phone app found')),
          ],
        ];
      case EventPayload():
        return <Widget>[
          primary('Add to calendar', Icons.event_available_outlined, () => _addEvent(p)),
        ];
      case TextPayload():
        return <Widget>[
          primary('Copy text', Icons.copy_outlined, () => _copy(p.text, 'Text copied')),
        ];
    }
  }
}

/// DD/MM/YYYY HH:mm, the app's default convention.
String formatDateTime(DateTime d) {
  String two(int v) => v.toString().padLeft(2, '0');
  final bool midnight = d.hour == 0 && d.minute == 0 && d.second == 0;
  final String date = '${two(d.day)}/${two(d.month)}/${d.year}';
  return midnight ? date : '$date ${two(d.hour)}:${two(d.minute)}';
}

class _KindChip extends StatelessWidget {
  const _KindChip({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icon, size: 16, color: AppColors.accentDark),
      label: Text(label),
      backgroundColor: AppColors.accentTint,
      side: BorderSide.none,
      visualDensity: VisualDensity.compact,
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(width: 104, child: Text(label, style: text.bodyMedium)),
          Expanded(child: SelectableText(value, style: text.bodyLarge)),
        ],
      ),
    );
  }
}

class _RawBox extends StatelessWidget {
  const _RawBox({required this.text, required this.semanticsLabel});

  final String text;
  final String semanticsLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticsLabel,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.ground,
          borderRadius: BorderRadius.circular(AppRadius.input),
          border: Border.all(color: AppColors.line),
        ),
        child: SelectableText(
          text,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.text, this.warn = false});

  final IconData icon;
  final String text;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final Color color = warn ? const Color(0xFFB45309) : AppColors.muted;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}
