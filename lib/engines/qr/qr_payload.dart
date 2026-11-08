/// Decoded QR payloads. Pure Dart, no platform code, nothing leaves the device.
///
/// A scanner hands [QrDecoder.decode] the raw string a code carries and gets
/// back a typed payload the UI can preview safely before acting on it.
library;

/// What kind of thing a code turned out to be.
sealed class QrPayload {
  const QrPayload({required this.raw});

  /// The exact text the code carried.
  final String raw;

  /// Short label for the result card, e.g. "Link".
  String get kindLabel;

  /// One line the result card can show as a headline.
  String get headline;
}

/// A link: web (http, https) or another launchable scheme (tel, mailto, sms, geo).
final class UrlPayload extends QrPayload {
  const UrlPayload({required super.raw, required this.uri});

  final Uri uri;

  bool get isWeb => uri.scheme == 'http' || uri.scheme == 'https';

  bool get isSecure => uri.scheme == 'https';

  /// The host shown big so the person knows where a link goes before opening.
  String get host => uri.host.isEmpty ? uri.path : uri.host;

  /// A host that is a bare IP address or punycode is worth a warning.
  bool get looksSuspicious {
    final String h = uri.host;
    if (h.isEmpty) {
      return false;
    }
    if (RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(h)) {
      return true;
    }
    return h.contains('xn--') || h.contains('@');
  }

  @override
  String get kindLabel => isWeb ? 'Link' : _schemeLabel(uri.scheme);

  @override
  String get headline => isWeb ? host : uri.toString();

  static String _schemeLabel(String scheme) {
    switch (scheme) {
      case 'tel':
        return 'Phone number';
      case 'mailto':
        return 'Email address';
      case 'sms':
      case 'smsto':
        return 'Text message';
      case 'geo':
        return 'Location';
      default:
        return 'Link';
    }
  }
}

enum WifiSecurity { wpa, wep, open }

/// A WIFI: code (the format Android and iOS both read).
final class WifiPayload extends QrPayload {
  const WifiPayload({
    required super.raw,
    required this.ssid,
    required this.password,
    required this.security,
    this.hidden = false,
  });

  final String ssid;
  final String password;
  final WifiSecurity security;
  final bool hidden;

  String get securityLabel {
    switch (security) {
      case WifiSecurity.wpa:
        return 'WPA/WPA2';
      case WifiSecurity.wep:
        return 'WEP';
      case WifiSecurity.open:
        return 'Open network';
    }
  }

  @override
  String get kindLabel => 'Wi-Fi';

  @override
  String get headline => ssid;
}

/// A upi://pay deep link.
final class UpiPayload extends QrPayload {
  const UpiPayload({
    required super.raw,
    required this.uri,
    required this.payeeAddress,
    this.payeeName,
    this.amount,
    this.currency,
    this.note,
  });

  final Uri uri;
  final String payeeAddress;
  final String? payeeName;
  final String? amount;
  final String? currency;
  final String? note;

  /// Amount with the Indian rupee sign by default, or empty when the payer
  /// decides the amount.
  String get amountLabel {
    if (amount == null || amount!.isEmpty) {
      return '';
    }
    final String cur = (currency ?? 'INR').toUpperCase();
    return cur == 'INR' ? '₹$amount' : '$cur $amount';
  }

  @override
  String get kindLabel => 'UPI payment';

  @override
  String get headline => payeeName ?? payeeAddress;
}

/// A vCard (BEGIN:VCARD).
final class VCardPayload extends QrPayload {
  const VCardPayload({
    required super.raw,
    required this.fullName,
    this.phones = const <String>[],
    this.emails = const <String>[],
    this.organisation,
    this.urls = const <String>[],
  });

  final String fullName;
  final List<String> phones;
  final List<String> emails;
  final String? organisation;
  final List<String> urls;

  @override
  String get kindLabel => 'Contact';

  @override
  String get headline => fullName.isEmpty ? 'Unnamed contact' : fullName;
}

/// A calendar event (BEGIN:VEVENT, alone or inside VCALENDAR).
final class EventPayload extends QrPayload {
  const EventPayload({
    required super.raw,
    required this.title,
    this.start,
    this.end,
    this.location,
    this.description,
  });

  final String title;
  final DateTime? start;
  final DateTime? end;
  final String? location;
  final String? description;

  @override
  String get kindLabel => 'Event';

  @override
  String get headline => title.isEmpty ? 'Untitled event' : title;
}

/// Anything that is not one of the above.
final class TextPayload extends QrPayload {
  const TextPayload({required super.raw});

  String get text => raw;

  @override
  String get kindLabel => 'Text';

