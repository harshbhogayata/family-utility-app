import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:family_utility_app/engines/family/family_identity.dart';
import 'package:family_utility_app/engines/transfer/nearby_share.dart';
import 'package:family_utility_app/platform/network/nearby_share_net.dart';
import 'package:flutter_test/flutter_test.dart';

Future<NearbyShareService> service(FamilyIdentity id, Directory inbox) async {
  final NearbyShareService s = NearbyShareService(
    identity: id,
    inbox: NearbyInbox(inbox),
    port: 0,
    discovery: false,
    bindAddress: InternetAddress.loopbackIPv4,
  );
  await s.start();
  return s;
}

Future<File> randomFile(Directory dir, String name, int size) async {
  final Random r = Random(7);
  final Uint8List bytes = Uint8List(size);
  for (int i = 0; i < size; i++) {
    bytes[i] = r.nextInt(256);
  }
  final File f = File('${dir.path}/$name');
  await f.writeAsBytes(bytes);
  return f;
}

void main() {
  late Directory tmp;
  late FamilyIdentity mum;
  late FamilyIdentity dad;
  late NearbyShareService mumSvc;
  late NearbyShareService dadSvc;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('nearby');
    mum = FamilyIdentity.create(familyName: 'Shahs', memberName: 'Mum');
    dad = FamilyIdentity.join(mum.invite(), memberName: 'Dad');
    mumSvc = await service(mum, Directory('${tmp.path}/mum_in'));
    dadSvc = await service(dad, Directory('${tmp.path}/dad_in'));
  });

  tearDown(() async {
    await mumSvc.stop();
    await dadSvc.stop();
    await tmp.delete(recursive: true);
  });

  NearbyDevice dadDevice() =>
      NearbyDevice(deviceId: dad.deviceId, name: 'Dad', host: '127.0.0.1', port: dadSvc.listeningPort);

  test('family devices are listed by name, never this phone itself', () {
    mumSvc.addDevice(dadDevice());
    mumSvc.addDevice(NearbyDevice(deviceId: mum.deviceId, name: 'Mum', host: '127.0.0.1', port: 1));
    expect(mumSvc.devices.map((NearbyDevice d) => d.name), <String>['Dad']);
  });

  test('a big file goes across intact at LAN speed', () async {
    final File f = await randomFile(tmp, 'video.mp4', 32 * 1024 * 1024);
    final List<int> progress = <int>[];
    final NearbySendResult r = await mumSvc.send(dadDevice(), f.path, onProgress: (int s, int _) => progress.add(s));
    expect(r.attempts, 1);
    expect(r.resumedFrom, <int>[0]);
    expect(progress.last, 32 * 1024 * 1024);
    // Loopback stands in for Wi-Fi: well above what a phone link needs.
    expect(r.megabytesPerSecond, greaterThan(10));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(dadSvc.received.single.from, 'Mum');
    expect(await File(dadSvc.received.single.path).readAsBytes(), await f.readAsBytes());
  });

  test('a dropped link resumes from the bytes already received', () async {
    final File f = await randomFile(tmp, 'photos.zip', 8 * 1024 * 1024);
    final NearbySendResult r =
        await mumSvc.send(dadDevice(), f.path, dropAfterBytes: 3 * 1024 * 1024, maxAttempts: 6);
    expect(r.attempts, greaterThanOrEqualTo(3));
    expect(r.resumedFrom.first, 0);
    for (int i = 1; i < r.resumedFrom.length; i++) {
      expect(r.resumedFrom[i], greaterThan(r.resumedFrom[i - 1]), reason: 'never starts again from zero');
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final File got = File(dadSvc.received.single.path);
    expect(got.path.endsWith('photos.zip'), isTrue);
    expect(await got.readAsBytes(), await f.readAsBytes());
    // No partial file is left behind.
    expect(Directory('${tmp.path}/dad_in').listSync().where((FileSystemEntity e) => e.path.endsWith('.part')), isEmpty);
  });

  test('a phone outside the family cannot send', () async {
    final FamilyIdentity eve = FamilyIdentity.create(familyName: 'Other', memberName: 'Eve');
    final NearbyShareService eveSvc = await service(eve, Directory('${tmp.path}/eve_in'));
    final File f = await randomFile(tmp, 'x.bin', 1024);
    await expectLater(eveSvc.send(dadDevice(), f.path, maxAttempts: 2), throwsA(isA<NearbyShareException>()));
    expect(dadSvc.received, isEmpty);
    await eveSvc.stop();
  });

  test('inbox resumes from the part file and refuses an oversize one', () async {
    final NearbyInbox inbox = NearbyInbox(tmp);
    const NearbyOffer o = NearbyOffer(transferId: 't1', name: '../../etc/passwd', size: 10, from: 'Mum');
    expect(await inbox.offsetFor(o), 0);
    await inbox.partFile(o).writeAsBytes(List<int>.filled(4, 1));
    expect(await inbox.offsetFor(o), 4);
    expect(await inbox.finish(o), isNull);
    await inbox.partFile(o).writeAsBytes(List<int>.filled(12, 1));
    expect(await inbox.offsetFor(o), 0);
    final NearbyOffer parsed = NearbyOffer.fromJson(o.toJson());
    expect(parsed.name, 'passwd');
  });
}
