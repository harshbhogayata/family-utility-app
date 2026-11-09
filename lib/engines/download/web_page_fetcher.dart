import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../pdf/web_page_to_pdf.dart';

/// Feature 023 — fetches the one public page the person pasted, with the
/// phone's own HTTP stack. No cookies and no account: a page behind a login
/// comes back as its login screen and is reported as such. Pages above
/// [maxBytes] are cut off. Nothing is sent but the GET for the page.
class HttpWebPageSource implements WebPageSource {
  HttpWebPageSource({HttpClient? client}) : _client = client ?? HttpClient() {
    _client.connectionTimeout = const Duration(seconds: 20);
  }

  final HttpClient _client;
  static const int maxBytes = 8 * 1024 * 1024;

  @override
  Future<FetchedWebPage> fetch(Uri url) async {
    try {
      final HttpClientRequest req = await _client.getUrl(url);
      req.followRedirects = true;
      req.maxRedirects = 8;
      req.headers.set(HttpHeaders.userAgentHeader, 'Mozilla/5.0 (Linux; Android 14) FamilyUtility/0.1');
      req.headers.set(HttpHeaders.acceptHeader, 'text/html,application/xhtml+xml,text/plain;q=0.8');
      final HttpClientResponse res = await req.close().timeout(const Duration(seconds: 40));
      final Uri finalUrl = res.redirects.isEmpty ? url : url.resolveUri(res.redirects.last.location);
      final String type = res.headers.contentType?.mimeType ?? '';
      if (res.statusCode >= 400) {
        await res.drain<void>();
        return FetchedWebPage(url: finalUrl, html: '', statusCode: res.statusCode, contentType: type);
      }
      final List<int> bytes = <int>[];
      await for (final List<int> chunk in res.timeout(const Duration(seconds: 40))) {
        bytes.addAll(chunk);
        if (bytes.length > maxBytes) {
          break;
        }
      }
      final String charset = (res.headers.contentType?.charset ?? _metaCharset(bytes) ?? 'utf-8').toLowerCase();
      final String html = charset == 'iso-8859-1' || charset == 'latin1' || charset == 'windows-1252'
          ? latin1.decode(bytes, allowInvalid: true)
          : utf8.decode(bytes, allowMalformed: true);
      return FetchedWebPage(url: finalUrl, html: html, statusCode: res.statusCode, contentType: type);
    } on SocketException catch (e) {
      throw WebPdfError(e.message.isEmpty ? 'No connection. Check the internet and try again.' : 'No connection: ${e.message}');
    } on HandshakeException {
      throw const WebPdfError('Could not make a secure connection to the site.');
    } on RedirectException {
      throw const WebPdfError('The site keeps redirecting. It may need a login.');
    } on HttpException catch (e) {
      throw WebPdfError('The site did not answer properly: ${e.message}');
    } on FormatException {
      throw const WebPdfError('The site sent something that is not a web page.');
    } on TimeoutException {
      throw const WebPdfError('The site took too long to answer.');
    }
  }

  /// `<meta charset="...">` in the first 2 KB.
  static String? _metaCharset(List<int> bytes) {
    final String head = latin1.decode(bytes.take(2048).toList(), allowInvalid: true);
    return RegExp(r'''charset\s*=\s*["']?([a-zA-Z0-9_-]+)''', caseSensitive: false).firstMatch(head)?.group(1);
  }
}
