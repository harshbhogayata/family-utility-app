import 'dart:typed_data';

import 'package:family_utility_app/app/theme.dart';
import 'package:family_utility_app/engines/family/document_vault.dart';
import 'package:family_utility_app/engines/family/family_identity.dart';
import 'package:family_utility_app/engines/family/family_space.dart';
import 'package:family_utility_app/engines/family/family_store.dart';
import 'package:family_utility_app/engines/family/family_sync.dart';
import 'package:family_utility_app/engines/security/private_vault.dart';
import 'package:family_utility_app/engines/security/secure_notes.dart' show MemoryKeyStore;
import 'package:family_utility_app/family/documents/document_vault_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

FamilySpace newSpace() => FamilySpace(
      identityStore: MemoryFamilyIdentityStore(),
      storage: MemoryFamilyStoreStorage(),
      transportsFor: (FamilyIdentity _) => <FamilySyncTransport>[],
    );

class FakeMasker implements DocumentMasker {
  int calls = 0;

  @override
  Future<Uint8List> mask(Uint8List image) async {
    calls++;
    return Uint8List.fromList(<int>[...image, 0]);
  }
}

final Uint8List photo = Uint8List.fromList(<int>[0xFF, 0xD8, 0xFF, 1, 2, 3, 4, 5, 6, 7]);

Future<Uint8List> fakePdf(Uint8List b) async => Uint8List.fromList(<int>[0x25, 0x50, 0x44, 0x46, ...b]);

