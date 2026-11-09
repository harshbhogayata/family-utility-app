import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import 'text_to_pdf.dart';

/// Feature 023 — Web page to PDF: paste a URL and get a clean PDF.
///
/// The page is fetched by a [WebPageSource] (the network part lives in
/// `lib/engines/download/`, the only place allowed to talk to servers).
/// Everything after that happens on the phone: the HTML is parsed here,
/// either down to the article (reader mode) or with all of its visible text
/// (full page), laid out by the phone's own text engine and written as a PDF
/// by [TextToPdf.writePdf]. Nothing the person has is uploaded; the only
/// request is the GET for the page itself, with no cookies, so pages that
/// need a login are reported as such instead of being saved half-empty.

enum WebPdfMode {
  reader('Reader', 'Just the article: no menus, ads or footers'),
  fullPage('Full page', 'All the text on the page, menus and footers too');

  const WebPdfMode(this.label, this.hint);
  final String label;
  final String hint;
}

class WebPdfError implements Exception {
  const WebPdfError(this.message);
  final String message;

  @override
  String toString() => message;
}

/// What the network side hands back.
class FetchedWebPage {
  const FetchedWebPage({required this.url, required this.html, this.statusCode = 200, this.contentType = 'text/html'});

  /// Where the page ended up after redirects.
  final Uri url;
  final String html;
  final int statusCode;
  final String contentType;
}

/// Fetches one public page. Behind an interface for tests.
abstract class WebPageSource {
  Future<FetchedWebPage> fetch(Uri url);
}

/// Turns what the person typed into an http(s) URL, or explains why not.
abstract final class WebPageUrl {
  static Uri parse(String input) {
    String s = input.trim();
    if (s.isEmpty) {
      throw const WebPdfError('Paste a web address first.');
    }
    // A shared message often has text around the link; take the first URL.
    final RegExpMatch? inText = RegExp(r'https?://\S+', caseSensitive: false).firstMatch(s);
    if (inText != null) {
      s = inText.group(0)!;
    } else if (s.contains(' ')) {
      throw const WebPdfError('That does not look like a web address.');
    }
    if (!RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://').hasMatch(s)) {
      s = 'https://$s';
    }
    final Uri? u = Uri.tryParse(s);
    if (u == null || (u.scheme != 'http' && u.scheme != 'https')) {
      throw const WebPdfError('Only http and https web addresses work.');
    }
    if (u.host.isEmpty || (!u.host.contains('.') && u.host != 'localhost')) {
      throw const WebPdfError('That does not look like a web address.');
    }
    return u;
  }
}

enum WebBlockKind { heading, paragraph, listItem, quote, code }

/// One block of readable text.
class WebBlock {
  const WebBlock(this.kind, this.text, {this.level = 0});
  final WebBlockKind kind;
  final String text;

  /// 1–6 for headings.
  final int level;

  @override
  bool operator ==(Object other) => other is WebBlock && other.kind == kind && other.text == text && other.level == level;

  @override
  int get hashCode => Object.hash(kind, text, level);

  @override
  String toString() => 'WebBlock($kind${level > 0 ? ' h$level' : ''}, "$text")';
}

/// A page boiled down to its readable text.
class WebArticle {
  const WebArticle({required this.title, required this.url, required this.blocks});
  final String title;
  final Uri url;
  final List<WebBlock> blocks;

  int get wordCount {
    int n = 0;
    for (final WebBlock b in blocks) {
      n += b.text.split(RegExp(r'\s+')).where((String w) => w.isNotEmpty).length;
    }
    return n;
  }
}

/// A small, forgiving HTML tree. Good enough to read text from real pages;
/// it never runs scripts.
class HtmlNode {
  HtmlNode(this.tag, [Map<String, String>? attrs]) : attrs = attrs ?? <String, String>{};

  /// Lower-case tag name; '#text' for text.
  final String tag;
  final Map<String, String> attrs;
  final List<HtmlNode> children = <HtmlNode>[];
  HtmlNode? parent;
  String text = '';

  bool get isText => tag == '#text';

