import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../app/tool_registry.dart';
import '../../engines/privacy/on_device_mode.dart';

/// Feature 059 — the on-device switch and a plain list of what every tool
/// touches. Default on. Nothing here is a chore, so there is no result bar.
class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key, OnDeviceMode? mode}) : _mode = mode;

  final OnDeviceMode? _mode;

  OnDeviceMode get mode => _mode ?? OnDeviceMode.instance;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final List<ToolEntry> tools = ToolRegistry.all;
    return Scaffold(
      appBar: AppBar(title: const Text('On-device mode')),
      body: ValueListenableBuilder<bool>(
        valueListenable: mode,
        builder: (BuildContext context, bool on, Widget? _) {
          final int networkTools = tools.where((ToolEntry t) => t.needsNetwork).length;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              Card(
                child: Column(
                  children: <Widget>[
                    SwitchListTile.adaptive(
                      key: const Key('on-device-switch'),
                      value: on,
                      onChanged: (bool v) => mode.set(v),
                      secondary: Icon(
                        on ? Icons.shield : Icons.shield_outlined,
                        color: on ? AppColors.accent : AppColors.muted,
                      ),
                      title: Text('On-device mode', style: text.titleMedium),
                      subtitle: Text(
                        on
                            ? 'On. Every tool runs on this phone and makes no network calls.'
                            : 'Off. Tools that need the network (downloads, cloud) can run.',
                        style: text.bodyMedium,
                      ),
                    ),
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        on
                            ? 'Works in airplane mode. $networkTools ${networkTools == 1 ? 'tool is' : 'tools are'} '
                                'greyed out on the home screen until you turn this off.'
                            : 'Turn it back on any time. Files you give the app are never uploaded '
                                'either way; only Share sends what you choose.',
                        style: text.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Text('What each tool touches', style: text.titleMedium),
              const SizedBox(height: 4),
              Text(
                'No accounts, no analytics, no ads, no cloud AI. This is the whole list.',
                style: text.bodySmall,
              ),
              const SizedBox(height: 12),
              if (tools.isEmpty)
                Text('Tools appear here as they are built.', style: text.bodyMedium)
              else
                Card(
                  child: Column(
                    children: <Widget>[
                      for (int i = 0; i < tools.length; i++) ...<Widget>[
                        if (i > 0) const Divider(height: 1),
                        _ToolPrivacyTile(tool: tools[i], onDeviceOn: on),
                      ],
                    ],
                  ),
                ),
              const SizedBox(height: 20),
              Text('What the words mean', style: text.titleMedium),
              const SizedBox(height: 8),
              Card(
                child: Column(
                  children: <Widget>[
                    for (int i = 0; i < DataTouch.values.length; i++) ...<Widget>[
                      if (i > 0) const Divider(height: 1),
                      ListTile(
                        leading: Icon(iconForTouch(DataTouch.values[i])),
                        title: Text(DataTouch.values[i].label, style: text.titleSmall),
                        subtitle: Text(DataTouch.values[i].explanation, style: text.bodyMedium),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ToolPrivacyTile extends StatelessWidget {
  const _ToolPrivacyTile({required this.tool, required this.onDeviceOn});

  final ToolEntry tool;
  final bool onDeviceOn;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final bool blocked = onDeviceOn && tool.needsNetwork;
    final List<DataTouch> touches = <DataTouch>[
      ...tool.touches,
      if (tool.needsNetwork && !tool.touches.contains(DataTouch.network)) DataTouch.network,
    ];
    return Semantics(
      label: '${tool.name} touches ${touches.map((DataTouch t) => t.label).join(', ')}'
          '${blocked ? '. Off in on-device mode' : ''}',
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(tool.icon, size: 20, color: blocked ? AppColors.muted : AppColors.accent),
                  const SizedBox(width: 10),
                  Expanded(child: Text(tool.name, style: text.titleSmall)),
                  if (blocked)
                    Text('Off in on-device mode', style: text.labelMedium),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: <Widget>[
                  for (final DataTouch t in touches)
                    Chip(
                      avatar: Icon(iconForTouch(t), size: 14, color: AppColors.muted),
                      label: Text(t.label),
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                    ),
                ],
              ),
              if (tool.needsNetwork && tool.networkReason != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('Needs network: ${tool.networkReason}', style: text.bodyMedium),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

IconData iconForTouch(DataTouch t) {
  return switch (t) {
    DataTouch.files => Icons.folder_outlined,
    DataTouch.camera => Icons.photo_camera_outlined,
    DataTouch.photos => Icons.photo_outlined,
    DataTouch.contacts => Icons.contacts_outlined,
    DataTouch.calendar => Icons.event_outlined,
    DataTouch.clipboard => Icons.content_paste_outlined,
    DataTouch.microphone => Icons.mic_none_outlined,
    DataTouch.location => Icons.location_on_outlined,
    DataTouch.lan => Icons.router_outlined,
    DataTouch.network => Icons.wifi,
  };
}
