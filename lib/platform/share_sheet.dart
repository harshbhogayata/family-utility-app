import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../engines/share/share_engine.dart';

/// The system share sheet through share_plus, with each file's MIME type set
/// so WhatsApp, Gmail, Drive and Telegram all accept it.
class SystemShareSheet implements ShareSheet {
  const SystemShareSheet();

  @override
  Future<ShareOutcome> share(ShareRequest request) async {
    try {
      final ShareResult result;
      if (request.hasFiles) {
        result = await Share.shareXFiles(
          request.files
              .map((ShareFile f) => XFile(f.path, mimeType: f.mimeType, name: f.name))
              .toList(),
          text: request.text,
          subject: request.subject,
        );
      } else {
        result = await Share.share(request.text ?? '', subject: request.subject);
      }
      return ShareOutcome(
        completed: result.status == ShareResultStatus.success,
        target: result.status == ShareResultStatus.success ? result.raw : null,
      );
    } on PlatformException {
      return const ShareOutcome.dismissed();
    } on MissingPluginException {
      return const ShareOutcome.dismissed();
    }
  }
}

/// Recent share targets in the app's preferences file.
class PrefsShareTargetStore implements ShareTargetStore {
  const PrefsShareTargetStore();

  static const String _key = 'share_recent_targets';

  @override
  Future<List<String>> read() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_key) ?? <String>[];
  }

  @override
  Future<void> write(List<String> rawTargets) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, rawTargets);
  }
}
