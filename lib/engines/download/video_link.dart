import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'download_queue.dart';

/// Feature 123 — Download video from a link.
///
/// The person pastes or shares a link to a public post (Instagram, YouTube,
/// Facebook, X, Pinterest, Threads, or any page that offers its video). One
/// extractor plugin per site reads the public page the link points to and
/// lists the video files it offers; the person picks a quality and the file
/// goes into the download queue (127) and lands in the folder they chose.
///
/// Extractors are isolated: each runs inside its own guard with a time limit,
/// so a site that changed its page (or a plugin that crashes) only fails that
/// one link, and the generic page reader still gets a turn. Nothing of the
/// person's is uploaded; the only requests are GETs for the link itself.
/// Videos the site protects are reported as such, never worked around.

/// A link this tool cannot use, or a video it cannot find.
class VideoLinkError implements Exception {
  const VideoLinkError(this.message);

  final String message;

  @override
  String toString() => message;
}

/// One downloadable file a page offers.
class VideoFormat {
  const VideoFormat({
    required this.url,
    this.width,
    this.height,
    this.bitrate,
    this.ext = 'mp4',
    this.hasAudio = true,
  });

  final Uri url;
  final int? width;
  final int? height;
  final int? bitrate;
  final String ext;
  final bool hasAudio;

  /// The shorter side, which is what people call 720p or 1080p.
  int? get lines {
    final int? w = width;
    final int? h = height;
    if (w != null && h != null) {
      return w < h ? w : h;
    }
    return h ?? w;
  }

  String get label {
    final int? l = lines;
    final String q = l == null ? 'Best available' : '${l}p';
    return hasAudio ? q : '$q (no sound)';
  }

  @override
  String toString() => '$label $url';
}

/// What a link resolved to.
class VideoLink {
  VideoLink({required this.page, required this.site, required this.title, required List<VideoFormat> formats})
      : formats = sortFormats(formats);

  final Uri page;

  /// Id of the extractor that found the video.
  final String site;
  final String title;

  /// Best first.
  final List<VideoFormat> formats;

  VideoFormat get best => formats.first;
}

/// Highest quality first, files with sound before silent ones; duplicates
/// (same URL) dropped.
List<VideoFormat> sortFormats(List<VideoFormat> input) {
  final Set<String> seen = <String>{};
  final List<VideoFormat> out = <VideoFormat>[];
  for (final VideoFormat f in input) {
    if (seen.add(f.url.toString())) {
      out.add(f);
    }
  }
  out.sort((VideoFormat a, VideoFormat b) {
    if (a.hasAudio != b.hasAudio) {
      return a.hasAudio ? -1 : 1;
    }
    final int c = (b.lines ?? 0).compareTo(a.lines ?? 0);
    if (c != 0) {
      return c;
    }
    return (b.bitrate ?? 0).compareTo(a.bitrate ?? 0);
  });
  return out;
}

/// Reads a public page as text.
abstract class PageFetcher {
  Future<String> getText(Uri url);
}

/// The phone's own HTTP stack. Pages above 6 MB are cut off.
class HttpPageFetcher implements PageFetcher {
  HttpPageFetcher({HttpClient? client}) : _client = client ?? HttpClient() {
    _client.connectionTimeout = const Duration(seconds: 20);
  }

  final HttpClient _client;
  static const int maxBytes = 6 * 1024 * 1024;

  @override
  Future<String> getText(Uri url) async {
    try {
      final HttpClientRequest req = await _client.getUrl(url);
      req.headers.set(HttpHeaders.userAgentHeader, 'Mozilla/5.0 (Linux; Android 14) FamilyUtility/0.1');
      req.headers.set(HttpHeaders.acceptHeader, 'text/html,application/xhtml+xml');
      final HttpClientResponse res = await req.close();
      if (res.statusCode >= 400) {
        await res.drain<void>();
        throw VideoLinkError('The site answered ${res.statusCode}. The post may be private or removed.');
      }
      final List<int> bytes = <int>[];
      await for (final List<int> chunk in res) {
        bytes.addAll(chunk);
        if (bytes.length > maxBytes) {
          break;
        }
      }
      return utf8.decode(bytes, allowMalformed: true);
    } on SocketException catch (e) {
      throw VideoLinkError(e.message.isEmpty ? 'No connection' : 'No connection: ${e.message}');
    } on HttpException catch (e) {
      throw VideoLinkError(e.message);
    } on HandshakeException {
      throw const VideoLinkError('Could not make a secure connection to the site');
    }
  }
}

