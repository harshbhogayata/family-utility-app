import 'package:flutter/material.dart';

import '../theme.dart';

/// The row every tool result ends with: Share, Save and Undo (DESIGN.md).
/// Pinned at the bottom of the result screen, each target at least 44 px.
class ResultBar extends StatelessWidget {
  const ResultBar({
    super.key,
    required this.onShare,
    required this.onSave,
    required this.onUndo,
    this.saveLabel = 'Save',
    this.undoLabel = 'Undo',
  });

  final VoidCallback onShare;
  final VoidCallback onSave;
  final VoidCallback onUndo;
  final String saveLabel;
  final String undoLabel;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.line)),
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: OutlinedButton.icon(
                key: const Key('result-undo'),
                onPressed: onUndo,
                icon: const Icon(Icons.undo),
                label: Text(undoLabel),
              ),
            ),
            const SizedBox(width: AppRadius.gridGap),
            Expanded(
              child: OutlinedButton.icon(
                key: const Key('result-share'),
                onPressed: onShare,
                icon: const Icon(Icons.ios_share),
                label: const Text('Share'),
              ),
            ),
            const SizedBox(width: AppRadius.gridGap),
            Expanded(
              child: FilledButton.icon(
                key: const Key('result-save'),
                onPressed: onSave,
                icon: const Icon(Icons.save_alt),
                label: Text(saveLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
