import 'dart:io';

import 'package:family_utility_app/app/theme.dart';
import 'package:family_utility_app/engines/qr/qr_actions.dart';
import 'package:family_utility_app/engines/qr/qr_payload.dart';
import 'package:family_utility_app/tools/qr_scanner/qr_result_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records what the screen asked for instead of touching the platform.
class FakeQrActions implements QrActions {
  final List<Uri> opened = <Uri>[];
  final List<String> joined = <String>[];
  final List<String> savedContacts = <String>[];
  final List<String> addedEvents = <String>[];
  final List<String> shared = <String>[];
  final List<String> copied = <String>[];
  final Map<String, String> files = <String, String>{};
  bool openResult = true;
  bool joinResult = true;

  @override
  Future<bool> openUri(Uri uri) async {
    opened.add(uri);
    return openResult;
  }

  @override
  Future<bool> joinWifi(WifiPayload wifi) async {
    joined.add(wifi.ssid);
    return joinResult;
  }

  @override
  Future<bool> saveContact(VCardPayload card) async {
    savedContacts.add(card.fullName);
    return true;
  }

  @override
  Future<bool> addEvent(EventPayload event) async {
    addedEvents.add(event.title);
    return true;
  }

  @override
  Future<void> shareText(String text) async => shared.add(text);

  @override
  Future<String> saveText(String fileName, String text) async {
    final String path = '/fake/scans/$fileName';
    files[path] = text;
    return path;
  }

  @override
  Future<void> deleteSaved(String path) async => files.remove(path);

  @override
  Future<void> copyText(String text) async => copied.add(text);
}

const String wifiRaw = r'WIFI:T:WPA;S:Home\;Net;P:pa\\ss\:word;H:true;;';
const String upiRaw = 'upi://pay?pa=shop@upi&pn=Corner%20Shop&am=250.00&cu=INR&tn=Milk';
const String vcardRaw = 'BEGIN:VCARD\r\n'
    'VERSION:3.0\r\n'
    'N:Sharma;Priya;;;\r\n'
    'FN:Priya Sharma\r\n'
    'ORG:Curator Group;Design\r\n'
    'TEL;TYPE=CELL:+91 98765 43210\r\n'
    'EMAIL:priya@example.com\r\n'
    'URL:https://example.com/pri\r\n'
    ' ya\r\n'
    'END:VCARD';
const String eventRaw = 'BEGIN:VCALENDAR\n'
    'VERSION:2.0\n'
    'BEGIN:VEVENT\n'
    'SUMMARY:Parent-teacher meeting\n'
    'DTSTART:20261120T133000Z\n'
    'DTEND:20261120T143000Z\n'
    'LOCATION:School hall\\, Block B\n'
    'DESCRIPTION:Bring the report card\n'
    'END:VEVENT\n'
    'END:VCALENDAR';

Widget harness(QrPayload payload, QrActions actions, {Widget? home}) {
  return MaterialApp(
    theme: buildAppTheme(),
    home: home ?? QrResultScreen(payload: payload, actions: actions),
  );
}

