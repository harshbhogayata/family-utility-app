import 'dart:convert';

import 'background_jobs.dart';

/// Feature 113 — Job notifications.
///
/// Every background job (067) shows its progress in a notification. When it
/// ends, the notification says how it went and carries a result action:
/// Share for the files it made (tapping the notification also shares), and
/// Open to see the job in the app. Files never leave the phone unless the
/// person picks a share target.

/// One button on a notification.
class JobNoticeAction {
  const JobNoticeAction(this.id, this.label);

  final String id;
  final String label;

  @override
  bool operator ==(Object other) => other is JobNoticeAction && other.id == id && other.label == label;

  @override
  int get hashCode => Object.hash(id, label);

  @override
  String toString() => 'JobNoticeAction($id, $label)';
}

/// What a notification for one job shows. The phone layer turns it into a
/// real notification; tests read it directly.
class JobNotice {
  const JobNotice({
    required this.title,
    required this.body,
    required this.ongoing,
    required this.payload,
    this.progress,
    this.actions = const <JobNoticeAction>[],
  });

  final String title;
  final String body;

  /// True while the job runs: the notification cannot be swiped away.
  final bool ongoing;

  /// 0 to 100 while running; null once the job ended.
  final int? progress;
  final List<JobNoticeAction> actions;

  /// Carries the job id and its files, so Share still works after the app
  /// was closed and the job list is gone.
  final String payload;
}

/// What a tap on a notification did.
enum JobTapResult { cancelled, shared, opened, ignored }

/// The job id and files decoded from a notification's payload.
class JobPayload {
  const JobPayload(this.jobId, this.files);

  final int jobId;
  final List<String> files;

  String encode() => jsonEncode(<String, Object>{'id': jobId, 'files': files});

  /// Accepts the JSON form and the bare id older notifications carried.
  static JobPayload? decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    final int? bare = int.tryParse(raw.trim());
    if (bare != null) {
      return JobPayload(bare, const <String>[]);
    }
    try {
      final Object? data = jsonDecode(raw);
      if (data is! Map) {
        return null;
      }
      final Object? id = data['id'];
      final Object? files = data['files'];
      if (id is! int) {
        return null;
      }
      return JobPayload(
        id,
        files is List ? files.whereType<String>().toList() : const <String>[],
      );
    } on FormatException {
      return null;
    }
  }
}

typedef ShareJobFiles = Future<void> Function(List<String> paths);
typedef OpenJob = void Function(int jobId);

class JobNotifications {
  JobNotifications({required this.jobs, required this.share, required this.open});

  static const String cancelAction = 'cancel_job';
  static const String shareAction = 'share_job';
  static const String openAction = 'open_job';

  static const JobNoticeAction cancel = JobNoticeAction(cancelAction, 'Cancel');
  static const JobNoticeAction shareButton = JobNoticeAction(shareAction, 'Share');
  static const JobNoticeAction openButton = JobNoticeAction(openAction, 'Open');

  final BackgroundJobs jobs;
  final ShareJobFiles share;
  final OpenJob open;

  /// The notification for [job] as it is right now.
  static JobNotice noticeFor(JobRecord job) {
    final String payload = JobPayload(job.id, List<String>.of(job.outputs)).encode();
    if (job.active) {
      return JobNotice(
        title: job.title,
        body: job.statusLine,
        ongoing: true,
        progress: job.percent,
        payload: payload,
        actions: const <JobNoticeAction>[cancel],
      );
    }
    final int n = job.outputs.length;
    final String files = n == 1 ? '1 file' : '$n files';
    final String body;
    if (job.state == JobState.done) {
      body = n == 0
          ? 'Done · tap to see it'
          : n == 1
              ? 'Done · tap to share'
              : 'Done · $files · tap to share';
    } else if (job.state == JobState.failed) {
      body = n == 0 ? '${job.statusLine} · tap for details' : '${job.statusLine} · $files kept · tap to share';
    } else {
      body = n == 0 ? 'Cancelled · tap to see it' : 'Cancelled · $files kept · tap to share';
    }
    return JobNotice(
      title: job.title,
      body: body,
      ongoing: false,
      payload: payload,
      actions: n == 0
          ? const <JobNoticeAction>[openButton]
          : const <JobNoticeAction>[shareButton, openButton],
    );
  }

  /// Handles a tap on the notification ([actionId] null or empty) or on
  /// one of its buttons.
  Future<JobTapResult> handle(String? actionId, String? payload) async {
    final JobPayload? p = JobPayload.decode(payload);
    if (p == null) {
      return JobTapResult.ignored;
    }
    final JobRecord? job = jobs.byId(p.jobId);
    final String action = actionId ?? '';
    if (action == cancelAction) {
      if (job == null || !job.active) {
        return JobTapResult.ignored;
      }
      jobs.cancel(job.id);
      return JobTapResult.cancelled;
    }
    if (action == openAction) {
      open(p.jobId);
      return JobTapResult.opened;
    }
    if (action == shareAction || action.isEmpty) {
      if (job != null && job.active) {
        open(p.jobId);
        return JobTapResult.opened;
      }
      // The live record knows best; after a restart the payload has the files.
      final List<String> files = job != null && job.outputs.isNotEmpty ? List<String>.of(job.outputs) : p.files;
      if (files.isEmpty) {
        open(p.jobId);
        return JobTapResult.opened;
      }
      await share(files);
      return JobTapResult.shared;
    }
    return JobTapResult.ignored;
  }

  static JobNotifications? _instance;

  /// App-wide handler; bootstrap installs one wired to the share sheet.
  static JobNotifications? get instance => _instance;

  static void install(JobNotifications handler) => _instance = handler;
}
