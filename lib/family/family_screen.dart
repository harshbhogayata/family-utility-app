import 'package:flutter/material.dart';

/// Family tab: live map, shared list, this week's events, sync status.
/// Filled in by Phase 2 features (068 onwards).
class FamilyScreen extends StatelessWidget {
  const FamilyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Family', style: text.titleLarge),
            const SizedBox(height: 8),
            Text(
              'Your family space lives here. Nothing leaves your devices.',
              style: text.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