/// One site's extractor. Plugins never touch files or the queue; they only
/// turn a page into a list of formats.
abstract class VideoExtractor {
  /// Short id, e.g. `instagram`.
  String get id;

  /// Name shown to people, e.g. `Instagram`.
  String get label;

  bool handles(Uri url);

  Future<VideoLink> extract(Uri url, PageFetcher pages);
}

/// The first http(s) link inside shared text such as
/// "Look at this https://www.instagram.com/reel/abc/ !".
Uri? findLink(String text) {
  final RegExpMatch? m = RegExp(r'''https?://[^\s<>"']+''').firstMatch(text);
  if (m == null) {
    return null;
  }
  String s = m.group(0)!;
  while (s.isNotEmpty && '.,;:!?)]}'.contains(s[s.length - 1])) {
    s = s.substring(0, s.length - 1);
  }
  final Uri? u = Uri.tryParse(s);
  if (u == null || u.host.isEmpty) {
    return null;
  }
  return u;
}

bool hostIs(Uri url, List<String> domains) {
  final String h = url.host.toLowerCase();
  for (final String d in domains) {
    if (h == d || h.endsWith('.$d')) {
      return true;
    }
  }
  return false;
}

/// HTML attribute text to plain text.
String decodeHtml(String s) {
  return s
      .replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'), (Match m) => String.fromCharCode(int.parse(m.group(1)!, radix: 16)))
      .replaceAllMapped(RegExp(r'&#(\d+);'), (Match m) => String.fromCharCode(int.parse(m.group(1)!)))
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&amp;', '&');
}

/// A string as it appears inside JSON in a page (`\/`, `&`) to plain text.
String decodeJsonString(String s) {
  try {
    final Object? v = jsonDecode('"$s"');
    if (v is String) {
      return v;
    }
  } catch (_) {
    // Not valid JSON text; fall back to the common escapes.
  }
  return s.replaceAll(r'\/', '/').replaceAll(r'&', '&').replaceAll(r'=', '=');
}

/// Every `<meta property|name="key" content="...">` value, in page order.
List<String> metaValues(String html, String key) {
  final List<String> out = <String>[];
  final RegExp tag = RegExp(r'<meta\b[^>]*>', caseSensitive: false);
  final RegExp keyAttr = RegExp(r'''(?:property|name)\s*=\s*["']([^"']+)["']''', caseSensitive: false);
  final RegExp contentAttr = RegExp(r'''content\s*=\s*(?:"([^"]*)"|'([^']*)')''', caseSensitive: false);
  for (final RegExpMatch m in tag.allMatches(html)) {
    final String t = m.group(0)!;
    final RegExpMatch? k = keyAttr.firstMatch(t);
    if (k == null || k.group(1)!.toLowerCase() != key.toLowerCase()) {
      continue;
    }
    final RegExpMatch? c = contentAttr.firstMatch(t);
    if (c != null) {
      out.add(decodeHtml(c.group(1) ?? c.group(2) ?? ''));
    }
  }
  return out;
}

String? metaValue(String html, String key) {
  final List<String> v = metaValues(html, key);
  return v.isEmpty ? null : v.first;
}

int? _int(String? s) => s == null ? null : int.tryParse(s.trim());

String _ext(Uri u, {String fallback = 'mp4'}) {
  final String p = u.path.toLowerCase();
  for (final String e in <String>['mp4', 'webm', 'mov', 'm4v', '3gp']) {
    if (p.endsWith('.$e')) {
      return e;
    }
  }
  return fallback;
}

Uri? _httpUri(String s) {
  final Uri? u = Uri.tryParse(s.trim());
  if (u == null || !(u.scheme == 'http' || u.scheme == 'https') || u.host.isEmpty) {
    return null;
  }
  return u;
}

/// The title a page gives itself (Open Graph first).
String pageTitle(String html, {String fallback = 'video'}) {
  final String? og = metaValue(html, 'og:title') ?? metaValue(html, 'twitter:title');
  if (og != null && og.trim().isNotEmpty) {
    return og.trim();
  }
  final RegExpMatch? t = RegExp(r'<title[^>]*>([^<]*)</title>', caseSensitive: false).firstMatch(html);
  final String s = t == null ? '' : decodeHtml(t.group(1)!).trim();
  return s.isEmpty ? fallback : s;
}

