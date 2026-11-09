import 'package:flutter/material.dart';

import '../../app/tool_registry.dart';
import '../../engines/family/member_profiles.dart';
import '../../engines/platform/paste_anything.dart';
import '../../engines/privacy/on_device_mode.dart';
import '../tools_home.dart';

/// Feature 105 — reads the clipboard once and shows the tools that fit.
Future<void> showPasteSheet(BuildContext context, {PasteSource? source}) async {
  final PastedContent content = await PasteAnything.read(source ?? PasteAnything.source);
  if (!context.mounted) {
    return;
  }
  final bool onDevice = OnDeviceMode.instance.value;
  final Set<String> available = ToolRegistry.all
      .where((ToolEntry t) => !(onDevice && t.needsNetwork))
      .map((ToolEntry t) => t.id)
      .toSet();
  final List<String> ids = PasteAnything.tools(
    content,
    history: MemberProfiles.instance.active.recents,
    available: available,
  );
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (BuildContext sheet) => PasteSheet(
      content: content,
      ids: ids,
      onOpen: (ToolEntry tool) {
        Navigator.of(sheet).pop();
        openTool(context, tool);
      },
    ),
  );
}

class PasteSheet extends StatelessWidget {
  const PasteSheet({super.key, required this.content, required this.ids, required this.onOpen});

  final PastedContent content;
  final List<String> ids;
  final void Function(ToolEntry tool) onOpen;

  String? get _preview {
    final String? t = content.kind == PasteKind.file ? content.path : content.text;
    if (t == null || t.isEmpty || content.kind == PasteKind.image) {
      return null;
    }
    return t.length > 120 ? '${t.substring(0, 120)}…' : t;
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final List<ToolEntry> tools = <ToolEntry>[
      for (final String id in ids)
        if (ToolRegistry.byId(id) case final ToolEntry t) t,
    ];
    final String heading = content.kind == PasteKind.empty
        ? 'The clipboard is empty'
        : 'Pasted: ${PasteAnything.label(content)}';
    return SafeArea(
      child: Padding(
        key: const Key('paste-sheet'),
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Semantics(
              header: true,
              liveRegion: true,
              child: Text(heading, key: const Key('paste-heading'), style: text.titleMedium),
            ),
            if (_preview != null) ...<Widget>[
              const SizedBox(height: 4),
              Text(_preview!, maxLines: 3, overflow: TextOverflow.ellipsis, style: text.bodyMedium),
            ],
            const SizedBox(height: 8),
            if (content.kind == PasteKind.empty)
              Text('Copy a link, some text, a picture or a file, then tap Paste again.', style: text.bodyMedium)
            else if (tools.isEmpty)
              Text('No tool fits this yet.', style: text.bodyMedium)
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: <Widget>[
                    for (final ToolEntry t in tools)
                      ListTile(
                        key: ValueKey<String>('paste-tool-${t.id}'),
                        minTileHeight: 52,
                        leading: Icon(t.icon),
                        title: Text(t.name),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => onOpen(t),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            Text('Read from the clipboard on this phone only. Nothing is uploaded.', style: text.bodySmall),
          ],
        ),
      ),
    );
  }
}
