import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../app/widgets/result_bar.dart';
import '../../engines/platform/accessibility.dart';
import '../../engines/share/share_engine.dart';

typedef AccessibilityTextAction = Future<String?> Function(String text);

/// Feature 109 — dark mode, larger text and the one-hand layout.
class AccessibilityScreen extends StatelessWidget {
  const AccessibilityScreen({super.key, this.prefs, this.share, this.save});

  final AccessibilityPrefs? prefs;
  final AccessibilityTextAction? share;
  final AccessibilityTextAction? save;

  AccessibilityPrefs get _p => prefs ?? AccessibilityPrefs.instance;

  static Future<String?> _saveToDocuments(String text) async {
    final Directory dir = await getApplicationDocumentsDirectory();
    final File f = File('${dir.path}/Accessibility settings.txt');
    await f.writeAsString(text);
    return f.path;
  }

  Future<void> _share() async {
    final String text = _p.value.describe();
    final AccessibilityTextAction? s = share;
    if (s != null) {
      await s(text);
    } else {
      await ShareEngine.instance.shareText(text, subject: 'Accessibility settings');
    }
  }

  @override
  Widget build(BuildContext context) {
    void snack(String t) => ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(t)));

    Future<void> doSave() async {
      String? where;
      try {
        where = await (save ?? _saveToDocuments)(_p.value.describe());
      } catch (_) {
        where = null;
      }
      if (context.mounted) {
        snack(where == null ? 'Could not save' : 'Saved to $where');
      }
    }

    Future<void> doUndo() async {
      final bool ok = await _p.undo();
      if (context.mounted) {
        snack(ok ? 'Undone' : 'Nothing to undo');
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Accessibility')),
      bottomNavigationBar: ResultBar(
        onShare: () => unawaited(_share()),
        onSave: () => unawaited(doSave()),
        onUndo: () => unawaited(doUndo()),
      ),
      body: ValueListenableBuilder<AccessibilitySettings>(
        valueListenable: _p,
        builder: (BuildContext context, AccessibilitySettings a, Widget? _) {
          final TextTheme text = Theme.of(context).textTheme;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            children: <Widget>[
              Semantics(header: true, child: Text('Theme', style: text.titleMedium)),
              const SizedBox(height: 8),
              SegmentedButton<AppThemeChoice>(
                segments: <ButtonSegment<AppThemeChoice>>[
                  for (final AppThemeChoice c in AppThemeChoice.values)
                    ButtonSegment<AppThemeChoice>(value: c, label: Text(c.label)),
                ],
                selected: <AppThemeChoice>{a.theme},
                onSelectionChanged: (Set<AppThemeChoice> s) => unawaited(_p.set(a.copyWith(theme: s.first))),
              ),
              const SizedBox(height: 20),
              Semantics(header: true, child: Text('Text size', style: text.titleMedium)),
              Text(
                'Follows the phone\'s text size. Make it larger here too; '
                'the app caps text at 200%.',
                style: text.bodyMedium,
              ),
              Slider(
                key: const Key('text-boost'),
                value: a.textBoost,
                min: 1.0,
                max: AccessibilitySettings.maxTextScale,
                divisions: 4,
                label: '${(a.textBoost * 100).round()}%',
                semanticFormatterCallback: (double v) => 'Text size ${(v * 100).round()} percent',
                onChanged: (double v) => unawaited(_p.set(a.copyWith(textBoost: v))),
              ),
              Text('Sample text at this size', style: text.bodyLarge),
              const SizedBox(height: 20),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('One-hand layout'),
                subtitle: const Text('Lowers every screen so the top is within thumb reach'),
                value: a.oneHand,
                onChanged: (bool v) => unawaited(_p.set(a.copyWith(oneHand: v))),
              ),
            ],
          );
        },
      ),
    );
  }
}
