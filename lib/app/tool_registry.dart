import 'package:flutter/widgets.dart';

import '../engines/privacy/on_device_mode.dart';

/// Where a tool lives in the home grid.
enum ToolSection {
  pdf('PDF'),
  convert('Convert'),
  compress('Compress'),
  image('Images'),
  scan('Scan and QR'),
  security('Security'),
  share('Share and transfer'),
  links('Links'),
  platform('Platform');

  const ToolSection(this.label);
  final String label;
}

/// One entry in the tool grid. Tools register here as features land.
class ToolEntry {
  const ToolEntry({
    required this.id,
    required this.name,
    required this.section,
    required this.icon,
    required this.builder,
    this.needsNetwork = false,
    this.networkReason,
    this.touches = const <DataTouch>{DataTouch.files},
    this.featureNumber,
  });

  /// Stable id, used for recents and deep links.
  final String id;
  final String name;
  final ToolSection section;
  final IconData icon;
  final WidgetBuilder builder;

  /// True only for the few tools that need the network (downloads, cloud).
  /// Offline-first rule: these carry a badge; everything else runs on device.
  final bool needsNetwork;

  /// Plain-words reason a network tool needs the network, shown when
  /// on-device mode keeps it closed.
  final String? networkReason;

  /// What the tool touches on the phone, listed on the privacy screen.
  final Set<DataTouch> touches;

  /// Spec number in `features/`, for cross-reference.
  final int? featureNumber;
}

/// The single list of tools. Keep it ordered as the home grid should read.
class ToolRegistry {
  ToolRegistry._();

  static final List<ToolEntry> _tools = <ToolEntry>[];

  static List<ToolEntry> get all => List<ToolEntry>.unmodifiable(_tools);

  static void register(ToolEntry entry) {
    if (_tools.any((ToolEntry t) => t.id == entry.id)) {
      return;
    }
    _tools.add(entry);
  }

  static void registerAll(Iterable<ToolEntry> entries) {
    entries.forEach(register);
  }

  static ToolEntry? byId(String id) {
    for (final ToolEntry t in _tools) {
      if (t.id == id) {
        return t;
      }
    }
    return null;
  }

  @visibleForTesting
  static void clear() => _tools.clear();
}
