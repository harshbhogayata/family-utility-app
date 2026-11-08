import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../engines/security/app_lock.dart';
import 'lock_screen.dart';

/// Feature 055 — App lock settings: turn the lock on with a PIN, offer
/// biometrics, pick the timeout, and lock chosen tools on their own.
class AppLockSettingsScreen extends StatefulWidget {
  const AppLockSettingsScreen({super.key, AppLock? lock}) : _lock = lock;

  final AppLock? _lock;

  @override
  State<AppLockSettingsScreen> createState() => _AppLockSettingsScreenState();
}

class _AppLockSettingsScreenState extends State<AppLockSettingsScreen> {
  AppLock get lock => widget._lock ?? AppLock.instance;

  bool _biometricsAvailable = false;

  @override
  void initState() {
    super.initState();
    lock.biometricsAvailable().then((bool v) {
      if (mounted) {
        setState(() => _biometricsAvailable = v);
      }
    });
  }

  Future<String?> _askPin() {
    return Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (BuildContext _) => LockScreen(lock: lock, mode: LockScreenMode.setPin),
        fullscreenDialog: true,
      ),
    );
  }

  Future<void> _toggleEnabled(bool on) async {
    if (!on) {
      final bool? sure = await showDialog<bool>(
        context: context,
        builder: (BuildContext dialogContext) => AlertDialog(
          title: const Text('Turn the lock off?'),
          content: const Text('The PIN is forgotten. Anyone with the phone can open the app.'),
          actions: <Widget>[
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Keep lock')),
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Turn off')),
          ],
        ),
      );
      if (sure ?? false) {
        await lock.disable();
      }
      return;
    }
    final String? pin = await _askPin();
    if (pin != null) {
      await lock.setPin(pin);
    }
  }

  Future<void> _changePin() async {
    final String? pin = await _askPin();
    if (pin != null) {
      await lock.setPin(pin);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PIN changed')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('App lock')),
      body: ListenableBuilder(
        listenable: lock,
        builder: (BuildContext context, Widget? _) {
          final LockSettings s = lock.settings;
          final bool on = lock.isEnabled;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              Card(
                child: Column(
                  children: <Widget>[
                    SwitchListTile.adaptive(
                      key: const Key('lock-enabled'),
                      value: on,
                      onChanged: _toggleEnabled,
                      secondary: Icon(on ? Icons.lock : Icons.lock_open_outlined,
                          color: on ? AppColors.accent : AppColors.muted),
                      title: Text('Lock the app', style: text.titleMedium),
                      subtitle: Text(
                        on ? 'PIN required when the app opens.' : 'Off. Set a PIN to turn it on.',
                        style: text.bodyMedium,
                      ),
                    ),
                    if (on) ...<Widget>[
                      const Divider(height: 1),
                      ListTile(
                        key: const Key('lock-change-pin'),
                        leading: const Icon(Icons.pin_outlined),
                        title: const Text('Change PIN'),
                        subtitle: Text('${s.pinLength} digits', style: text.bodyMedium),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: _changePin,
                      ),
                      const Divider(height: 1),
                      SwitchListTile.adaptive(
                        key: const Key('lock-biometrics'),
                        value: s.biometrics,
                        onChanged: _biometricsAvailable ? (bool v) => lock.setBiometrics(v) : null,
                        secondary: const Icon(Icons.fingerprint),
                        title: const Text('Fingerprint or face'),
                        subtitle: Text(
                          _biometricsAvailable
                              ? 'Unlock without typing; the PIN still works.'
                              : 'Not set up on this phone.',
                          style: text.bodyMedium,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (on) ...<Widget>[
                const SizedBox(height: 20),
                Text('Lock again', style: text.titleMedium),
                const SizedBox(height: 8),
                Card(
                  child: RadioGroup<LockTimeout>(
                    groupValue: s.timeout,
                    onChanged: (LockTimeout? v) {
                      if (v != null) {
                        lock.setTimeout(v);
                      }
                    },
                    child: Column(
                      children: <Widget>[
                        for (final LockTimeout t in LockTimeout.values)
                          RadioListTile<LockTimeout>(
                            key: ValueKey<String>('timeout-${t.name}'),
                            value: t,
                            title: Text(t.label),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text('Lock these on their own', style: text.titleMedium),
                const SizedBox(height: 4),
                Text(
                  'Asks for the PIN again when opened, even while the app is unlocked.',
                  style: text.bodySmall,
                ),
                const SizedBox(height: 8),
                Card(
                  child: Column(
                    children: <Widget>[
                      for (final MapEntry<String, String> e in LockableIds.labels.entries)
                        SwitchListTile.adaptive(
                          key: ValueKey<String>('tool-lock-${e.key}'),
                          value: s.lockedIds.contains(e.key),
                          onChanged: (bool v) => lock.setToolLocked(e.key, v),
                          title: Text(e.value),
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Text(
                'The PIN never leaves this phone. Only a scrambled version is kept, in the '
                'phone\'s secure storage.',
                style: text.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
          );
        },
      ),
    );
  }
}
