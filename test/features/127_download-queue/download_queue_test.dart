import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:family_utility_app/engines/download/download_queue.dart';
import 'package:family_utility_app/engines/platform/background_jobs.dart';
import 'package:family_utility_app/tools/download_queue/download_queue_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List sample(int n) => Uint8List.fromList(List<int>.generate(n, (int i) => (i * 7 + 3) % 256));

/// Serves [data] in 100-byte chunks, honouring Range unless told not to.
class BytesFetcher implements DownloadFetcher {
  BytesFetcher(this.data);

  final Uint8List data;
  final List<int> froms = <int>[];
  bool offline = false;
  bool ignoreRange = false;
  int status = 200;

  /// Drop the connection after this many bytes of the next response.
  int? dropAfter;

  @override
  Future<FetchResponse> open(Uri url, int from) async {
    froms.add(from);
    if (offline) {
      throw const DownloadNetworkError('No connection');
    }
    if (status != 200) {
      return FetchResponse(statusCode: status, body: const Stream<List<int>>.empty());
    }
    final int start = ignoreRange ? 0 : from;
    if (start > 0 && start >= data.length) {
      return FetchResponse(statusCode: 416, body: const Stream<List<int>>.empty());
    }
    final Uint8List rest = data.sublist(start);
    final int? drop = dropAfter;
    dropAfter = null;
    Stream<List<int>> body() async* {
      int sent = 0;
      for (int i = 0; i < rest.length; i += 100) {
        final Uint8List chunk = rest.sublist(i, min(i + 100, rest.length));
        if (drop != null && sent + chunk.length > drop) {
          throw const SocketException('Connection reset');
        }
        sent += chunk.length;
        yield chunk;
      }
    }

    return FetchResponse(statusCode: start > 0 ? 206 : 200, totalLength: data.length, body: body());
  }
}

/// Hands out bytes only when the test says so.
class GatedFetcher implements DownloadFetcher {
  GatedFetcher(this.data);

  final Uint8List data;
  final List<int> froms = <int>[];
  StreamController<List<int>>? current;
  int _pos = 0;

  @override
  Future<FetchResponse> open(Uri url, int from) async {
    froms.add(from);
    _pos = from;
    current = StreamController<List<int>>();
    return FetchResponse(statusCode: from > 0 ? 206 : 200, totalLength: data.length, body: current!.stream);
  }

  void feed(int n) {
    final int end = min(_pos + n, data.length);
    current!.add(data.sublist(_pos, end));
    _pos = end;
  }

  void finish() => unawaited(current!.close());
}

