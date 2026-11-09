import 'package:family_utility_app/app/theme.dart';
import 'package:family_utility_app/engines/family/family_identity.dart';
import 'package:family_utility_app/engines/family/family_space.dart';
import 'package:family_utility_app/engines/family/family_store.dart';
import 'package:family_utility_app/engines/family/family_sync.dart';
import 'package:family_utility_app/family/family_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeTransport extends FamilySyncTransport {
  FamilyInvite? reached;

  @override
  String get status => 'Wi-Fi: looking for family phones';

  @override
  Future<void> start(FamilySyncContext context) async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> reach(FamilyInvite invite) async => reached = invite;
}

FamilySpace space(FakeTransport t) => FamilySpace(
      identityStore: MemoryFamilyIdentityStore(),
      storage: MemoryFamilyStoreStorage(),
      transportsFor: (FamilyIdentity _) => <FamilySyncTransport>[t],
    );

Widget host(FamilySpace s, {FamilyQrScan? scan}) => MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(body: FamilyScreen(space: s, scan: scan, pickFolder: () async => '/storage/Drive/Family')),
    );

void main() {
  testWidgets('start a family space, see yourself, set a sync folder, leave', (WidgetTester tester) async {
    final FakeTransport t = FakeTransport();
    final FamilySpace s = space(t);
    await tester.pumpWidget(host(s));

    await tester.enterText(find.widgetWithText(TextField, 'Your name'), 'Asha');
    await tester.enterText(find.widgetWithText(TextField, 'Family name (when starting one)'), 'Shahs');
    await tester.tap(find.text('Start a family space'));
    await tester.pumpAndSettle();

    expect(find.text('Shahs'), findsOneWidget);
    expect(find.text('Asha'), findsOneWidget);
    expect(find.text('This phone'), findsOneWidget);
    expect(find.bySemanticsLabel('Sync status: Wi-Fi: looking for family phones'), findsOneWidget);

    await tester.tap(find.text('Sync folder (your own Drive or iCloud)'));
    await tester.pumpAndSettle();
    expect(s.identity!.syncFolder, '/storage/Drive/Family');
    expect(find.text('/storage/Drive/Family'), findsOneWidget);

    // Touch targets of the main actions are at least 44 px tall.
    expect(tester.getSize(find.widgetWithText(FilledButton, 'Invite a member')).height, greaterThanOrEqualTo(44));

    await tester.ensureVisible(find.text('Leave family on this phone', skipOffstage: false));
    await tester.tap(find.text('Leave family on this phone'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Leave'));
    await tester.pumpAndSettle();
    expect(s.inFamily, isFalse);
    expect(find.text('Start a family space'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('join by scanning a QR from an existing member, with Undo', (WidgetTester tester) async {
    final FamilyIdentity mum = FamilyIdentity.create(familyName: 'Shahs', memberName: 'Mum');
    final String code = mum.invite(hosts: <String>['192.168.1.5'], port: 47820).encode();
    final FakeTransport t = FakeTransport();
    final FamilySpace s = space(t);
    await tester.pumpWidget(host(s, scan: (BuildContext _) async => code));

    expect(tester.getSize(find.widgetWithText(OutlinedButton, 'Join by scanning a QR')).height, greaterThanOrEqualTo(44));
    await tester.enterText(find.widgetWithText(TextField, 'Your name'), 'Ravi');
    await tester.tap(find.text('Join by scanning a QR'));
    await tester.pumpAndSettle();

    expect(s.identity!.familyId, mum.familyId);
    expect(t.reached!.hosts, <String>['192.168.1.5']);
    expect(find.text('Joined Shahs'), findsOneWidget);
    expect(find.text('Ravi'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(s.inFamily, isFalse);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('a QR that is not an invite is refused', (WidgetTester tester) async {
    final FamilySpace s = space(FakeTransport());
    await tester.pumpWidget(host(s, scan: (BuildContext _) async => 'WIFI:S:home;P:secret;;'));
    await tester.tap(find.text('Join by scanning a QR'));
    await tester.pumpAndSettle();
    expect(find.text('That QR is not a family invite'), findsOneWidget);
    expect(s.inFamily, isFalse);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('the invite sheet shows the QR and a way to share it', (WidgetTester tester) async {
    final FamilyIdentity mum = FamilyIdentity.create(familyName: 'Shahs', memberName: 'Mum');
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(body: InviteSheet(code: mum.invite().encode(), familyName: 'Shahs')),
    ));
    expect(find.text('Join Shahs'), findsOneWidget);
    expect(find.bySemanticsLabel('Family invite QR code'), findsOneWidget);
    expect(find.text('Share code'), findsOneWidget);
  });
}
