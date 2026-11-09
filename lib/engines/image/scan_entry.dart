import 'package:flutter/services.dart';

/// Opens the scanner and resolves to the saved file paths (empty when the
/// person backs out).
typedef ScanLauncher = Future<List<String>> Function();

/// Feature 047 — the scanner as a share-sheet / intent target.
///
/// Other apps reach the scanner through the platform: an Android intent
/// (action `app.family.SCAN`, also listed in the share sheet) or the iOS
/// `familyutility://scan` link. The platform side calls `scan` on the
/// `app.family/scan` channel; Dart opens the scanner and replies with the
/// paths of the saved PDF or JPGs, which the platform hands back to the
/// calling app. Nothing is uploaded.
class ScanEntry {
  ScanEntry(this.launch);

  static const String channelName = 'app.family/scan';
  static const MethodChannel channel = MethodChannel(channelName);

  final ScanLauncher launch;
  bool _open = false;

  /// Handles one call from the platform.
  Future<Object?> handle(MethodCall call) async {
    if (call.method != 'scan') {
      throw MissingPluginException('No handler for ${call.method}');
    }
    if (_open) {
      // Already scanning: a second request should not stack a second camera.
      return <String>[];
    }
    _open = true;
    try {
      return await launch();
    } finally {
      _open = false;
    }
  }

  /// Listens for the platform. Safe to call before the binding exists
  /// (plain unit tests): it then does nothing.
  void attach() {
    try {
      channel.setMethodCallHandler(handle);
    } catch (_) {
      // No binding yet; the real app initialises it before bootstrap().
    }
  }
}