  Iterable<HtmlNode> get descendants sync* {
    for (final HtmlNode c in children) {
      yield c;
      yield* c.descendants;
    }
  }

  String get allText {
    if (isText) {
      return text;
    }
    final StringBuffer b = StringBuffer();
    for (final HtmlNode d in descendants) {
      if (d.isText) {
        b
          ..write(d.text)
          ..write(' ');
      }
    }
    return b.toString();
  }
}

abstract final class HtmlText {
  static const Set<String> _void = <String>{
    'area', 'base', 'br', 'col', 'embed', 'hr', 'img', 'input', 'link', 'meta', 'param', 'source', 'track', 'wbr',
  };

  /// Elements whose content is never shown as text.
  static const Set<String> _hidden = <String>{
    'script', 'style', 'noscript', 'template', 'svg', 'math', 'head', 'title', 'canvas', 'object', 'iframe', 'select',
    'textarea', 'video', 'audio', 'picture', 'map',
  };

  /// Raw-text elements: their content is skipped without parsing.
  static const Set<String> _raw = <String>{'script', 'style', 'textarea', 'title', 'noscript', 'template', 'svg', 'math'};

  /// Page chrome left out in reader mode.
  static const Set<String> _chrome = <String>{'nav', 'footer', 'aside', 'form', 'button', 'dialog', 'menu', 'figure'};

  static final RegExp _chromeHint = RegExp(
    r'(^|[\s_-])(nav|navbar|menu|footer|sidebar|side-bar|comments?|cookie|consent|share|sharing|social|advert|ads?|sponsor|promo|related|recommended|breadcrumbs?|banner|popup|modal|newsletter|subscribe|signup|skip|masthead|toolbar)([\s_-]|$)',
    caseSensitive: false,
  );

  static const Set<String> _block = <String>{
    'p', 'div', 'section', 'article', 'main', 'header', 'footer', 'nav', 'aside', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6',
    'ul', 'ol', 'li', 'dl', 'dt', 'dd', 'blockquote', 'pre', 'table', 'thead', 'tbody', 'tfoot', 'tr', 'td', 'th',
    'figure', 'figcaption', 'form', 'fieldset', 'address', 'details', 'summary', 'hr', 'br', 'body', 'html', 'caption',
  };

  /// Closing these is implied by opening one of the listed tags.
  static const Map<String, Set<String>> _impliedEnd = <String, Set<String>>{
    'p': <String>{
      'p', 'div', 'section', 'article', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'ul', 'ol', 'blockquote', 'pre', 'table',
      'header', 'footer', 'nav', 'aside', 'form', 'figure', 'hr', 'dl', 'main', 'address', 'details',
    },
    'li': <String>{'li'},
    'dt': <String>{'dt', 'dd'},
    'dd': <String>{'dt', 'dd'},
    'tr': <String>{'tr'},
    'td': <String>{'td', 'th', 'tr'},
    'th': <String>{'td', 'th', 'tr'},
    'option': <String>{'option'},
  };

  static const Map<String, String> _entities = <String, String>{
    'amp': '&', 'lt': '<', 'gt': '>', 'quot': '"', 'apos': "'", 'nbsp': ' ', 'ndash': '–', 'mdash': '—',
    'hellip': '…', 'lsquo': '‘', 'rsquo': '’', 'ldquo': '“', 'rdquo': '”', 'copy': '©', 'reg': '®', 'trade': '™',
    'bull': '•', 'middot': '·', 'laquo': '«', 'raquo': '»', 'deg': '°', 'times': '×', 'rupee': '₹', 'euro': '€',
    'pound': '£', 'shy': '', 'zwj': '‍', 'zwnj': '‌', 'thinsp': ' ', 'ensp': ' ', 'emsp': ' ',
  };

