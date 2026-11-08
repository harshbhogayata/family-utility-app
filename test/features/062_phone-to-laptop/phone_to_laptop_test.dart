import 'dart:convert';
import 'dart:io';

import 'package:family_utility_app/app/theme.dart';
import 'package:family_utility_app/engines/transfer/lan_transfer.dart';
import 'package:family_utility_app/tools/phone_to_laptop/phone_to_laptop_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeChooser implements FileChooser {
  FakeChooser(this.paths);
  final List<String> paths;

  @override
  Future<List<String>> pickPaths() async => paths;
}

Future<HttpClientResponse> get(HttpClient c, String url) async => (await c.getUrl(Uri.parse(url))).close();

Future<String> body(HttpClientResponse r) => r.transform(utf8.decoder).join();

Future<Map<String, Object?>> upload(HttpClient c, String base, String token, String name, String content) async {
  final HttpClientRequest req =
      await c.postUrl(Uri.parse('$base/api/upload?t=$token&name=${Uri.encodeQueryComponent(name)}'));
  req.add(utf8.encode(content));
  final HttpClientResponse res = await req.close();
  return jsonDecode(await body(res)) as Map<String, Object?>;
}

void main() {
  group('TransferToken and SafeNames', () {
    test('tokens are long, url-safe and compared in constant time', () {
      final String t = TransferToken.generate();
      expect(t, hasLength(20));
      expect(RegExp(r'^[a-z0-9]+$').hasMatch(t), isTrue);
      expect(TransferToken.generate(), isNot(t));
      expect(TransferToken.matches(t, t), isTrue);
      expect(TransferToken.matches('${t.substring(1)}x', t), isFalse);
      expect(TransferToken.matches(null, t), isFalse);
      expect(TransferToken.matches('', t), isFalse);
    });

    test('file names from the browser are made safe and unique', () async {
      expect(SafeNames.clean('../../etc/passwd'), 'passwd');
      expect(SafeNames.clean(r'C:\Users\me\report.pdf'), 'report.pdf');
      expect(SafeNames.clean('  '), 'file');
      expect(SafeNames.clean('..'), 'file');
      expect(SafeNames.clean('my photo (1).JPG'), 'my photo (1).JPG');
      expect(SafeNames.clean('a/b<c>d|e.txt'), 'd_e.txt');
      final Directory dir = await Directory.systemTemp.createTemp('p2l');
      File('${dir.path}/a.txt').writeAsStringSync('x');
      expect(SafeNames.unique(dir, 'a.txt'), 'a (2).txt');
      expect(SafeNames.unique(dir, 'b.txt'), 'b.txt');
      await dir.delete(recursive: true);
    });
  });

  group('LanTransferServer', () {
    late Directory tmp;
    late LanTransferServer server;
    late HttpClient client;
    late String base;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('p2l');
      server = LanTransferServer(inbox: Directory('${tmp.path}/inbox'));
      await server.start(address: InternetAddress.loopbackIPv4);
      client = HttpClient();
      base = 'http://127.0.0.1:${server.port}';
    });

    tearDown(() async {
      client.close(force: true);
      await server.stop();
      await tmp.delete(recursive: true);
    });

    test('every request needs the one-time token', () async {
      expect((await get(client, '$base/')).statusCode, 403);
      expect((await get(client, '$base/?t=wrong')).statusCode, 403);
      expect((await get(client, '$base/api/files?t=wrong')).statusCode, 403);
      final HttpClientResponse ok = await get(client, '$base/?t=${server.token}');
      expect(ok.statusCode, 200);
      final String html = await body(ok);
      expect(html, contains('Drop files here'));
      expect(html, contains(server.token));
      expect(html, isNot(contains('http://')), reason: 'no external resources');
      expect(html, isNot(contains('https://')));
    });

    test('offered files are listed and downloadable with their name', () async {
      final File f = File('${tmp.path}/holiday.pdf')..writeAsStringSync('%PDF-fake');
      await server.offer(f.path);
      await server.offer(f.path);
      expect(server.offered, hasLength(1));
      final Map<String, Object?> list =
          jsonDecode(await body(await get(client, '$base/api/files?t=${server.token}'))) as Map<String, Object?>;
      final List<Object?> files = list['files']! as List<Object?>;
      expect((files.single! as Map<String, Object?>)['name'], 'holiday.pdf');
      final HttpClientResponse dl = await get(client, '$base/api/files/0?t=${server.token}');
      expect(dl.statusCode, 200);
      expect(dl.headers.value('content-disposition'), contains('holiday.pdf'));
      expect(await body(dl), '%PDF-fake');
      expect(server.downloads, 1);
      expect((await get(client, '$base/api/files/7?t=${server.token}')).statusCode, 404);
      server.withdraw(f.path);
      expect(server.offered, isEmpty);
    });

    test('uploads land in the inbox under a safe, unique name', () async {
      final Map<String, Object?> a = await upload(client, base, server.token, 'notes.txt', 'hello');
      expect(a['ok'], isTrue);
      expect(a['name'], 'notes.txt');
      final Map<String, Object?> b = await upload(client, base, server.token, '../../notes.txt', 'again');
      expect(b['name'], 'notes (2).txt');
      expect(server.received.map((ReceivedFile r) => r.name), <String>['notes.txt', 'notes (2).txt']);
      expect(File('${tmp.path}/inbox/notes.txt').readAsStringSync(), 'hello');
      expect(File('${tmp.path}/inbox/notes (2).txt').readAsStringSync(), 'again');
      expect(server.received.first.size, 5);

      await server.discardReceived();
      expect(server.received, isEmpty);
      expect(File('${tmp.path}/inbox/notes.txt').existsSync(), isFalse);
    });

    test('stop closes the port and a restart gets a new token', () async {
      final String first = server.token;
      final int port = server.port;
      await server.stop();
      expect(server.isRunning, isFalse);
      expect(server.token, isEmpty);
      await expectLater(client.getUrl(Uri.parse('http://127.0.0.1:$port/')), throwsA(isA<SocketException>()));
      await server.start(address: InternetAddress.loopbackIPv4);
      expect(server.token, isNot(first));
      base = 'http://127.0.0.1:${server.port}';
      expect((await get(client, '$base/?t=${server.token}')).statusCode, 200);
    });

    test('connect URLs carry the port and token', () {
      expect(server.urlFor('192.168.1.5'), 'http://192.168.1.5:${server.port}/?t=${server.token}');
    });
  });

  group('screen', () {
    testWidgets('Start shows a QR and the address; files flow both ways; Undo removes received',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final Directory tmp = await Directory.systemTemp.createTemp('p2l');
      addTearDown(() => tmp.delete(recursive: true));
      final File offer = File('${tmp.path}/scan.jpg')..writeAsStringSync('jpegdata');
      final LanTransferServer server = LanTransferServer(inbox: Directory('${tmp.path}/inbox'));
      addTearDown(server.stop);

      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: PhoneToLaptopScreen(
          server: server,
          chooser: FakeChooser(<String>[offer.path]),
          addresses: () async => <String>['192.168.1.5'],
        ),
      ));
      expect(find.text('Start'), findsOneWidget);
      expect(find.byKey(const Key('transfer-qr')), findsNothing);

      await tester.runAsync(() async {
        await tester.tap(find.byKey(const Key('transfer-toggle')));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pumpAndSettle();
      expect(server.isRunning, isTrue);
      expect(find.byKey(const Key('transfer-qr')), findsOneWidget);
      expect(find.text(server.urlFor('192.168.1.5')), findsOneWidget);
      expect(find.text('Stop'), findsOneWidget);

      await tester.runAsync(() async {
        await tester.tap(find.byKey(const Key('transfer-add')));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(find.text('scan.jpg'), findsOneWidget);

      await tester.runAsync(() async {
        final HttpClient c = HttpClient();
        final Map<String, Object?> r =
            await upload(c, 'http://127.0.0.1:${server.port}', server.token, 'from-laptop.pdf', 'pdf!');
        expect(r['ok'], isTrue);
        c.close(force: true);
      });
      await tester.pumpAndSettle();
      expect(find.text('from-laptop.pdf'), findsOneWidget);
      expect(File('${tmp.path}/inbox/from-laptop.pdf').existsSync(), isTrue);

      for (final String key in <String>['transfer-toggle', 'transfer-add', 'result-share', 'result-save', 'result-undo']) {
        expect(tester.getSize(find.byKey(Key(key))).height, greaterThanOrEqualTo(44), reason: key);
      }

      await tester.runAsync(() async {
        await tester.tap(find.byKey(const Key('result-undo')));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(find.text('from-laptop.pdf'), findsNothing);
      expect(File('${tmp.path}/inbox/from-laptop.pdf').existsSync(), isFalse);

      await tester.runAsync(() async {
        await tester.tap(find.byKey(const Key('transfer-toggle')));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(server.isRunning, isFalse);
      expect(find.text('Start'), findsOneWidget);
    });
  });
}
