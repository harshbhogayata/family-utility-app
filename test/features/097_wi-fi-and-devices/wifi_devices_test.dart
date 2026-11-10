import 'package:family_utility_app/engines/qr/qr_generator.dart';
import 'package:family_utility_app/engines/records/wifi_devices.dart';
import 'package:family_utility_app/engines/security/secure_notes.dart';
import 'package:family_utility_app/records/wifi_devices/wifi_devices_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

WifiDevicesBook make({MemoryKeyStore? keys, MemoryNoteBlobStore? blobs}) =>
    WifiDevicesBook(keyStore: keys ?? MemoryKeyStore(), blobStore: blobs ?? MemoryNoteBlobStore());

void main() {
  group('engine', () {
    test('Wi-Fi as QR, devices with serials and dates, encrypted, undo', () async {
      final MemoryKeyStore keys = MemoryKeyStore();
      final MemoryNoteBlobStore blobs = MemoryNoteBlobStore();
      final WifiDevicesBook b = make(keys: keys, blobs: blobs);
      await b.load();
      expect(await b.saveNetwork(ssid: '  '), isNull);
      expect(await b.saveNetwork(ssid: 'Home'), isNull); // WPA needs a password
      final WifiNetwork home = (await b.saveNetwork(ssid: ' Sharma Home ', password: 'p@ss;word', where: 'Home'))!;
      final WifiNetwork guest = (await b.saveNetwork(ssid: 'Guest', password: 'ignored', auth: WifiAuth.open))!;
      expect(home.qrData, r'WIFI:T:WPA;S:Sharma Home;P:p@ss\;word;;');
      expect(guest.qrData, 'WIFI:T:nopass;S:Guest;;');
      expect(guest.password, '');

      final DateTime today = DateTime(2026, 1, 20);
      expect(await b.saveDevice(name: 'TV', bought: DateTime(2026, 2, 1), today: today), isNull);
      final HomeDevice tv = (await b.saveDevice(
        name: 'Living room TV',
        model: 'Sony Bravia 55',
        serial: 'SN-4421 X9',
        bought: DateTime(2024, 10, 2),
        networkId: home.id,
        today: today,
      ))!;
      await b.saveDevice(name: 'Router', serial: 'R1', bought: DateTime(2025, 3, 1), today: today);
      await b.saveDevice(name: 'AC', networkId: 'nope', today: today);
      expect(b.devices.map((HomeDevice d) => d.name), <String>['Router', 'Living room TV', 'AC']);
      expect(b.devices.last.networkId, isNull);
      expect(b.devicesOn(home.id).single.id, tv.id);
      expect(b.bySerial('sn 4421-x9')?.id, tv.id);

      // Stored encrypted: the password is not in the saved blob.
      expect(blobs.blob, isNotNull);
      expect(blobs.blob!.contains('p@ss'), isFalse);
      expect(blobs.blob!.contains('SN-4421'), isFalse);
      final WifiDevicesBook again = make(keys: keys, blobs: blobs);
      await again.load();
      expect(again.network(home.id)!.password, 'p@ss;word');
      expect(again.devices.length, 3);

      final String shared = b.toText();
      expect(shared, contains('- Sharma Home (Home) · WPA/WPA2'));
      expect(shared, isNot(contains('p@ss')));
      expect(shared, contains('- Living room TV · Sony Bravia 55 · S/N SN-4421 X9 · bought 2 Oct 2024 · on Sharma Home'));
      expect(b.toText(includePasswords: true), contains('password p@ss;word'));

      expect(await b.removeNetwork(home.id), isTrue);
      expect(b.devices.firstWhere((HomeDevice d) => d.id == tv.id).networkId, isNull);
      expect(await b.undo(), isTrue);
      expect(b.network(home.id), isNotNull);
      expect(b.devicesOn(home.id).single.id, tv.id);

      // Editing keeps the id and position.
      await b.saveNetwork(id: home.id, ssid: 'Sharma 5G', password: 'new');
      expect(b.networks.first.ssid, 'Sharma 5G');
      expect(b.networks.length, 2);
    });
  });

  testWidgets('screen: add network, show QR, add device, share, undo; 44 px', (WidgetTester tester) async {
    final SemanticsHandle sem = tester.ensureSemantics();
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final WifiDevicesBook b = make();
    await b.load();
    final List<String> shared = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: WifiDevicesScreen(
        book: b,
        share: (String t) async => shared.add(t),
        save: (String t, String n) async => '/x/$n',
        today: () => DateTime(2026, 1, 20),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('No networks yet'), findsOneWidget);

    await tester.tap(find.byKey(const Key('wifi-devices-add')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('wifi-ssid')), 'Sharma Home');
    await tester.enterText(find.byKey(const Key('wifi-password')), 'secret123');
    await tester.tap(find.byKey(const Key('wifi-save')));
    await tester.pumpAndSettle();
    final WifiNetwork n = b.networks.single;
    expect(find.text('WPA/WPA2 · ••••••••'), findsOneWidget);
    expect(find.text('secret123'), findsNothing);

    expect(tester.getSize(find.byKey(Key('wifi-show-${n.id}'))).height, greaterThanOrEqualTo(44));
    await tester.tap(find.byKey(Key('wifi-show-${n.id}')));
    await tester.pumpAndSettle();
    expect(find.text('WPA/WPA2 · secret123'), findsOneWidget);
    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.bySemanticsLabel('QR code to join Sharma Home'), findsOneWidget);

    await tester.tap(find.byKey(const Key('tab-devices')));
    await tester.pumpAndSettle();
    expect(find.textContaining('No devices yet'), findsOneWidget);
    await tester.tap(find.byKey(const Key('wifi-devices-add')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('device-name')), 'Living room TV');
    await tester.enterText(find.byKey(const Key('device-serial')), 'SN-4421');
    await tester.enterText(find.byKey(const Key('device-bought')), '02/10/2024');
    await tester.tap(find.byKey(const Key('device-network')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sharma Home').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('device-save')));
    await tester.pumpAndSettle();
    expect(find.text('S/N SN-4421'), findsOneWidget);
    expect(find.text('Bought 2 Oct 2024'), findsOneWidget);
    expect(find.text('On Sharma Home'), findsOneWidget);

    await tester.tap(find.byKey(const Key('result-share')));
    await tester.pumpAndSettle();
    expect(shared.last, contains('- Living room TV · S/N SN-4421 · bought 2 Oct 2024 · on Sharma Home'));
    expect(shared.last, isNot(contains('secret123')));

    await tester.tap(find.byKey(const Key('result-undo')));
    await tester.pumpAndSettle();
    expect(find.textContaining('No devices yet'), findsOneWidget);
    await tester.pumpAndSettle(const Duration(seconds: 5));
    sem.dispose();
  });
}
