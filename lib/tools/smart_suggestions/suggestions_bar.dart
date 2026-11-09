import 'package:flutter/material.dart';

import '../../app/tool_registry.dart';
import '../../engines/family/member_profiles.dart';
import '../../engines/platform/smart_suggestions.dart';
import '../../engines/privacy/on_device_mode.dart';
import '../tools_home.dart';

/// Feature 106 — the "Suggested for this PDF" row shown when a file is open.
///
/// Tools come from [SmartSuggestions] with the active member's recent tools
/// as history, so a tool the member keeps using moves to the front. Each
/// suggestion is a labelled chip at least 48 px tall; tapping one opens the
/// tool the same way the home grid does (and records it as recent).
class SuggestionsBar extends StatelessWidget {
  const SuggestionsBar({super.key, required this.path, this.limit = 4});

  final String path;
  final int limit;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: MemberProfiles.instance,
      builder: (BuildContext context, Widget? _) => _build(context),
    );
  }

  Widget _build(BuildContext context) {
    final bool onDevice = OnDeviceMode.instance.value;
    final Set<String> available = ToolRegistry.all
        .where((ToolEntry t) => !(onDevice && t.needsNetwork))
        .map((ToolEntry t) => t.id)
        .toSet();
    final SuggestKind kind = SmartSuggestions.kindForName(path);
    final List<String> ids = SmartSuggestions.suggest(
      kind,
      history: MemberProfiles.instance.active.recents,
      available: available,
      limit: limit,
    );
    if (ids.isEmpty) {
      return const SizedBox.shrink();
    }
    final TextTheme text = Theme.of(context).textTheme;
    final String heading = 'Suggested for this ${SmartSuggestions.label(kind)}';
    return Padding(
      key: const Key('smart-suggestions'),
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Semantics(header: true, child: Text(heading, style: text.titleMedium)),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: <Widget>[
              for (final String id in ids)
                if (ToolRegistry.byId(id) case final ToolEntry tool)
                  ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 48),
                    child: ActionChip(
                      key: ValueKey<String>('suggest-$id'),
                      materialTapTargetSize: MaterialTapTargetSize.padded,
                      avatar: Icon(tool.icon, size: 18),
                      label: Text(tool.name),
                      tooltip: 'Open ${tool.name} for this file',
                      onPressed: () => openTool(context, tool),
                    ),
                  ),
            ],
          ),
        ],
      ),
    );
  }
}
