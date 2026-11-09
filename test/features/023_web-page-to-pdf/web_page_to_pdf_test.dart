import 'dart:typed_data';

import 'package:family_utility_app/app/theme.dart';
import 'package:family_utility_app/engines/pdf/pdf_compressor.dart';
import 'package:family_utility_app/engines/pdf/text_to_pdf.dart';
import 'package:family_utility_app/engines/pdf/web_page_to_pdf.dart';
import 'package:family_utility_app/engines/share/share_engine.dart';
import 'package:family_utility_app/tools/text_to_pdf/text_to_pdf_screen.dart';
import 'package:family_utility_app/tools/web_page_pdf/web_page_pdf_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const String article = '''<!doctype html>
<html><head><title>Ignored tab title</title>
<meta property="og:title" content="Monsoon &amp; the city">
<style>p { color: red }</style>
<script>var x = "<p>not text</p>";</script></head>
<body>
<header class="site-header"><nav><a href="/">Home</a> <a href="/news">News</a></nav></header>
<div id="cookie-banner">We use cookies</div>
<main><article>
<h1>Monsoon &amp; the city</h1>
<p>Rain arrived in Mumbai on Tuesday, a week early. Commuters waded
   through water on the way to work, and trains ran late all morning.
<p>The weather office said the rain would continue through the weekend &mdash; with heavy spells in the evenings.</p>
<h2>What to carry</h2>
<ul><li>An umbrella that folds<li>Spare socks in a plastic bag</ul>
<blockquote>Stay indoors when you can.</blockquote>
<div class="share-buttons"><a>Share</a> <a>Tweet</a></div>
<pre>line 1
  line 2</pre>
