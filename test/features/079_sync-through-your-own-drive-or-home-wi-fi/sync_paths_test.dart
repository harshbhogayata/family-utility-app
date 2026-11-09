import 'dart:io';

import 'package:family_utility_app/app/theme.dart';
import 'package:family_utility_app/engines/family/family_identity.dart';
import 'package:family_utility_app/engines/family/family_space.dart';
import 'package:family_utility_app/engines/family/family_store.dart';
import 'package:family_utility_app/engines/family/family_sync.dart';
import 'package:family_utility_app/engines/family/vector_clock.dart';
import 'package:family_utility_app/family/family_screen.dart';
import 'package:family_utility_app/family/sync/lan_family_sync.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> until(bool Function() done, {Duration limit = const Duration(seconds: 5)}) async {
  final Stopwatch sw = Stopwatch()..start();
  while (!done()) {
    if (sw.elapsed > limit) {
      fail('condition not met within $limit');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

FamilySpace bothSpace() => FamilySpace(
      identityStore: MemoryFamilyIdentityStore(),
      storage: MemoryFamilyStoreStorage(),
      transportsFor: (FamilyIdentity id) => <FamilySyncTransport>[
        LanFamilySync(port: 0, discovery: false, bindAddress: InternetAddress.loopbackIPv4),
        if (id.syncFolder != null) FolderFamilySync(id.syncFolder!, writeDelay: Duration.zero),
      ],
    );

void main() {
  test('a change made here is marked as this phone', () {
    final FamilyStore s = FamilyStore(deviceId: 'a');
    s.put('list', 'x', <String, Object?>{'n': 1});
    expect(s.pathOf('list', 'x'), FamilyPath.thisPhone);
    expect(s.recentChanges.first.via, FamilyPath.thisPhone);
  });

  test('a change through the own-cloud folder is marked as the folder, and the file is sealed', () async {
    final Directory dir = await Directory.systemTemp.createTemp('fam079');
    addTearDown(() => dir.delete(recursive: true));
    final FamilyIdentity mumId = FamilyIdentity.create(familyName: 'Shahs', memberName: 'Mum');
    final FamilyIdentity dadId = FamilyIdentity.join(mumId.invite(), memberName: 'Dad');
    final FamilyStore mum = FamilyStore(deviceId: mumId.deviceId);
    final FamilyStore dad = FamilyStore(deviceId: dadId.deviceId);
    final FolderFamilySync mumSync = FolderFamilySync(dir.path, writeDelay: Duration.zero);
    final FolderFamilySync dadSync = FolderFamilySync(dir.path, writeDelay: Duration.zero);
    await mumSync.start(FamilySyncContext(store: mum, identity: mumId));
    await dadSync.start(FamilySyncContext(store: dad, identity: dadId));

    mum.put('calendar', 'e1', <String, Object?>{'title': 'School play'});
    await mumSync.flushOut();
    expect(await dadSync.pollIn(), 1);
    expect(dad.pathOf('calendar', 'e1'), FamilyPath.folder);
    expect(dad.recentChanges.first.via, FamilyPath.folder);
    for (final FileSystemEntity f in Directory('${dir.path}/family-space').listSync()) {
      expect(File(f.path).readAsStringSync().contains('School play'), isFalse);
    }
    await mumSync.stop();
    await dadSync.stop();
  });

  test('Wi-Fi and the folder both on at once; a Wi-Fi change is marked as Wi-Fi', () async {
    final Directory dir = await Directory.systemTemp.createTemp('fam079b');
    addTearDown(() => dir.delete(recursive: true));
    final FamilySpace mum = bothSpace();
    final FamilySpace dad = bothSpace();
    await mum.create(familyName: 'Shahs', memberName: 'Mum');
    await mum.setSyncFolder(dir.path);
    expect(mum.statusLines.length, 2);
    expect(mum.transports.whereType<LanFamilySync>().length, 1);
    expect(mum.transports.whereType<FolderFamilySync>().length, 1);

    final String code = (await mum.inviteCode())!;
    await dad.join(code, memberName: 'Dad');
    await until(() => mum.memberRecords.length == 2);

    mum.store.put('shopping', 'milk', <String, Object?>{'name': 'Milk'});
    await until(() => dad.store.get('shopping', 'milk') != null);
    expect(dad.store.pathOf('shopping', 'milk'), FamilyPath.wifi);
    expect(mum.store.pathOf('shopping', 'milk'), FamilyPath.thisPhone);
    await mum.leave();
    await dad.leave();
  });

  testWidgets('the Family tab shows which path each recent change took', (WidgetTester tester) async {
    final FamilySpace s = FamilySpace(
      identityStore: MemoryFamilyIdentityStore(),
      storage: MemoryFamilyStoreStorage(),
      transportsFor: (FamilyIdentity _) => <FamilySyncTransport>[],
    );
    await tester.runAsync(() => s.create(familyName: 'Shahs', memberName: 'Asha'));
    await tester.pumpWidget(MaterialApp(theme: buildAppTheme(), home: Scaffold(body: FamilyScreen(space: s))));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Recent changes'), 200);
    expect(find.textContaining('Member changed · via This phone'), findsOneWidget);
    s.store.merge(
      const FamilyRecord(
        collection: 'calendar',
        id: 'e9',
        fields: <String, Object?>{'title': 'Diwali lunch'},
        clock: VectorClock(<String, int>{'other': 1}),
        wallMillis: 1,
        writer: 'other',
      ),
      via: FamilyPath.folder,
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.textContaining('Calendar event changed · via Own folder'), 200);
    expect(find.textContaining('Calendar event changed · via Own folder'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1)); // let the store's save timer run
  });
}
