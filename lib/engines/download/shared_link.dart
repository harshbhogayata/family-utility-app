import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Feature 123 — links shared into the app from another app's share sheet.
///
/// Android hands `ACTION_SEND` text to MainActivity, which passes it over the
/// `app.family/shared_link` channel: `initialLink` for the text the app was
/// opened with, and a `link` call for text shared while it is running.
class SharedLinkInbox extends ChangeNotifier {
  SharedLinkInbox();

  static const String channelName = 'app.family/shared_link';
  static const MethodChannel channel = MethodChannel(channelName);

  String? _pending;

  /// Shared text not yet taken by the video screen.
  String? get pending => _pending;

  /// Called for each shared text.
  void Function(String text)? onLink;

  void receive(String text) {
    if (text.trim().isEmpty) {
      return;
    }
    _pending = text;
    notifyListeners();
    onLink?.call(text);
  }

  /// Hands over the pending text once.
  String? take() {
    final String? t = _pending;
    _pending = null;
    return t;
  }

  Future<Object?> handle(MethodCall call) async {
    if (call.method == 'link' && call.arguments is String) {
      receive(call.arguments as String);
      return null;
    }
    throw MissingPluginException('No handler for ${call.method}');
  }

  /// Listens for the platform and asks for the text the app was opened with.
  /// Does nothing where there is no platform side (tests, iOS for now).
  Future<void> attach() async {
    try {
      channel.setMethodCallHandler(handle);
      final String? first = await channel.invokeMethod<String>('initialLink');
      if (first != null) {
        receive(first);
      }
    } catch (_) {
      // No binding or no platform side.
    }
  }

  static SharedLinkInbox? _instance;

  static SharedLinkInbox get instance => _instance ??= SharedLinkInbox();

  static void install(SharedLinkInbox inbox) => _instance = inbox;
}
