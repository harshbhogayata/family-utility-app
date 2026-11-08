import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../app/tool_registry.dart';

/// Home / Tools: greeting, paste-or-pick box, tool grid.
class ToolsHome extends StatelessWidget {
  const ToolsHome({super.key});

  @override
  Widget build(BuildContext context) {
    final List<ToolEntry> tools = ToolRegistry.all;
    final TextTheme text = Theme.of(context).textTheme;
    return SafeArea(
      child: CustomScrollView(
        slivers: <Widget>[
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            sliver: SliverToBoxAdapter(
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      'Tools',
                      style: text.titleLarge,
                      semanticsLabel: 'Tools home',
                    ),
                  ),
                  const CircleAvatar(
                    radius: 18,
                    backgroundColor: AppColors.accentTint,
                    child: Icon(Icons.person_outline, color: AppColors.accentDark),
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverToBoxAdapter(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: <Widget>[
                      const Icon(Icons.add_circle_outline, color: AppColors.accent),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Paste or pick a file to start',
                          style: text.bodyLarge,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (tools.isEmpty)
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverToBoxAdapter(
                child: Text(
                  'Tools appear here as they are built.',
                  style: text.bodyMedium,
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: AppRadius.gridGap,
                  crossAxisSpacing: AppRadius.gridGap,
                  childAspectRatio: 1,
                ),
                delegate: SliverChildBuilderDelegate(
                  (BuildContext context, int i) => ToolTile(tool: tools[i]),
                  childCount: tools.length,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A square tile in the tool grid. Stroke icon, name, optional network badge.
class ToolTile extends StatelessWidget {
  const ToolTile({super.key, required this.tool});

  final ToolEntry tool;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      label: tool.needsNetwork ? '${tool.name}, needs network' : tool.name,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Navigator.of(context).push<void>(
            MaterialPageRoute<void>(builder: tool.builder),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(tool.icon, color: AppColors.accent),
                    const Spacer(),
                    if (tool.needsNetwork)
                      const Tooltip(
                        message: 'Needs network',
                        child: Icon(Icons.wifi, size: 16, color: AppColors.muted),
                      ),
                  ],
                ),
                const Spacer(),
                Text(
                  tool.name,
                  style: text.titleSmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
