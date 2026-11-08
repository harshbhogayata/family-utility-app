import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

/// Feature 062 — Phone to laptop.
///
/// A tiny HTTP server on the phone, reachable only on the local Wi-Fi, that
/// serves a drag-and-drop page to the laptop browser. Every request must
/// carry the one-time token printed in the QR code; the server lives only
/// while the screen is open and dies with the app. No internet is involved
/// and nothing is relayed through any server but the phone itself.

/// A file the phone offers for download.
@immutable
class OfferedFile {
  const OfferedFile({required this.path, required this.name, required this.size});

  final String path;
  final String name;
  final int size;

  static Future<OfferedFile> fromPath(String path) async {
    final File f = File(path);
    return OfferedFile(path: path, name: path.split('/').last, size: await f.length());
  }
}

/// A file the laptop sent.
@immutable
class ReceivedFile {
  const ReceivedFile({required this.path, required this.name, required this.size, required this.at});

  final String path;
  final String name;
  final int size;
  final DateTime at;
}

/// One-time token: 20 url-safe characters from a secure source.
abstract final class TransferToken {
  static const String _alphabet = 'abcdefghjkmnpqrstuvwxyz23456789';

  static String generate([int length = 20]) {
    final Random r = Random.secure();
    return List<String>.generate(length, (int _) => _alphabet[r.nextInt(_alphabet.length)]).join();
  }

  /// Constant-time compare so timing says nothing about the token.
  static bool matches(String? given, String expected) {
    if (given == null || given.length != expected.length) {
      return false;
    }
    int diff = 0;
    for (int i = 0; i < expected.length; i++) {
      diff |= given.codeUnitAt(i) ^ expected.codeUnitAt(i);
    }
    return diff == 0;
  }
}

/// File names from the browser are untrusted: keep only the base name and
/// plain characters, and never overwrite an existing file.
abstract final class SafeNames {
  static String clean(String raw) {
    String name = raw.split('/').last.split(r'\').last.trim();
    name = name.replaceAll(RegExp(r'[^\w.\- ()]'), '_');
    if (name.isEmpty || name == '.' || name == '..') {
      name = 'file';
    }
    return name.length > 120 ? name.substring(name.length - 120) : name;
  }

  static String unique(Directory dir, String name) {
    if (!File('${dir.path}/$name').existsSync()) {
      return name;
    }
    final int dot = name.lastIndexOf('.');
    final String stem = dot > 0 ? name.substring(0, dot) : name;
    final String ext = dot > 0 ? name.substring(dot) : '';
    for (int i = 2; i < 10000; i++) {
      final String candidate = '$stem ($i)$ext';
      if (!File('${dir.path}/$candidate').existsSync()) {
        return candidate;
      }
    }
    return '$stem-${DateTime.now().millisecondsSinceEpoch}$ext';
  }
}

/// The server. Start it, show [connectUrls] as a QR, stop it when done.
class LanTransferServer extends ChangeNotifier {
  LanTransferServer({required this.inbox, this.maxUploadBytes = 2 * 1024 * 1024 * 1024});

  /// Where received files land.
  final Directory inbox;
  final int maxUploadBytes;

  HttpServer? _server;
  String _token = '';
  final List<OfferedFile> _offered = <OfferedFile>[];
  final List<ReceivedFile> _received = <ReceivedFile>[];
  int _downloads = 0;

  bool get isRunning => _server != null;

  int get port => _server?.port ?? 0;

  String get token => _token;

  List<OfferedFile> get offered => List<OfferedFile>.unmodifiable(_offered);

  List<ReceivedFile> get received => List<ReceivedFile>.unmodifiable(_received);

  int get downloads => _downloads;

  /// Starts on every interface so the laptop can reach the phone's Wi-Fi
  /// address. A fresh token is made each start.
  Future<void> start({int port = 0, InternetAddress? address}) async {
    if (_server != null) {
      return;
    }
    _token = TransferToken.generate();
    if (!await inbox.exists()) {
      await inbox.create(recursive: true);
    }
    final HttpServer server = await HttpServer.bind(address ?? InternetAddress.anyIPv4, port);
    _server = server;
    server.listen(_handle, onError: (Object _) {});
    notifyListeners();
  }

  Future<void> stop() async {
    final HttpServer? s = _server;
    _server = null;
    _token = '';
    if (s != null) {
      await s.close(force: true);
    }
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(stop());
    super.dispose();
  }

