import 'dart:io';

import 'package:add_2_calendar/add_2_calendar.dart' as cal;
import 'package:flutter/services.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wifi_iot/wifi_iot.dart';

import '../../engines/qr/qr_actions.dart';
import '../../engines/qr/qr_payload.dart';

/// Real device actions. Every call stays on the phone: links open in the
/// system browser or app, contacts and events go to the device's own apps.
class PlatformQrActions implements QrActions {
  const PlatformQrActions();

  @override
  Future<bool> openUri(Uri uri) async {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<bool> joinWifi(WifiPayload wifi) async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return false;
    }
    final NetworkSecurity security;
    switch (wifi.security) {
      case WifiSecurity.wpa:
        security = NetworkSecurity.WPA;
      case WifiSecurity.wep:
        security = NetworkSecurity.WEP;
      case WifiSecurity.open:
        security = NetworkSecurity.NONE;
    }
    try {
      return await WiFiForIoTPlugin.connect(
        wifi.ssid,
        password: wifi.password.isEmpty ? null : wifi.password,
        security: security,
        isHidden: wifi.hidden,
        joinOnce: false,
        withInternet: true,
      );
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<bool> saveContact(VCardPayload card) async {
    try {
      if (!await FlutterContacts.requestPermission()) {
        return false;
      }
      final Contact contact = Contact.fromVCard(card.raw);
      await contact.insert();
      return true;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<bool> addEvent(EventPayload event) async {
    final DateTime start = event.start ?? DateTime.now();
    final DateTime end = event.end ?? start.add(const Duration(hours: 1));
    try {
      return await cal.Add2Calendar.addEvent2Cal(
        cal.Event(
          title: event.title.isEmpty ? 'Event' : event.title,
          description: event.description ?? '',
          location: event.location ?? '',
          startDate: start,
          endDate: end.isAfter(start) ? end : start.add(const Duration(hours: 1)),
        ),
      );
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<void> shareText(String text) async {
    await Share.share(text);
  }

  @override
  Future<String> saveText(String fileName, String text) async {
    final Directory base = await getApplicationDocumentsDirectory();
    final Directory dir = Directory('${base.path}${Platform.pathSeparator}scans');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final File file = File('${dir.path}${Platform.pathSeparator}$fileName');
    await file.writeAsString(text, flush: true);
    return file.path;
  }

  @override
  Future<void> deleteSaved(String path) async {
    final File file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }

  @override
  Future<void> copyText(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
  }
}
