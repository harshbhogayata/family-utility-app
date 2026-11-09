import 'package:flutter/material.dart';

import '../../engines/platform/cross_links.dart';

/// Feature 122 — the related-items strip every record screen shows: one
/// chip per linked record that still exists; tapping it opens that record.
class RelatedItemsStrip extends StatelessWidget {
  const RelatedItemsStrip({super.key, required this.record, required this.onOpen, this.links});

  final RecordRef record;
  final ValueChanged<RecordRef> onOpen;
  final CrossLinks? links;

  @override
  Widget build(BuildContext context) {
    final CrossLinks l = links ?? CrossLinks.instance;
    return ListenableBuilder(
      listenable: l,
      builder: (BuildContext context, Widget? _) {
        final List<RelatedItem> items = l.related(record);
        if (items.isEmpty) {
          return const SizedBox.shrink();
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Semantics(header: true, child: Text('Related', style: Theme.of(context).textTheme.titleSmall)),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: <Widget>[
                for (final RelatedItem i in items)
                  Semantics(
                    button: true,
                    label: 'Open ${i.noun}: ${i.title}',
                    excludeSemantics: true,
                    child: ActionChip(
                      materialTapTargetSize: MaterialTapTargetSize.padded,
                      avatar: const Icon(Icons.link, size: 18),
                      label: Text('${i.noun} · ${i.title}'),
                      onPressed: () => onOpen(i.ref),
                    ),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}
