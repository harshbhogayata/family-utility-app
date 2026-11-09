import 'dart:async';

import 'package:family_utility_app/app/theme.dart';
import 'package:family_utility_app/engines/platform/background_jobs.dart';
import 'package:family_utility_app/tools/background_jobs/background_jobs_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A job that advances one step each time [step] completes.
class SteppedJob {
  final List<Completer<void>> gates = <Completer<void>>[];

  Future<String> body(JobContext ctx, int steps) async {
    for (int i = 0; i < steps; i++) {
      final Completer<void> gate = Completer<void>();
      gates.add(gate);
      await gate.future;
      ctx.report((i + 1) / steps, 'Step ${i + 1} of $steps');
    }
    return '/out/result.pdf';
  }

  Future<void> step() async {
    gates.removeAt(0).complete();
    await Future<void>.delayed(Duration.zero);
  }
}

Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  group('engine', () {
    test('starts the service, reports progress, finishes and stops', () async {
      final NoopJobHost host = NoopJobHost();
      final BackgroundJobs jobs = BackgroundJobs(host);
      final SteppedJob s = SteppedJob();
      final Future<String> f = jobs.run('Compress PDF', (JobContext c) => s.body(c, 4), outputOf: (String r) => r);
      await settle();
      expect(host.log.first, 'start 1');
      expect(jobs.busy, isTrue);
      await s.step();
      expect(jobs.jobs.single.percent, 25);
      expect(jobs.jobs.single.statusLine, '25% · Step 1 of 4');
      await s.step();
      await s.step();
      await s.step();
      expect(await f, '/out/result.pdf');
      final JobRecord j = jobs.jobs.single;
      expect(j.state, JobState.done);
      expect(j.outputPath, '/out/result.pdf');
      expect(host.log, containsAllInOrder(<String>['update 1 25', 'update 1 100', 'finished 1 done', 'stop']));
      expect(jobs.busy, isFalse);
    });

    test('Cancel in the notification stops the job at its next step', () async {
      final NoopJobHost host = NoopJobHost();
      final BackgroundJobs jobs = BackgroundJobs(host);
      final SteppedJob s = SteppedJob();
      final Future<String> f = jobs.run('Convert', (JobContext c) => s.body(c, 3));
      await settle();
      await s.step();
      host.tapCancel(1);
      await settle();
      expect(jobs.jobs.single.detail, 'Cancelling…');
      final Future<void> expectation = expectLater(f, throwsA(isA<JobCancelled>()));
      await s.step();
      await expectation;
      expect(jobs.jobs.single.state, JobState.cancelled);
      expect(host.log, contains('finished 1 cancelled'));
      expect(host.log.last, 'stop');
    });

    test('a failing job is recorded and the service stops only when all are done', () async {
      final NoopJobHost host = NoopJobHost();
      final BackgroundJobs jobs = BackgroundJobs(host);
      final SteppedJob s = SteppedJob();
      final Future<String> long = jobs.run('Long', (JobContext c) => s.body(c, 1));
      await settle();
      await expectLater(jobs.run<void>('Bad', (JobContext c) async => throw StateError('broken')), throwsStateError);
      expect(host.log.where((String l) => l == 'start 1').length, 1);
      expect(host.log, isNot(contains('stop')));
      expect(jobs.jobs.first.statusLine, startsWith('Failed'));
      await s.step();
      await long;
      expect(host.log.last, 'stop');
    });

    test('a broken notification host never fails the job', () async {
      final BackgroundJobs jobs = BackgroundJobs(_ThrowingHost());
      expect(await jobs.run('Ok', (JobContext c) async {
        c.report(0.5);
        return 7;
      }), 7);
    });

    test('clear finished and put back', () async {
      final BackgroundJobs jobs = BackgroundJobs(NoopJobHost());
      await jobs.run('A', (JobContext c) async => 1);
      await jobs.run('B', (JobContext c) async => 2);
      final List<JobRecord> gone = jobs.clearFinished();
      expect(gone.length, 2);
      expect(jobs.jobs, isEmpty);
      jobs.restore(gone);
      expect(jobs.jobs.map((JobRecord j) => j.title), <String>['B', 'A']);
    });
  });

  group('screen', () {
    testWidgets('shows progress with a Cancel button that stops the job', (WidgetTester tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      final BackgroundJobs jobs = BackgroundJobs(NoopJobHost());
      await tester.pumpWidget(MaterialApp(theme: buildAppTheme(), home: BackgroundJobsScreen(engine: jobs)));
      expect(find.byKey(const Key('jobs-empty')), findsOneWidget);

      final SteppedJob s = SteppedJob();
      Object? error;
      unawaited(jobs.run('Compress PDF', (JobContext c) => s.body(c, 2)).catchError((Object e) {
        error = e;
        return '';
      }));
      await tester.pump(const Duration(milliseconds: 10));
      await tester.pump(const Duration(milliseconds: 10));
      expect(s.gates, hasLength(1));
      s.gates.removeAt(0).complete();
      await tester.pump(const Duration(milliseconds: 10));
      await tester.pump(const Duration(milliseconds: 10));
      expect(jobs.jobs.single.percent, 50);
      expect(tester.widget<Text>(find.byKey(const Key('job-status-1'))).data, '50% · Step 1 of 2');
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      final Finder cancel = find.byKey(const Key('job-cancel-1'));
      expect(tester.getSize(cancel).height, greaterThanOrEqualTo(44));
      expect(find.bySemanticsLabel('Cancel Compress PDF'), findsOneWidget);

      await tester.tap(cancel);
      await tester.pump(const Duration(milliseconds: 10));
      s.gates.removeAt(0).complete();
      await tester.pump(const Duration(milliseconds: 10));
      await tester.pump(const Duration(milliseconds: 10));
      expect(error, isA<JobCancelled>());
      expect(find.text('Cancelled'), findsOneWidget);
      expect(find.byKey(const Key('job-cancel-1')), findsNothing);

      await tester.tap(find.byKey(const Key('result-save')));
      await tester.pump();
      expect(find.byKey(const Key('job-1')), findsNothing);
      await tester.tap(find.byKey(const Key('result-undo')));
      await tester.pump();
      expect(find.byKey(const Key('job-1')), findsOneWidget);
      handle.dispose();
    });
  });
}

class _ThrowingHost implements JobHost {
  @override
  Stream<int> get cancelTaps => Stream<int>.empty();

  @override
  Future<void> start(JobRecord first) async => throw StateError('no service');

  @override
  Future<void> update(JobRecord job) async => throw StateError('no notifications');

  @override
  Future<void> finished(JobRecord job) async => throw StateError('no notifications');

  @override
  Future<void> stop() async => throw StateError('no service');
}
