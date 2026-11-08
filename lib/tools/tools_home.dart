import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../app/tool_registry.dart';
import '../engines/privacy/on_device_mode.dart';
import 'privacy/privacy_screen.dart';

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
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            sliver: SliverToBoxAdapter(
              child: const Align(
                alignment: Alignment.centerLeft,
                child: OnDeviceChip(),
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

/// The home-screen line that says where things run. Tap for the privacy screen.
class OnDeviceChip extends StatelessWidget {
  const OnDeviceChip({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: OnDeviceMode.instance,
      builder: (BuildContext context, bool on, Widget? _) {
        return ActionChip(
          key: const Key('on-device-chip'),
          avatar: Icon(
            on ? Icons.shield : Icons.shield_outlined,
            size: 16,
            color: on ? AppColors.accentDark : AppColors.muted,
          ),
          label: Text(on ? 'On-device mode on' : 'On-device mode off'),
          tooltip: 'Privacy: what each tool touches',
          onPressed: () => Navigator.of(context).push<void>(
            MaterialPageRoute<void>(builder: (BuildContext _) => const PrivacyScreen()),
          ),
        );
      },
    );
  }
}

/// A square tile in the tool grid. Stroke icon, name, optional network badge.
/// A network tool is greyed out, with the reason, while on-device mode is on.
class ToolTile extends StatelessWidget {
  const ToolTile({super.key, required this.tool});

  final ToolEntry tool;

  void _open(BuildContext context) {
    Navigator.of(context).push<void>(MaterialPageRoute<void>(builder: tool.builder));
  }

  Future<void> _explain(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text('${tool.name} needs the network'),
        content: Text(
          'On-device mode is on, so this tool stays off and nothing leaves your phone.'
          '${tool.networkReason == null ? '' : '\n\n${tool.networkReason}'}',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Keep on-device'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              Navigator.of(context).push<void>(
                MaterialPageRoute<void>(builder: (BuildContext _) => const PrivacyScreen()),
              );
            },
            child: const Text('Privacy settings'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return ValueListenableBuilder<bool>(
      valueListenable: OnDeviceMode.instance,
      builder: (BuildContext context, bool on, Widget? _) {
        final bool blocked = on && tool.needsNetwork;
        final String label = blocked
            ? '${tool.name}, needs network, off in on-device mode'
            : tool.needsNetwork
                ? '${tool.name}, needs network'
                : tool.name;
        return Semantics(
          button: true,
          label: label,
          child: Card(
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () {
                if (blocked) {
                  _explain(context);
                } else {
                  _open(context);
                }
              },
              child: Opacity(
                opacity: blocked ? 0.45 : 1,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Icon(tool.icon, color: blocked ? AppColors.muted : AppColors.accent),
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
                      if (blocked)
                        Text('Off in on-device mode', style: text.labelSmall, maxLines: 1),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