  /// Decodes `&amp;`, `&#8377;`, `&#x20B9;` and the common named entities.
  static String decode(String s) {
    if (!s.contains('&')) {
      return s;
    }
    return s.replaceAllMapped(RegExp(r'&(#[xX][0-9a-fA-F]{1,6}|#[0-9]{1,7}|[a-zA-Z]{2,8});'), (Match m) {
      final String e = m.group(1)!;
      if (e.startsWith('#')) {
        final bool hex = e.length > 1 && (e[1] == 'x' || e[1] == 'X');
        final int? code = int.tryParse(hex ? e.substring(2) : e.substring(1), radix: hex ? 16 : 10);
        if (code == null || code <= 0 || code > 0x10FFFF || (code >= 0xD800 && code <= 0xDFFF)) {
          return m.group(0)!;
        }
        return code == 0xA0 ? ' ' : String.fromCharCode(code);
      }
      return _entities[e.toLowerCase()] ?? m.group(0)!;
    });
  }

  static final RegExp _attr = RegExp(r'''([^\s=/>"']+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+)))?''');

  /// Parses [html] into a tree rooted at a synthetic `#document` node.
  static HtmlNode parse(String html) {
    final HtmlNode doc = HtmlNode('#document');
    HtmlNode cur = doc;
    int i = 0;
    final int n = html.length;

    void addText(String raw) {
      if (raw.isEmpty) {
        return;
      }
      final HtmlNode t = HtmlNode('#text')..text = decode(raw);
      t.parent = cur;
      cur.children.add(t);
    }

    bool hasOpen(String tag) {
      for (HtmlNode? p = cur; p != null; p = p.parent) {
        if (p.tag == tag) {
          return true;
        }
      }
      return false;
    }

    void closeTo(String tag) {
      for (HtmlNode? p = cur; p != null; p = p.parent) {
        if (p.tag == tag) {
          cur = p.parent ?? doc;
          return;
        }
      }
    }

    while (i < n) {
      final int lt = html.indexOf('<', i);
      if (lt < 0) {
        addText(html.substring(i));
        break;
      }
      if (lt > i) {
        addText(html.substring(i, lt));
      }
      if (html.startsWith('<!--', lt)) {
        final int end = html.indexOf('-->', lt + 4);
        i = end < 0 ? n : end + 3;
        continue;
      }
      if (lt + 1 < n && (html[lt + 1] == '!' || html[lt + 1] == '?')) {
        final int end = html.indexOf('>', lt);
        i = end < 0 ? n : end + 1;
        continue;
      }
      final bool closing = lt + 1 < n && html[lt + 1] == '/';
      final int nameStart = closing ? lt + 2 : lt + 1;
      final RegExpMatch? name = RegExp(r'[a-zA-Z][a-zA-Z0-9:-]*').matchAsPrefix(html, nameStart);
      if (name == null) {
        addText('<');
        i = lt + 1;
        continue;
      }
      final int gt = _tagEnd(html, name.end);
      final String tag = name.group(0)!.toLowerCase();
      final String inside = html.substring(name.end, gt < 0 ? n : gt);
      i = gt < 0 ? n : gt + 1;
      if (closing) {
        if (hasOpen(tag)) {
          closeTo(tag);
        }
        continue;
      }
      // Implied ends: <p> before a block, <li> before the next <li>.
      for (int guard = 0; guard < 8; guard++) {
        final Set<String>? ends = _impliedEnd[cur.tag];
        if (ends != null && ends.contains(tag)) {
          cur = cur.parent ?? doc;
        } else {
          break;
        }
      }
      final Map<String, String> attrs = <String, String>{};
      for (final RegExpMatch a in _attr.allMatches(inside)) {
        final String key = a.group(1)!.toLowerCase();
        attrs[key] = decode(a.group(2) ?? a.group(3) ?? a.group(4) ?? '');
      }
      final HtmlNode el = HtmlNode(tag, attrs)..parent = cur;
      cur.children.add(el);
      final bool selfClosed = inside.trimRight().endsWith('/');
      if (_raw.contains(tag)) {
        final RegExpMatch? closeTag = RegExp('</$tag', caseSensitive: false).allMatches(html, i).firstOrNull;
        final int end = closeTag == null ? -1 : closeTag.start;
        final String body = html.substring(i, end < 0 ? n : end);
        if (tag == 'title') {
          el.children.add(HtmlNode('#text')
            ..text = decode(body)
            ..parent = el);
        }
        if (end < 0) {
          i = n;
        } else {
          final int close = html.indexOf('>', end);
          i = close < 0 ? n : close + 1;
        }
        continue;
      }
      if (!_void.contains(tag) && !selfClosed) {
        cur = el;
      }
    }
    return doc;
  }