  Future<void> offer(String path) async {
    if (_offered.any((OfferedFile f) => f.path == path)) {
      return;
    }
    _offered.add(await OfferedFile.fromPath(path));
    notifyListeners();
  }

  void withdraw(String path) {
    _offered.removeWhere((OfferedFile f) => f.path == path);
    notifyListeners();
  }

  /// Deletes every received file (Undo) and forgets them.
  Future<void> discardReceived() async {
    for (final ReceivedFile r in _received) {
      final File f = File(r.path);
      if (await f.exists()) {
        await f.delete();
      }
    }
    _received.clear();
    notifyListeners();
  }

  void forgetReceived() {
    _received.clear();
    notifyListeners();
  }

  /// Non-loopback IPv4 addresses of this phone.
  static Future<List<String>> localAddresses() async {
    try {
      final List<NetworkInterface> all =
          await NetworkInterface.list(type: InternetAddressType.IPv4, includeLinkLocal: false);
      final List<String> out = <String>[];
      for (final NetworkInterface i in all) {
        for (final InternetAddress a in i.addresses) {
          if (!a.isLoopback) {
            out.add(a.address);
          }
        }
      }
      // Prefer private LAN ranges first.
      out.sort((String a, String b) => _lanRank(a).compareTo(_lanRank(b)));
      return out;
    } catch (_) {
      return <String>[];
    }
  }

  static int _lanRank(String ip) {
    if (ip.startsWith('192.168.')) {
      return 0;
    }
    if (ip.startsWith('10.')) {
      return 1;
    }
    if (RegExp(r'^172\.(1[6-9]|2\d|3[01])\.').hasMatch(ip)) {
      return 2;
    }
    return 3;
  }

  String urlFor(String host) => 'http://$host:$port/?t=$_token';

  Future<List<String>> connectUrls() async {
    if (!isRunning) {
      return <String>[];
    }
    return (await localAddresses()).map(urlFor).toList();
  }

  // ---- HTTP -----------------------------------------------------------------

  Future<void> _handle(HttpRequest req) async {
    try {
      final String path = req.uri.path;
      if (!TransferToken.matches(req.uri.queryParameters['t'], _token)) {
        await _text(req, HttpStatus.forbidden, 'Scan the QR code on the phone to get a fresh link.');
        return;
      }
      if (req.method == 'GET' && (path == '/' || path == '/index.html')) {
        req.response.headers.contentType = ContentType.html;
        req.response.write(transferPageHtml(_token));
        await req.response.close();
      } else if (req.method == 'GET' && path == '/api/files') {
        final List<Map<String, Object?>> list = <Map<String, Object?>>[
          for (int i = 0; i < _offered.length; i++)
            <String, Object?>{'index': i, 'name': _offered[i].name, 'size': _offered[i].size},
        ];
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode(<String, Object?>{'files': list}));
        await req.response.close();
      } else if (req.method == 'GET' && path.startsWith('/api/files/')) {
        final int? index = int.tryParse(path.substring('/api/files/'.length));
        if (index == null || index < 0 || index >= _offered.length) {
          await _text(req, HttpStatus.notFound, 'No such file.');
          return;
        }
        final OfferedFile f = _offered[index];
        req.response.headers.contentType = ContentType.binary;
        req.response.headers.set('Content-Disposition', 'attachment; filename="${Uri.encodeComponent(f.name)}"');
        req.response.headers.contentLength = f.size;
        await req.response.addStream(File(f.path).openRead());
        await req.response.close();
        _downloads++;
        notifyListeners();
      } else if (req.method == 'POST' && path == '/api/upload') {
        final String name = SafeNames.unique(inbox, SafeNames.clean(req.uri.queryParameters['name'] ?? 'file'));
        final int declared = req.contentLength;
        if (declared > maxUploadBytes) {
          await _text(req, HttpStatus.requestEntityTooLarge, 'Too big.');
          return;
        }
        final File target = File('${inbox.path}/$name');
        final IOSink sink = target.openWrite();
        int size = 0;
        try {
          await for (final List<int> chunk in req) {
            size += chunk.length;
            if (size > maxUploadBytes) {
              throw const HttpException('too big');
            }
            sink.add(chunk);
          }
          await sink.flush();
        } finally {
          await sink.close();
        }
        _received.add(ReceivedFile(path: target.path, name: name, size: size, at: DateTime.now()));
        notifyListeners();
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode(<String, Object?>{'ok': true, 'name': name, 'size': size}));
        await req.response.close();
      } else {
        await _text(req, HttpStatus.notFound, 'Not here.');
      }
    } catch (_) {
      try {
        await _text(req, HttpStatus.internalServerError, 'Something went wrong on the phone.');
      } catch (_) {
        // The socket is gone; nothing to do.
      }
    }
  }

  Future<void> _text(HttpRequest req, int status, String body) async {
    req.response.statusCode = status;
    req.response.headers.contentType = ContentType.text;
    req.response.write(body);
    await req.response.close();
  }
}