  @override
  String get headline => raw;
}

/// Turns the raw text of a code into a typed payload. Pure, synchronous, fast.
abstract final class QrDecoder {
  static QrPayload decode(String rawInput) {
    final String raw = rawInput.trim();
    if (raw.isEmpty) {
      return const TextPayload(raw: '');
    }
    final String upper = raw.toUpperCase();

    if (upper.startsWith('WIFI:')) {
      final WifiPayload? wifi = _parseWifi(raw);
      if (wifi != null) {
        return wifi;
      }
    }
    if (upper.startsWith('BEGIN:VCARD')) {
      return _parseVCard(raw);
    }
    if (upper.startsWith('BEGIN:VCALENDAR') || upper.startsWith('BEGIN:VEVENT')) {
      final EventPayload? event = _parseEvent(raw);
      if (event != null) {
        return event;
      }
    }
    if (upper.startsWith('UPI://')) {
      final UpiPayload? upi = _parseUpi(raw);
      if (upi != null) {
        return upi;
      }
    }
    final UrlPayload? url = _parseUrl(raw);
    if (url != null) {
      return url;
    }
    return TextPayload(raw: raw);
  }

  // ---- links -------------------------------------------------------------

  static const Set<String> _launchable = <String>{
    'http',
    'https',
    'tel',
    'mailto',
    'sms',
    'smsto',
    'geo',
  };

  static UrlPayload? _parseUrl(String raw) {
    if (raw.contains('\n') || raw.contains(' ')) {
      return null;
    }
    String candidate = raw;
    final String lower = raw.toLowerCase();
    if (lower.startsWith('www.')) {
      candidate = 'https://$raw';
    }
    final Uri? uri = Uri.tryParse(candidate);
    if (uri == null) {
      return null;
    }
    final String scheme = uri.scheme.toLowerCase();
    if (!_launchable.contains(scheme)) {
      return null;
    }
    if ((scheme == 'http' || scheme == 'https') && uri.host.isEmpty) {
      return null;
    }
    return UrlPayload(raw: raw, uri: uri);
  }

  // ---- Wi-Fi -------------------------------------------------------------

  /// WIFI:T:WPA;S:MyNet;P:secret;H:true;;  with backslash escapes.
  static WifiPayload? _parseWifi(String raw) {
    final Map<String, String> fields = <String, String>{};
    final String body = raw.substring('WIFI:'.length);
    int i = 0;
    while (i < body.length) {
      final int colon = body.indexOf(':', i);
      if (colon < 0) {
        break;
      }
      final String key = body.substring(i, colon).trim().toUpperCase();
      final StringBuffer value = StringBuffer();
      int j = colon + 1;
      while (j < body.length) {
        final String c = body[j];
        if (c == r'\' && j + 1 < body.length) {
          value.write(body[j + 1]);
          j += 2;
          continue;
        }
        if (c == ';') {
          break;
        }
        value.write(c);
        j++;
      }
      if (key.isNotEmpty) {
        fields[key] = value.toString();
      }
      i = j + 1;
    }
    final String ssid = fields['S'] ?? '';
    if (ssid.isEmpty) {
      return null;
    }
    final String type = (fields['T'] ?? '').toUpperCase();
    final WifiSecurity security;
    if (type.isEmpty || type == 'NOPASS') {
      security = WifiSecurity.open;
    } else if (type == 'WEP') {
      security = WifiSecurity.wep;
    } else {
      security = WifiSecurity.wpa;
    }
    return WifiPayload(
      raw: raw,
      ssid: ssid,
      password: fields['P'] ?? '',
      security: security,
      hidden: (fields['H'] ?? '').toLowerCase() == 'true',
    );
  }

  // ---- UPI ---------------------------------------------------------------

  static UpiPayload? _parseUpi(String raw) {
    final Uri? uri = Uri.tryParse(raw);
    if (uri == null) {
      return null;
    }
    final Map<String, String> q = uri.queryParameters;
    final String? pa = q['pa'];
    if (pa == null || pa.isEmpty) {
      return null;
    }
    String? clean(String? s) => (s == null || s.trim().isEmpty) ? null : s.trim();
    return UpiPayload(
      raw: raw,
      uri: uri,
      payeeAddress: pa.trim(),
      payeeName: clean(q['pn']),
      amount: clean(q['am']),
      currency: clean(q['cu']),
      note: clean(q['tn']),
    );
  }

  // ---- vCard and vEvent (RFC 6350 / RFC 5545 line syntax) ----------------

