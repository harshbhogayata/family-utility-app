import 'dart:io';

import 'package:family_utility_app/app/theme.dart';
import 'package:family_utility_app/app/widgets/result_bar.dart';
import 'package:family_utility_app/engines/family/family_identity.dart';
import 'package:family_utility_app/engines/family/family_space.dart';
import 'package:family_utility_app/engines/family/family_store.dart';
import 'package:family_utility_app/engines/family/family_sync.dart';
import 'package:family_utility_app/engines/transfer/nearby_share.dart';
import 'package:family_utility_app/platform/network/nearby_share_net.dart';
import 'package:family_utility_app/tools/nearby_share/nearby_share_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

FamilySpace space() => FamilySpace(
      identityStore: MemoryFamilyIdentityStore(),
      storage: MemoryFamilyStoreStorage(),
      transportsFor: (FamilyIdentity _) => <FamilySyncTransport>[],
    );

void main() {
  testWidgets('outside a family it points to the Family tab', (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(theme: buildAppTheme(), home: NearbyShareScreen(space: space())));
    expect(find.textContaining('Family tab'), findsOneWidget);
    expect(find.byType(ResultBar), findsOneWidget);
  });

  testWidgets('lists family phones by name with 44 px targets', (WidgetTester tester) async {
    final FamilySpace s = space();
    await s.create(familyName: 'Shahs', memberName: 'Mum');
    final NearbyShareService svc = NearbyShareService(
      identity: s.identity!,
      inbox: NearbyInbox(Directory.systemTemp),
      discovery: false,
    );
    svc.addDevice(const NearbyDevice(deviceId: 'dad1', name: 'Dad', host: '10.0.0.2', port: 47830));
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: NearbyShareScreen(space: s, serviceBuilder: (FamilyIdentity _) async => svc),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Dad'), findsOneWidget);
    expect(tester.getSize(find.widgetWithText(ListTile, 'Dad')).height, greaterThanOrEqualTo(44));
    expect(find.text('Nothing yet'), findsOneWidget);
    await tester.tap(find.text('Share'));
    await tester.pump();
    expect(find.text('Nothing received yet'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });
}
