import '../../app/tool_registry.dart';
import 'on_device_mode.dart';

/// Feature 104 — Offline first.
///
/// Every tool runs on the device. The few that need the network are listed
/// here by feature number; nothing else may declare `needsNetwork`, and the
/// test under test/features/104_offline-first scans lib/ for network code
/// outside the folders those features own. [NetworkGuard] is the one choke
/// point a network tool must go through, so on-device mode (059) always wins.
abstract final class OfflinePolicy {
  /// Features allowed to use the internet: web page to PDF, cloud import/save
  /// and downloads.
  static const Set<int> networkFeatures = <int>{23, 63, 123, 124, 127};

  /// Features that talk only to devices on the same Wi-Fi (no internet).
  /// They stay off the network list: airplane mode with Wi-Fi back on works.
  static const Set<int> lanFeatures = <int>{61, 62, 68};

  /// Folders (relative to the repo root) that may contain network code.
  static const List<String> networkSourceFolders = <String>[
    'lib/engines/download/',
    'lib/platform/cloud/',
    'lib/family/sync/',
    'lib/platform/network/',
  ];

  /// Source fragments that mean "talks to a server".
  static const List<String> networkMarkers = <String>[
    'package:http/',
    'package:dio/',
    'HttpClient(',
    'HttpClient.',
    'WebSocket.connect',
    'Socket.connect',
    'package:web_socket_channel/',
  ];

  static bool mayUseNetwork(ToolEntry tool) {
    final int? n = tool.featureNumber;
    return n != null && networkFeatures.contains(n);
  }

  /// Problems with a registry: tools that claim the network without being
  /// allowed, or allowed tools missing their reason. Empty means fine.
  static List<String> violations(Iterable<ToolEntry> tools) {
    final List<String> out = <String>[];
    for (final ToolEntry t in tools) {
      if (t.needsNetwork && !mayUseNetwork(t)) {
        out.add('${t.id} needs network but is not in OfflinePolicy.networkFeatures');
      }
      if (t.needsNetwork && (t.networkReason == null || t.networkReason!.trim().isEmpty)) {
        out.add('${t.id} needs network but gives no reason');
      }
      if (t.needsNetwork && !t.touches.contains(DataTouch.network)) {
        out.add('${t.id} needs network but does not list DataTouch.network');
      }
    }
    return out;
  }
}

/// Thrown when a network job is asked for while it is not allowed.
class OfflineBlocked implements Exception {
  const OfflineBlocked(this.toolId, this.reason);

  final String toolId;
  final String reason;

  @override
  String toString() => 'OfflineBlocked($toolId): $reason';
}

/// The only way a tool may reach the network.
abstract final class NetworkGuard {
  /// Why [tool] cannot use the network right now, or null when it can.
  static String? blockedReason(ToolEntry tool, {OnDeviceMode? mode}) {
    if (!OfflinePolicy.mayUseNetwork(tool)) {
      return '${tool.name} is an on-device tool and never uses the network.';
    }
    if ((mode ?? OnDeviceMode.instance).isOn) {
      return 'On-device mode is on. Turn it off in On-device mode to let ${tool.name} use the network.';
    }
    return null;
  }

  /// Runs [job] only when [tool] may use the network now.
  static Future<T> run<T>(ToolEntry tool, Future<T> Function() job, {OnDeviceMode? mode}) {
    final String? why = blockedReason(tool, mode: mode);
    if (why != null) {
      throw OfflineBlocked(tool.id, why);
    }
    return job();
  }
}
