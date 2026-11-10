import 'dart:typed_data';

import 'package:family_utility_app/engines/records/contacts_backup.dart';
import 'package:family_utility_app/records/contacts_backup/contacts_backup_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final Uint8List jpeg = Uint8List.fromList(<int>[0xff, 0xd8, 0xff, 0xe0, ...List<int>.generate(200, (int i) => i % 256), 0xff, 0xd9]);

class FakeContacts implements ContactsSource {
  FakeContacts(this.contacts);
  final List<BackupContact> contacts;
  final List<BackupContact> inserted = <BackupContact>[];
  final List<BackupContact> updated = <BackupContact>[];

  @override
  Future<bool> allowed({required bool write}) async => true;

  @override
  Future<List<BackupContact>> readAll() async => List<BackupContact>.of(contacts);

  @override
  Future<void> insert(BackupContact c) async {
    inserted.add(c);
    contacts.add(c);
  }

  @override
  Future<void> update(BackupContact c) async {
    updated.add(c);
    final int i = contacts.indexWhere((BackupContact x) => x.id == c.id);
    contacts[i] = c;
  }
}

void main() {
  group('engine', () {
    test('export writes every contact with its photo; parse reads it back', () {
      final List<BackupContact> src = <BackupContact>[
        BackupContact(id: '1', first: 'Asha', last: 'Patel', display: 'Asha Patel', phones: const <String>['+91 98765 43210'], emails: const <String>['asha@example.com'], org: 'City Hospital', photo: jpeg),
        const BackupContact(id: '2', first: 'Ravi; Jr', last: '', display: 'Ravi; Jr', phones: <String>['022-1234567', '9000000001']),
      ];
      final String vcf = ContactsBackup.toVcf(src);
      expect(RegExp('BEGIN:VCARD').allMatches(vcf).length, 2);
      expect(vcf, contains('PHOTO;ENCODING=b;TYPE=JPEG:'));
      expect(vcf.split('\r\n').where((String l) => l.isNotEmpty).every((String l) => l.length <= 75), isTrue);
      final List<BackupContact> back = ContactsBackup.parse(vcf);
      expect(back.length, 2);
      expect(back[0].name, 'Asha Patel');
      expect(back[0].first, 'Asha');
      expect(back[0].last, 'Patel');
      expect(back[0].phones, <String>['+91 98765 43210']);
      expect(back[0].emails, <String>['asha@example.com']);
      expect(back[0].org, 'City Hospital');
      expect(back[0].photo, jpeg);
      expect(back[1].name, 'Ravi; Jr');
      expect(back[1].phones.length, 2);
      expect(back[1].photo, isNull);
    });

    test('reads vCard 2.1 from other phones, with quoted-printable names', () {
      const String v21 = 'BEGIN:VCARD\nVERSION:2.1\nN;CHARSET=UTF-8;ENCODING=QUOTED-PRINTABLE:;=E0=A4=AE=E0=A4=BE;;;\n'
          'FN;CHARSET=UTF-8;ENCODING=QUOTED-PRINTABLE:=E0=A4=AE=E0=A4=BE\nTEL;CELL:+919812345678\nitem1.EMAIL;type=INTERNET:maa@example.com\nEND:VCARD\n';
      final List<BackupContact> c = ContactsBackup.parse(v21);
      expect(c.single.name, 'मा');
      expect(c.single.phones, <String>['+919812345678']);
      expect(c.single.emails, <String>['maa@example.com']);
    });

    test('restore merges into matching contacts and never duplicates', () {
      final List<BackupContact> phone = <BackupContact>[
        const BackupContact(id: 'a', display: 'Asha Patel', phones: <String>['098765-43210']),
        const BackupContact(id: 'b', display: 'Dr Mehta', emails: <String>['mehta@clinic.in'], org: 'Clinic'),
      ];
      final List<BackupContact> file = <BackupContact>[
        // Same number written differently: gains the email and photo.
        BackupContact(display: 'Asha', phones: const <String>['+91 98765 43210'], emails: const <String>['asha@example.com'], photo: jpeg),
        // Already there in full.
        const BackupContact(display: 'Dr Mehta', emails: <String>['MEHTA@clinic.in']),
        // New, and repeated in the file.
        const BackupContact(display: 'Plumber', phones: <String>['9000000001']),
        const BackupContact(display: 'Plumber Raju', phones: <String>['+91 90000 00001', '9000000002']),
        // Nothing to match on but the name.
        const BackupContact(display: 'Milkman'),
        const BackupContact(display: 'milkman'),
      ];
      final RestorePlan p = ContactsBackup.plan(phone, file);
      expect(p.add.map((BackupContact c) => c.name).toList(), <String>['Plumber', 'Milkman']);
      expect(p.add.first.phones, <String>['9000000001', '9000000002']);
      expect(p.update.single.id, 'a');
      expect(p.update.single.emails, <String>['asha@example.com']);
      expect(p.update.single.phones, <String>['098765-43210']);
      expect(p.update.single.photo, jpeg);
      expect(p.same, 2);

      // Restoring the same file again changes nothing.
      final List<BackupContact> after = <BackupContact>[...phone.where((BackupContact c) => c.id != 'a'), p.update.single, ...p.add];
      expect(ContactsBackup.plan(after, file).isEmpty, isTrue);
    });
  });

  testWidgets('screen: back up, share and save the .vcf, restore without duplicates, undo; 44 px targets', (WidgetTester tester) async {
    final SemanticsHandle sem = tester.ensureSemantics();
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final FakeContacts phone = FakeContacts(<BackupContact>[
      BackupContact(id: '1', display: 'Asha Patel', first: 'Asha', last: 'Patel', phones: const <String>['9876543210'], photo: jpeg),
    ]);
    String? shared;
    String? savedName;
    final String file = ContactsBackup.toVcf(<BackupContact>[
      const BackupContact(display: 'Asha Patel', phones: <String>['+91 98765 43210']),
      const BackupContact(display: 'Ravi', phones: <String>['9000000001']),
    ]);
    await tester.pumpWidget(MaterialApp(
      home: ContactsBackupScreen(
        source: phone,
        now: () => DateTime(2026, 3, 20),
        pickVcf: () async => file,
        share: (String vcf, String name) async => shared = vcf,
        save: (String vcf, String name) async {
          savedName = name;
          return '/x/$name';
        },
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('contacts-backup')));
    await tester.pumpAndSettle();
    expect(find.text('Backed up 1 contacts (1 with photos). Share or save the file.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('result-share')));
    await tester.pumpAndSettle();
    expect(ContactsBackup.parse(shared!).single.photo, jpeg);
    await tester.tap(find.byKey(const Key('result-save')));
    await tester.pumpAndSettle();
    expect(savedName, 'Contacts 2026-03-20.vcf');

    await tester.tap(find.byKey(const Key('contacts-restore-pick')));
    await tester.pumpAndSettle();
    expect(find.text('Restore adds 1, adds details to 0, skips 1 already here.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('contacts-restore')));
    await tester.pumpAndSettle();
    expect(phone.inserted.single.name, 'Ravi');
    expect(phone.contacts.length, 2);
    expect(find.text('Restored: 1 added, 0 updated, no duplicates.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('contacts-restore-pick')));
    await tester.pumpAndSettle();
    expect(find.text('All 2 contacts are already on this phone.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('result-undo')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('contacts-status')), findsNothing);

    expect(tester.getSize(find.byKey(const Key('contacts-backup'))).height, greaterThanOrEqualTo(44));
    expect(tester.getSize(find.byKey(const Key('contacts-restore-pick'))).height, greaterThanOrEqualTo(44));
    sem.dispose();
  });
}
