import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../platform/background_jobs.dart';

/// Feature 127 — Download queue.
///
/// Links the person adds are fetched one by one (two at a time) into a folder
/// they chose. Each file streams into `<name>.part`; a pause, a dropped
/// connection or closing the app keeps the part, and the next attempt asks the
/// server for the rest with a Range request. The queue itself is saved as
/// JSON, so it survives the app closing. Downloads run as background jobs
/// (067) so the phone keeps them alive with a progress notification.
/// Nothing is uploaded: the only request is a GET for the link itself.

enum DownloadState { queued, running, paused, waiting, done, failed }

/// The connection dropped or the phone is offline. The task waits and goes
/// again on reconnect.
class DownloadNetworkError implements Exception {
  const DownloadNetworkError(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The server answered with a status that will not get better by retrying soon.
class DownloadHttpError implements Exception {
  const DownloadHttpError(this.statusCode);

  final int statusCode;

  @override
  String toString() => 'Server said $statusCode';
}

/// A link the queue cannot fetch.
class DownloadLinkError implements Exception {
  const DownloadLinkError(this.message);

  final String message;

  @override
  String toString() => message;
}

/// One answer from the server.
class FetchResponse {
  FetchResponse({required this.statusCode, required this.body, this.totalLength});

  /// 200 for the whole file, 206 for the rest of it, 416 when nothing is left.
  final int statusCode;

  /// Length of the whole file when the server says, else null.
  final int? totalLength;
  final Stream<List<int>> body;

  bool get partial => statusCode == 206;

  /// Reads and drops the body so the connection is released.
  Future<void> discard() async {
    try {
      await body.drain<void>();
    } catch (_) {
      // Nothing to keep.
    }
  }
}

/// Fetches a link from byte [from] onward.
abstract class DownloadFetcher {
  Future<FetchResponse> open(Uri url, int from);
}

/// Total size from a `Content-Range: bytes a-b/total` header; null when unknown.
int? contentRangeTotal(String? header) {
  if (header == null) {
    return null;
  }
  final int slash = header.lastIndexOf('/');
  if (slash < 0) {
    return null;
  }
  return int.tryParse(header.substring(slash + 1).trim());
}

/// The phone's own HTTP stack, no extra package.
class HttpDownloadFetcher implements DownloadFetcher {
  HttpDownloadFetcher({HttpClient? client}) : _client = client ?? HttpClient() {
    _client.connectionTimeout = const Duration(seconds: 20);
    _client.autoUncompress = false;
  }

  final HttpClient _client;

  @override
  Future<FetchResponse> open(Uri url, int from) async {
    try {
      final HttpClientRequest req = await _client.getUrl(url);
      req.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      if (from > 0) {
        req.headers.set(HttpHeaders.rangeHeader, 'bytes=$from-');
      }
      final HttpClientResponse res = await req.close();
      int? total;
      if (res.statusCode == 206) {
        total = contentRangeTotal(res.headers.value(HttpHeaders.contentRangeHeader));
      } else if (res.contentLength >= 0) {
        total = res.contentLength;
      }
      return FetchResponse(statusCode: res.statusCode, totalLength: total, body: res);
    } on SocketException catch (e) {
      throw DownloadNetworkError(e.message.isEmpty ? 'No connection' : e.message);
    } on HttpException catch (e) {
      throw DownloadNetworkError(e.message);
    } on TimeoutException {
      throw const DownloadNetworkError('The server took too long');
    } on HandshakeException catch (e) {
      throw DownloadNetworkError(e.message);
    }
  }
}

/// Where the queue is kept between launches.
abstract class DownloadQueueStore {
  Future<String?> read();

  Future<void> write(String json);
}

class MemoryDownloadQueueStore implements DownloadQueueStore {
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String json) async => value = json;
}

/// `queue.json` in the app's own folder.
class FileDownloadQueueStore implements DownloadQueueStore {
  const FileDownloadQueueStore(this.folder);

  final Future<Directory> Function() folder;

  Future<File> _file() async => File('${(await folder()).path}/queue.json');

  @override
  Future<String?> read() async {
    final File f = await _file();
    return await f.exists() ? f.readAsString() : null;
  }

  @override
  Future<void> write(String json) async {
    final File f = await _file();
    await f.parent.create(recursive: true);
    await f.writeAsString(json, flush: true);
  }
}

class DownloadTask {
  DownloadTask({
    required this.id,
    required this.url,
    required this.folder,
    required this.name,
    this.state = DownloadState.queued,
    this.received = 0,
    this.total,
    this.error,
  });