  /// The `>` that ends a tag, skipping quoted attribute values.
  static int _tagEnd(String s, int from) {
    String? quote;
    for (int j = from; j < s.length; j++) {
      final String c = s[j];
      if (quote != null) {
        if (c == quote) {
          quote = null;
        }
      } else if (c == '"' || c == "'") {
        quote = c;
      } else if (c == '>') {
        return j;
      }
    }
    return -1;
  }

  static String _clean(String s) => s.replaceAll(RegExp(r'[\s ]+'), ' ').trim();

  static HtmlNode? _first(HtmlNode root, String tag) {
    for (final HtmlNode d in root.descendants) {
      if (d.tag == tag) {
        return d;
      }
    }
    return null;
  }

  /// The page's title: og:title, then <title>, then the first <h1> or <h2>.
  static String title(HtmlNode doc) {
    for (final HtmlNode d in doc.descendants) {
      if (d.tag == 'meta' && (d.attrs['property'] == 'og:title' || d.attrs['name'] == 'twitter:title')) {
        final String t = _clean(d.attrs['content'] ?? '');
        if (t.isNotEmpty) {
          return t;
        }
      }
    }
    final HtmlNode? t = _first(doc, 'title');
    if (t != null && _clean(t.allText).isNotEmpty) {
      return _clean(t.allText);
    }
    final HtmlNode? h = _first(doc, 'h1') ?? _first(doc, 'h2');
    return h == null ? '' : _clean(h.allText);
  }

  static bool _isChrome(HtmlNode el) {
    if (_chrome.contains(el.tag)) {
      return true;
    }
    final String role = (el.attrs['role'] ?? '').toLowerCase();
    if (role == 'navigation' || role == 'banner' || role == 'contentinfo' || role == 'complementary' || role == 'search') {
      return true;
    }
    if (el.attrs.containsKey('hidden') || (el.attrs['aria-hidden'] ?? '') == 'true') {
      return true;
    }
    if (el.tag == 'header') {
      // A header holding the article's headline stays; a site banner goes.
      return !el.descendants.any((HtmlNode d) => d.tag == 'h1' || d.tag == 'h2') ||
          el.descendants.any((HtmlNode d) => d.tag == 'nav');
    }
    final String hint = '${el.attrs['class'] ?? ''} ${el.attrs['id'] ?? ''}';
    return hint.trim().isNotEmpty && _chromeHint.hasMatch(hint);
  }

  static int _textLength(HtmlNode el) {
    int n = 0;
    for (final HtmlNode d in el.descendants) {
      if (d.isText && !_insideHidden(d, el)) {
        n += _clean(d.text).length;
      }
    }
    return n;
  }

  static bool _insideHidden(HtmlNode node, HtmlNode stop) {
    for (HtmlNode? p = node.parent; p != null && p != stop; p = p.parent) {
      if (_hidden.contains(p.tag)) {
        return true;
      }
    }
    return false;
  }

  /// Where the article is: the <article> or <main> with the most text,
  /// else the element whose direct <p> children hold the most text.
  static HtmlNode readerRoot(HtmlNode doc) {
    HtmlNode? best;
    int bestLen = 0;
    for (final HtmlNode d in doc.descendants) {
      if (d.tag == 'article' || d.tag == 'main' || (d.attrs['role'] ?? '') == 'main') {
        final int len = _textLength(d);
        if (len > bestLen) {
          best = d;
          bestLen = len;
        }
      }
    }
    if (best != null && bestLen >= 200) {
      return best;
    }
    HtmlNode? para;
    int paraLen = 0;
    for (final HtmlNode d in doc.descendants) {
      if (d.isText || _isChrome(d)) {
        continue;
      }
      int len = 0;
      for (final HtmlNode c in d.children) {
        if (c.tag == 'p') {
          len += _textLength(c);
        }
      }
      if (len > paraLen) {
        para = d;
        paraLen = len;
      }
    }
    if (para != null && paraLen >= 140) {
      return para;
    }
    return best ?? _first(doc, 'body') ?? doc;
  }

