import 'package:flutter/material.dart';

import '../../engines/share/share_engine.dart';
import '../../engines/platform/app_strings.dart';
import '../strings_scope.dart';
import '../theme.dart';

/// The row every tool result ends with: Share, Save and Undo (DESIGN.md).
/// Pinned at the bottom of the result screen, each target at least 44 px.
/// Shows where the last shares went (feature 060) when there is a history.
class ResultBar extends StatelessWidget {
  const ResultBar({
    super.key,
    required this.onShare,
    required this.onSave,
    required this.onUndo,
    this.saveLabel,
    this.undoLabel,
  });

  final VoidCallback onShare;
  final VoidCallback onSave;
  final VoidCallback onUndo;
  /// Defaults to "Save" in the active profile's language (feature 110).
  final String? saveLabel;
  final String? undoLabel;

  @override
  Widget build(BuildContext context) {
    final AppStrings t = AppStringsScope.of(context);
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border(top: BorderSide(color: Theme.of(context).colorScheme.outline)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const RecentShareTargetsLine(),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton.icon(
                    key: const Key('result-undo'),
                    onPressed: onUndo,
                    icon: const Icon(Icons.undo),
                    label: Text(undoLabel ?? t.undo),
                  ),
                ),
                const SizedBox(width: AppRadius.gridGap),
                Expanded(
                  child: OutlinedButton.icon(
                    key: const Key('result-share'),
                    onPressed: onShare,
                    icon: const Icon(Icons.ios_share),
                    label: Text(t.share),
                  ),
                ),
                const SizedBox(width: AppRadius.gridGap),
                Expanded(
                  child: FilledButton.icon(
                    key: const Key('result-save'),
                    onPressed: onSave,
                    icon: const Icon(Icons.save_alt),
                    label: Text(saveLabel ?? t.save),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// "Last shared to WhatsApp, Gmail" above the bar, when there is a history.
class RecentShareTargetsLine extends StatelessWidget {
  const RecentShareTargetsLine({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<ShareTarget>>(
      valueListenable: ShareEngine.instance.recents,
      builder: (BuildContext context, List<ShareTarget> recents, Widget? _) {
        if (recents.isEmpty) {
          return const SizedBox.shrink();
        }
        final String names = recents.take(3).map((ShareTarget t) => t.label).join(', ');
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            AppStringsScope.of(context).lastSharedTo(names),
            key: const Key('recent-share-targets'),
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        );
      },
    );
  }
}