  factory DownloadTask.fromJson(Map<String, Object?> j) {
    final String stateName = j['state'] is String ? j['state']! as String : 'queued';
    return DownloadTask(
      id: j['id'] is int ? j['id']! as int : 0,
      url: j['url'] is String ? j['url']! as String : '',
      folder: j['folder'] is String ? j['folder']! as String : '',
      name: j['name'] is String ? j['name']! as String : 'download',
      state: DownloadState.values.firstWhere((DownloadState s) => s.name == stateName,
          orElse: () => DownloadState.queued),
      received: j['received'] is int ? j['received']! as int : 0,
      total: j['total'] is int ? j['total']! as int : null,
      error: j['error'] is String ? j['error']! as String : null,
    );
  }

  final int id;
  final String url;
  final String folder;
  String name;
  DownloadState state;
  int received;
  int? total;
  String? error;

  bool _pauseRequested = false;
  void Function()? _stop;

  String get path => '${folder.endsWith('/') ? folder.substring(0, folder.length - 1) : folder}/$name';
  String get partPath => '$path.part';

  /// 0 to 1, or null while the size is unknown.
  double? get fraction {
    if (state == DownloadState.done) {
      return 1;
    }
    final int? t = total;
    if (t == null || t <= 0) {
      return null;
    }
    return (received / t).clamp(0.0, 1.0).toDouble();
  }

  String get statusLine {
    final String got = formatBytes(received);
    final String size = total == null ? got : '$got of ${formatBytes(total!)}';
    switch (state) {
      case DownloadState.queued:
        return received > 0 ? 'Queued · $size' : 'Queued';
      case DownloadState.running:
        final double? f = fraction;
        return f == null ? size : '${(f * 100).round()}% · $size';
      case DownloadState.paused:
        return 'Paused · $size';
      case DownloadState.waiting:
        return 'Waiting for connection · ${error ?? size}';
      case DownloadState.done:
        return 'Done · ${formatBytes(total ?? received)}';
      case DownloadState.failed:
        return 'Failed: ${error ?? 'unknown error'}';
    }
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'url': url,
        'folder': folder,
        'name': name,
        'state': state.name,
        'received': received,
        'total': total,
        'error': error,
      };
}

String formatBytes(int n) {
  if (n < 1000) {
    return '$n B';
  }
  if (n < 1000 * 1000) {
    return '${(n / 1000).toStringAsFixed(0)} KB';
  }
  if (n < 1000 * 1000 * 1000) {
    return '${(n / 1000 / 1000).toStringAsFixed(1)} MB';
  }
  return '${(n / 1000 / 1000 / 1000).toStringAsFixed(2)} GB';
}

/// A file name from the link's last path part, safe for any file system.
String nameFromUrl(Uri url) {
  final List<String> parts = url.pathSegments.where((String s) => s.isNotEmpty).toList();
  String name = parts.isEmpty ? 'download' : parts.last;
  name = name.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_').trim();
  if (name.isEmpty || name == '.' || name == '..') {
    name = 'download';
  }
  return name.length > 120 ? name.substring(name.length - 120) : name;
}

class DownloadQueue extends ChangeNotifier {
  DownloadQueue({
    required this.fetcher,
    required this.store,
    required this.defaultFolder,
    BackgroundJobs? jobs,
    this.blockedReason,
    this.maxParallel = 2,
  }) : _jobs = jobs;

  final DownloadFetcher fetcher;
  final DownloadQueueStore store;

  /// The app's own downloads folder, used until the person picks another.
  final Future<String> Function() defaultFolder;

  /// Why the network may not be used now (on-device mode), or null.
  final String? Function()? blockedReason;
  final int maxParallel;
  final BackgroundJobs? _jobs;

  final List<DownloadTask> _tasks = <DownloadTask>[];
  String? _folder;
  int _nextId = 1;
  bool _disposed = false;

  BackgroundJobs get jobs => _jobs ?? BackgroundJobs.instance;
  List<DownloadTask> get tasks => List<DownloadTask>.unmodifiable(_tasks);
  List<DownloadTask> get done => _tasks.where((DownloadTask t) => t.state == DownloadState.done).toList();
  int get running => _tasks.where((DownloadTask t) => t.state == DownloadState.running).length;

  /// The chosen folder, or null while it is still the default.
  String? get chosenFolder => _folder;

  Future<String> folder() async => _folder ?? await defaultFolder();

  Future<void> setFolder(String? path) async {
    _folder = (path == null || path.trim().isEmpty) ? null : path;
    _changed();
    await _save();
  }

  DownloadTask? byId(int id) {
    for (final DownloadTask t in _tasks) {
      if (t.id == id) {
        return t;
      }
    }
    return null;
  }