/// Video files announced in Open Graph / Twitter card tags and JSON-LD.
List<VideoFormat> openGraphFormats(String html) {
  final List<VideoFormat> out = <VideoFormat>[];
  final int? w = _int(metaValue(html, 'og:video:width'));
  final int? h = _int(metaValue(html, 'og:video:height'));
  for (final String key in <String>['og:video:secure_url', 'og:video:url', 'og:video', 'twitter:player:stream']) {
    for (final String v in metaValues(html, key)) {
      final Uri? u = _httpUri(v);
      if (u != null) {
        out.add(VideoFormat(url: u, width: w, height: h, ext: _ext(u)));
      }
    }
  }
  for (final RegExpMatch m in RegExp(r'"contentUrl"\s*:\s*"([^"]+)"').allMatches(html)) {
    final Uri? u = _httpUri(decodeJsonString(m.group(1)!));
    if (u != null && _ext(u, fallback: '') != '') {
      out.add(VideoFormat(url: u, width: w, height: h, ext: _ext(u)));
    }
  }
  return out;
}

/// `"video_versions":[{"width":720,"height":1280,"url":"..."}]` as used by
/// Instagram and Threads pages, plus the older `"video_url":"..."`.
List<VideoFormat> videoVersionFormats(String html) {
  final List<VideoFormat> out = <VideoFormat>[];
  final RegExp obj = RegExp(r'\{[^{}]*"url"\s*:\s*"([^"]+)"[^{}]*\}');
  for (final RegExpMatch block in RegExp(r'"video_versions"\s*:\s*\[([^\]]*)\]').allMatches(html)) {
    for (final RegExpMatch m in obj.allMatches(block.group(1)!)) {
      final String o = m.group(0)!;
      final Uri? u = _httpUri(decodeJsonString(m.group(1)!));
      if (u == null) {
        continue;
      }
      out.add(VideoFormat(
        url: u,
        width: _int(RegExp(r'"width"\s*:\s*(\d+)').firstMatch(o)?.group(1)),
        height: _int(RegExp(r'"height"\s*:\s*(\d+)').firstMatch(o)?.group(1)),
        ext: _ext(u),
      ));
    }
  }
  for (final RegExpMatch m in RegExp(r'"video_url"\s*:\s*"([^"]+)"').allMatches(html)) {
    final Uri? u = _httpUri(decodeJsonString(m.group(1)!));
    if (u != null) {
      out.add(VideoFormat(url: u, ext: _ext(u)));
    }
  }
  return out;
}

VideoLink _found(Uri url, String site, String html, List<VideoFormat> formats) {
  if (formats.isEmpty) {
    throw const VideoLinkError('No video found at this link. The post may be private, a photo, or need a login.');
  }
  return VideoLink(page: url, site: site, title: pageTitle(html), formats: formats);
}

class InstagramExtractor implements VideoExtractor {
  const InstagramExtractor();

  @override
  String get id => 'instagram';

  @override
  String get label => 'Instagram';

  @override
  bool handles(Uri url) => hostIs(url, <String>['instagram.com', 'instagr.am']);

  @override
  Future<VideoLink> extract(Uri url, PageFetcher pages) async {
    final String html = await pages.getText(url);
    return _found(url, id, html, <VideoFormat>[...videoVersionFormats(html), ...openGraphFormats(html)]);
  }
}

class ThreadsExtractor implements VideoExtractor {
  const ThreadsExtractor();

  @override
  String get id => 'threads';

  @override
  String get label => 'Threads';

  @override
  bool handles(Uri url) => hostIs(url, <String>['threads.net', 'threads.com']);

  @override
  Future<VideoLink> extract(Uri url, PageFetcher pages) async {
    final String html = await pages.getText(url);
    return _found(url, id, html, <VideoFormat>[...videoVersionFormats(html), ...openGraphFormats(html)]);
  }
}

class FacebookExtractor implements VideoExtractor {
  const FacebookExtractor();

  @override
  String get id => 'facebook';

  @override
  String get label => 'Facebook';

  @override
  bool handles(Uri url) => hostIs(url, <String>['facebook.com', 'fb.watch', 'fb.com']);

  @override
  Future<VideoLink> extract(Uri url, PageFetcher pages) async {
    final String html = await pages.getText(url);
    final List<VideoFormat> out = <VideoFormat>[];
    void add(String key, int? lines) {
      for (final RegExpMatch m in RegExp('"$key"\\s*:\\s*"([^"]+)"').allMatches(html)) {
        final Uri? u = _httpUri(decodeJsonString(m.group(1)!));
        if (u != null) {
          out.add(VideoFormat(url: u, height: lines, ext: _ext(u)));
        }
      }
    }

    add('browser_native_hd_url', 720);
    add('playable_url_quality_hd', 720);
    add('hd_src', 720);
    add('browser_native_sd_url', 360);
    add('playable_url', 360);
    add('sd_src', 360);
    out.addAll(openGraphFormats(html));
    return _found(url, id, html, out);
  }
}

