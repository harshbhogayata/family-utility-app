import 'dart:async';
import 'dart:io';

import 'package:family_utility_app/app/theme.dart';
import 'package:family_utility_app/engines/platform/background_jobs.dart';
import 'package:family_utility_app/engines/platform/job_notifications.dart';
import 'package:family_utility_app/engines/share/share_engine.dart';
import 'package:family_utility_app/tools/background_jobs/background_jobs_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records what each job's notification would show at every host call.
class NoticeHost implements JobHost {
  final StreamController<int> _taps = StreamController<int>.broadcast();
  final List<JobNotice> shown = <JobNotice>[];

  void tapCancel(int id) => _taps.add(id);

  @override
  Stream<int> get cancelTaps => _taps.stream;

  @override
  Future<void> start(JobRecord first) async => shown.add(JobNotifications.noticeFor(first));

  @override
  Future<void> update(JobRecord job) async => shown.add(JobNotifications.noticeFor(job));

  @override
  Future<void> finished(JobRecord job) async => shown.add(JobNotifications.noticeFor(job));

  @override
  Future<void> stop() async {}
}

class FakeSheet implements ShareSheet {
  final List<ShareRequest> requests = <ShareRequest>[];

  @override
  Future<ShareOutcome> share(ShareRequest request) async {
    requests.add(request);
    return const ShareOutcome(completed: true);
  }
}

Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  group('notice', () {
    test('running jobs post progress with Cancel', () async {
      final NoticeHost host = NoticeHost();
      final BackgroundJobs jobs = BackgroundJobs(host);
      final Completer<void> gate = Completer<void>();
      final Future<String> f = jobs.run('Compress PDF', (JobContext c) async {
        c.report(0.4, 'Page 4 of 10');
        await gate.future;
        c.addOutput('/out/small.pdf');
        return '/out/small.pdf';
      });
      await settle();
      final JobNotice running = host.shown.last;
      expect(running.ongoing, isTrue);
      expect(running.progress, 40);
      expect(running.body, '40% · Page 4 of 10');
      expect(running.actions, <JobNoticeAction>[JobNotifications.cancel]);

      gate.complete();
      await f;
      final JobNotice done = host.shown.last;
      expect(done.ongoing, isFalse);
      expect(done.progress, isNull);
      expect(done.body, 'Done · tap to share');
      expect(done.actions, <JobNoticeAction>[JobNotifications.shareButton, JobNotifications.openButton]);
      final JobPayload p = JobPayload.decode(done.payload)!;
      expect(p.jobId, 1);
      expect(p.files, <String>['/out/small.pdf']);
    });

    test('outputOf and addOutput are merged without repeats', () async {
      final BackgroundJobs jobs = BackgroundJobs(NoticeHost());
      await jobs.run('Two', (JobContext c) async {
        c.addOutput('/a.jpg');
        c.addOutput('/b.jpg');
        return '/a.jpg';
      }, outputOf: (String r) => r);
      final JobRecord j = jobs.jobs.single;
      expect(j.outputs, <String>['/a.jpg', '/b.jpg']);
      expect(j.outputPath, '/a.jpg');
      expect(JobNotifications.noticeFor(j).body, 'Done · 2 files · tap to share');
    });

    test('failed and cancelled jobs still end with a result action', () async {
      final NoticeHost host = NoticeHost();
      final BackgroundJobs jobs = BackgroundJobs(host);
      await expectLater(jobs.run<void>('Broken', (JobContext c) async => throw StateError('bad file')), throwsStateError);
      expect(host.shown.last.body, startsWith('Failed: '));
      expect(host.shown.last.body, endsWith('tap for details'));
      expect(host.shown.last.actions, <JobNoticeAction>[JobNotifications.openButton]);

      final Completer<void> gate = Completer<void>();
      final Future<void> f = jobs.run<void>('Batch', (JobContext c) async {
        c.addOutput('/kept.png');
        await gate.future;
        c.throwIfCancelled();
      });
      await settle();
      host.tapCancel(2);
      await settle();
      gate.complete();
      await expectLater(f, throwsA(isA<JobCancelled>()));
      expect(host.shown.last.body, 'Cancelled · 1 file kept · tap to share');
      expect(host.shown.last.actions.first, JobNotifications.shareButton);
    });

    test('a job with no file says so and offers Open', () async {
      final NoticeHost host = NoticeHost();
      await BackgroundJobs(host).run('Index', (JobContext c) async => 0);
      expect(host.shown.last.body, 'Done · tap to see it');
      expect(host.shown.last.actions, <JobNoticeAction>[JobNotifications.openButton]);
    });

    test('payload decodes the JSON form and the old bare id', () {
      expect(JobPayload.decode('7')!.jobId, 7);
      expect(JobPayload.decode(const JobPayload(3, <String>['/x']).encode())!.files, <String>['/x']);
      expect(JobPayload.decode(null), isNull);
      expect(JobPayload.decode('not json'), isNull);
    });
  });

  group('taps', () {
    late BackgroundJobs jobs;
    late List<List<String>> shared;
    late List<int> opened;
    late JobNotifications n;

    setUp(() {
      jobs = BackgroundJobs(NoticeHost());
      shared = <List<String>>[];
      opened = <int>[];
      n = JobNotifications(
        jobs: jobs,
        share: (List<String> p) async => shared.add(p),
        open: opened.add,
      );
    });

    test('tapping a finished notification shares its files', () async {
      await jobs.run('Zip', (JobContext c) async => '/out/a.zip', outputOf: (String r) => r);
      final String payload = JobNotifications.noticeFor(jobs.jobs.single).payload;
      expect(await n.handle(null, payload), JobTapResult.shared);
      expect(await n.handle(JobNotifications.shareAction, payload), JobTapResult.shared);
      expect(shared, <List<String>>[
        <String>['/out/a.zip'],
        <String>['/out/a.zip'],
      ]);
      expect(await n.handle(JobNotifications.openAction, payload), JobTapResult.opened);
      expect(opened, <int>[1]);
    });

    test('after a restart the payload still carries the files', () async {
      final String payload = const JobPayload(9, <String>['/out/old.pdf']).encode();
      expect(await n.handle('', payload), JobTapResult.shared);
      expect(shared.single, <String>['/out/old.pdf']);
      expect(await n.handle(null, '9'), JobTapResult.opened);
    });

    test('a running job opens the list; Cancel stops it', () async {
      final Completer<void> gate = Completer<void>();
      final Future<void> f = jobs.run<void>('Long', (JobContext c) async {
        await gate.future;
        c.throwIfCancelled();
      });
      await settle();
      final String payload = JobNotifications.noticeFor(jobs.jobs.single).payload;
      expect(await n.handle(null, payload), JobTapResult.opened);
      expect(await n.handle(JobNotifications.cancelAction, payload), JobTapResult.cancelled);
      gate.complete();
      await expectLater(f, throwsA(isA<JobCancelled>()));
      expect(await n.handle('something_else', payload), JobTapResult.ignored);
      expect(await n.handle(null, null), JobTapResult.ignored);
    });
  });

  group('screen', () {
    testWidgets('finished job has a labelled Share that sends every file', (WidgetTester tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      final BackgroundJobs jobs = BackgroundJobs(NoticeHost());
      final FakeSheet sheet = FakeSheet();
      await tester.runAsync(() async {
        await jobs.run('Convert 2 photos', (JobContext c) async {
          c.addOutput('/out/1.jpg');
          c.addOutput('/out/2.jpg');
          return 2;
        });
        await jobs.run('Other', (JobContext c) async => 0);
      });
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: BackgroundJobsScreen(engine: jobs, share: ShareEngine(sheet, MemoryShareTargetStore()), highlight: 1),
      ));
      await tester.pump();
      // The tapped job is listed first even though it is older.
      final double first = tester.getTopLeft(find.byKey(const Key('job-1'))).dy;
      final double second = tester.getTopLeft(find.byKey(const Key('job-2'))).dy;
      expect(first, lessThan(second));
      expect(find.byKey(const Key('job-share-2')), findsNothing);

      final Finder share = find.byKey(const Key('job-share-1'));
      expect(tester.getSize(share).height, greaterThanOrEqualTo(44));
      expect(find.bySemanticsLabel('Share what Convert 2 photos made'), findsOneWidget);
      await tester.tap(share);
      await tester.pump();
      expect(sheet.requests.single.files.map((ShareFile f) => f.path), <String>['/out/1.jpg', '/out/2.jpg']);
      handle.dispose();
    });

    testWidgets('a note passed in is shown', (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: BackgroundJobsScreen(engine: BackgroundJobs(NoticeHost()), note: 'That file was moved or removed'),
      ));
      expect(find.text('That file was moved or removed'), findsOneWidget);
    });
  });

  test('every job that makes files registers them for the notification', () {
    final List<String> missing = <String>[];
    for (final FileSystemEntity e in Directory('lib').listSync(recursive: true)) {
      if (e is! File || !e.path.endsWith('.dart') || e.path.endsWith('background_jobs.dart')) {
        continue;
      }
      final String src = e.readAsStringSync();
      if (src.contains('(JobContext ') && !src.contains('addOutput(') && !src.contains('outputOf:')) {
        missing.add(e.path);
      }
    }
    expect(missing, isEmpty);
  });

  test('nothing in the notification path uploads', () {
    final String src = File('lib/engines/platform/job_notifications.dart').readAsStringSync() +
        File('lib/platform/job_host_platform.dart').readAsStringSync();
    expect(src.contains('HttpClient'), isFalse);
    expect(src.contains('package:http'), isFalse);
  });
}