void main() {
  group('engine', () {
    test('encrypted at rest, per member, sorted by expiry; remove and undo', () async {
      final FamilySpace s = newSpace();
      await s.create(familyName: 'Shahs', memberName: 'Asha');
      s.store.put(FamilySpace.members, 'ravi-phone', <String, Object?>{'name': 'Ravi'});
      final MemoryDocumentBlobStore blobs = MemoryDocumentBlobStore();
      final DocumentVault v = DocumentVault(
          cipher: VaultCipher(MemoryKeyStore()), blobs: blobs, space: s, now: () => DateTime(2026, 11, 9, 10));

      final FamilyDocument passport = await v.add(
          member: 'ravi-phone', type: FamilyDocType.passport, bytes: photo, expiry: DateTime(2027, 1, 20));
      final FamilyDocument ins = await v.add(
          member: s.identity!.deviceId,
          type: FamilyDocType.insurance,
          bytes: photo,
          title: 'Car insurance',
          expiry: DateTime(2026, 12, 1));
      final FamilyDocument aadhaar = await v.add(member: s.identity!.deviceId, type: FamilyDocType.aadhaar, bytes: photo);

      expect(passport.title, 'Passport · Ravi');
      expect(blobs.files[passport.id], isNot(equals(photo)));
      expect(blobs.files[passport.id]!.length, greaterThan(photo.length));
      expect(await v.open(passport), photo);
      expect(v.documents.map((FamilyDocument d) => d.id), <String>[ins.id, passport.id, aadhaar.id]);
      expect(ins.daysLeft(DateTime(2026, 11, 9)), 22);
      expect(v.byMember().map((MapEntry<String, List<FamilyDocument>> e) => v.memberName(e.key)), <String>['Asha', 'Ravi']);

      // Only the card's details are shared, never the picture.
      final Map<String, Object?> shared = s.store.get(DocumentVault.collection, passport.id)!.fields;
      expect(shared.keys.toSet(), <String>{'member', 'type', 'title', 'holder', 'at', 'expiry'});

      expect(v.remove(ins.id), isTrue);
      expect(v.document(ins.id), isNull);
      expect(v.undo(), isTrue);
      expect(v.document(ins.id)!.title, 'Car insurance');
      expect(await v.open(v.document(ins.id)!), photo);

      final String text = v.toText();
      expect(text, contains('- Car insurance (Insurance) · expires 2026-12-01 · 22 days left'));
      expect(text, contains('- Aadhaar · Asha (Aadhaar)'));
    });

    test('reminders at 30, 7 and 1 day; the watcher catches up after a closed app', () async {
      final FamilySpace s = newSpace();
      await s.create(familyName: 'F', memberName: 'A');
      final DocumentVault v =
          DocumentVault(cipher: VaultCipher(MemoryKeyStore()), blobs: MemoryDocumentBlobStore(), space: s);
      final FamilyDocument d =
          await v.add(member: 'x', type: FamilyDocType.vehicle, bytes: photo, title: 'RC', expiry: DateTime(2027, 3, 31));
      expect(DocumentVault.reminderAt(d.expiry!, 30), DateTime(2027, 3, 1, 9));
      expect(DocumentVault.reminderAt(d.expiry!, 7), DateTime(2027, 3, 24, 9));
      expect(DocumentVault.reminderAt(d.expiry!, 1), DateTime(2027, 3, 30, 9));
      expect(v.dueReminders(DateTime(2027, 2, 1), DateTime(2027, 3, 31)).map((DocumentReminder r) => r.days),
          <int>[30, 7, 1]);
      expect(v.dueReminders(DateTime(2027, 3, 1, 9), DateTime(2027, 3, 2)), isEmpty);

      final List<String> fired = <String>[];
      final MemoryDocumentReminderMarks marks = MemoryDocumentReminderMarks()..value = DateTime(2027, 3, 20);
      DateTime now = DateTime(2027, 3, 25, 8);
      final DocumentReminderWatcher w = DocumentReminderWatcher(
        vault: v,
        sink: _ListSink(fired),
        marks: marks,
        now: () => now,
      );
      expect(await w.check(), 1);
      expect(fired, <String>['RC expires in 7 days']);
      expect(marks.value, now);
      now = DateTime(2027, 3, 30, 10);
      expect(await w.check(), 1);
      expect(fired.last, 'RC expires tomorrow');
      expect(await w.check(), 0);
    });

    test('send as PDF and send masked; a PDF goes as it is; file on another phone', () async {
      final FamilySpace s = newSpace();
      await s.create(familyName: 'F', memberName: 'A');
      final DocumentVault v =
          DocumentVault(cipher: VaultCipher(MemoryKeyStore()), blobs: MemoryDocumentBlobStore(), space: s);
      final FamilyDocument d = await v.add(member: 'x', type: FamilyDocType.aadhaar, bytes: photo);
      final Uint8List pdf = await v.asPdf(d, fakePdf);
      expect(DocumentVault.isPdf(pdf), isTrue);
      final FakeMasker m = FakeMasker();
      final Uint8List masked = await v.maskedPdf(d, m, fakePdf);
      expect(m.calls, 1);
      expect(masked.last, 0);

      final Uint8List realPdf = Uint8List.fromList('%PDF-1.4 x'.codeUnits);
      final FamilyDocument p = await v.add(member: 'x', type: FamilyDocType.pan, bytes: realPdf);
      expect(await v.asPdf(p, fakePdf), realPdf);
      await expectLater(v.maskedPdf(p, m, fakePdf), throwsA(isA<DocumentVaultException>()));

      s.store.put(DocumentVault.collection, 'far', <String, Object?>{
        'member': 'x',
        'type': 'passport',
        'title': 'Passport',
        'holder': 'other-phone',
        'at': '2026-11-09T10:00:00.000',
      });
      await expectLater(v.open(v.document('far')!), throwsA(isA<DocumentVaultException>()));
    });

    test('expiry edits made on another phone merge in', () {
      final FamilyStore a = FamilyStore(deviceId: 'phone-a');
      final FamilyStore b = FamilyStore(deviceId: 'phone-b');
      a.put(DocumentVault.collection, 'd', <String, Object?>{'member': 'm', 'type': 'insurance', 'title': 'Health', 'holder': 'phone-a'});
      b.mergeAll(a.allRecords);
      b.put(DocumentVault.collection, 'd', <String, Object?>{...b.get(DocumentVault.collection, 'd')!.fields, 'expiry': '2027-05-01'});
      a.mergeAll(b.allRecords);
      expect(FamilyDocument.fromRecord(a.get(DocumentVault.collection, 'd')!).expiry, DateTime(2027, 5, 1));
    });
  });

  testWidgets('add a document with expiry, send as PDF, send masked, share, save, undo', (WidgetTester tester) async {
    final FamilySpace s = newSpace();
    await tester.runAsync(() => s.create(familyName: 'Shahs', memberName: 'Asha'));
    final DocumentVault v =
        DocumentVault(cipher: VaultCipher(MemoryKeyStore()), blobs: MemoryDocumentBlobStore(), space: s);
    final List<String> sent = <String>[];
    String? shared;
    String? saved;
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: DocumentVaultScreen(
        vault: v,
        pickFile: () async => photo,
        pickDate: (BuildContext c, DateTime i) async => DateTime(2099, 6, 30),
        send: (String name, Uint8List bytes) async => sent.add(name),
        share: (String t) async => shared = t,
        save: (String t) async {
          saved = t;
          return '/docs/Family documents.txt';
        },
        masker: FakeMasker(),
        toPdf: fakePdf,
      ),
    ));

    await tester.tap(find.text('Add document'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Name (optional)'), 'Asha passport');
    await tester.tap(find.text('Expiry date (optional)'));
    await tester.pumpAndSettle();
    expect(find.text('Expires 30 Jun 2099'), findsOneWidget);
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    expect(v.documents.single.title, 'Asha passport');
    expect(find.text('Asha passport'), findsOneWidget);
    expect(find.textContaining('Expires 30 Jun 2099'), findsOneWidget);
    expect(tester.getSize(find.byTooltip('Actions for Asha passport')).height, greaterThanOrEqualTo(44));

    Future<void> menu(String item) async {
      await tester.tap(find.byTooltip('Actions for Asha passport'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(item));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();
    }

    await menu('Send as PDF');
    await menu('Send masked');
    expect(sent, <String>['Asha passport.pdf', 'Asha passport (masked).pdf']);

    await tester.tap(find.byKey(const Key('result-share')));
    await tester.pumpAndSettle();
    expect(shared, contains('Asha passport (Aadhaar)'));
    await tester.tap(find.byKey(const Key('result-save')));
    await tester.pumpAndSettle();
    expect(saved, isNotNull);
    expect(find.text('Saved to /docs/Family documents.txt'), findsOneWidget);

    await tester.tap(find.byKey(const Key('result-undo')));
    await tester.pumpAndSettle();
    expect(v.documents, isEmpty);
    await tester.pump(const Duration(seconds: 5));
  });
}

class _ListSink implements DocumentReminderSink {
  _ListSink(this.out);
  final List<String> out;

  @override
  Future<void> remind(DocumentReminder reminder) async => out.add(reminder.text);
}
