import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Feature 025 — pictures shared into the app from Photos or Gallery.
///
/// Android hands `ACTION_SEND` / `ACTION_SEND_MULTIPLE` images to
/// MainActivity, which copies them into the app's cache in the order they
/// were shared and passes the paths over `app.family/shared_files`:
/// `initialFiles` for the share that opened the app, and a `files` call for
/// a share while it is running.
class SharedFilesInbox extends ChangeNotifier {
  SharedFilesInbox();

  static const String channelName = 'app.family/shared_files';
  static const MethodChannel channel = MethodChannel(channelName);

  List<String>? _pending;

  /// Called for each share, with the paths in shared order.
  void Function(List<String> paths)? onFiles;

  void receive(List<String> paths) {
    if (paths.isEmpty) {
      return;
    }
    _pending = List<String>.unmodifiable(paths);
    notifyListeners();
    onFiles?.call(_pending!);
  }

  /// Hands the pending paths over once.
  List<String>? take() {
    final List<String>? p = _pending;
    _pending = null;
    return p;
  }

  static List<String> _paths(Object? args) =>
      args is List<Object?> ? args.whereType<String>().toList() : <String>[];

  Future<Object?> handle(MethodCall call) async {
    if (call.method == 'files') {
      receive(_paths(call.arguments));
      return null;
    }
    throw MissingPluginException('No handler for ${call.method}');
  }

  /// Does nothing where there is no platform side (tests, iOS for now).
  Future<void> attach() async {
    try {
      channel.setMethodCallHandler(handle);
      receive(_paths(await channel.invokeMethod<Object?>('initialFiles')));
    } catch (_) {
      // No binding or no platform side.
    }
  }

  static SharedFilesInbox? _instance;

  static SharedFilesInbox get instance => _instance ??= SharedFilesInbox();

  static void install(SharedFilesInbox inbox) => _instance = inbox;
}
