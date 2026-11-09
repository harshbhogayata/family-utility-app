import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../engines/platform/background_jobs.dart';

/// Android: a data-sync foreground service whose notification shows the
/// progress bar and a Cancel button. iOS: the same notification as text,
/// while the app finishes the job in its background time.
class NotificationJobHost implements JobHost {
  NotificationJobHost({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  static const String channelId = 'background_jobs';
  static const String channelName = 'Background jobs';
  static const String cancelAction = 'cancel_job';

  /// The service's own notification id; per-job ids start above it.
  static const int serviceId = 6700;

  final FlutterLocalNotificationsPlugin _plugin;
  final StreamController<int> _taps = StreamController<int>.broadcast();
  bool _ready = false;
  bool _service = false;

  @override
  Stream<int> get cancelTaps => _taps.stream;

  Future<void> _init() async {
    if (_ready) {
      return;
    }
    _ready = true;
    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ),
      onDidReceiveNotificationResponse: _onResponse,
    );
    await _android?.requestNotificationsPermission();
  }

  void _onResponse(NotificationResponse response) {
    if (response.actionId != cancelAction) {
      return;
    }
    final int? id = int.tryParse(response.payload ?? '');
    if (id != null) {
      _taps.add(id);
    }
  }

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  NotificationDetails _details(JobRecord job, {required bool running}) {
    return NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        channelName,
        channelDescription: 'Progress of long conversions',
        importance: Importance.low,
        priority: Priority.low,
        onlyAlertOnce: true,
        ongoing: running,
        autoCancel: !running,
        showProgress: running,
        maxProgress: 100,
        progress: job.percent,
        actions: running
            ? const <AndroidNotificationAction>[
                AndroidNotificationAction(cancelAction, 'Cancel', showsUserInterface: true),
              ]
            : null,
      ),
      iOS: const DarwinNotificationDetails(presentSound: false),
    );
  }

  @override
  Future<void> start(JobRecord first) async {
    await _init();
    if (!kIsWeb && Platform.isAndroid) {
      try {
        await _android?.startForegroundService(
          serviceId,
          first.title,
          'Keeps working while you use other apps',
          notificationDetails: _details(first, running: true).android,
          payload: '${first.id}',
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
    await _plugin.show(
      serviceId + job.id,
      job.title,
      job.statusLine,
      _details(job, running: true),
      payload: '${job.id}',
    );
  }

  @override
  Future<void> finished(JobRecord job) async {
    await _init();
    await _plugin.show(serviceId + job.id, job.title, job.statusLine, _details(job, running: false));
  }

  @override
  Future<void> stop() async {
    if (_service) {
      _service = false;
      await _android?.stopForegroundService();
    }
  }
}