class XExtractor implements VideoExtractor {
  const XExtractor();

  @override
  String get id => 'x';

  @override
  String get label => 'X';

  @override
  bool handles(Uri url) => hostIs(url, <String>['x.com', 'twitter.com']);

  @override
  Future<VideoLink> extract(Uri url, PageFetcher pages) async {
    final String html = await pages.getText(url);
    final List<VideoFormat> out = <VideoFormat>[];
    // Variant URLs carry their size: .../vid/720x1280/....mp4
    final RegExp variant = RegExp(r'"url"\s*:\s*"(https?:[^"]+?\.mp4[^"]*)"');
    for (final RegExpMatch m in variant.allMatches(html)) {
      final Uri? u = _httpUri(decodeJsonString(m.group(1)!));
      if (u == null || !u.host.contains('video')) {
        continue;
      }
      final RegExpMatch? size = RegExp(r'/(\d+)x(\d+)/').firstMatch(u.path);
      out.add(VideoFormat(url: u, width: _int(size?.group(1)), height: _int(size?.group(2))));
    }
    out.addAll(openGraphFormats(html));
    return _found(url, id, html, out);
  }
}

class PinterestExtractor implements VideoExtractor {
  const PinterestExtractor();

  @override
  String get id => 'pinterest';

  @override
  String get label => 'Pinterest';

  @override
  bool handles(Uri url) => hostIs(url, <String>['pinterest.com', 'pin.it']) || url.host.contains('pinterest.');

  @override
  Future<VideoLink> extract(Uri url, PageFetcher pages) async {
    final String html = await pages.getText(url);
    final List<VideoFormat> out = <VideoFormat>[];
    final RegExp v = RegExp(r'"V_(\d+)P\w*"\s*:\s*\{[^{}]*?"url"\s*:\s*"([^"]+)"');
    for (final RegExpMatch m in v.allMatches(html)) {
      final Uri? u = _httpUri(decodeJsonString(m.group(2)!));
      if (u != null && _ext(u, fallback: '') != '') {
        out.add(VideoFormat(url: u, height: _int(m.group(1)), ext: _ext(u)));
      }
    }
    out.addAll(openGraphFormats(html).where((VideoFormat f) => _ext(f.url, fallback: '') != ''));
    return _found(url, id, html, out);
  }
}

/// YouTube and Shorts. Only files the page offers openly (a plain `url`) are
/// listed; videos whose links are scrambled or protected are reported as
/// unavailable rather than worked around.
class YouTubeExtractor implements VideoExtractor {
  const YouTubeExtractor();

  @override
  String get id => 'youtube';

  @override
  String get label => 'YouTube';

  @override
  bool handles(Uri url) => hostIs(url, <String>['youtube.com', 'youtu.be', 'youtube-nocookie.com']);

  /// The 11-character video id from watch, Shorts, youtu.be and embed links.
  static String? videoId(Uri url) {
    final RegExp idPattern = RegExp(r'^[A-Za-z0-9_-]{11}$');
    String? id;
    if (hostIs(url, <String>['youtu.be'])) {
      id = url.pathSegments.isEmpty ? null : url.pathSegments.first;
    } else if (url.queryParameters['v'] != null) {
      id = url.queryParameters['v'];
    } else {
      final List<String> seg = url.pathSegments;
      for (int i = 0; i + 1 < seg.length; i++) {
        if (seg[i] == 'shorts' || seg[i] == 'embed' || seg[i] == 'live' || seg[i] == 'v') {
          id = seg[i + 1];
        }
      }
    }
    return id != null && idPattern.hasMatch(id) ? id : null;
  }

