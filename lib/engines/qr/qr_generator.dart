import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:qr/qr.dart';

import '../pdf/images_to_pdf.dart';

/// Feature 052 — QR generator. Builds the text for URL, Wi-Fi, UPI, vCard
/// and WhatsApp codes, and draws the code as PNG, SVG or a printable sheet,
/// all on the phone.

enum QrKind {
  url('Link'),
  wifi('Wi-Fi'),
  upi('UPI payment'),
  vcard('Contact card'),
  whatsapp('WhatsApp'),
  text('Text');

  const QrKind(this.label);
  final String label;
}

enum WifiAuth { wpa, wep, open }

class QrContentError implements Exception {
  const QrContentError(this.message);
  final String message;
  @override
  String toString() => message;
}

abstract final class QrContent {
  static String url(String input) {
    final String t = input.trim();
    if (t.isEmpty) {
      throw const QrContentError('Type a link');
    }
    return RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*:').hasMatch(t) ? t : 'https://$t';
  }

  static String _wifiEscape(String v) => v.replaceAllMapped(RegExp(r'([\;,:"])'), (Match m) => '\\${m[1]}');

  static String wifi(String ssid, String password, {WifiAuth auth = WifiAuth.wpa, bool hidden = false}) {
    if (ssid.isEmpty) {
      throw const QrContentError('Type the network name');
    }
    final String t = auth == WifiAuth.open ? 'nopass' : (auth == WifiAuth.wep ? 'WEP' : 'WPA');
    final String p = auth == WifiAuth.open ? '' : 'P:${_wifiEscape(password)};';
    return 'WIFI:T:$t;S:${_wifiEscape(ssid)};$p${hidden ? 'H:true;' : ''};';
  }

  static String upi(String vpa, {String? name, String? amount, String? note}) {
    final String id = vpa.trim();
    if (!RegExp(r'^[\w.\-]{2,}@[a-zA-Z][\w.\-]*$').hasMatch(id)) {
      throw const QrContentError('Type a UPI ID like name@bank');
    }
    final String? amt = amount == null || amount.trim().isEmpty ? null : amount.trim();
    if (amt != null && !RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(amt)) {
      throw const QrContentError('Amount should be a number like 250 or 99.50');
    }
    final Map<String, String> q = <String, String>{
      'pa': id,
      if (name != null && name.trim().isNotEmpty) 'pn': name.trim(),
      if (amt != null) 'am': amt,
      'cu': 'INR',
      if (note != null && note.trim().isNotEmpty) 'tn': note.trim(),
    };
    return 'upi://pay?${q.entries.map((MapEntry<String, String> e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&')}';
  }

  static String _vEscape(String v) =>
      v.replaceAll(r'\', r'\\').replaceAll(',', r'\,').replaceAll(';', r'\;').replaceAll('\n', r'\n');

  static String vcard({required String name, String? phone, String? email, String? organisation}) {
    final String n = name.trim();
    if (n.isEmpty) {
      throw const QrContentError('Type a name');
    }
    final int space = n.lastIndexOf(' ');
    final String family = space > 0 ? n.substring(space + 1) : n;
    final String given = space > 0 ? n.substring(0, space) : '';
    return <String>[
      'BEGIN:VCARD',
      'VERSION:3.0',
      'N:${_vEscape(family)};${_vEscape(given)};;;',
      'FN:${_vEscape(n)}',
      if (phone != null && phone.trim().isNotEmpty) 'TEL;TYPE=CELL:${phone.trim()}',
      if (email != null && email.trim().isNotEmpty) 'EMAIL:${email.trim()}',
      if (organisation != null && organisation.trim().isNotEmpty) 'ORG:${_vEscape(organisation.trim())}',
      'END:VCARD',
    ].join('\r\n');
  }

  static String whatsapp(String phone, {String? message}) {
    final String digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 8) {
      throw const QrContentError('Type the number with country code, like 91 98765 43210');
    }
    final String m = message?.trim() ?? '';
    return 'https://wa.me/$digits${m.isEmpty ? '' : '?text=${Uri.encodeComponent(m)}'}';
  }
}

/// Colours are 0xAARRGGBB.
class QrStyle {
  const QrStyle({this.foreground = 0xFF000000, this.background = 0xFFFFFFFF, this.logo});

  final int foreground;
  final int background;

  /// PNG or JPG shown in the middle; error correction goes up to H for it.
  final Uint8List? logo;

  static double _lum(int argb) {
    double ch(int v) {
      final double c = v / 255;
      return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4).toDouble();
    }

    return 0.2126 * ch((argb >> 16) & 0xFF) + 0.7152 * ch((argb >> 8) & 0xFF) + 0.0722 * ch(argb & 0xFF);
  }

  /// WCAG contrast ratio between the two colours.
  double get contrast {
    final double a = _lum(foreground);
    final double b = _lum(background);
    return (a > b ? a + 0.05 : b + 0.05) / (a > b ? b + 0.05 : a + 0.05);
  }

  /// Scanners need dark modules on a light background with enough contrast.
  bool get scannable => contrast >= 3 && _lum(foreground) < _lum(background);
}