  /// Reads [doc] (from [parse]) into blocks of text.
  static List<WebBlock> blocks(HtmlNode doc, WebPdfMode mode) {
    final HtmlNode root = mode == WebPdfMode.reader ? readerRoot(doc) : (_first(doc, 'body') ?? doc);
    final List<WebBlock> out = <WebBlock>[];
    final StringBuffer buf = StringBuffer();
    WebBlockKind kind = WebBlockKind.paragraph;
    int level = 0;

    void flush() {
      final String raw = buf.toString();
      buf.clear();
      final String t = kind == WebBlockKind.code
          ? raw.replaceAll('\r\n', '\n').replaceAll(RegExp(r'^\n+|\s+$'), '')
          : _clean(raw);
      if (t.isNotEmpty) {
        // Reader mode drops lone link-style crumbs ("Share", "Next »").
        final bool crumb = mode == WebPdfMode.reader && kind == WebBlockKind.paragraph && t.length < 3;
        if (!crumb && !(out.isNotEmpty && out.last.text == t && out.last.kind == kind)) {
          out.add(WebBlock(kind, t, level: level));
        }
      }
      kind = WebBlockKind.paragraph;
      level = 0;
    }

    void walk(HtmlNode el, {bool pre = false}) {
      for (final HtmlNode c in el.children) {
        if (c.isText) {
          buf.write(c.text);
          continue;
        }
        if (_hidden.contains(c.tag)) {
          continue;
        }
        if (mode == WebPdfMode.reader && c != root && _isChrome(c)) {
          continue;
        }
        if (c.tag == 'br') {
          if (pre) {
            buf.write('\n');
          } else {
            flush();
          }
          continue;
        }
        if (c.tag == 'img') {
          final String alt = _clean(c.attrs['alt'] ?? '');
          if (mode == WebPdfMode.fullPage && alt.isNotEmpty) {
            buf.write(' [$alt] ');
          }
          continue;
        }
        if (c.tag == 'td' || c.tag == 'th') {
          if (buf.toString().trim().isNotEmpty) {
            buf.write('  ·  ');
          }
          walk(c, pre: pre);
          continue;
        }
        if (!_block.contains(c.tag)) {
          walk(c, pre: pre);
          continue;
        }
        flush();
        final RegExpMatch? h = RegExp(r'^h([1-6])$').firstMatch(c.tag);
        if (h != null) {
          kind = WebBlockKind.heading;
          level = int.parse(h.group(1)!);
        } else if (c.tag == 'li' || c.tag == 'dt') {
          kind = WebBlockKind.listItem;
        } else if (c.tag == 'blockquote') {
          kind = WebBlockKind.quote;
        } else if (c.tag == 'pre') {
          kind = WebBlockKind.code;
        }
        final WebBlockKind outer = kind;
        final int outerLevel = level;
        walk(c, pre: pre || c.tag == 'pre');
        if (buf.isNotEmpty) {
          kind = outer;
          level = outerLevel;
        }
        flush();
      }
    }

    walk(root);
    flush();
    if (mode == WebPdfMode.reader) {
      return _trimReader(out);
    }
    return out;
  }

  /// Drops trailing link lists and leading crumbs the reader root dragged in.
  static List<WebBlock> _trimReader(List<WebBlock> b) {
    int start = 0;
    while (start < b.length && b[start].kind == WebBlockKind.listItem && b[start].text.length < 40) {
      start++;
    }
    int end = b.length;
    while (end > start && b[end - 1].kind == WebBlockKind.listItem && b[end - 1].text.length < 40) {
      end--;
    }
    // Keep genuine lists that are the whole article.
    if (end <= start) {
      return b;
    }
    return b.sublist(start, end);
  }