  /// The JSON object assigned to `ytInitialPlayerResponse`, or null.
  static Map<String, Object?>? playerResponse(String html) {
    final int at = html.indexOf('ytInitialPlayerResponse');
    if (at < 0) {
      return null;
    }
    final int start = html.indexOf('{', at);
    if (start < 0) {
      return null;
    }
    int depth = 0;
    bool inString = false;
    bool escaped = false;
    for (int i = start; i < html.length; i++) {
      final String c = html[i];
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (c == r'\') {
          escaped = true;
        } else if (c == '"') {
          inString = false;
        }
        continue;
      }
      if (c == '"') {
        inString = true;
      } else if (c == '{') {
        depth++;
      } else if (c == '}') {
        depth--;
        if (depth == 0) {
          try {
            final Object? v = jsonDecode(html.substring(start, i + 1));
            return v is Map<String, Object?> ? v : null;
          } catch (_) {
            return null;
          }
        }
      }
    }
    return null;
  }

  @override
  Future<VideoLink> extract(Uri url, PageFetcher pages) async {
    final String? id = videoId(url);
    if (id == null) {
      throw const VideoLinkError('This YouTube link does not point at a video');
    }
    final Uri page = Uri.https('www.youtube.com', '/watch', <String, String>{'v': id});
    final String html = await pages.getText(page);
    final Map<String, Object?>? player = playerResponse(html);
    String title = pageTitle(html);
    final Object? details = player?['videoDetails'];
    if (details is Map<String, Object?> && details['title'] is String) {
      title = details['title']! as String;
    }
    final Object? streaming = player?['streamingData'];
    final List<VideoFormat> out = <VideoFormat>[];
    bool protectedOnly = false;
    if (streaming is Map<String, Object?>) {
      final Object? formats = streaming['formats'];
      if (formats is List<Object?>) {
        for (final Object? f in formats) {
          if (f is! Map<String, Object?>) {
            continue;
          }
          final Object? raw = f['url'];
          if (raw is! String) {
            protectedOnly = true;
            continue;
          }
          final Uri? u = _httpUri(raw);
          if (u == null) {
            continue;
          }
          final Object? mime = f['mimeType'];
          out.add(VideoFormat(
            url: u,
            width: f['width'] is int ? f['width']! as int : null,
            height: f['height'] is int ? f['height']! as int : null,
            bitrate: f['bitrate'] is int ? f['bitrate']! as int : null,
            ext: mime is String && mime.contains('webm') ? 'webm' : 'mp4',
          ));
        }
      }
    }
    if (out.isEmpty) {
      throw VideoLinkError(protectedOnly
          ? 'YouTube protects this video, so it cannot be saved here.'
          : 'No video found at this link. It may be private, age-restricted or removed.');
    }
    return VideoLink(page: page, site: this.id, title: title, formats: out);
  }
}

/// Any other page: a direct link to a video file, or a page that announces
/// its video in Open Graph tags. Also the fallback when a site plugin fails.
class GenericExtractor implements VideoExtractor {
  const GenericExtractor();

  @override
  String get id => 'generic';

  @override
  String get label => 'Web page';

  @override
  bool handles(Uri url) => true;

  @override
  Future<VideoLink> extract(Uri url, PageFetcher pages) async {
    final String ext = _ext(url, fallback: '');
    if (ext.isNotEmpty) {
      final String name = nameFromUrl(url);
      final int dot = name.lastIndexOf('.');
      return VideoLink(
        page: url,
        site: id,
        title: dot > 0 ? name.substring(0, dot) : name,
        formats: <VideoFormat>[VideoFormat(url: url, ext: ext)],
      );
    }
    final String html = await pages.getText(url);
    return _found(url, id, html, openGraphFormats(html));
  }
}

/// One plugin's failure while resolving a link.
class ExtractorFailure {
  const ExtractorFailure(this.extractor, this.message);

  final String extractor;
  final String message;

  @override
  String toString() => '$extractor: $message';
}

/// Holds the plugins and runs them one at a time, each inside its own guard.
class VideoExtractorRegistry {
  VideoExtractorRegistry({
    List<VideoExtractor>? plugins,
    this.fallback = const GenericExtractor(),
    this.timeout = const Duration(seconds: 30),
  }) : plugins = plugins ?? defaultPlugins();

  static List<VideoExtractor> defaultPlugins() => const <VideoExtractor>[
        InstagramExtractor(),
        YouTubeExtractor(),
        FacebookExtractor(),
        XExtractor(),
        PinterestExtractor(),
        ThreadsExtractor(),
      ];

  final List<VideoExtractor> plugins;
  final VideoExtractor? fallback;
  final Duration timeout;

  /// Plugins switched off (by id), e.g. after a site broke.
  final Set<String> disabled = <String>{};

  /// What went wrong on the last [resolve], one line per plugin tried.
  final List<ExtractorFailure> lastFailures = <ExtractorFailure>[];

