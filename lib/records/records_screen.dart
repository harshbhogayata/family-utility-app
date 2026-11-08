import 'package:flutter/material.dart';

/// Records tab: quick-add, due soon, Money / Health / Documents / Home.
/// Filled in by Phase 3 features (080 onwards).
class RecordsScreen extends StatelessWidget {
  const RecordsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Records', style: text.titleLarge),
            const SizedBox(height: 8),
            Text(
              'Money, health, documents and home records, kept on this phone.',
              style: text.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