/// The page the laptop sees. Plain HTML and JS, no external resources, so it
/// works with no internet at all.
String transferPageHtml(String token) {
  final String t = Uri.encodeQueryComponent(token);
  return '''<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Family Utility - phone to laptop</title>
<style>
body{font-family:system-ui,-apple-system,Segoe UI,Roboto,sans-serif;background:#F6F5F2;color:#16181D;margin:0;padding:24px;max-width:720px;margin:auto}
h1{font-size:22px}h2{font-size:16px;margin-top:28px}
#drop{border:2px dashed #0F766E;border-radius:16px;padding:40px;text-align:center;background:#fff;cursor:pointer}
#drop.over{background:#E5F4F1}
ul{list-style:none;padding:0}li{background:#fff;border:1px solid #E3E1DC;border-radius:14px;padding:12px 16px;margin:8px 0;display:flex;justify-content:space-between;align-items:center}
a{color:#0F766E}.muted{color:#5B6069;font-size:13px}button{font:inherit;padding:10px 16px;border-radius:22px;border:1px solid #E3E1DC;background:#fff;cursor:pointer;min-height:44px}
progress{width:100%}
</style></head><body>
<h1>Phone to laptop</h1>
<p class="muted">This page is served by the phone over your home Wi-Fi. Nothing goes to the internet.</p>
<h2>Send to the phone</h2>
<div id="drop" tabindex="0" role="button" aria-label="Drop files here or click to choose">Drop files here, or click to choose</div>
<input id="pick" type="file" multiple style="display:none" aria-hidden="true">
<ul id="sent"></ul>
<h2>From the phone</h2>
<ul id="files"><li class="muted">Nothing offered yet. Add files on the phone.</li></ul>
<script>
const T='$t';
const drop=document.getElementById('drop'),pick=document.getElementById('pick'),sent=document.getElementById('sent'),files=document.getElementById('files');
drop.onclick=()=>pick.click();drop.onkeydown=e=>{if(e.key==='Enter'||e.key===' ')pick.click();};
pick.onchange=()=>upload(pick.files);
['dragenter','dragover'].forEach(n=>drop.addEventListener(n,e=>{e.preventDefault();drop.classList.add('over')}));
['dragleave','drop'].forEach(n=>drop.addEventListener(n,e=>{e.preventDefault();drop.classList.remove('over')}));
drop.addEventListener('drop',e=>upload(e.dataTransfer.files));
async function upload(list){for(const f of list){const li=document.createElement('li');li.innerHTML='<span>'+esc(f.name)+'</span><progress max="1" value="0"></progress>';sent.prepend(li);
try{const r=await fetch('/api/upload?t='+T+'&name='+encodeURIComponent(f.name),{method:'POST',body:f});const j=await r.json();li.innerHTML='<span>'+esc(j.name)+'</span><span class="muted">sent, '+fmt(j.size)+'</span>';}
catch(e){li.innerHTML='<span>'+esc(f.name)+'</span><span class="muted">failed</span>';}}}
async function refresh(){try{const r=await fetch('/api/files?t='+T);const j=await r.json();
if(!j.files.length){files.innerHTML='<li class="muted">Nothing offered yet. Add files on the phone.</li>';return;}
files.innerHTML=j.files.map(f=>'<li><span>'+esc(f.name)+' <span class="muted">'+fmt(f.size)+'</span></span><a href="/api/files/'+f.index+'?t='+T+'" download>Download</a></li>').join('');}catch(e){}}
function fmt(n){return n>1048576?(n/1048576).toFixed(1)+' MB':n>1024?Math.round(n/1024)+' KB':n+' B'}
function esc(s){return s.replace(/[&<>"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]))}
refresh();setInterval(refresh,3000);
</script></body></html>''';
}