  /// True when the page is a login wall rather than content.
  static bool looksLikeLogin(HtmlNode doc, List<WebBlock> blocks) {
    final bool password = doc.descendants
        .any((HtmlNode d) => d.tag == 'input' && (d.attrs['type'] ?? '').toLowerCase() == 'password');
    int words = 0;
    for (final WebBlock b in blocks) {
      words += b.text.split(' ').length;
    }
    return password && words < 150;
  }

  static WebArticle article(String html, Uri url, WebPdfMode mode) {
    final HtmlNode doc = parse(html);
    final List<WebBlock> b = blocks(doc, mode);
    if (looksLikeLogin(doc, b)) {
      throw const WebPdfError('This page asks you to sign in. Only pages that open without a login can be saved.');
    }
    String t = title(doc);
    if (t.isEmpty) {
      t = url.host;
    }
    // Reader mode: the article's own headline repeats the title.
    final List<WebBlock> body = <WebBlock>[...b];
    if (body.isNotEmpty && body.first.kind == WebBlockKind.heading && _clean(body.first.text) == t) {
      body.removeAt(0);
    }
    return WebArticle(title: t, url: url, blocks: body);
  }
}

/// Lays an article out and draws its pages. Behind an interface for tests.
abstract class WebPageRenderer {
  Future<List<GreyPage>> render(WebArticle article, TextPdfOptions o);
}

/// Uses the phone's text engine, as Text to PDF does, so every script the
/// phone has fonts for is shaped properly.
class FlutterWebPageRenderer implements WebPageRenderer {
  const FlutterWebPageRenderer();

  static const ui.Color _ink = ui.Color(0xFF000000);
  static const ui.Color _soft = ui.Color(0xFF555555);

  static TextSpan spanFor(WebArticle a, TextPdfOptions o) {
    final double s = o.fontSize;
    final List<InlineSpan> parts = <InlineSpan>[
      TextSpan(text: '${a.title}\n', style: TextStyle(fontSize: s * 1.7, fontWeight: FontWeight.w700, height: 1.25)),
      TextSpan(text: '${a.url}\n\n', style: TextStyle(fontSize: s * 0.8, color: _soft)),
    ];
    for (final WebBlock b in a.blocks) {
      switch (b.kind) {
        case WebBlockKind.heading:
          final double k = b.level <= 1 ? 1.45 : (b.level == 2 ? 1.3 : (b.level == 3 ? 1.15 : 1.05));
          parts.add(TextSpan(text: '${b.text}\n\n', style: TextStyle(fontSize: s * k, fontWeight: FontWeight.w700, height: 1.3)));
        case WebBlockKind.listItem:
          parts.add(TextSpan(text: '•  ${b.text}\n'));
        case WebBlockKind.quote:
          parts.add(TextSpan(text: '${b.text}\n\n', style: const TextStyle(fontStyle: FontStyle.italic, color: _soft)));
        case WebBlockKind.code:
          parts.add(TextSpan(text: '${b.text}\n\n', style: TextStyle(fontFamily: 'monospace', fontSize: s * 0.85)));
        case WebBlockKind.paragraph:
          parts.add(TextSpan(text: '${b.text}\n\n'));
      }
    }
    return TextSpan(
      style: TextStyle(color: _ink, fontFamily: o.font.family, fontSize: s, height: o.lineHeight),
      children: parts,
    );
  }