Future<void> until(bool Function() cond, {String reason = ''}) async {
  for (int i = 0; i < 400; i++) {
    if (cond()) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('timed out waiting $reason');
}

void main() {
  late Directory dir;
  late NoopJobHost host;
  late BackgroundJobs jobs;
  late MemoryDownloadQueueStore store;

  DownloadQueue queue(DownloadFetcher f, {String? Function()? blocked}) => DownloadQueue(
        fetcher: f,
        store: store,
        defaultFolder: () async => dir.path,
        jobs: jobs,
        blockedReason: blocked,
      );

  setUp(() {
    dir = Directory.systemTemp.createTempSync('dlq_');
    host = NoopJobHost();
    jobs = BackgroundJobs(host);
    store = MemoryDownloadQueueStore();
  });

  tearDown(() {
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
  });

  group('engine', () {
    test('downloads into the folder as a background job with per-file progress', () async {
      final Uint8List data = sample(1000);
      final DownloadQueue q = queue(BytesFetcher(data));
      final List<double?> seen = <double?>[];
      q.addListener(() => seen.add(q.tasks.isEmpty ? null : q.tasks.first.fraction));
      final DownloadTask t = await q.add('https://example.com/files/report.pdf');
      expect(t.name, 'report.pdf');
      await until(() => t.state == DownloadState.done, reason: 'for done');
      expect(File('${dir.path}/report.pdf').readAsBytesSync(), data);
      expect(File('${dir.path}/report.pdf.part').existsSync(), isFalse);
      expect(seen.whereType<double>().where((double f) => f > 0 && f < 1), isNotEmpty,
          reason: 'progress is reported between start and end');
      expect(t.statusLine, startsWith('Done'));
      expect(host.log, contains('start 1'));
      expect(host.log, contains('finished 1 done'));
      expect(jobs.jobs.single.title, 'Download report.pdf');
    });

    test('a dropped connection waits, then resumes from where it stopped on reconnect', () async {
      final Uint8List data = sample(1000);
      final BytesFetcher f = BytesFetcher(data)..dropAfter = 300;
      final DownloadQueue q = queue(f);
      final DownloadTask t = await q.add('https://example.com/big.bin');
      await until(() => t.state == DownloadState.waiting, reason: 'for waiting');
      expect(t.received, 300);
      expect(File(t.partPath).lengthSync(), 300);
      expect(t.statusLine, startsWith('Waiting for connection'));
      q.reconnected();
      await until(() => t.state == DownloadState.done, reason: 'for done');
      expect(f.froms, <int>[0, 300]);
      expect(File(t.path).readAsBytesSync(), data);
    });

    test('pause keeps the part; resume asks only for the rest', () async {
      final Uint8List data = sample(800);
      final GatedFetcher f = GatedFetcher(data);
      final DownloadQueue q = queue(f);
      final DownloadTask t = await q.add('https://example.com/a.zip');
      await until(() => f.current != null, reason: 'for the request');
      f.feed(250);
      await until(() => t.received == 250, reason: 'for bytes');
      expect(t.fraction, closeTo(250 / 800, 1e-9));
      q.pause(t.id);
      await until(() => t.state == DownloadState.paused, reason: 'for pause');
      expect(File(t.partPath).lengthSync(), 250);
      expect(jobs.busy, isFalse);

      q.resume(t.id);
      await until(() => f.froms.length == 2, reason: 'for the second request');
      expect(f.froms.last, 250);
      f.feed(1000);
      f.finish();
      await until(() => t.state == DownloadState.done, reason: 'for done');
      expect(File(t.path).readAsBytesSync(), data);
    });

    test('Cancel in the notification pauses the download', () async {
      final GatedFetcher f = GatedFetcher(sample(500));
      final DownloadQueue q = queue(f);
      final DownloadTask t = await q.add('https://example.com/n.bin');
      await until(() => f.current != null);
      f.feed(100);
      await until(() => t.received == 100);
      host.tapCancel(1);
      await Future<void>.delayed(Duration.zero);
      f.feed(100);
      await until(() => t.state == DownloadState.paused, reason: 'for pause');
    });

    test('survives the app closing: a saved running task resumes from its part file', () async {
      final Uint8List data = sample(1000);
      File('${dir.path}/movie.mp4.part').writeAsBytesSync(data.sublist(0, 400));
      store.value = jsonEncode(<String, Object?>{
        'folder': null,
        'tasks': <Object?>[
          <String, Object?>{
            'id': 7,
            'url': 'https://example.com/movie.mp4',
            'folder': dir.path,
            'name': 'movie.mp4',
            'state': 'running',
            'received': 123,
            'total': 1000,
          },
        ],
      });
      final BytesFetcher f = BytesFetcher(data);
      final DownloadQueue q = queue(f);
      await q.load();
      final DownloadTask t = q.tasks.single;
      await until(() => t.state == DownloadState.done, reason: 'for done');
      expect(f.froms, <int>[400]);
      expect(File(t.path).readAsBytesSync(), data);
      final DownloadTask next = await q.add('https://example.com/other.bin');
      expect(next.id, 8);
    });

    test('the queue and the chosen folder are saved and read back', () async {
      final BytesFetcher f = BytesFetcher(sample(300))..offline = true;
      final DownloadQueue q1 = queue(f);
      final Directory other = Directory('${dir.path}/picked')..createSync();
      await q1.setFolder(other.path);
      final DownloadTask t = await q1.add('https://example.com/x.txt');
      expect(t.folder, other.path);
      await until(() => t.state == DownloadState.waiting);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(store.value, contains('waiting'));

      f.offline = false;
      final DownloadQueue q2 = queue(f);
      await q2.load();
      expect(q2.chosenFolder, other.path);
      expect(q2.tasks.single.state, DownloadState.waiting);
      q2.reconnected();
      await until(() => q2.tasks.single.state == DownloadState.done);
      expect(File('${other.path}/x.txt').lengthSync(), 300);
    });

    test('a server that ignores Range gets a clean restart', () async {
      final Uint8List data = sample(600);
      final BytesFetcher f = BytesFetcher(data)..dropAfter = 200;
      final DownloadQueue q = queue(f);
      final DownloadTask t = await q.add('https://example.com/r.bin');
      await until(() => t.state == DownloadState.waiting);
      f.ignoreRange = true;
      q.reconnected();
      await until(() => t.state == DownloadState.done);
      expect(File(t.path).readAsBytesSync(), data);
    });

    test('a server error fails the file; retry fetches it', () async {
      final BytesFetcher f = BytesFetcher(sample(200))..status = 404;
      final DownloadQueue q = queue(f);
      final DownloadTask t = await q.add('https://example.com/missing.pdf');
      await until(() => t.state == DownloadState.failed);
      expect(t.statusLine, 'Failed: Server said 404');
      f.status = 200;
      q.retry(t.id);
      await until(() => t.state == DownloadState.done);
    });

    test('on-device mode keeps downloads waiting without touching the network', () async {
      final BytesFetcher f = BytesFetcher(sample(100));
      String? why = 'On-device mode is on';
      final DownloadQueue q = queue(f, blocked: () => why);
      final DownloadTask t = await q.add('https://example.com/a.bin');
      expect(t.state, DownloadState.waiting);
      expect(t.error, contains('On-device mode'));
      expect(f.froms, isEmpty);
      why = null;
      q.reconnected();
      await until(() => t.state == DownloadState.done);
    });

    test('links, names, sizes and remove with undo', () async {
      final DownloadQueue q = queue(BytesFetcher(sample(10))..offline = true);
      await expectLater(q.add('ftp://example.com/a'), throwsA(isA<DownloadLinkError>()));
      await expectLater(q.add('not a link'), throwsA(isA<DownloadLinkError>()));
      File('${dir.path}/a.bin').writeAsBytesSync(<int>[1]);
      final DownloadTask a = await q.add('https://example.com/a.bin');
      final DownloadTask b = await q.add('https://example.com/a.bin');
      expect(a.name, 'a (2).bin');
      expect(b.name, 'a (3).bin');
      expect(nameFromUrl(Uri.parse('https://example.com/')), 'download');
      expect(nameFromUrl(Uri.parse('https://example.com/a%3Fb.txt')), 'a_b.txt');
      expect(contentRangeTotal('bytes 100-999/1000'), 1000);
      expect(contentRangeTotal('bytes 0-1/*'), isNull);
      expect(formatBytes(2500000), '2.5 MB');

      final (DownloadTask, int)? r = q.remove(a.id);
      expect(q.tasks.map((DownloadTask t) => t.id), <int>[b.id]);
      q.restore(r!);
      expect(q.tasks.map((DownloadTask t) => t.id), <int>[a.id, b.id]);
      await until(() => q.running == 0);
    });
  });

  group('screen', () {
    Future<void> io(WidgetTester tester) async {
      for (int i = 0; i < 6; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump();
      }
    }

    testWidgets('add, progress, pause, resume, done, remove and undo', (WidgetTester tester) async {
      final Uint8List data = sample(400);
      final GatedFetcher f = GatedFetcher(data);
      final DownloadQueue q = queue(f);
      final String picked = '${dir.path}/chosen';
      await tester.pumpWidget(MaterialApp(
        home: DownloadQueueScreen(queue: q, pickFolder: () async => picked),
      ));
      await io(tester);
      expect(find.text('No downloads yet'), findsOneWidget);
      expect(find.text(dir.path), findsOneWidget);

      await tester.enterText(find.byKey(const Key('dl-link')), 'nonsense');
      await tester.tap(find.byKey(const Key('dl-add')));
      await io(tester);
      expect(find.textContaining('http:// or https://'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('dl-link')), 'https://example.com/files/photo.jpg');
      await tester.tap(find.byKey(const Key('dl-add')));
      await io(tester);
      expect(find.text('photo.jpg'), findsOneWidget);
      expect(f.froms, <int>[0]);

      f.feed(100);
      await io(tester);
      expect(find.textContaining('25%'), findsOneWidget);
      expect(
          find.byWidgetPredicate((Widget w) =>
              w is LinearProgressIndicator && w.semanticsLabel == 'photo.jpg progress' && w.semanticsValue == '25%'),
          findsOneWidget);
      final Size pauseSize = tester.getSize(find.byKey(const Key('dl-pause-1')));
      expect(pauseSize.width, greaterThanOrEqualTo(44));
      expect(pauseSize.height, greaterThanOrEqualTo(44));
      expect(find.byTooltip('Pause photo.jpg'), findsOneWidget);

      await tester.tap(find.byKey(const Key('dl-pause-1')));
      await io(tester);
      expect(find.textContaining('Paused'), findsOneWidget);

      await tester.tap(find.byKey(const Key('dl-resume-1')));
      await io(tester);
      expect(f.froms, <int>[0, 100]);
      f.feed(1000);
      f.finish();
      await io(tester);
      expect(find.textContaining('Done'), findsOneWidget);
      await tester.runAsync(() async {
        expect(File('${dir.path}/photo.jpg').readAsBytesSync(), data);
      });

      await tester.tap(find.byKey(const Key('dl-remove-1')));
      await io(tester);
      expect(find.text('photo.jpg'), findsNothing);
      await tester.tap(find.byKey(const Key('result-undo')));
      await io(tester);
      expect(find.text('photo.jpg'), findsOneWidget);

      await tester.tap(find.byKey(const Key('result-save')));
      await io(tester);
      expect(q.chosenFolder, picked);
      expect(find.text(picked), findsOneWidget);
    });
  });
}
