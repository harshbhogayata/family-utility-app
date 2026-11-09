import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../engines/platform/background_jobs.dart';
import '../engines/platform/job_notifications.dart';

/// Android: a data-sync foreground service whose notification shows the
/// progress bar and a Cancel button. iOS: the same notification as text,
/// while the app finishes the job in its background time.
///
/// 113: what each notification says and which buttons it has comes from
/// [JobNotifications.noticeFor]; taps other than Cancel go to [onTap].
class NotificationJobHost implements JobHost {
  NotificationJobHost({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  static const String channelId = 'background_jobs';
  static const String channelName = 'Background jobs';
  static const String cancelAction = JobNotifications.cancelAction;
  static const String runningCategory = 'job_running';
  static const String finishedCategory = 'job_finished';

  /// The service's own notification id; per-job ids start above it.
  static const int serviceId = 6700;

  final FlutterLocalNotificationsPlugin _plugin;
  final StreamController<int> _taps = StreamController<int>.broadcast();
  Future<void>? _ready;
  bool _asked = false;
  bool _service = false;

  /// Share, Open and taps on the notification itself (113).
  Future<JobTapResult> Function(String? actionId, String? payload)? onTap;

  @override
  Stream<int> get cancelTaps => _taps.stream;

  /// Sets up the plugin at app start so a tap that launched the app, or one
  /// that arrives later, reaches [onTap]. Does not ask for permission.
  Future<void> attach() async {
    try {
      await _init();
      final NotificationAppLaunchDetails? launch = await _plugin.getNotificationAppLaunchDetails();
      final NotificationResponse? r = launch?.notificationResponse;
      if (launch != null && launch.didNotificationLaunchApp && r != null) {
        _onResponse(r);
      }
    } catch (e) {
      debugPrint('job notifications launch details: $e');
    }
  }

  Future<void> _init() => _ready ??= _plugin.initialize(
        InitializationSettings(
          android: const AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
            notificationCategories: <DarwinNotificationCategory>[
              DarwinNotificationCategory(runningCategory, actions: <DarwinNotificationAction>[
                DarwinNotificationAction.plain(JobNotifications.cancelAction, 'Cancel'),
              ]),
              DarwinNotificationCategory(finishedCategory, actions: <DarwinNotificationAction>[
                DarwinNotificationAction.plain(
                  JobNotifications.shareAction,
                  'Share',
                  options: <DarwinNotificationActionOption>{DarwinNotificationActionOption.foreground},
                ),
                DarwinNotificationAction.plain(
                  JobNotifications.openAction,
                  'Open',
                  options: <DarwinNotificationActionOption>{DarwinNotificationActionOption.foreground},
                ),
              ]),
            ],
          ),
        ),
        onDidReceiveNotificationResponse: _onResponse,
      );

  /// Asks once, when the first job starts, so a fresh install is not
  /// greeted by a permission prompt.
  Future<void> _askPermission() async {
    if (_asked) {
      return;
    }
    _asked = true;
    await _android?.requestNotificationsPermission();
    await _plugin
        .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: false, sound: false);
  }

  void _onResponse(NotificationResponse response) {
    if (response.actionId == JobNotifications.cancelAction) {
      final JobPayload? p = JobPayload.decode(response.payload);
      if (p != null) {
        _taps.add(p.jobId);
      }
      return;
    }
    final Future<JobTapResult> Function(String? actionId, String? payload)? handler = onTap;
    if (handler != null) {
      unawaited(handler(response.actionId, response.payload));
    }
  }

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  NotificationDetails _details(JobNotice notice) {
    return NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        channelName,
        channelDescription: 'Progress of long conversions and their results',
        importance: Importance.low,
        priority: Priority.low,
        onlyAlertOnce: true,
        ongoing: notice.ongoing,
        autoCancel: !notice.ongoing,
        showProgress: notice.progress != null,
        maxProgress: 100,
        progress: notice.progress ?? 0,
        actions: <AndroidNotificationAction>[
          for (final JobNoticeAction a in notice.actions)
            AndroidNotificationAction(a.id, a.label, showsUserInterface: true),
        ],
      ),
      iOS: DarwinNotificationDetails(
        presentSound: false,
        categoryIdentifier: notice.ongoing ? runningCategory : finishedCategory,
      ),
    );
  }

  @override
  Future<void> start(JobRecord first) async {
    await _init();
    await _askPermission();
    if (!kIsWeb && Platform.isAndroid) {
      final JobNotice notice = JobNotifications.noticeFor(first);
      try {
        await _android?.startForegroundService(
          serviceId,
          first.title,
          'Keeps working while you use other apps',
          notificationDetails: _details(notice).android,
          payload: notice.payload,
          foregroundServiceTypes: <AndroidServiceForegroundType>{
            AndroidServiceForegroundType.foregroundServiceTypeDataSync,
          },
        );
        _service = true;
      } catch (e) {
        // Service not declared on this build: the notification still shows.
        debugPrint('foreground service unavailable: $e');
      }
    }
    await update(first);
  }

  @override
  Future<void> update(JobRecord job) async {
    await _init();
    final JobNotice notice = JobNotifications.noticeFor(job);
    await _plugin.show(serviceId + job.id, notice.title, notice.body, _details(notice), payload: notice.payload);
  }

  @override
  Future<void> finished(JobRecord job) async {
    await _init();
    final JobNotice notice = JobNotifications.noticeFor(job);
    await _plugin.show(serviceId + job.id, notice.title, notice.body, _details(notice), payload: notice.payload);
  }

  @override
  Future<void> stop() async {
    if (_service) {
      _service = false;
      await _android?.stopForegroundService();
    }
  }
}