<p>नमस्ते &#8377;500 &#x20B9;</p>
</article></main>
<aside class="related">Related stories</aside>
<footer>&copy; 2026 City News</footer>
</body></html>''';

const String loginPage = '''<html><head><title>Sign in</title></head><body>
<form><label>Email <input type="email"></label><label>Password <input type="password"></label>
<button>Sign in</button></form><p>Forgot your password?</p></body></html>''';

List<PdfDict> pageDicts(Uint8List pdf) {
  final PdfDocumentModel d = PdfDocumentModel.parse(pdf);
  final PdfDict root = d.resolve(d.trailer['Root'])! as PdfDict;
  final PdfDict pages = d.resolve(root['Pages'])! as PdfDict;
  return <PdfDict>[for (final Object k in (pages['Kids']! as PdfArray).items) d.resolve(k)! as PdfDict];
}

class FakeSource implements WebPageSource {
  FakeSource(this.html, {this.status = 200, this.type = 'text/html'});
  final String html;
  final int status;
  final String type;
  final List<Uri> asked = <Uri>[];

  @override
  Future<FetchedWebPage> fetch(Uri url) async {
    asked.add(url);
    return FetchedWebPage(url: url, html: html, statusCode: status, contentType: type);
  }
}

class FakeRenderer implements WebPageRenderer {
  final List<WebArticle> calls = <WebArticle>[];

  @override
  Future<List<GreyPage>> render(WebArticle a, TextPdfOptions o) async {
    calls.add(a);
    final int n = (a.blocks.length + 4) ~/ 5;
    return <GreyPage>[
      for (int i = 0; i < n; i++)
        GreyPage(width: 4, height: 4, pixels: Uint8List(16)..fillRange(0, 16, 255), widthPt: o.page.$1, heightPt: o.page.$2),
    ];
  }
}

class FakeFiles implements TextPdfFiles {
  FakeFiles([this.clip]);
  final String? clip;
  final Map<String, Uint8List> written = <String, Uint8List>{};

  @override
  Future<String?> paste() async => clip;

  @override
  Future<String> write(String name, Uint8List bytes) async {
    written['/converted/$name'] = bytes;
    return '/converted/$name';
  }

  @override
  Future<void> remove(String path) async => written.remove(path);
}

class FakeSheet implements ShareSheet {
  final List<ShareRequest> requests = <ShareRequest>[];

  @override
  Future<ShareOutcome> share(ShareRequest request) async {
    requests.add(request);
    return const ShareOutcome(completed: true);
  }
}

final Uri url = Uri.parse('https://news.example.in/monsoon');

void main() {
  group('addresses', () {
    test('adds https, finds the link inside shared text, refuses the rest', () {
      expect(WebPageUrl.parse(' example.com/a ').toString(), 'https://example.com/a');
      expect(WebPageUrl.parse('Read this https://news.example.in/x?y=1 now').toString(), 'https://news.example.in/x?y=1');
      expect(WebPageUrl.parse('http://example.org').scheme, 'http');
      for (final String bad in <String>['', '   ', 'ftp://example.com/f', 'hello world', 'nodot']) {
        expect(() => WebPageUrl.parse(bad), throwsA(isA<WebPdfError>()), reason: bad);
      }
    });
  });

  group('reading HTML', () {
    test('entities decode, unknown ones stay', () {
      expect(HtmlText.decode('a &amp; b &#8377; &#x20B9; &nbsp;x &bogus;'), 'a & b ₹ ₹  x &bogus;');
    });

    test('reader mode keeps the article and drops menus, banners, ads and footers', () {
      final WebArticle a = HtmlText.article(article, url, WebPdfMode.reader);
      expect(a.title, 'Monsoon & the city');
      expect(a.blocks, const <WebBlock>[
        WebBlock(WebBlockKind.paragraph,
            'Rain arrived in Mumbai on Tuesday, a week early. Commuters waded through water on the way to work, and trains ran late all morning.'),
        WebBlock(WebBlockKind.paragraph,
            'The weather office said the rain would continue through the weekend — with heavy spells in the evenings.'),
        WebBlock(WebBlockKind.heading, 'What to carry', level: 2),
        WebBlock(WebBlockKind.listItem, 'An umbrella that folds'),
        WebBlock(WebBlockKind.listItem, 'Spare socks in a plastic bag'),
        WebBlock(WebBlockKind.quote, 'Stay indoors when you can.'),
        WebBlock(WebBlockKind.code, 'line 1\n  line 2'),
        WebBlock(WebBlockKind.paragraph, 'नमस्ते ₹500 ₹'),
      ]);
      expect(a.wordCount, greaterThan(40));
    });

    test('full page keeps all visible text but never scripts or styles', () {
      final WebArticle a = HtmlText.article(article, url, WebPdfMode.fullPage);
      final String all = a.blocks.map((WebBlock b) => b.text).join('\n');
      for (final String s in <String>['Home News', 'We use cookies', 'Share Tweet', 'Related stories', '© 2026 City News', 'What to carry']) {
        expect(all, contains(s));
      }
      expect(all, isNot(contains('not text')));
      expect(all, isNot(contains('color: red')));
      expect(all, isNot(contains('Ignored tab title')));
      expect(a.blocks.length, greaterThan(HtmlText.article(article, url, WebPdfMode.reader).blocks.length));
    });

    test('pages without <article> use the block with the most paragraphs', () {
      final String body =
          List<String>.generate(4, (int i) => '<p>Plain sentence $i about the family budget. ${'More words here. ' * 6}</p>').join();
      final WebArticle a = HtmlText.article(
          '<html><body><div class="menu"><a>Home</a></div><div id="post"><h2>Budget</h2>$body</div>'
          '<div class="footer">Contact us</div></body></html>',
          url,
          WebPdfMode.reader);
      expect(a.title, 'Budget');
      expect(a.blocks, hasLength(4));
      expect(a.blocks.every((WebBlock b) => b.text.startsWith('Plain sentence')), isTrue);
      expect(a.url.host, 'news.example.in');
    });

    test('a login wall is reported, not saved', () {
      expect(() => HtmlText.article(loginPage, url, WebPdfMode.fullPage),
          throwsA(isA<WebPdfError>().having((WebPdfError e) => e.message, 'message', contains('sign in'))));
    });

    test('broken markup does not throw', () {
      final WebArticle a = HtmlText.article('<div><p>One <b>two<p>three</div></span><', url, WebPdfMode.fullPage);
      expect(a.blocks.map((WebBlock b) => b.text), <String>['One two', 'three', '<']);
    });
  });

  group('maker', () {
    test('fetches once, reads the article and writes one PDF', () async {
      final FakeSource src = FakeSource(article);
      final FakeRenderer r = FakeRenderer();
      final WebPdfResult res = await WebPdfMaker(source: src, renderer: r).make('news.example.in/monsoon', WebPdfMode.reader);
      expect(src.asked, <Uri>[url]);
      expect(res.name, 'Monsoon & the city.pdf');
      expect(res.pages, 2);
      expect(pageDicts(res.bytes), hasLength(2));
      expect(r.calls.single.blocks.first.text, startsWith('Rain arrived'));
    });

    test('logins, missing pages, PDFs and empty pages give plain reasons', () async {
      Future<String> why(FakeSource s, [WebPdfMode m = WebPdfMode.reader]) async {
        try {
          await WebPdfMaker(source: s, renderer: FakeRenderer()).make('https://example.com/x', m);
        } on WebPdfError catch (e) {
          return e.message;
        }
        return 'no error';
      }

      expect(await why(FakeSource('', status: 403)), contains('login'));
      expect(await why(FakeSource('', status: 404)), contains('does not exist'));
      expect(await why(FakeSource('', status: 503)), contains('503'));
      expect(await why(FakeSource('%PDF-1.4', type: 'application/pdf')), contains('already a PDF'));
      expect(await why(FakeSource('<html><body><script>app()</script></body></html>')), contains('Try Full page'));
      expect(await why(FakeSource('<html><body></body></html>'), WebPdfMode.fullPage), contains('JavaScript'));
    });

    test('plain text links keep their lines', () async {
      final FakeRenderer r = FakeRenderer();
      await WebPdfMaker(source: FakeSource('a\n  b\n\nc', type: 'text/plain'), renderer: r)
          .make('https://example.com/notes.txt', WebPdfMode.reader);
      expect(r.calls.single.title, 'notes.txt');
      expect(r.calls.single.blocks.map((WebBlock b) => b.text), <String>['a\n  b', 'c']);
    });

    testWidgets('the phone text engine draws the article onto pages', (WidgetTester tester) async {
      final WebArticle a = HtmlText.article(article, url, WebPdfMode.reader);
      final WebArticle long = WebArticle(title: a.title, url: a.url, blocks: <WebBlock>[for (int i = 0; i < 12; i++) ...a.blocks]);
      final List<GreyPage> pages = (await tester.runAsync(
          () => const FlutterWebPageRenderer().render(long, const TextPdfOptions(fontSize: 11, dpi: 36))))!;
      expect(pages.length, greaterThan(1));
      final GreyPage p = pages.first;
      expect(p.width, (595.28 * 36 / 72).round());
      expect(p.pixels.length, p.width * p.height);
      expect(p.pixels.any((int v) => v < 128), isTrue);
      expect(p.pixels.sublist(0, p.width * 5).every((int v) => v > 250), isTrue);
    });
  });

  group('screen', () {
    Future<FakeFiles> pump(WidgetTester tester, FakeSource src, {String? clip, ShareEngine? share, FakeRenderer? renderer}) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final FakeFiles files = FakeFiles(clip);
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: WebPagePdfScreen(
          files: files,
          maker: WebPdfMaker(source: src, renderer: renderer ?? FakeRenderer()),
          share: share,
        ),
      ));
      return files;
    }

    testWidgets('paste a link, pick full page, make, share and undo', (WidgetTester tester) async {
      final FakeSheet sheet = FakeSheet();
      final FakeRenderer renderer = FakeRenderer();
      final FakeSource src = FakeSource(article);
      final FakeFiles files = await pump(tester, src,
          clip: 'Look https://news.example.in/monsoon', share: ShareEngine(sheet, MemoryShareTargetStore()), renderer: renderer);
      for (final String k in <String>['web-pdf-paste', 'web-pdf-make', 'web-pdf-mode']) {
        expect(tester.getSize(find.byKey(Key(k))).height, greaterThanOrEqualTo(44), reason: k);
      }

      await tester.tap(find.byKey(const Key('web-pdf-paste')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Full page'));
      await tester.pumpAndSettle();
      expect(find.text(WebPdfMode.fullPage.hint), findsOneWidget);

      await tester.tap(find.byKey(const Key('web-pdf-make')));
      await tester.pumpAndSettle();
      expect(src.asked, <Uri>[url]);
      const String name = '/converted/Monsoon & the city.pdf';
      expect(files.written.keys, <String>[name]);
      expect(renderer.calls.single.blocks.map((WebBlock b) => b.text), contains('We use cookies'));
      expect(find.byKey(const Key('web-pdf-result')), findsOneWidget);

      await tester.tap(find.byKey(const Key('result-share')));
      await tester.pumpAndSettle();
      expect(sheet.requests.single.files.single.path, name);

      await tester.tap(find.byKey(const Key('result-undo')));
      await tester.pumpAndSettle();
      expect(files.written, isEmpty);
      expect(find.byKey(const Key('web-pdf-result')), findsNothing);
    });

    testWidgets('no address makes nothing; a login page says why; controls are labelled', (WidgetTester tester) async {
      final SemanticsHandle h = tester.ensureSemantics();
      final FakeFiles files = await pump(tester, FakeSource(loginPage));
      await tester.tap(find.byKey(const Key('result-save')));
      await tester.pumpAndSettle();
      expect(files.written, isEmpty);
      expect(find.text('Paste a web address first.'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('web-pdf-url')), 'accounts.example.com');
      await tester.tap(find.byKey(const Key('web-pdf-make')));
      await tester.pumpAndSettle();
      expect(files.written, isEmpty);
      expect(find.textContaining('sign in'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Web address')), findsWidgets);
      expect(find.bySemanticsLabel(RegExp('Reader')), findsWidgets);
      h.dispose();
    });
  });
}
