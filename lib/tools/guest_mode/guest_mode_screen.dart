import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../../app/tool_registry.dart';
import '../../app/widgets/result_bar.dart';
import '../../engines/platform/guest_mode.dart';
import '../../engines/security/app_lock.dart';
import '../../engines/share/share_engine.dart';

typedef GuestTextAction = Future<String?> Function(String text);

/// Feature 119 — pick the tools a guest may use, set the owner's PIN and
/// hand the phone over.
class GuestModeScreen extends StatefulWidget {
  const GuestModeScreen({super.key, this.mode, this.share, this.save});

  final GuestMode? mode;
  final GuestTextAction? share;
  final GuestTextAction? save;

  @override
  State<GuestModeScreen> createState() => _GuestModeScreenState();
}

class _GuestModeScreenState extends State<GuestModeScreen> {
  final TextEditingController _pin = TextEditingController();
  final List<List<String>> _undo = <List<String>>[];

  GuestMode get _g => widget.mode ?? GuestMode.instance;

  /// The tools a guest can be given: everything but this screen.
  List<ToolEntry> get _tools => ToolRegistry.all.where((ToolEntry t) => t.id != guestModeToolId).toList();

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  void _snack(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  Future<void> _toggle(String id) async {
    _undo.add(_g.allowed);
    await _g.toggleAllowed(id);
  }

  String _describe() {
    final StringBuffer b = StringBuffer('Guest mode tools\n');
    for (final String id in _g.allowed) {
      b.writeln('- ${ToolRegistry.byId(id)?.name ?? id}');
    }
    return b.toString();
  }

  static Future<String?> _saveToDocuments(String text) async {
    final Directory dir = await getApplicationDocumentsDirectory();
    final File f = File('${dir.path}/Guest mode tools.txt');
    await f.writeAsString(text);
    return f.path;
  }

  Future<void> _share() async {
    final GuestTextAction? s = widget.share;
    if (s != null) {
      await s(_describe());
    } else {
      await ShareEngine.instance.shareText(_describe(), subject: 'Guest mode tools');
    }
  }

  Future<void> _save() async {
    String? where;
    try {
      where = await (widget.save ?? _saveToDocuments)(_describe());
    } catch (_) {
      where = null;
    }
    if (mounted) {
      _snack(where == null ? 'Could not save the list' : 'Saved to $where');
    }
  }

  Future<void> _undoLast() async {
    if (_undo.isEmpty) {
      _snack('Nothing to undo');
      return;
    }
    await _g.setAllowed(_undo.removeLast());
    if (mounted) {
      _snack('Undone');
    }
  }

  Future<void> _start() async {
    final String? why = _g.whyNotStart(_pin.text);
    if (why != null) {
      _snack(why);
      return;
    }
    final NavigatorState nav = Navigator.of(context);
    final bool ok = await _g.start(_pin.text);
    _pin.clear();
    if (ok && mounted) {
      nav.popUntil((Route<dynamic> r) => r.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _g,
      builder: (BuildContext context, Widget? _) {
        final List<ToolEntry> tools = _tools;
        final TextTheme text = Theme.of(context).textTheme;
        return Scaffold(
          appBar: AppBar(title: const Text('Guest mode')),
          bottomNavigationBar: ResultBar(
            onShare: () => unawaited(_share()),
            onSave: () => unawaited(_save()),
            onUndo: () => unawaited(_undoLast()),
          ),
          body: ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  'Hand the phone to a child or relative. They see only the tools you tick, '
                  'and only your PIN brings everything back.',
                  style: text.bodyMedium,
                ),
              ),
              for (final ToolEntry t in tools)
                CheckboxListTile(
                  key: Key('guest-allow-${t.id}'),
                  value: _g.isAllowed(t.id),
                  onChanged: (bool? _) => unawaited(_toggle(t.id)),
                  secondary: Icon(t.icon),
                  title: Text(t.name),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: TextField(
                  key: const Key('guest-pin'),
                  controller: _pin,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(PinHasher.maxLength),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Your PIN to leave guest mode',
                    helperText: '4 to 6 digits. Only you should know it.',
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: SizedBox(
                  height: 48,
                  child: FilledButton.icon(
                    key: const Key('guest-start'),
                    onPressed: () => unawaited(_start()),
                    icon: const Icon(Icons.child_care),
                    label: Text('Start guest mode (${_g.allowed.length} tools)'),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The registry id of this screen; never offered to a guest.
const String guestModeToolId = 'guest-mode';

/// Asks for the owner's PIN and leaves guest mode when it is right.
Future<void> showGuestExitDialog(BuildContext context, {GuestMode? mode}) {
  final GuestMode g = mode ?? GuestMode.instance;
  return showDialog<void>(
    context: context,
    builder: (BuildContext dialogContext) => _GuestExitDialog(mode: g),
  );
}

class _GuestExitDialog extends StatefulWidget {
  const _GuestExitDialog({required this.mode});

  final GuestMode mode;

  @override
  State<_GuestExitDialog> createState() => _GuestExitDialogState();
}

class _GuestExitDialogState extends State<_GuestExitDialog> {
  final TextEditingController _pin = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final NavigatorState nav = Navigator.of(context);
    final GuestExit r = await widget.mode.exit(_pin.text);
    _pin.clear();
    if (!mounted) {
      return;
    }
    switch (r) {
      case GuestExit.exited:
      case GuestExit.notActive:
        nav.pop();
      case GuestExit.wrongPin:
        setState(() => _error = 'That is not the owner PIN');
      case GuestExit.lockedOut:
        setState(() => _error = 'Too many tries. Wait ${widget.mode.lockoutSeconds} seconds.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Leave guest mode'),
      content: TextField(
        key: const Key('guest-exit-pin'),
        controller: _pin,
        autofocus: true,
        obscureText: true,
        keyboardType: TextInputType.number,
        inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(labelText: 'Owner PIN', errorText: _error),
        onSubmitted: (String _) => unawaited(_submit()),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          key: const Key('guest-exit-confirm'),
          onPressed: () => unawaited(_submit()),
          child: const Text('Leave'),
        ),
      ],
    );
  }
}
