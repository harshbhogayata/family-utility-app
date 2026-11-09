import 'package:flutter/foundation.dart';

import 'video_link.dart';

/// Feature 126 — Clipboard link watch.
///
/// Opt-in. When the app comes to the front and the switch is on, the
/// clipboard text is looked at once, in memory: if it holds a link one of the
/// 123 site plugins handles, the app offers to save it. Anything else on the
/// clipboard is dropped on the spot: never stored, logged, shown or sent.

/// Where the clipboard text comes from (the system clipboard in the app).
abstract class ClipboardTextSource {
  /// Only called while the watch is switched on.
  Future<String?> readText();
}

/// Remembers the opt-in switch.
abstract class ClipboardWatchStore {
  Future<bool> readEnabled();
  Future<void> writeEnabled(bool enabled);
}

class MemoryClipboardWatchStore implements ClipboardWatchStore {
  MemoryClipboardWatchStore({this.enabled = false});

  bool enabled;

  @override
  Future<bool> readEnabled() async => enabled;

  @override
  Future<void> writeEnabled(bool value) async => enabled = value;
}

/// A link the app offers to save, with the site that handles it.
class LinkOffer {
  const LinkOffer(this.url, this.site);

  final Uri url;
  final String site;
}

/// The supported link inside [text], or null. Only site plugins count; the
/// generic fallback does not, so ordinary links are never offered.
LinkOffer? supportedLink(String? text, List<VideoExtractor> plugins) {
  if (text == null || text.length > 4096) {
    return null;
  }
  final Uri? url = findLink(text);
  if (url == null) {
    return null;
  }
  for (final VideoExtractor p in plugins) {
    bool match = false;
    try {
      match = p.handles(url);
    } catch (_) {
      match = false;
    }
    if (match) {
      return LinkOffer(url, p.label);
    }
  }
  return null;
}

class ClipboardLinkWatch extends ChangeNotifier {
  ClipboardLinkWatch({
    required this.source,
    required this.store,
    List<VideoExtractor>? plugins,
  }) : plugins = plugins ?? VideoExtractorRegistry.defaultPlugins();

  final ClipboardTextSource source;
  final ClipboardWatchStore store;
  final List<VideoExtractor> plugins;

  bool _enabled = false;
  bool get enabled => _enabled;

  LinkOffer? _offer;

  /// The link on offer right now, if any.
  LinkOffer? get offer => _offer;

  /// The last link offered, so the same copy is not offered twice.
  String? _lastOffered;

  /// How many times the clipboard was looked at (for tests and the screen).
  int checks = 0;

  Future<void> load() async {
    try {
      _enabled = await store.readEnabled();
    } catch (_) {
      _enabled = false;
    }
    notifyListeners();
  }

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    if (!value) {
      _offer = null;
      _lastOffered = null;
    }
    notifyListeners();
    await store.writeEnabled(value);
  }

  /// Looks at the clipboard once. Returns a new offer, or null. Does nothing
  /// at all while the switch is off.
  Future<LinkOffer?> check() async {
    if (!_enabled) {
      return null;
    }
    checks++;
    String? text;
    try {
      text = await source.readText();
    } catch (_) {
      text = null;
    }
    final LinkOffer? found = supportedLink(text, plugins);
    text = null; // Nothing else from the clipboard is kept.
    if (found == null) {
      return null;
    }
    final String key = found.url.toString();
    if (key == _lastOffered) {
      return null;
    }
    _lastOffered = key;
    _offer = found;
    notifyListeners();
    return found;
  }

  /// The person took the offer: hand the link over once.
  LinkOffer? accept() {
    final LinkOffer? o = _offer;
    _offer = null;
    notifyListeners();
    return o;
  }

  void dismiss() {
    _offer = null;
    notifyListeners();
  }

  /// Brings back the offer just dismissed or taken (Undo).
  void restore(LinkOffer offer) {
    _offer = offer;
    notifyListeners();
  }

  static ClipboardLinkWatch? _instance;

  static ClipboardLinkWatch get instance => _instance ??= ClipboardLinkWatch(
        source: const _NoClipboard(),
        store: MemoryClipboardWatchStore(),
      );

  static void install(ClipboardLinkWatch watch) => _instance = watch;
}

class _NoClipboard implements ClipboardTextSource {
  const _NoClipboard();

  @override
  Future<String?> readText() async => null;
}
