import 'dart:convert';
import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';

import '../engines/family/family_location.dart';

/// Feature 076 — one position at a time from the phone's own location
/// service. Nothing is sent anywhere by this class.
class GeolocatorPositionSource implements PositionSource {
  const GeolocatorPositionSource();

  @override
  Future<LocationFix?> current() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return null;
    }
    LocationPermission p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) {
      p = await Geolocator.requestPermission();
    }
    if (p == LocationPermission.denied || p == LocationPermission.deniedForever) {
      return null;
    }
    final Position pos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium, timeLimit: Duration(seconds: 30)),
    );
    return LocationFix(pos.latitude, pos.longitude, pos.timestamp.toLocal(), accuracy: pos.accuracy);
  }
}

/// The 7-day trail as JSON in an app-private file.
class FileLocationHistoryStore implements LocationHistoryStore {
  const FileLocationHistoryStore(this.folder);

  final Future<Directory> Function() folder;

  Future<File> _file() async {
    final Directory d = await folder();
    if (!await d.exists()) {
      await d.create(recursive: true);
    }
    return File('${d.path}/location_history.json');
  }

  @override
  Future<List<LocationFix>> read() async {
    final File f = await _file();
    if (!await f.exists()) {
      return <LocationFix>[];
    }
    final Object? data = jsonDecode(await f.readAsString());
    final List<LocationFix> out = <LocationFix>[];
    if (data is List<Object?>) {
      for (final Object? e in data) {
        if (e is Map<String, Object?>) {
          final LocationFix? fix = LocationFix.fromJson(e);
          if (fix != null) {
            out.add(fix);
          }
        }
      }
    }
    return out;
  }

  @override
  Future<void> write(List<LocationFix> fixes) async {
    final File f = await _file();
    await f.writeAsString(jsonEncode(<Object?>[for (final LocationFix x in fixes) x.toJson()]), flush: true);
  }
}

/// Arrive and leave alerts as local notifications.
class NotificationPlaceEvents implements PlaceEventSink {
  NotificationPlaceEvents({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  int _n = 0;

  @override
  Future<void> notify(String text) async {
    await _plugin.show(
      760000 + (_n++ & 0xFFFF),
      text,
      'Family places',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'family_places',
          'Family arrive and leave',
          channelDescription: 'When a family member arrives at or leaves a saved place',
        ),
        iOS: DarwinNotificationDetails(),
      ),
    );
  }
}