class QrRender {
  QrRender._();

  /// Dark modules, row by row.
  static List<List<bool>> matrix(String data, {bool forLogo = false}) {
    final QrCode code = QrCode.fromData(
      data: data,
      errorCorrectLevel: forLogo ? QrErrorCorrectLevel.H : QrErrorCorrectLevel.M,
    );
    final QrImage image = QrImage(code);
    final int n = image.moduleCount;
    return <List<bool>>[
      for (int r = 0; r < n; r++) <bool>[for (int c = 0; c < n; c++) image.isDark(r, c)],
    ];
  }

  static String _hex(int argb) => '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

  /// Vector code with a 4-module quiet zone; one path for all dark modules.
  static String svg(String data, QrStyle style) {
    final List<List<bool>> m = matrix(data, forLogo: style.logo != null);
    final int n = m.length;
    final int size = n + 8;
    final StringBuffer path = StringBuffer();
    for (int r = 0; r < n; r++) {
      for (int c = 0; c < n; c++) {
        if (m[r][c]) {
          path.write('M${c + 4} ${r + 4}h1v1h-1z');
        }
      }
    }
    final StringBuffer out = StringBuffer()
      ..write('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 $size $size" '
          'shape-rendering="crispEdges">')
      ..write('<rect width="$size" height="$size" fill="${_hex(style.background)}"/>')
      ..write('<path fill="${_hex(style.foreground)}" d="$path"/>');
    final Uint8List? logo = style.logo;
    if (logo != null) {
      final double box = size * 0.22;
      final double at = (size - box) / 2;
      final String mime = logo.length > 1 && logo[0] == 0xFF ? 'image/jpeg' : 'image/png';
      out
        ..write('<rect x="${at - 0.5}" y="${at - 0.5}" width="${box + 1}" height="${box + 1}" '
            'fill="${_hex(style.background)}"/>')
        ..write('<image x="$at" y="$at" width="$box" height="$box" '
            'href="data:$mime;base64,${base64Encode(logo)}"/>');
    }
    out.write('</svg>');
    return out.toString();
  }

  static img.ColorRgba8 _c(int argb) =>
      img.ColorRgba8((argb >> 16) & 0xFF, (argb >> 8) & 0xFF, argb & 0xFF, (argb >> 24) & 0xFF);

  /// Raster code about [size] pixels wide (whole pixels per module).
  static img.Image image(String data, QrStyle style, {int size = 1024}) {
    final List<List<bool>> m = matrix(data, forLogo: style.logo != null);
    final int n = m.length;
    final int scale = size ~/ (n + 8) < 1 ? 1 : size ~/ (n + 8);
    final int px = (n + 8) * scale;
    final img.Image out = img.Image(width: px, height: px, numChannels: 4);
    img.fill(out, color: _c(style.background));
    final img.ColorRgba8 fg = _c(style.foreground);
    for (int r = 0; r < n; r++) {
      for (int c = 0; c < n; c++) {
        if (m[r][c]) {
          img.fillRect(out,
              x1: (c + 4) * scale, y1: (r + 4) * scale, x2: (c + 5) * scale - 1, y2: (r + 5) * scale - 1, color: fg);
        }
      }
    }
    final Uint8List? logoBytes = style.logo;
    if (logoBytes != null) {
      final img.Image? logo = img.decodeImage(logoBytes);
      if (logo != null) {
        final int box = (px * 0.22).round();
        final int at = (px - box) ~/ 2;
        img.fillRect(out, x1: at - scale, y1: at - scale, x2: at + box + scale, y2: at + box + scale, color: _c(style.background));
        final img.Image fit = img.copyResize(logo, width: box, height: box, maintainAspect: true, backgroundColor: _c(style.background));
        img.compositeImage(out, fit, dstX: at, dstY: at);
      }
    }
    return out;
  }

  static Uint8List png(String data, QrStyle style, {int size = 1024}) => img.encodePng(image(data, style, size: size));

  /// An A4 page of 12 copies (3 × 4) with a cutting gap, as a PDF.
  static Future<Uint8List> printSheet(String data, QrStyle style) async {
    const int w = 1240; // A4 at 150 dpi
    const int h = 1754;
    final img.Image sheet = img.Image(width: w, height: h);
    img.fill(sheet, color: img.ColorRgb8(255, 255, 255));
    final img.Image one = image(data, style, size: 360);
    const int cols = 3;
    const int rows = 4;
    final int gx = (w - cols * one.width) ~/ (cols + 1);
    final int gy = (h - rows * one.height) ~/ (rows + 1);
    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        img.compositeImage(sheet, one, dstX: gx + c * (one.width + gx), dstY: gy + r * (one.height + gy));
      }
    }
    return ImagesToPdf().build(
      <Uint8List>[img.encodePng(sheet)],
      const ImagesToPdfOptions(marginPt: 0, jpegQuality: 95),
    );
  }
}