  List<VideoExtractor> candidates(Uri url) {
    final List<VideoExtractor> out = <VideoExtractor>[];
    for (final VideoExtractor p in plugins) {
      bool match = false;
      try {
        match = !disabled.contains(p.id) && p.handles(url);
      } catch (_) {
        match = false; // A broken plugin cannot claim links.
      }
      if (match) {
        out.add(p);
      }
    }
    final VideoExtractor? f = fallback;
    if (f != null && !disabled.contains(f.id)) {
      out.add(f);
    }
    return out;
  }

  /// Tries the site's plugin, then the generic reader. Every error, crash or
  /// hang inside a plugin is caught and recorded; it never reaches the others.
  Future<VideoLink> resolve(Uri url, PageFetcher pages) async {
    lastFailures.clear();
    final List<VideoExtractor> list = candidates(url);
    for (final VideoExtractor p in list) {
      try {
        final VideoLink link = await Future<VideoLink>.sync(() => p.extract(url, pages)).timeout(timeout);
        if (link.formats.isNotEmpty) {
          return link;
        }
        lastFailures.add(ExtractorFailure(p.id, 'no video found'));
      } on VideoLinkError catch (e) {
        lastFailures.add(ExtractorFailure(p.id, e.message));
      } on TimeoutException {
        lastFailures.add(ExtractorFailure(p.id, 'the site took too long'));
      } catch (e) {
        // A plugin bug (TypeError, RangeError, ...) only fails this plugin.
        lastFailures.add(ExtractorFailure(p.id, 'stopped working ($e)'));
      }
    }
    if (lastFailures.isEmpty) {
      throw const VideoLinkError('No reader for this link');
    }
    // The site's own message is more useful than the generic reader's.
    throw VideoLinkError(lastFailures.first.message);
  }
}

/// Where "the personal-use notice was shown" is remembered.
abstract class NoticeStore {
  Future<bool> read();

  Future<void> write(bool shown);
}

class MemoryNoticeStore implements NoticeStore {
  MemoryNoticeStore({this.shown = false});

  bool shown;

  @override
  Future<bool> read() async => shown;

  @override
  Future<void> write(bool value) async => shown = value;
}

/// Glue between a pasted link, the plugins and the download queue.
class VideoLinkDownloader {
  VideoLinkDownloader({
    required this.pages,
    required this.notice,
    VideoExtractorRegistry? registry,
    this.blockedReason,
  }) : registry = registry ?? VideoExtractorRegistry();

  static const String personalUseNotice =
      'Save only videos you made, have permission to keep, or that the site lets you download. '
      'Saved videos are for personal use: respect the creator and the site\'s terms. '
      'The app reads the public page only; nothing of yours is uploaded.';

  final PageFetcher pages;
  final NoticeStore notice;
  final VideoExtractorRegistry registry;

  /// Why the network may not be used now (on-device mode), or null.
  final String? Function()? blockedReason;

  /// True until the person has seen the notice once.
  Future<bool> needsNotice() async {
    try {
      return !await notice.read();
    } catch (_) {
      return true;
    }
  }

  Future<void> noticeSeen() => notice.write(true);

  /// Finds the video behind a pasted or shared text.
  Future<VideoLink> resolve(String text) async {
    final Uri? url = findLink(text);
    if (url == null) {
      throw const VideoLinkError('Paste a link that starts with http:// or https://');
    }
    final String? why = blockedReason?.call();
    if (why != null) {
      throw VideoLinkError(why);
    }
    return registry.resolve(url, pages);
  }

  /// A file name from the title and quality, e.g. `Sunset at the beach 720p.mp4`.
  static String fileName(VideoLink link, VideoFormat format) {
    String base = link.title.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f#%]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    if (base.length > 80) {
      base = base.substring(0, 80).trim();
    }
    if (base.isEmpty) {
      base = '${link.site} video';
    }
    final int? l = format.lines;
    return l == null ? '$base.${format.ext}' : '$base ${l}p.${format.ext}';
  }

  /// Puts the chosen file in the download queue, which saves it into the
  /// queue's folder (the one the person chose).
  Future<DownloadTask> save(DownloadQueue queue, VideoLink link, VideoFormat format) {
    return queue.add(format.url.toString(), name: fileName(link, format));
  }
}

/// App-wide instance; bootstrap installs the real one.
abstract final class VideoLinks {
  static VideoLinkDownloader? _instance;

  static VideoLinkDownloader get instance =>
      _instance ??= VideoLinkDownloader(pages: HttpPageFetcher(), notice: MemoryNoticeStore());

  static void install(VideoLinkDownloader d) => _instance = d;
}
