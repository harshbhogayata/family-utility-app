import 'dart:convert';
import 'dart:typed_data';

import 'package:family_utility_app/app/theme.dart';
import 'package:family_utility_app/engines/qr/qr_generator.dart';
import 'package:family_utility_app/engines/qr/qr_payload.dart';
import 'package:family_utility_app/tools/qr_generator/qr_generator_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

Uint8List logoPng() {
  final img.Image im = img.Image(width: 20, height: 20);
  img.fill(im, color: img.ColorRgb8(220, 40, 40));
  return img.encodePng(im);
}

class FakeFiles implements QrFiles {
  final Map<String, Uint8List> written = <String, Uint8List>{};

  @override
  Future<Uint8List?> pickLogo() async => logoPng();

  @override
  Future<String> write(String name, Uint8List bytes) async {
    final String p = '/qr/$name';
    written[p] = bytes;
    return p;
  }

  @override
  Future<void> remove(String path) async => written.remove(path);
}

void main() {
  group('content', () {
    test('Wi-Fi, UPI and vCard read back with the scanner\'s decoder', () {
      final WifiPayload w = QrDecoder.decode(QrContent.wifi('Home;Net', 'pa:ss', auth: WifiAuth.wpa)) as WifiPayload;
      expect(w.ssid, 'Home;Net');
      expect(w.password, 'pa:ss');

      final UpiPayload u =
          QrDecoder.decode(QrContent.upi('asha@okbank', name: 'Asha K', amount: '99.50', note: 'Milk')) as UpiPayload;
      expect(u.payeeAddress, 'asha@okbank');
      expect(u.payeeName, 'Asha K');
      expect(u.amount, '99.50');

      final VCardPayload v = QrDecoder.decode(
          QrContent.vcard(name: 'Asha Kumar', phone: '+91 98765 43210', email: 'a@b.in', organisation: 'Home')) as VCardPayload;
      expect(v.fullName, 'Asha Kumar');
      expect(v.phones, contains('+91 98765 43210'));
    });

    test('links, WhatsApp and checks', () {
      expect(QrContent.url('example.com'), 'https://example.com');
      expect(QrContent.url('mailto:a@b.in'), 'mailto:a@b.in');
      expect(QrContent.whatsapp('+91 98765-43210', message: 'Hi there'), 'https://wa.me/919876543210?text=Hi%20there');
      expect(() => QrContent.upi('not-an-id'), throwsA(isA<QrContentError>()));
      expect(() => QrContent.upi('a@ok', amount: '12,5'), throwsA(isA<QrContentError>()));
      expect(() => QrContent.whatsapp('123'), throwsA(isA<QrContentError>()));
      expect(QrContent.wifi('Cafe', '', auth: WifiAuth.open), 'WIFI:T:nopass;S:Cafe;;');
    });
  });

  group('render', () {
    const String data = 'https://example.com';

    test('matrix has finder patterns; a logo raises error correction', () {
      final List<List<bool>> m = QrRender.matrix(data);
      expect(m.length, greaterThanOrEqualTo(21));
      expect(m[0][0] && m[0][6] && m[6][0], isTrue);
      expect(m[1][1], isFalse);
      expect(QrRender.matrix(data, forLogo: true).length, greaterThanOrEqualTo(m.length));
    });

    test('PNG uses the chosen colours with a quiet zone', () {
      final img.Image im = img.decodePng(QrRender.png(data, const QrStyle(foreground: 0xFF1A237E), size: 300))!;
      final img.Pixel corner = im.getPixel(1, 1);
      expect((corner.r, corner.g, corner.b), (255, 255, 255));
      final int scale = im.width ~/ (QrRender.matrix(data).length + 8);
      final img.Pixel finder = im.getPixel(4 * scale + 1, 4 * scale + 1);
      expect((finder.r, finder.g, finder.b), (0x1A, 0x23, 0x7E));
    });

    test('SVG, logo and print sheet', () async {
      final String svg = QrRender.svg(data, const QrStyle(foreground: 0xFF1B5E20));
      expect(svg, startsWith('<svg'));
      expect(svg, contains('fill="#1b5e20"'));
      expect(svg, contains('M4 4h1v1h-1z'));
      final String withLogo = QrRender.svg(data, QrStyle(logo: logoPng()));
      expect(withLogo, contains('data:image/png;base64,'));

      final img.Image logoed = img.decodePng(QrRender.png(data, QrStyle(logo: logoPng()), size: 400))!;
      final img.Pixel mid = logoed.getPixel(logoed.width ~/ 2, logoed.height ~/ 2);
      expect((mid.r, mid.g, mid.b), (220, 40, 40));

      final Uint8List pdf = await QrRender.printSheet(data, const QrStyle());
      expect(ascii.decode(pdf.sublist(0, 5)), '%PDF-');
    });

    test('light colours are flagged as hard to scan', () {
      expect(const QrStyle().scannable, isTrue);
      expect(const QrStyle().contrast, closeTo(21, 0.1));
      expect(const QrStyle(foreground: 0xFFBDBDBD).scannable, isFalse);
      expect(const QrStyle(foreground: 0xFFFFFFFF, background: 0xFF000000).scannable, isFalse);
    });
  });

  testWidgets('type a link, preview, export PNG, SVG and print sheet, undo', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final FakeFiles files = FakeFiles();
    await tester.pumpWidget(MaterialApp(theme: buildAppTheme(), home: QrGeneratorScreen(files: files)));
    expect(find.byKey(const Key('qr-preview')), findsNothing);
    await tester.enterText(find.byKey(const Key('qr-url')), 'example.com');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('qr-preview')), findsOneWidget);

    await tester.tap(find.byKey(const Key('qr-colour-Navy')));
    await tester.tap(find.byKey(const Key('qr-logo')));
    await tester.pumpAndSettle();
    expect(find.text('Change logo'), findsOneWidget);

    for (final String k in <String>['qr-save-png', 'qr-save-svg', 'qr-print']) {
      expect(tester.getSize(find.byKey(Key(k))).height, greaterThanOrEqualTo(44), reason: k);
      await tester.tap(find.byKey(Key(k)));
      await tester.pumpAndSettle();
    }
    expect(files.written.keys, <String>['/qr/qr-url.png', '/qr/qr-url.svg', '/qr/qr-url-sheet.pdf']);
    expect(find.text('Saved qr-url-sheet.pdf in Files › qr'), findsOneWidget);

    await tester.tap(find.byKey(const Key('result-undo')));
    await tester.pumpAndSettle();
    expect(files.written.keys, <String>['/qr/qr-url.png', '/qr/qr-url.svg']);

    await tester.tap(find.byKey(const Key('qr-kind-upi')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('qr-vpa')), 'bad');
    await tester.tap(find.byKey(const Key('qr-save-png')));
    await tester.pumpAndSettle();
    expect(find.text('Type a UPI ID like name@bank'), findsOneWidget);
  });
}
