import 'package:flutter/material.dart';

/// Files tab: recents, favourites, folders and search (feature 117).
class FilesScreen extends StatelessWidget {
  const FilesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Files', style: text.titleLarge),
            const SizedBox(height: 8),
            Text(
              'Recents, favourites and folders.',
              style: text.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