  /// Unfolds continuation lines and splits each into (name, params, value).
  static List<_Line> _lines(String raw) {
    final String unfolded =
        raw.replaceAll('\r\n', '\n').replaceAll(RegExp(r'\n[ \t]'), '');
    final List<_Line> out = <_Line>[];
    for (final String line in unfolded.split('\n')) {
      final int colon = line.indexOf(':');
      if (colon <= 0) {
        continue;
      }
      final String head = line.substring(0, colon);
      final List<String> parts = head.split(';');
      out.add(_Line(
        parts.first.trim().toUpperCase(),
        parts.skip(1).map((String p) => p.trim().toUpperCase()).toList(),
        _unescape(line.substring(colon + 1)),
      ));
    }
    return out;
  }

  static String _unescape(String v) {
    return v
        .replaceAll(r'\n', '\n')
        .replaceAll(r'\N', '\n')
        .replaceAll(r'\,', ',')
        .replaceAll(r'\;', ';')
        .replaceAll(r'\\', r'\')
        .trim();
  }

  static VCardPayload _parseVCard(String raw) {
    String fullName = '';
    String? nField;
    String? org;
    final List<String> phones = <String>[];
    final List<String> emails = <String>[];
    final List<String> urls = <String>[];
    for (final _Line l in _lines(raw)) {
      switch (l.name) {
        case 'FN':
          fullName = l.value;
        case 'N':
          nField = l.value;
        case 'TEL':
          if (l.value.isNotEmpty) {
            phones.add(l.value.replaceFirst(RegExp('^tel:'), ''));
          }
        case 'EMAIL':
          if (l.value.isNotEmpty) {
            emails.add(l.value);
          }
        case 'ORG':
          org = l.value.split(';').first.trim();
        case 'URL':
          if (l.value.isNotEmpty) {
            urls.add(l.value);
          }
      }
    }
    if (fullName.isEmpty && nField != null) {
      // N is family;given;additional;prefix;suffix
      final List<String> parts = nField.split(';');
      final String given = parts.length > 1 ? parts[1].trim() : '';
      final String family = parts.first.trim();
      fullName = <String>[given, family].where((String s) => s.isNotEmpty).join(' ');
    }
    return VCardPayload(
      raw: raw,
      fullName: fullName,
      phones: phones,
      emails: emails,
      organisation: (org == null || org.isEmpty) ? null : org,
      urls: urls,
    );
  }

  static EventPayload? _parseEvent(String raw) {
    bool inEvent = false;
    bool seen = false;
    String title = '';
    DateTime? start;
    DateTime? end;
    String? location;
    String? description;
    for (final _Line l in _lines(raw)) {
      if (l.name == 'BEGIN' && l.value.toUpperCase() == 'VEVENT') {
        inEvent = true;
        seen = true;
        continue;
      }
      if (l.name == 'END' && l.value.toUpperCase() == 'VEVENT') {
        break;
      }
      if (!inEvent) {
        continue;
      }
      switch (l.name) {
        case 'SUMMARY':
          title = l.value;
        case 'DTSTART':
          start = parseIcsDate(l.value, l.params);
        case 'DTEND':
          end = parseIcsDate(l.value, l.params);
        case 'LOCATION':
          location = l.value.isEmpty ? null : l.value;
        case 'DESCRIPTION':
          description = l.value.isEmpty ? null : l.value;
      }
    }
    if (!seen) {
      return null;
    }
    return EventPayload(
      raw: raw,
      title: title,
      start: start,
      end: end,
      location: location,
      description: description,
    );
  }

  static final RegExp _icsDate =
      RegExp(r'^(\d{4})(\d{2})(\d{2})(?:T(\d{2})(\d{2})(\d{2})?(Z)?)?$');

  /// Parses 20261108, 20261108T190000 and 20261108T190000Z.
  /// A TZID parameter is ignored and the time treated as local.
  static DateTime? parseIcsDate(String value, [List<String> params = const <String>[]]) {
    final RegExpMatch? m = _icsDate.firstMatch(value.trim());
    if (m == null) {
      return null;
    }
    final int y = int.parse(m.group(1)!);
    final int mo = int.parse(m.group(2)!);
    final int d = int.parse(m.group(3)!);
    final int h = int.tryParse(m.group(4) ?? '') ?? 0;
    final int mi = int.tryParse(m.group(5) ?? '') ?? 0;
    final int s = int.tryParse(m.group(6) ?? '') ?? 0;
    if (m.group(7) == 'Z') {
      return DateTime.utc(y, mo, d, h, mi, s).toLocal();
    }
    return DateTime(y, mo, d, h, mi, s);
  }
}

class _Line {
  const _Line(this.name, this.params, this.value);
  final String name;
  final List<String> params;
  final String value;
}