  @override
  Future<List<GreyPage>> render(WebArticle article, TextPdfOptions o) async {
    final (double pw, double ph) = o.page;
    final double boxH = ph - 2 * o.marginPt;
    final TextPainter painter = TextPainter(text: spanFor(article, o), textDirection: TextDirection.ltr)
      ..layout(maxWidth: pw - 2 * o.marginPt);
    final List<LineSpan> lines = <LineSpan>[
      for (final ui.LineMetrics m in painter.computeLineMetrics()) LineSpan(m.baseline - m.ascent, m.baseline + m.descent),
    ];
    final List<PageSlice> slices = TextToPdf.paginate(lines, boxH);
    final double scale = o.dpi / 72;
    final int w = (pw * scale).round();
    final int h = (ph * scale).round();
    final List<GreyPage> pages = <GreyPage>[];
    try {
      for (final PageSlice sl in slices) {
        final ui.PictureRecorder rec = ui.PictureRecorder();
        final ui.Canvas c = ui.Canvas(rec);
        c.drawRect(ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), ui.Paint()..color = const ui.Color(0xFFFFFFFF));
        c.scale(scale);
        c.translate(o.marginPt, o.marginPt);
        c.clipRect(ui.Rect.fromLTWH(-o.marginPt, 0, pw, sl.bottom - sl.top));
        c.translate(0, -sl.top);
        painter.paint(c, ui.Offset.zero);
        final ui.Picture picture = rec.endRecording();
        final ui.Image image = await picture.toImage(w, h);
        picture.dispose();
        final ByteData? rgba = await image.toByteData();
        image.dispose();
        if (rgba == null) {
          throw const WebPdfError('The page could not be drawn.');
        }
        final Uint8List px = rgba.buffer.asUint8List(rgba.offsetInBytes, rgba.lengthInBytes);
        final Uint8List grey = Uint8List(w * h);
        for (int i = 0, j = 0; i < grey.length; i++, j += 4) {
          grey[i] = (px[j] * 299 + px[j + 1] * 587 + px[j + 2] * 114) ~/ 1000;
        }
        pages.add(GreyPage(width: w, height: h, pixels: grey, widthPt: pw, heightPt: ph));
      }
    } finally {
      painter.dispose();
    }
    return pages;
  }
}

class WebPdfResult {
  const WebPdfResult({required this.name, required this.bytes, required this.pages, required this.article});
  final String name;
  final Uint8List bytes;
  final int pages;
  final WebArticle article;
}

/// URL in, PDF out.
class WebPdfMaker {
  const WebPdfMaker({required this.source, this.renderer = const FlutterWebPageRenderer()});
  final WebPageSource source;
  final WebPageRenderer renderer;

  static const TextPdfOptions defaultOptions = TextPdfOptions(fontSize: 11, dpi: 150);

  Future<WebArticle> read(String input, WebPdfMode mode) async {
    final Uri url = WebPageUrl.parse(input);
    final FetchedWebPage page = await source.fetch(url);
    if (page.statusCode == 401 || page.statusCode == 403) {
      throw const WebPdfError('This page needs a login or blocks saving. Only pages that open without a login work.');
    }
    if (page.statusCode == 404 || page.statusCode == 410) {
      throw const WebPdfError('The site says this page does not exist.');
    }
    if (page.statusCode >= 400) {
      throw WebPdfError('The site answered ${page.statusCode}. Try again later.');
    }
    final String type = page.contentType.toLowerCase();
    if (type.isNotEmpty && !type.contains('html') && !type.contains('xml') && !type.startsWith('text/')) {
      if (type.contains('pdf')) {
        throw const WebPdfError('That link is already a PDF. Open it in Download queue to save it.');
      }
      throw const WebPdfError('That link is not a web page.');
    }
    final WebArticle a = type.startsWith('text/plain')
        ? WebArticle(
            title: page.url.pathSegments.isEmpty ? page.url.host : page.url.pathSegments.last,
            url: page.url,
            blocks: <WebBlock>[
              for (final String p in page.html.split(RegExp(r'\n\s*\n')))
                if (p.trim().isNotEmpty) WebBlock(WebBlockKind.code, p.trimRight()),
            ],
          )
        : HtmlText.article(page.html, page.url, mode);
    if (a.blocks.isEmpty) {
      throw WebPdfError(mode == WebPdfMode.reader
          ? 'No article text found. Try Full page; some sites only show text after a login or through JavaScript.'
          : 'This page has no text to save. It may need a login or build itself with JavaScript.');
    }
    return a;
  }

  Future<WebPdfResult> make(String input, WebPdfMode mode, {TextPdfOptions options = defaultOptions}) async {
    final WebArticle a = await read(input, mode);
    final List<GreyPage> pages = await renderer.render(a, options);
    return WebPdfResult(name: TextToPdf.nameFor(a.title), bytes: TextToPdf.writePdf(pages), pages: pages.length, article: a);
  }
}
