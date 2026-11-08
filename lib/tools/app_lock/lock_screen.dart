import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../engines/security/app_lock.dart';

/// The PIN pad. Used full-screen when the app is locked and pushed as a
/// route when a locked tool is opened or a PIN is being set.
///
/// In [LockScreenMode.unlock] it pops `true` on success (or unlocks the app
/// in place when used as the gate). In [LockScreenMode.setPin] it asks twice
/// and pops the new PIN as a String.
enum LockScreenMode { unlock, setPin }

class LockScreen extends StatefulWidget {
  const LockScreen({
    super.key,
    required this.lock,
    this.mode = LockScreenMode.unlock,
    this.title,
    this.asRoute = true,
  });

  final AppLock lock;
  final LockScreenMode mode;
  final String? title;

  /// True when pushed with Navigator (pops with the result); false when
  /// shown in place by [LockGate].
  final bool asRoute;

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  String _entry = '';
  String? _firstEntry;
  String? _message;
  bool _busy = false;

  AppLock get lock => widget.lock;

  bool get _settingUp => widget.mode == LockScreenMode.setPin;

  int get _targetLength => _settingUp ? (_firstEntry?.length ?? PinHasher.maxLength) : lock.settings.pinLength;

  @override
  void initState() {
    super.initState();
    if (!_settingUp && lock.biometricsOffered) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _tryBiometrics());
    }
  }

  Future<void> _tryBiometrics() async {
    if (_busy || !mounted) {
      return;
    }
    setState(() => _busy = true);
    final bool ok = await lock.unlockWithBiometrics();
    if (!mounted) {
      return;
    }
    setState(() => _busy = false);
    if (ok) {
      _done();
    }
  }

  void _done() {
    if (widget.asRoute && mounted) {
      Navigator.of(context).pop<bool>(true);
    }
  }

  void _tap(String digit) {
    if (_busy || _entry.length >= PinHasher.maxLength) {
      return;
    }
    setState(() {
      _entry += digit;
      _message = null;
    });
    if (_settingUp) {
      _maybeFinishSetup();
    } else if (_entry.length == _targetLength) {
      _submit();
    }
  }

  void _backspace() {
    if (_entry.isEmpty) {
      return;
    }
    setState(() => _entry = _entry.substring(0, _entry.length - 1));
  }

  /// In set-up mode the person taps Next; in unlock mode entry auto-submits.
  void _maybeFinishSetup() {
    final String? first = _firstEntry;
    if (first != null && _entry.length == first.length) {
      if (_entry == first) {
        Navigator.of(context).pop<String>(_entry);
      } else {
        setState(() {
          _entry = '';
          _firstEntry = null;
          _message = 'The PINs did not match. Start again.';
        });
      }
    }
  }

  void _next() {
    if (!PinHasher.isValidPin(_entry)) {
      setState(() => _message = 'Use ${PinHasher.minLength} to ${PinHasher.maxLength} digits.');
      return;
    }
    setState(() {
      _firstEntry = _entry;
      _entry = '';
      _message = 'Enter it once more.';
    });
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    final UnlockFailure? failure = await lock.unlockWithPin(_entry);
    if (!mounted) {
      return;
    }
    setState(() {
      _busy = false;
      _entry = '';
      _message = switch (failure) {
        null => null,
        UnlockFailure.wrongPin => 'Wrong PIN. Try again.',
        UnlockFailure.lockedOut => 'Too many tries. Wait ${lock.lockoutSecondsLeft} seconds.',
        UnlockFailure.notSetUp => 'No PIN is set.',
      };
    });
    if (failure == null) {
      _done();
    }
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final String heading = widget.title ??
        (_settingUp
            ? (_firstEntry == null ? 'Choose a PIN' : 'Repeat the PIN')
            : 'Enter your PIN');
    final int dots = _settingUp ? PinHasher.maxLength : _targetLength;
    return Scaffold(
      appBar: AppBar(
        title: Text(_settingUp ? 'Set PIN' : 'Locked'),
        automaticallyImplyLeading: widget.asRoute,
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            const Spacer(),
            const Icon(Icons.lock_outline, size: 40, color: AppColors.accent),
            const SizedBox(height: 12),
            Text(heading, style: text.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            Semantics(
              label: '${_entry.length} of $dots digits entered',
              liveRegion: true,
              child: ExcludeSemantics(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    for (int i = 0; i < dots; i++)
                      Container(
                        key: ValueKey<String>('pin-dot-$i'),
                        width: 14,
                        height: 14,
                        margin: const EdgeInsets.symmetric(horizontal: 6),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: i < _entry.length ? AppColors.accent : Colors.transparent,
                          border: Border.all(color: AppColors.accent, width: 1.5),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            SizedBox(
              height: 40,
              child: Center(
                child: Text(
                  _message ?? '',
                  key: const Key('lock-message'),
                  style: text.bodyMedium?.copyWith(color: const Color(0xFFB45309)),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            const Spacer(),
            _PinPad(
              onDigit: _tap,
              onBackspace: _backspace,
              enabled: !_busy,
              trailing: _settingUp
                  ? _PadButton(
                      key: const Key('pin-next'),
                      label: 'Next',
                      semantics: 'Next',
                      onTap: _firstEntry == null && !_busy ? _next : null,
                    )
                  : (lock.biometricsOffered
                      ? _PadButton(
                          key: const Key('pin-biometrics'),
                          icon: Icons.fingerprint,
                          semantics: 'Use fingerprint or face',
                          onTap: _busy ? null : _tryBiometrics,
                        )
                      : const SizedBox(width: 84, height: 68)),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class _PinPad extends StatelessWidget {
  const _PinPad({
    required this.onDigit,
    required this.onBackspace,
    required this.enabled,
    required this.trailing,
  });

  final void Function(String) onDigit;
  final VoidCallback onBackspace;
  final bool enabled;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    Widget digit(String d) => _PadButton(
          key: ValueKey<String>('pin-$d'),
          label: d,
          semantics: d,
          onTap: enabled ? () => onDigit(d) : null,
        );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (final List<String> row in const <List<String>>[
          <String>['1', '2', '3'],
          <String>['4', '5', '6'],
          <String>['7', '8', '9'],
        ])
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[for (final String d in row) digit(d)],
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            trailing,
            digit('0'),
            _PadButton(
              key: const Key('pin-backspace'),
              icon: Icons.backspace_outlined,
              semantics: 'Delete last digit',
              onTap: enabled ? onBackspace : null,
            ),
          ],
        ),
      ],
    );
  }
}

class _PadButton extends StatelessWidget {
  const _PadButton({
    super.key,
    this.label,
    this.icon,
    required this.semantics,
    required this.onTap,
  });

  final String? label;
  final IconData? icon;
  final String semantics;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.all(6),
      child: Semantics(
        button: true,
        label: semantics,
        enabled: onTap != null,
        child: ExcludeSemantics(
          child: Material(
            color: AppColors.surface,
            shape: const CircleBorder(side: BorderSide(color: AppColors.line)),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: SizedBox(
                width: 72,
                height: 56,
                child: Center(
                  child: label != null
                      ? Text(label!, style: text.titleLarge)
                      : Icon(icon, color: AppColors.ink),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Wraps the app: shows [LockScreen] in place while [AppLock] is locked and
/// relocks after the timeout when the app comes back from the background.
class LockGate extends StatefulWidget {
  const LockGate({super.key, required this.child, AppLock? lock}) : _lock = lock;

  final Widget child;
  final AppLock? _lock;

  @override
  State<LockGate> createState() => _LockGateState();
}

class _LockGateState extends State<LockGate> with WidgetsBindingObserver {
  AppLock get lock => widget._lock ?? AppLock.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        lock.onBackground();
      case AppLifecycleState.resumed:
        lock.onForeground();
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: lock,
      builder: (BuildContext context, Widget? _) {
        if (!lock.isLocked) {
          return widget.child;
        }
        return LockScreen(key: const Key('app-lock-screen'), lock: lock, asRoute: false);
      },
    );
  }
}

/// Asks for the PIN before [id] opens, once per unlock. Returns true when
/// the person may go on.
Future<bool> ensureUnlockedFor(BuildContext context, String id, {AppLock? lock}) async {
  final AppLock l = lock ?? AppLock.instance;
  if (!l.needsUnlockFor(id)) {
    return true;
  }
  // The tool lock reuses the app's PIN; unlocking it must not unlock the app
  // screen state, so run the check through a scoped route.
  final bool? ok = await Navigator.of(context).push<bool>(
    MaterialPageRoute<bool>(
      builder: (BuildContext _) => _ToolUnlockScreen(lock: l, id: id),
      fullscreenDialog: true,
    ),
  );
  if (ok ?? false) {
    l.markOpened(id);
    return true;
  }
  return false;
}

class _ToolUnlockScreen extends StatelessWidget {
  const _ToolUnlockScreen({required this.lock, required this.id});

  final AppLock lock;
  final String id;

  @override
  Widget build(BuildContext context) {
    return LockScreen(
      lock: lock,
      title: 'Enter your PIN to open ${LockableIds.labels[id] ?? id}',
    );
  }
}

/// A tab or section that carries its own lock: shows a placeholder with an
/// Unlock button until the PIN is given, then the real content.
class LockedSection extends StatelessWidget {
  const LockedSection({super.key, required this.id, required this.child, AppLock? lock}) : _lock = lock;

  final String id;
  final Widget child;
  final AppLock? _lock;

  @override
  Widget build(BuildContext context) {
    final AppLock lock = _lock ?? AppLock.instance;
    return ListenableBuilder(
      listenable: lock,
      builder: (BuildContext context, Widget? _) {
        if (!lock.needsUnlockFor(id)) {
          return child;
        }
        final TextTheme text = Theme.of(context).textTheme;
        return SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Icon(Icons.lock_outline, size: 40, color: AppColors.accent),
                  const SizedBox(height: 12),
                  Text('Locked', style: text.titleLarge),
                  const SizedBox(height: 6),
                  Text(
                    'Enter your PIN to open ${LockableIds.labels[id] ?? id}.',
                    style: text.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    key: ValueKey<String>('unlock-$id'),
                    onPressed: () => ensureUnlockedFor(context, id, lock: lock),
                    icon: const Icon(Icons.lock_open_outlined),
                    label: const Text('Unlock'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