  /// Reads the saved queue. Downloads that were running when the app closed
  /// go back in the queue and continue from their part file.
  Future<void> load() async {
    try {
      final String? raw = await store.read();
      if (raw != null && raw.isNotEmpty) {
        final Object? decoded = jsonDecode(raw);
        if (decoded is Map<String, Object?>) {
          final Object? f = decoded['folder'];
          _folder = f is String ? f : null;
          final Object? list = decoded['tasks'];
          if (list is List<Object?>) {
            for (final Object? item in list) {
              if (item is Map<String, Object?>) {
                final DownloadTask t = DownloadTask.fromJson(item);
                if (t.url.isEmpty || byId(t.id) != null) {
                  continue;
                }
                if (t.state == DownloadState.running) {
                  t.state = DownloadState.queued;
                }
                if (t.state != DownloadState.done) {
                  final File part = File(t.partPath);
                  t.received = await part.exists() ? await part.length() : 0;
                }
                _tasks.add(t);
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('download queue: could not read the saved queue: $e');
    }
    for (final DownloadTask t in _tasks) {
      if (t.id >= _nextId) {
        _nextId = t.id + 1;
      }
    }
    _changed();
    _pump();
  }

  /// Adds a link. Throws [DownloadLinkError] for anything but http(s).
  Future<DownloadTask> add(String link, {String? name}) async {
    final Uri? url = Uri.tryParse(link.trim());
    if (url == null || !(url.scheme == 'http' || url.scheme == 'https') || url.host.isEmpty) {
      throw const DownloadLinkError('Paste a link that starts with http:// or https://');
    }
    final String dir = await folder();
    final String wanted = (name == null || name.trim().isEmpty) ? nameFromUrl(url) : nameFromUrl(Uri(path: name.trim()));
    final DownloadTask t = DownloadTask(
      id: _nextId++,
      url: url.toString(),
      folder: dir,
      name: await _freeName(dir, wanted),
    );
    _tasks.add(t);
    _changed();
    await _save();
    _pump();
    return t;
  }

  void pause(int id) {
    final DownloadTask? t = byId(id);
    if (t == null) {
      return;
    }
    switch (t.state) {
      case DownloadState.queued:
      case DownloadState.waiting:
        t.state = DownloadState.paused;
        _changed();
        unawaited(_save());
      case DownloadState.running:
        t._pauseRequested = true;
        t._stop?.call();
      case DownloadState.paused:
      case DownloadState.done:
      case DownloadState.failed:
        break;
    }
  }

  /// Resumes a paused download, or retries a failed or waiting one.
  void resume(int id) {
    final DownloadTask? t = byId(id);
    if (t == null || t.state == DownloadState.running || t.state == DownloadState.done) {
      return;
    }
    t
      ..state = DownloadState.queued
      ..error = null;
    _changed();
    unawaited(_save());
    _pump();
  }

  void retry(int id) => resume(id);

  /// The connection is back (or the app came to the front): waiting tasks go again.
  void reconnected() {
    bool any = false;
    for (final DownloadTask t in _tasks) {
      if (t.state == DownloadState.waiting) {
        t.state = DownloadState.queued;
        any = true;
      }
    }
    if (any) {
      _changed();
      unawaited(_save());
    }
    _pump();
  }

  /// Takes a task off the list; a running one is paused first. Its part file
  /// stays so Undo can put it back where it was.
  (DownloadTask, int)? remove(int id) {
    final int i = _tasks.indexWhere((DownloadTask t) => t.id == id);
    if (i < 0) {
      return null;
    }
    final DownloadTask t = _tasks[i];
    if (t.state == DownloadState.running) {
      pause(id);
    }
    _tasks.removeAt(i);
    _changed();
    unawaited(_save());
    return (t, i);
  }

  void restore((DownloadTask, int) removed) {
    final (DownloadTask t, int i) = removed;
    if (byId(t.id) != null) {
      return;
    }
    if (t.state == DownloadState.running) {
      t.state = DownloadState.paused;
    }
    _tasks.insert(i.clamp(0, _tasks.length), t);
    _changed();
    unawaited(_save());
  }

  void _pump() {
    if (_disposed) {
      return;
    }
    for (final DownloadTask t in List<DownloadTask>.of(_tasks)) {
      if (running >= maxParallel) {
        return;
      }
      if (t.state == DownloadState.queued) {
        final String? why = blockedReason?.call();
        if (why != null) {
          t
            ..state = DownloadState.waiting
            ..error = why;
          _changed();
          continue;
        }
        t.state = DownloadState.running;
        t._pauseRequested = false;
        _changed();
        unawaited(_run(t));
      }
    }
  }

  Future<void> _run(DownloadTask t) async {
    try {
      await jobs.run<void>('Download ${t.name}', (JobContext ctx) async {
        await _fetch(t, ctx);
        ctx.addOutput(t.path);
      });
      t
        ..state = DownloadState.done
        ..error = null;
    } on JobCancelled {
      t.state = DownloadState.paused;
    } on DownloadNetworkError catch (e) {
      t
        ..state = t._pauseRequested ? DownloadState.paused : DownloadState.waiting
        ..error = e.message;
    } on SocketException catch (e) {
      t
        ..state = DownloadState.waiting
        ..error = e.message.isEmpty ? 'No connection' : e.message;
    } on HttpException catch (e) {
      t
        ..state = DownloadState.waiting
        ..error = e.message;
    } catch (e) {
      t
        ..state = DownloadState.failed
        ..error = e.toString();
    } finally {
      t._stop = null;
      t._pauseRequested = false;
      _changed();
      await _save();
      _pump();
    }
  }

  Future<void> _fetch(DownloadTask t, JobContext ctx) async {
    final File part = File(t.partPath);
    await part.parent.create(recursive: true);
    int from = await part.exists() ? await part.length() : 0;
    final FetchResponse res = await fetcher.open(Uri.parse(t.url), from);
    if (res.statusCode == 416 && from > 0) {
      // Nothing left to fetch: the part is already the whole file.
      await res.discard();
      t.total ??= from;
      t.received = from;
      await _finish(t, part);
      return;
    }
    if (res.statusCode != 200 && res.statusCode != 206) {
      await res.discard();
      throw DownloadHttpError(res.statusCode);
    }
    if (!res.partial) {
      from = 0; // The server sent the whole file; start the part again.
    }
    t
      ..total = res.totalLength
      ..received = from
      ..error = null;
    _changed();

    final IOSink sink = part.openWrite(mode: from > 0 ? FileMode.append : FileMode.write);
    final Completer<void> finished = Completer<void>();
    late final StreamSubscription<List<int>> sub;
    void fail(Object e) {
      if (!finished.isCompleted) {
        finished.completeError(e);
      }
    }

    t._stop = () {
      unawaited(sub.cancel());
      fail(const JobCancelled());
    };
    sub = res.body.listen(
      (List<int> chunk) {
        if (t._pauseRequested) {
          t._stop?.call();
          return;
        }
        sink.add(chunk);
        t.received += chunk.length;
        try {
          final double? f = t.fraction;
          ctx.report(f ?? 0, f == null ? formatBytes(t.received) : '${formatBytes(t.received)} of ${formatBytes(t.total!)}');
        } on JobCancelled catch (e) {
          // Cancel in the notification pauses the download.
          unawaited(sub.cancel());
          fail(e);
          return;
        }
        _changed();
      },
      onError: (Object e) => fail(e is DownloadNetworkError ? e : DownloadNetworkError(e.toString())),
      onDone: () {
        if (!finished.isCompleted) {
          finished.complete();
        }
      },
      cancelOnError: true,
    );
    try {
      await finished.future;
    } finally {
      await sink.flush();
      await sink.close();
    }
    final int? total = t.total;
    if (total != null && t.received < total) {
      throw const DownloadNetworkError('The connection dropped');
    }
    t.total ??= t.received;
    await _finish(t, part);
  }

  Future<void> _finish(DownloadTask t, File part) async {
    if (await File(t.path).exists()) {
      t.name = await _freeName(t.folder, t.name);
    }
    await part.rename(t.path);
  }

  /// [wanted], or "name (2).ext" and so on when a file or another task has it.
  Future<String> _freeName(String folder, String wanted) async {
    final String base = folder.endsWith('/') ? folder.substring(0, folder.length - 1) : folder;
    final int dot = wanted.lastIndexOf('.');
    final String stem = dot > 0 ? wanted.substring(0, dot) : wanted;
    final String ext = dot > 0 ? wanted.substring(dot) : '';
    String name = wanted;
    int i = 2;
    while (await File('$base/$name').exists() ||
        _tasks.any((DownloadTask t) => t.folder == folder && t.name == name && t.state != DownloadState.done)) {
      name = '$stem ($i)$ext';
      i++;
    }
    return name;
  }

  Future<void> _save() async {
    try {
      await store.write(jsonEncode(<String, Object?>{
        'folder': _folder,
        'tasks': _tasks.map((DownloadTask t) => t.toJson()).toList(),
      }));
    } catch (e) {
      debugPrint('download queue: could not save: $e');
    }
  }

  void _changed() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  static DownloadQueue? _instance;

  /// App-wide queue; bootstrap installs the real one.
  static DownloadQueue get instance => _instance ??= DownloadQueue(
        fetcher: HttpDownloadFetcher(),
        store: MemoryDownloadQueueStore(),
        defaultFolder: () async => '${Directory.systemTemp.path}/downloads',
      );

  static void install(DownloadQueue queue) => _instance = queue;
}
