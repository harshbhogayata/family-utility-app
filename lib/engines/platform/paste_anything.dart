import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:pasteboard/pasteboard.dart';

import 'smart_suggestions.dart';

/// Feature 105 — Paste anything.
///
/// Tap the paste box on the home screen: the app reads the clipboard once,
/// works out what is on it (a video link, a web link, a file, a picture or
/// plain text) and lists the tools that fit, the member's recent tools first.
/// The clipboard is read only on that tap, on the phone; nothing is uploaded.

enum PasteKind { videoLink, link, file, image, text, empty }

@immutable
class PastedContent {
  const PastedContent._(this.kind, {this.text, this.image, this.path, this.fileKind});

  const PastedContent.empty() : this._(PasteKind.empty);

  final PasteKind kind;

  /// The link or text, trimmed.
  final String? text;

  /// PNG or other image bytes from the clipboard.
  final Uint8List? image;

  /// A local path, for [PasteKind.file].
  final String? path;

  /// What kind of file [path] is, for [PasteKind.file].
  final SuggestKind? fileKind;
}

/// Where the clipboard comes from; the real one and a test one.
abstract class PasteSource {
  Future<String?> text();

  Future<Uint8List?> image();
}

class MemoryPasteSource implements PasteSource {
  MemoryPasteSource({this.value, this.picture});

  String? value;
  Uint8List? picture;
  int reads = 0;

  @override
  Future<String?> text() async {
    reads++;
    return value;
  }

  @override
  Future<Uint8List?> image() async => picture;
}

class SystemPasteSource implements PasteSource {
  const SystemPasteSource();

  @override
  Future<String?> text() async {
    try {
      return (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    } on PlatformException {
      return null;
    }
  }

  @override
  Future<Uint8List?> image() async {
    try {
      return await Pasteboard.image;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    } on UnimplementedError {
      return null;
    }
  }
}

abstract final class PasteAnything {
  /// Sites whose links are videos (feature 123 takes them).
  static const List<String> videoHosts = <String>[
    'youtube.com',
    'youtu.be',
    'instagram.com',
    'facebook.com',
    'fb.watch',
    'x.com',
    'twitter.com',
    'vimeo.com',
    'dailymotion.com',
    'sharechat.com',
    'mojapp.in',
    'tiktok.com',
  ];

  static const List<String> _videoExtensions = <String>['.mp4', '.mkv', '.webm', '.mov', '.m3u8'];

  /// Tool ids per kind of paste, best first. Files use feature 106's rules.
  static const Map<PasteKind, List<String>> rules = <PasteKind, List<String>>{
    PasteKind.videoLink: <String>['video-link', 'audio-link', 'download-queue', 'qr-generator'],
    PasteKind.link: <String>['web-page-pdf', 'qr-generator', 'download-queue', 'video-link'],
    PasteKind.text: <String>['text-to-pdf', 'qr-generator', 'copy-result', 'encrypt-file'],
    PasteKind.empty: <String>[],
  };

  /// Works out what [text] and [image] are. A picture wins over text (a
  /// copied photo often carries its file name as text too).
  static PastedContent classify({String? text, Uint8List? image}) {
    if (image != null && image.isNotEmpty) {
      return PastedContent._(PasteKind.image, image: image, text: text?.trim());
    }
    final String t = (text ?? '').trim();
    if (t.isEmpty) {
      return const PastedContent.empty();
    }
    final String? path = _localPath(t);
    if (path != null) {
      return PastedContent._(PasteKind.file, path: path, text: t, fileKind: SmartSuggestions.kindForName(path));
    }
    final Uri? url = _link(t);
    if (url != null) {
      return PastedContent._(isVideoLink(url) ? PasteKind.videoLink : PasteKind.link, text: url.toString());
    }
    return PastedContent._(PasteKind.text, text: t);
  }

  static bool isVideoLink(Uri url) {
    final String host = url.host.toLowerCase();
    final bool site = videoHosts.any((String d) => host == d || host.endsWith('.$d'));
    final String p = url.path.toLowerCase();
    return site || _videoExtensions.any(p.endsWith);
  }

  /// A single http(s) link, with or without the scheme (`www.site.com/x`).
  static Uri? _link(String t) {
    if (t.contains(RegExp(r'\s'))) {
      return null;
    }
    String s = t;
    if (!s.toLowerCase().startsWith('http://') && !s.toLowerCase().startsWith('https://')) {
      if (!s.toLowerCase().startsWith('www.')) {
        return null;
      }
      s = 'https://$s';
    }
    final Uri? u = Uri.tryParse(s);
    if (u == null || u.host.isEmpty || !u.host.contains('.')) {
      return null;
    }
    return u;
  }

  /// `file:///…` or an absolute path with a file extension, on one line.
  static String? _localPath(String t) {
    if (t.contains('\n')) {
      return null;
    }
    String p = t;
    if (p.toLowerCase().startsWith('file://')) {
      final Uri? u = Uri.tryParse(p);
      if (u == null) {
        return null;
      }
      p = u.toFilePath();
    }
    if (!p.startsWith('/')) {
      return null;
    }
    final String name = p.split('/').last;
    final int dot = name.lastIndexOf('.');
    if (dot <= 0 || dot == name.length - 1 || name.length - dot > 6) {
      return null;
    }
    return p;
  }

  /// Plain-words heading for what was pasted.
  static String label(PastedContent c) {
    switch (c.kind) {
      case PasteKind.videoLink:
        return 'video link';
      case PasteKind.link:
        return 'link';
      case PasteKind.file:
        return SmartSuggestions.label(c.fileKind ?? SuggestKind.other);
      case PasteKind.image:
        return 'picture';
      case PasteKind.text:
        return 'text';
      case PasteKind.empty:
        return 'nothing';
    }
  }

  /// Tools for [c], best first: the member's recent tools from the rule list
  /// move to the front (feature 106's ordering), then the rule order.
  static List<String> tools(
    PastedContent c, {
    List<String> history = const <String>[],
    Set<String>? available,
    int limit = 6,
  }) {
    switch (c.kind) {
      case PasteKind.image:
        return SmartSuggestions.suggest(SuggestKind.image, history: history, available: available, limit: limit);
      case PasteKind.file:
        return SmartSuggestions.suggest(c.fileKind ?? SuggestKind.other,
            history: history, available: available, limit: limit);
      case PasteKind.videoLink:
      case PasteKind.link:
      case PasteKind.text:
      case PasteKind.empty:
        break;
    }
    final List<String> rule = rules[c.kind] ?? const <String>[];
    bool ok(String id) => available == null || available.contains(id);
    final Set<String> inRule = rule.toSet();
    final List<String> out = <String>[];
    for (final String id in history) {
      if (inRule.contains(id) && ok(id) && !out.contains(id)) {
        out.add(id);
      }
    }
    for (final String id in rule) {
      if (ok(id) && !out.contains(id)) {
        out.add(id);
      }
    }
    return out.length > limit ? out.sublist(0, limit) : out;
  }

  /// Reads [source] once and classifies it.
  static Future<PastedContent> read(PasteSource source) async {
    final Uint8List? picture = await source.image();
    final String? text = await source.text();
    return classify(text: text, image: picture);
  }

  /// The clipboard the home screen reads; tests swap in a memory one.
  static PasteSource source = const SystemPasteSource();
}
