import 'dart:io';

import 'package:family_utility_app/engines/family/family_identity.dart';
import 'package:family_utility_app/engines/family/family_space.dart';
import 'package:family_utility_app/engines/family/family_store.dart';
import 'package:family_utility_app/engines/family/family_sync.dart';
import 'package:family_utility_app/engines/family/vector_clock.dart';
import 'package:family_utility_app/engines/privacy/offline_policy.dart';
import 'package:family_utility_app/family/sync/lan_family_sync.dart';
import 'package:flutter_test/flutter_test.dart';

/// Waits until [done] holds, polling every 20 ms, up to [limit].
Future<Duration> until(bool Function() done, {Duration limit = const Duration(seconds: 5)}) async {
  final Stopwatch sw = Stopwatch()..start();
  while (!done()) {
    if (sw.elapsed > limit) {
      fail('condition not met within $limit');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  return sw.elapsed;
}

FamilySpace lanSpace() => FamilySpace(
      identityStore: MemoryFamilyIdentityStore(),
      storage: MemoryFamilyStoreStorage(),
      transportsFor: (FamilyIdentity _) => <FamilySyncTransport>[
        LanFamilySync(port: 0, discovery: false, bindAddress: InternetAddress.loopbackIPv4),
      ],
    );

void main() {
  group('vector clocks', () {
    test('increment, compare and merge', () {
      const VectorClock zero = VectorClock();
      final VectorClock a = zero.increment('a');
      final VectorClock ab = a.increment('b');
      expect(zero.compare(a), ClockOrder.before);
      expect(ab.compare(a), ClockOrder.after);
      expect(a.compare(VectorClock.fromJson(a.toJson())), ClockOrder.equal);
      final VectorClock a2 = a.increment('a');
      expect(a2.compare(ab), ClockOrder.concurrent);
      expect(a2.merge(ab).counters, <String, int>{'a': 2, 'b': 1});
    });
  });

  group('local-first CRDT store', () {
    test('a later edit that saw the earlier one wins', () {
      final FamilyStore mum = FamilyStore(deviceId: 'mum');
      final FamilyStore dad = FamilyStore(deviceId: 'dad');
      final FamilyRecord r1 = mum.put('list', 'milk', <String, Object?>{'qty': 1});
      expect(dad.merge(r1), isTrue);
      final FamilyRecord r2 = dad.put('list', 'milk', <String, Object?>{'qty': 2});
      expect(mum.merge(r2), isTrue);
      expect(mum.get('list', 'milk')!.fields['qty'], 2);
      // Replaying the old edit changes nothing.
      expect(mum.merge(r1), isFalse);
      expect(mum.get('list', 'milk')!.fields['qty'], 2);
    });

    test('offline edits on both phones converge to the same winner, in any order', () {
      int t = 1000;
      final FamilyStore mum = FamilyStore(deviceId: 'mum', now: () => DateTime.fromMillisecondsSinceEpoch(t));
      final FamilyStore dad = FamilyStore(deviceId: 'dad', now: () => DateTime.fromMillisecondsSinceEpoch(t));
      dad.merge(mum.put('list', 'eggs', <String, Object?>{'qty': 6}));

      // Both go offline and edit the same record, plus one each of their own.
      t = 2000;
      final FamilyRecord mumEdit = mum.put('list', 'eggs', <String, Object?>{'qty': 12});
      final FamilyRecord mumNew = mum.put('list', 'bread', <String, Object?>{'qty': 1});
      t = 3000;
      final FamilyRecord dadEdit = dad.put('list', 'eggs', <String, Object?>{'qty': 18});
      final FamilyRecord dadDel = dad.delete('list', 'eggs')!;
      final FamilyRecord dadNew = dad.put('list', 'rice', <String, Object?>{'qty': 2});
      expect(dadEdit.clock.compare(mumEdit.clock), ClockOrder.concurrent);

      // Back online: exchange in opposite orders.
      mum.mergeAll(<FamilyRecord>[dadNew, dadDel, dadEdit]);
      dad.mergeAll(<FamilyRecord>[mumNew, mumEdit]);

      String dump(FamilyStore s) =>
          (s.allRecords.map((FamilyRecord r) => '${r.key}:${r.deleted}:${r.fields}:${r.clock.counters}').toList()
                ..sort())
              .join('|');
      expect(dump(mum), dump(dad));
      expect(mum.get('list', 'eggs'), isNull, reason: 'the later delete wins the tie');
      expect(mum.list('list').map((FamilyRecord r) => r.id), <String>['bread', 'rice']);
    });

    test('records survive a restart through storage', () async {
      final MemoryFamilyStoreStorage storage = MemoryFamilyStoreStorage();
      final FamilyStore a = FamilyStore(deviceId: 'a', storage: storage);
      a.put('notes', 'n1', <String, Object?>{'text': 'Gas bill'});
      await a.flush();
      final FamilyStore b = FamilyStore(deviceId: 'a', storage: storage);
      await b.load();
      expect(b.get('notes', 'n1')!.fields['text'], 'Gas bill');
      a.dispose();
      b.dispose();
    });
  });

  group('invite QR', () {
    test('round-trips and rejects anything else', () {
      final FamilyIdentity id = FamilyIdentity.create(familyName: 'Shahs', memberName: 'Asha');
      final String code = id.invite(hosts: <String>['192.168.1.5'], port: 47820).encode();
      final FamilyInvite back = FamilyInvite.parse(code)!;
      expect(back.familyId, id.familyId);
      expect(back.familyName, 'Shahs');
      expect(back.secret, id.secret);
      expect(back.hosts, <String>['192.168.1.5']);
      expect(back.port, 47820);
      expect(FamilyInvite.parse('https://example.com'), isNull);
      expect(FamilyInvite.parse('${FamilyInvite.prefix}garbage'), isNull);
      final FamilyIdentity joined = FamilyIdentity.join(back, memberName: 'Ravi');
      expect(joined.familyId, id.familyId);
      expect(joined.deviceId, isNot(id.deviceId));
    });

    test('a different family key cannot open sealed data', () async {
      final FamilyIdentity a = FamilyIdentity.create(familyName: 'A', memberName: 'x');
      final FamilyIdentity b = FamilyIdentity.create(familyName: 'B', memberName: 'y');
      final String sealed = await FamilyCipher(a.secret).seal('hello');
      expect(sealed.contains('hello'), isFalse);
      expect(await FamilyCipher(a.secret).open(sealed), 'hello');
      await expectLater(FamilyCipher(b.secret).open(sealed), throwsA(anything));
    });
  });

  group('home Wi-Fi sync', () {
    test('join by invite, then a change reaches the other phone in under 3 s', () async {
      final FamilySpace mum = lanSpace();
      final FamilySpace dad = lanSpace();
      await mum.create(familyName: 'Shahs', memberName: 'Mum');
      mum.store.put('list', 'milk', <String, Object?>{'qty': 1});

      final String code = (await mum.inviteCode())!;
      expect(FamilyInvite.parse(code)!.hosts, <String>['127.0.0.1']);
      final FamilyIdentity? joined = await dad.join(code, memberName: 'Dad');
      expect(joined, isNotNull);

      // Dad receives what was there before he joined; Mum sees Dad.
      await until(() => dad.store.get('list', 'milk') != null);
      await until(() => mum.memberRecords.length == 2);
      expect(dad.memberRecords.map((FamilyRecord r) => r.fields['name']), containsAll(<String>['Mum', 'Dad']));

      // Live edit both ways, timed.
      mum.store.put('list', 'milk', <String, Object?>{'qty': 3});
      final Duration there = await until(() => dad.store.get('list', 'milk')!.fields['qty'] == 3);
      expect(there, lessThan(const Duration(seconds: 3)));
      dad.store.delete('list', 'milk');
      final Duration back = await until(() => mum.store.get('list', 'milk') == null);
      expect(back, lessThan(const Duration(seconds: 3)));

      expect(mum.statusLines.single, 'Wi-Fi: 1 phone connected');
      await mum.leave();
      await dad.leave();
      expect(mum.inFamily, isFalse);
    });

    test('a phone without the family key is hung up on', () async {
      final FamilySpace mum = lanSpace();
      await mum.create(familyName: 'Shahs', memberName: 'Mum');
      final LanFamilySync lan = mum.transports.single as LanFamilySync;

      final FamilySpace stranger = lanSpace();
      await stranger.create(familyName: 'Other', memberName: 'Eve');
      final LanFamilySync evil = stranger.transports.single as LanFamilySync;
      expect(await evil.connect('127.0.0.1', lan.listeningPort), isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(lan.peerCount, 0);
      expect(mum.memberRecords.length, 1);
      await mum.leave();
      await stranger.leave();
    });
  });

  group('own-cloud folder sync', () {
    test('sealed change files carry edits between phones within a minute', () async {
      final Directory dir = await Directory.systemTemp.createTemp('famsync');
      addTearDown(() => dir.delete(recursive: true));
      final FamilyIdentity mumId = FamilyIdentity.create(familyName: 'Shahs', memberName: 'Mum');
      final FamilyIdentity dadId = FamilyIdentity.join(mumId.invite(), memberName: 'Dad');
      final FamilyStore mum = FamilyStore(deviceId: mumId.deviceId);
      final FamilyStore dad = FamilyStore(deviceId: dadId.deviceId);
      final FolderFamilySync mumSync = FolderFamilySync(dir.path, writeDelay: Duration.zero);
      final FolderFamilySync dadSync = FolderFamilySync(dir.path, writeDelay: Duration.zero);
      expect(mumSync.pollEvery + mumSync.writeDelay, lessThan(const Duration(minutes: 1)));

      mum.put('vault', 'passport', <String, Object?>{'expires': '2030-01-01'});
      await mumSync.start(FamilySyncContext(store: mum, identity: mumId));
      await dadSync.start(FamilySyncContext(store: dad, identity: dadId));
      expect(dad.get('vault', 'passport')!.fields['expires'], '2030-01-01');

      dad.put('vault', 'passport', <String, Object?>{'expires': '2035-01-01'});
      await dadSync.flushOut();
      expect(await mumSync.pollIn(), 1);
      expect(mum.get('vault', 'passport')!.fields['expires'], '2035-01-01');

      // Nothing readable lands in the folder.
      for (final FileSystemEntity f in Directory('${dir.path}/family-space').listSync()) {
        final String body = File(f.path).readAsStringSync();
        expect(body.contains('passport'), isFalse);
        expect(body.contains('2035'), isFalse);
      }
      await mumSync.stop();
      await dadSync.stop();
    });
  });

  test('family sync is home-Wi-Fi only, never an internet feature', () {
    expect(OfflinePolicy.lanFeatures, contains(68));
    expect(OfflinePolicy.networkFeatures, isNot(contains(68)));
    expect(OfflinePolicy.networkSourceFolders, contains('lib/family/sync/'));
  });
}
