import 'package:family_utility_app/engines/family/family_identity.dart';
import 'package:family_utility_app/engines/family/family_space.dart';
import 'package:family_utility_app/engines/family/family_store.dart';
import 'package:family_utility_app/engines/family/family_sync.dart';
import 'package:family_utility_app/engines/family/shared_contacts.dart';
import 'package:family_utility_app/family/contacts/shared_contacts_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

FamilySpace newSpace() => FamilySpace(
      identityStore: MemoryFamilyIdentityStore(),
      storage: MemoryFamilyStoreStorage(),
      transportsFor: (FamilyIdentity _) => <FamilySyncTransport>[],
    );

void main() {
  group('engine', () {
    test('add with tags, reject bad or duplicate numbers, filter, undo', () async {
      final FamilySpace s = newSpace();
      await s.create(familyName: 'Shahs', memberName: 'Asha');
      final SharedContacts c = SharedContacts(space: s);

      expect(c.add('Ramesh', '98200 12345', tags: <String>['Plumber']), ContactOutcome.added);
      expect(c.add('Dr Mehta', '+91 22 2345 6789', tags: <String>['Doctor']), ContactOutcome.added);
      expect(c.add('Neha', '9820012345'), ContactOutcome.duplicate);
      expect(c.add('', '12345678'), ContactOutcome.missingName);
      expect(c.add('X', '12'), ContactOutcome.badNumber);
      expect(c.add('Sunil', '9000011111'), ContactOutcome.added);

      expect(c.contacts.map((SharedContact x) => x.name), <String>['Dr Mehta', 'Ramesh', 'Sunil']);
      expect(c.contacts.last.tags, <String>[ContactTags.other]);
      expect(c.tagsInUse, <String>['Doctor', 'Plumber', 'Other']);
      expect(c.filter(tag: 'Plumber').single.name, 'Ramesh');
      expect(c.filter(query: 'mehta').single.name, 'Dr Mehta');
      expect(c.filter(query: '00123').single.name, 'Ramesh');
      expect(c.filter(query: 'doc').single.name, 'Dr Mehta');

      final SharedContact r = c.filter(tag: 'Plumber').single;
      expect(r.callUri.toString(), 'tel:9820012345');
      expect(r.whatsAppUri.toString(), 'https://wa.me/919820012345');
      expect(c.filter(tag: 'Doctor').single.whatsAppUri.toString(), 'https://wa.me/912223456789');

      expect(c.remove(r.id), isTrue);
      expect(c.contact(r.id), isNull);
      expect(c.undo(), isTrue);
      expect(c.contact(r.id)!.name, 'Ramesh');
      expect(c.toText(), contains('Plumber\nRamesh: 98200 12345'));
    });

    test('speed dial holds three and feeds the widget row', () async {
      final FamilySpace s = newSpace();
      await s.create(familyName: 'F', memberName: 'A');
      final SharedContacts c = SharedContacts(space: s);
      for (int i = 0; i < 4; i++) {
        c.add('P$i', '98765000$i$i');
      }
      final List<SharedContact> all = c.contacts;
      expect(c.setSpeedDial(all[0].id, true), isTrue);
      expect(c.setSpeedDial(all[1].id, true), isTrue);
      expect(c.setSpeedDial(all[2].id, true), isTrue);
      expect(c.setSpeedDial(all[3].id, true), isFalse);
      expect(c.add('P9', '9876500099', speedDial: true), ContactOutcome.speedDialFull);
      expect(c.speedDialEntries.map((e) => e.label), <String>['P0', 'P1', 'P2']);
      expect(c.speedDialEntries.first.number, '9876500000');
      expect(c.setSpeedDial(all[0].id, false), isTrue);
      expect(c.speedDial.length, 2);
      expect(c.toText(), contains('(speed dial)'));
    });
  });

  testWidgets('screen: add, filter by tag, call, WhatsApp, pin, Undo', (WidgetTester tester) async {
    final SemanticsHandle sem = tester.ensureSemantics();
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final FamilySpace s = newSpace();
    await s.create(familyName: 'F', memberName: 'Asha');
    final SharedContacts c = SharedContacts(space: s);
    c.add('Dr Mehta', '+91 22 2345 6789', tags: <String>['Doctor']);
    final List<Uri> opened = <Uri>[];
    String? shared;
    await tester.pumpWidget(MaterialApp(
      home: SharedContactsScreen(
        contacts: c,
        launch: (Uri u) async {
          opened.add(u);
          return true;
        },
        share: (String t) async => shared = t,
      ),
    ));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('contact-name')), 'Ramesh');
    await tester.enterText(find.byKey(const Key('contact-phone')), '98200 12345');
    await tester.tap(find.byKey(const Key('contact-add')));
    await tester.pumpAndSettle();
    expect(c.contacts.length, 2);
    final SharedContact ramesh = c.contacts.firstWhere((SharedContact x) => x.name == 'Ramesh');
    expect(ramesh.tags, <String>['Family']);

    await tester.tap(find.byKey(const Key('filter-Doctor')));
    await tester.pumpAndSettle();
    expect(find.text('Ramesh'), findsNothing);
    expect(find.text('Dr Mehta'), findsOneWidget);
    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(Key('call-${ramesh.id}')));
    await tester.tap(find.byKey(Key('whatsapp-${ramesh.id}')));
    await tester.pumpAndSettle();
    expect(opened.map((Uri u) => u.toString()), <String>['tel:9820012345', 'https://wa.me/919820012345']);

    expect(tester.getSize(find.byKey(Key('call-${ramesh.id}'))).height, greaterThanOrEqualTo(44));
    expect(find.byTooltip('WhatsApp Ramesh'), findsOneWidget);

    await tester.tap(find.byKey(Key('pin-${ramesh.id}')));
    await tester.pumpAndSettle();
    expect(c.contact(ramesh.id)!.speedDial, isTrue);
    expect(find.byTooltip('Unpin Ramesh from speed dial'), findsOneWidget);

    await tester.tap(find.byKey(const Key('result-undo')));
    await tester.pumpAndSettle();
    expect(c.contact(ramesh.id)!.speedDial, isFalse);

    await tester.tap(find.byKey(const Key('result-share')));
    await tester.pumpAndSettle();
    expect(shared, contains('Dr Mehta'));
    sem.dispose();
  });
}