void main() {
  group('QrDecoder', () {
    test('web links keep the full address and expose the host', () {
      final QrPayload p = QrDecoder.decode('https://example.com/offer?id=42');
      expect(p, isA<UrlPayload>());
      final UrlPayload u = p as UrlPayload;
      expect(u.host, 'example.com');
      expect(u.isSecure, isTrue);
      expect(u.uri.toString(), 'https://example.com/offer?id=42');
      expect(u.looksSuspicious, isFalse);
    });

    test('http and bare www links are links too, and IPs are flagged', () {
      expect((QrDecoder.decode('http://10.0.0.1/admin') as UrlPayload).looksSuspicious, isTrue);
      expect((QrDecoder.decode('http://10.0.0.1/admin') as UrlPayload).isSecure, isFalse);
      final UrlPayload www = QrDecoder.decode('www.example.org/x') as UrlPayload;
      expect(www.uri.scheme, 'https');
      expect(www.host, 'www.example.org');
    });

    test('tel, mailto and geo are launchable links with their own labels', () {
      expect((QrDecoder.decode('tel:+919876543210') as UrlPayload).kindLabel, 'Phone number');
      expect((QrDecoder.decode('mailto:a@b.co') as UrlPayload).kindLabel, 'Email address');
      expect((QrDecoder.decode('geo:19.07,72.87') as UrlPayload).kindLabel, 'Location');
    });

    test('Wi-Fi codes parse with escapes, security and hidden flag', () {
      final WifiPayload w = QrDecoder.decode(wifiRaw) as WifiPayload;
      expect(w.ssid, 'Home;Net');
      expect(w.password, r'pa\ss:word');
      expect(w.security, WifiSecurity.wpa);
      expect(w.hidden, isTrue);
      final WifiPayload open = QrDecoder.decode('WIFI:S:Cafe;T:nopass;;') as WifiPayload;
      expect(open.security, WifiSecurity.open);
      expect(open.password, '');
    });

    test('UPI links carry payee, name, amount and note', () {
      final UpiPayload u = QrDecoder.decode(upiRaw) as UpiPayload;
      expect(u.payeeAddress, 'shop@upi');
      expect(u.payeeName, 'Corner Shop');
      expect(u.amountLabel, '₹250.00');
      expect(u.note, 'Milk');
      expect(u.uri.scheme, 'upi');
    });

    test('vCards unfold lines and read name, phone, email, org, url', () {
      final VCardPayload v = QrDecoder.decode(vcardRaw) as VCardPayload;
      expect(v.fullName, 'Priya Sharma');
      expect(v.phones, <String>['+91 98765 43210']);
      expect(v.emails, <String>['priya@example.com']);
      expect(v.organisation, 'Curator Group');
      expect(v.urls, <String>['https://example.com/priya']);
    });

    test('vCard without FN builds the name from N', () {
      final VCardPayload v =
          QrDecoder.decode('BEGIN:VCARD\nN:Sharma;Priya\nTEL:123\nEND:VCARD') as VCardPayload;
      expect(v.fullName, 'Priya Sharma');
    });

    test('events inside VCALENDAR parse title, times and escaped location', () {
      final EventPayload e = QrDecoder.decode(eventRaw) as EventPayload;
      expect(e.title, 'Parent-teacher meeting');
      expect(e.start!.toUtc(), DateTime.utc(2026, 11, 20, 13, 30));
      expect(e.end!.toUtc(), DateTime.utc(2026, 11, 20, 14, 30));
      expect(e.location, 'School hall, Block B');
      expect(e.description, 'Bring the report card');
      expect(QrDecoder.parseIcsDate('20261120'), DateTime(2026, 11, 20));
      expect(QrDecoder.parseIcsDate('nonsense'), isNull);
    });

    test('anything else is plain text, never auto-opened', () {
      expect(QrDecoder.decode('hello world'), isA<TextPayload>());
      expect(QrDecoder.decode('ftp://files.example.com'), isA<TextPayload>());
      expect(QrDecoder.decode('   '), isA<TextPayload>());
      expect(QrDecoder.decode('WIFI:T:WPA;;'), isA<TextPayload>());
    });

    test('decodes every sample well under 300 ms', () {
      const List<String> samples = <String>[
        'https://example.com/offer?id=42',
        wifiRaw,
        upiRaw,
        vcardRaw,
        eventRaw,
        'some plain text with spaces',
      ];
      final Stopwatch sw = Stopwatch()..start();
      for (int i = 0; i < 200; i++) {
        for (final String s in samples) {
          QrDecoder.decode(s);
        }
      }
      sw.stop();
      // 1200 decodes; a single one must be far below the 300 ms budget.
      expect(sw.elapsedMilliseconds / 1200, lessThan(300));
      expect(sw.elapsedMilliseconds, lessThan(3000));
    });
  });

  group('QrResultScreen', () {
    testWidgets('shows the full URL before opening and opens on tap', (WidgetTester tester) async {
      final FakeQrActions fake = FakeQrActions();
      await tester.pumpWidget(harness(QrDecoder.decode('https://example.com/offer?id=42'), fake));
      expect(find.text('https://example.com/offer?id=42'), findsOneWidget);
      expect(find.text('example.com'), findsOneWidget);
      expect(fake.opened, isEmpty, reason: 'nothing opens before the person taps');

      await tester.tap(find.byKey(const Key('primary-action')));
      await tester.pumpAndSettle();
      expect(fake.opened.single.toString(), 'https://example.com/offer?id=42');
    });

    testWidgets('UPI opens the payment app with the upi:// link', (WidgetTester tester) async {
      final FakeQrActions fake = FakeQrActions();
      await tester.pumpWidget(harness(QrDecoder.decode(upiRaw), fake));
      expect(find.text('Corner Shop'), findsOneWidget);
      expect(find.text('₹250.00'), findsOneWidget);
      await tester.tap(find.text('Pay with UPI app'));
      await tester.pumpAndSettle();
      expect(fake.opened.single.scheme, 'upi');
      expect(fake.opened.single.queryParameters['pa'], 'shop@upi');
    });

    testWidgets('UPI with no payment app shows a message instead of failing silently',
        (WidgetTester tester) async {
      final FakeQrActions fake = FakeQrActions()..openResult = false;
      await tester.pumpWidget(harness(QrDecoder.decode(upiRaw), fake));
      await tester.tap(find.text('Pay with UPI app'));
      await tester.pump();
      expect(find.text('No UPI app found on this phone'), findsOneWidget);
    });

    testWidgets('Wi-Fi joins in one tap and hides the password by default',
        (WidgetTester tester) async {
      final FakeQrActions fake = FakeQrActions();
      await tester.pumpWidget(harness(QrDecoder.decode(wifiRaw), fake));
      expect(find.text(r'pa\ss:word'), findsNothing);
      await tester.tap(find.byTooltip('Show password'));
      await tester.pump();
      expect(find.text(r'pa\ss:word'), findsOneWidget);

      await tester.tap(find.text('Join Home;Net'));
      await tester.pumpAndSettle();
      expect(fake.joined, <String>['Home;Net']);
    });

    testWidgets('Wi-Fi join failure copies the password for the settings page',
        (WidgetTester tester) async {
      final FakeQrActions fake = FakeQrActions()..joinResult = false;
      await tester.pumpWidget(harness(QrDecoder.decode(wifiRaw), fake));
      await tester.tap(find.byKey(const Key('primary-action')));
      await tester.pump();
      expect(fake.copied, <String>[r'pa\ss:word']);
      expect(find.textContaining('Password copied'), findsOneWidget);
    });

    testWidgets('vCards save to contacts', (WidgetTester tester) async {
      final FakeQrActions fake = FakeQrActions();
      await tester.pumpWidget(harness(QrDecoder.decode(vcardRaw), fake));
      expect(find.text('Priya Sharma'), findsOneWidget);
      expect(find.text('+91 98765 43210'), findsOneWidget);
      await tester.tap(find.text('Save to contacts'));
      await tester.pumpAndSettle();
      expect(fake.savedContacts, <String>['Priya Sharma']);
    });

    testWidgets('events go to the calendar with DD/MM dates shown', (WidgetTester tester) async {
      final FakeQrActions fake = FakeQrActions();
      final EventPayload e = QrDecoder.decode(eventRaw) as EventPayload;
      await tester.pumpWidget(harness(e, fake));
      expect(find.text(formatDateTime(e.start!)), findsOneWidget);
      expect(formatDateTime(DateTime(2026, 11, 20, 9, 5)), '20/11/2026 09:05');
      await tester.tap(find.text('Add to calendar'));
      await tester.pumpAndSettle();
      expect(fake.addedEvents, <String>['Parent-teacher meeting']);
    });

    testWidgets('result ends with Share, Save and Undo; Undo removes the saved copy',
        (WidgetTester tester) async {
      final FakeQrActions fake = FakeQrActions();
      await tester.pumpWidget(harness(QrDecoder.decode('hello world'), fake));
      expect(find.text('Share'), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);
      expect(find.text('Undo'), findsOneWidget);

      await tester.tap(find.byKey(const Key('result-share')));
      await tester.pumpAndSettle();
      expect(fake.shared, <String>['hello world']);

      await tester.tap(find.byKey(const Key('result-save')));
      await tester.pumpAndSettle();
      expect(fake.files.length, 1);
      expect(fake.files.values.single, 'hello world');
      expect(find.text('Saved'), findsOneWidget);

      await tester.tap(find.byKey(const Key('result-undo')));
      await tester.pumpAndSettle();
      expect(fake.files, isEmpty);
      expect(find.text('Save'), findsOneWidget);
    });

    testWidgets('Undo with nothing saved goes back to the scanner', (WidgetTester tester) async {
      final FakeQrActions fake = FakeQrActions();
      await tester.pumpWidget(
        harness(
          const TextPayload(raw: 'x'),
          fake,
          home: Builder(
            builder: (BuildContext context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (BuildContext _) =>
                          QrResultScreen(payload: const TextPayload(raw: 'x'), actions: fake),
                    ),
                  ),
                  child: const Text('scan'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('scan'));
      await tester.pumpAndSettle();
      expect(find.text('Scan result'), findsOneWidget);
      await tester.tap(find.byKey(const Key('result-undo')));
      await tester.pumpAndSettle();
      expect(find.text('Scan result'), findsNothing);
      expect(find.text('scan'), findsOneWidget);
    });

    testWidgets('every button is at least 44 px tall and labelled', (WidgetTester tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      final FakeQrActions fake = FakeQrActions();
      await tester.pumpWidget(harness(QrDecoder.decode(upiRaw), fake));
      final Finder buttons = find.byWidgetPredicate(
        (Widget w) => w is FilledButton || w is OutlinedButton || w is IconButton,
      );
      expect(buttons, findsWidgets);
      for (final Element e in buttons.evaluate()) {
        final Size size = tester.getSize(find.byWidget(e.widget));
        expect(size.height, greaterThanOrEqualTo(44), reason: '${e.widget.runtimeType} too short');
        expect(size.width, greaterThanOrEqualTo(44), reason: '${e.widget.runtimeType} too narrow');
      }
      for (final String label in <String>['Pay with UPI app', 'Copy UPI ID', 'Share', 'Undo']) {
        expect(find.bySemanticsLabel(RegExp(RegExp.escape(label))), findsWidgets);
      }
      handle.dispose();
    });
  });

  group('privacy', () {
    test('the QR engine has no network code', () {
      final Directory dir = Directory('lib/engines/qr');
      expect(dir.existsSync(), isTrue);
      for (final FileSystemEntity f in dir.listSync()) {
        if (f is File && f.path.endsWith('.dart')) {
          final String src = f.readAsStringSync();
          expect(src.contains('HttpClient'), isFalse, reason: f.path);
          expect(src.contains('package:http'), isFalse, reason: f.path);
          expect(src.contains('dart:io'), isFalse, reason: f.path);
        }
      }
    });
  });
}
