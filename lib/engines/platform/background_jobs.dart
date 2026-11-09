import 'dart:async';

import 'package:flutter/foundation.dart';

/// Feature 067 — Background jobs.
///
/// Long conversions run through [BackgroundJobs]. While any job runs, the
/// [JobHost] keeps the app alive (a foreground service on Android, a
/// background task on iOS) and shows progress with a Cancel button. Jobs run
/// in this app's process only; nothing is uploaded.

enum JobState { running, done, failed, cancelled }

/// Thrown inside a job body when the person cancelled it.
class JobCancelled implements Exception {
  const JobCancelled();

  @override
  String toString() => 'Job cancelled';
}

/// What a job body uses to report progress and notice a cancel.
class JobContext {
  JobContext._(this._job, this._engine);

  final JobRecord _job;
  final BackgroundJobs _engine;

  bool get cancelled => _job._cancelRequested;

  /// Throws [JobCancelled] if the person tapped Cancel. Call between steps.
  void throwIfCancelled() {
    if (cancelled) {
      throw const JobCancelled();
    }
  }

  /// [fraction] runs from 0 to 1. [detail] is a short line such as "Page 3 of 10".
  void report(double fraction, [String? detail]) {
    throwIfCancelled();
    _engine._progress(_job, fraction, detail);
  }
}

/// One job as the jobs screen and the notification see it.
class JobRecord {
  JobRecord._(this.id, this.title, this.startedAt);

  final int id;
  final String title;
  final DateTime startedAt;

  JobState state = JobState.running;
  double fraction = 0;
  String? detail;
  String? error;

  /// Path of the file the job produced, if any, for Share.
  String? outputPath;
  DateTime? finishedAt;
  bool _cancelRequested = false;

  int get percent => (fraction * 100).clamp(0, 100).round();
  bool get active => state == JobState.running;

  String get statusLine {
    switch (state) {
      case JobState.running:
        return detail == null ? '$percent%' : '$percent% · $detail';
      case JobState.done:
        return 'Done';
      case JobState.failed:
        return 'Failed: ${error ?? 'unknown error'}';
      case JobState.cancelled:
        return 'Cancelled';
    }
  }
}

/// The phone side: keep-alive service plus the progress notification.
abstract class JobHost {
  /// Called when the first job starts. Starts the foreground service.
  Future<void> start(JobRecord first);

  /// Progress for one job; called at most once per whole percent.
  Future<void> update(JobRecord job);

  /// A job ended; shows a done, failed or cancelled notification.
  Future<void> finished(JobRecord job);

  /// Called when no job is left. Stops the service.
  Future<void> stop();

  /// Job ids whose Cancel button was tapped in the notification.
  Stream<int> get cancelTaps;
}

/// No service and no notifications: tests and platforms without support.
class NoopJobHost implements JobHost {
  NoopJobHost();

  final StreamController<int> _taps = StreamController<int>.broadcast();
  final List<String> log = <String>[];

  /// Simulates tapping Cancel in the notification.
  void tapCancel(int id) => _taps.add(id);

  @override
  Future<void> start(JobRecord first) async => log.add('start ${first.id}');

  @override
  Future<void> update(JobRecord job) async => log.add('update ${job.id} ${job.percent}');

  @override
  Future<void> finished(JobRecord job) async => log.add('finished ${job.id} ${job.state.name}');

  @override
  Future<void> stop() async => log.add('stop');

  @override
  Stream<int> get cancelTaps => _taps.stream;
}

typedef JobBody<T> = Future<T> Function(JobContext context);

class BackgroundJobs extends ChangeNotifier {
  BackgroundJobs(this._host) {
    _sub = _host.cancelTaps.listen(cancel);
  }

  final JobHost _host;
  late final StreamSubscription<int> _sub;
  final List<JobRecord> _jobs = <JobRecord>[];
  int _nextId = 1;
  bool _hostRunning = false;

  /// Newest first.
  List<JobRecord> get jobs => List<JobRecord>.unmodifiable(_jobs.reversed);
  List<JobRecord> get active => _jobs.where((JobRecord j) => j.active).toList();
  bool get busy => _jobs.any((JobRecord j) => j.active);

  /// Runs [body] as a background job. Returns the body's result, or throws
  /// [JobCancelled] if cancelled, or the body's own error if it failed.
  Future<T> run<T>(String title, JobBody<T> body, {String? Function(T result)? outputOf}) async {
    final JobRecord job = JobRecord._(_nextId++, title, DateTime.now());
    _jobs.add(job);
    notifyListeners();
    if (!_hostRunning) {
      _hostRunning = true;
      await _safe(() => _host.start(job));
    }
    try {
      final T result = await body(JobContext._(job, this));
      if (job._cancelRequested) {
        throw const JobCancelled();
      }
      job
        ..state = JobState.done
        ..fraction = 1
        ..outputPath = outputOf?.call(result);
      return result;
    } on JobCancelled {
      job.state = JobState.cancelled;
      rethrow;
    } catch (e) {
      job
        ..state = JobState.failed
        ..error = e.toString();
      rethrow;
    } finally {
      job.finishedAt = DateTime.now();
      notifyListeners();
      await _safe(() => _host.finished(job));
      if (!busy && _hostRunning) {
        _hostRunning = false;
        await _safe(_host.stop);
      }
    }
  }

  /// Asks a running job to stop at its next step.
  void cancel(int id) {
    for (final JobRecord j in _jobs) {
      if (j.id == id && j.active && !j._cancelRequested) {
        j._cancelRequested = true;
        j.detail = 'Cancelling…';
        notifyListeners();
      }
    }
  }

  /// Removes finished jobs from the list; returns them so Undo can put them back.
  List<JobRecord> clearFinished() {
    final List<JobRecord> gone = _jobs.where((JobRecord j) => !j.active).toList();
    _jobs.removeWhere((JobRecord j) => !j.active);
    notifyListeners();
    return gone;
  }

  void restore(List<JobRecord> records) {
    _jobs
      ..addAll(records)
      ..sort((JobRecord a, JobRecord b) => a.id.compareTo(b.id));
    notifyListeners();
  }

  void _progress(JobRecord job, double fraction, String? detail) {
    final int before = job.percent;
    job.fraction = fraction.clamp(0.0, 1.0).toDouble();
    final bool detailChanged = detail != job.detail;
    job.detail = detail;
    if (job.percent != before || detailChanged) {
      notifyListeners();
      unawaited(_safe(() => _host.update(job)));
    }
  }

  /// The host is the phone's; a failing notification must not fail the job.
  Future<void> _safe(Future<void> Function() f) async {
    try {
      await f();
    } catch (e) {
      debugPrint('background jobs host: $e');
    }
  }

  @override
  void dispose() {
    unawaited(_sub.cancel());
    super.dispose();
  }

  static BackgroundJobs? _instance;

  /// App-wide engine; bootstrap installs the phone's host.
  static BackgroundJobs get instance => _instance ??= BackgroundJobs(NoopJobHost());

  static void install(BackgroundJobs engine) => _instance = engine;
}
