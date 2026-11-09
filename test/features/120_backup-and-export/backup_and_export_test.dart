import 'dart:convert';
import 'dart:typed_data';

import 'package:family_utility_app/engines/family/family_identity.dart';
import 'package:family_utility_app/engines/family/family_space.dart';
import 'package:family_utility_app/engines/family/family_store.dart';
import 'package:family_utility_app/engines/family/family_sync.dart';
import 'package:family_utility_app/engines/platform/backup_export.dart';
import 'package:family_utility_app/tools/backup/backup_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

FamilySpace newSpace() => FamilySpace(
      identityStore: MemoryFamilyIdentityStore(),
      storage: MemoryFamilyStoreStorage(),
      transportsFor: (FamilyIdentity _) => <FamilySyncTransport>[],
    );

BackupExport engineFor(
  FamilySpace space,
  MemorySettingsSource prefs, {
  MemoryBackupFolder? folder,
  MemoryBackupSettingsStore? store,
  DateTime Function()? now,
}) =>
    BackupExport(
      parts: <BackupPart>[
        FamilyIdentityBackupPart(space),
        FamilyBackupPart(space.store),
        SettingsBackupPart(prefs),
      ],
      sections: () => <ExportSection>[
        FamilyCollectionSection(space.store, 'contacts', 'Family contacts'),
        FamilyCollectionSection(space.store, 'shopping', 'Shopping list'),
      ],
      folder: folder ?? MemoryBackupFolder(),
      settingsStore: store ?? MemoryBackupSettingsStore(),
      now: now,
      iterations: 1000,
    );

void main() {
  group('engine', () {
    test('full backup restores family and settings on a new phone', () async {
      final FamilySpace old = newSpace();
      await old.create(familyName: 'Shahs', memberName: 'Asha');
      old.store.put('contacts', 'c1', <String, Object?>{'name': 'Ramesh', 'phone': '9820012345'});
      old.store.put('shopping', 's1', <String, Object?>{'text': 'Milk', 'done': false});
      old.store.put('shopping', 's2', <String, Object?>{'text': 'Bread'});
      old.store.delete('shopping', 's2');
      final MemorySettingsSource oldPrefs = MemorySettingsSource(<String, Object?>{
        'accessibility': '{"scale":1.3}',
        'on_device_mode': true,
        'backup_export_settings': '{"f":"daily"}',
      });
      final BackupExport a = engineFor(old, oldPrefs);
      final Uint8List file = await a.createBackup('family-secret');
      expect(BackupExport.isBackup(file), isTrue);
      expect(utf8.decode(file, allowMalformed: true), isNot(contains('Ramesh')));

      await expectLater(BackupExport.read(file, 'wrong-one'), throwsA(isA<BackupWrongPassword>()));
      final Uint8List tampered = Uint8List.fromList(file)..[60] ^= 1;
      await expectLater(BackupExport.read(tampered, 'family-secret'), throwsA(isA<BackupError>()));
      await expectLater(BackupExport.read(Uint8List(80), 'family-secret'), throwsA(isA<BackupError>()));

      final FamilySpace fresh = newSpace();
      final MemorySettingsSource newPrefs = MemorySettingsSource(<String, Object?>{'on_device_mode': false});
      final BackupExport b = engineFor(fresh, newPrefs);
      final int n = await b.restore(file, 'family-secret');
      expect(n, greaterThan(3));
      expect(fresh.identity!.familyId, old.identity!.familyId);
      expect(fresh.identity!.deviceId, isNot(old.identity!.deviceId));
      expect(fresh.store.get('contacts', 'c1')!.fields['name'], 'Ramesh');
      expect(fresh.store.get('shopping', 's1')!.fields['text'], 'Milk');
      expect(fresh.store.get('shopping', 's2'), isNull);
      expect(newPrefs.values['accessibility'], '{"scale":1.3}');
      expect(newPrefs.values['on_device_mode'], true);
      expect(newPrefs.values.containsKey('backup_export_settings'), isFalse);

      // Undo puts the settings back and removes what the restore added.
      expect(await b.undo(), isTrue);
      expect(newPrefs.values['on_device_mode'], false);
      expect(newPrefs.values.containsKey('accessibility'), isFalse);
      expect(fresh.store.get('contacts', 'c1'), isNull);
    });

    test('restore keeps newer edits made on this phone', () async {
      final FamilySpace s = newSpace();
      await s.create(familyName: 'F', memberName: 'A');
      s.store.put('contacts', 'c1', <String, Object?>{'name': 'Old'});
      final BackupExport e = engineFor(s, MemorySettingsSource());
      final Uint8List file = await e.createBackup('123456');
      s.store.put('contacts', 'c1', <String, Object?>{'name': 'New'});
      await e.restore(file, '123456');
      expect(s.store.get('contacts', 'c1')!.fields['name'], 'New');
    });

    test('CSV and JSON export per section, with undo', () async {
      final FamilySpace s = newSpace();
      await s.create(familyName: 'F', memberName: 'A');
      s.store.put('contacts', 'c1', <String, Object?>{'name': 'Dr "Mehta", MD', 'tags': <String>['Doctor', 'Family']});
      s.store.put('contacts', 'c2', <String, Object?>{'name': '=SUM(A1)', 'phone': '+91 98200'});
      final MemoryBackupFolder folder = MemoryBackupFolder();
      final BackupExport e = engineFor(s, MemorySettingsSource(), folder: folder);
      final ExportSection contacts = e.sections().first;
      final String csvPath = await e.exportTo('/x', contacts, csv: true);
      expect(csvPath, '/x/Family contacts.csv');
      final String csv = utf8.decode(folder.files[csvPath]!);
      expect(
        csv,
        'id,name,tags,phone\r\n'
        'c1,"Dr ""Mehta"", MD",Doctor; Family,\r\n'
        "c2,'=SUM(A1),,'+91 98200\r\n",
      );
      final String jsonPath = await e.exportTo('/x', contacts, csv: false);
      final Object? rows = jsonDecode(utf8.decode(folder.files[jsonPath]!));
      expect((rows! as List).length, 2);
      expect(await e.undo(), isTrue);
      expect(folder.files.containsKey(jsonPath), isFalse);
      expect(folder.files.containsKey(csvPath), isTrue);
      expect(BackupExport.toCsv(<Map<String, Object?>>[]), '\r\n');
    });

    test('schedule runs when due, keeps the last five, needs a password', () async {
      final FamilySpace s = newSpace();
      await s.create(familyName: 'F', memberName: 'A');
      DateTime now = DateTime(2026, 1, 1, 9);
      final MemoryBackupFolder folder = MemoryBackupFolder();
      final MemoryBackupSettingsStore store = MemoryBackupSettingsStore();
      final BackupExport e = engineFor(s, MemorySettingsSource(), folder: folder, store: store, now: () => now);
      await e.load();
      expect(await e.runIfDue(), isNull);

      await e.setSchedule(BackupFrequency.daily, folderPath: '/drive/backups', password: 'abcdef');
      expect(store.pw, 'abcdef');
      expect(e.settings.isDue(now), isTrue);
      for (int day = 0; day < 7; day++) {
        now = DateTime(2026, 1, 1 + day, 9);
        expect(await e.runIfDue(), isNotNull);
        expect(await e.runIfDue(), isNull, reason: 'not due again the same day');
      }
      final List<String> files = await folder.list('/drive/backups');
      expect(files.length, 5);
      expect(files.every((String f) => f.endsWith('.fuabak')), isTrue);
      expect(files, contains('/drive/backups/family-utility-backup-2026-01-07-0900.fuabak'));
      expect(files, isNot(contains('/drive/backups/family-utility-backup-2026-01-01-0900.fuabak')));

      // Settings survive a restart.
      final BackupSettings round = BackupSettings.fromJson(jsonDecode(jsonEncode(e.settings.toJson())));
      expect(round.frequency, BackupFrequency.daily);
      expect(round.folder, '/drive/backups');
      expect(round.lastAt, now);

      const BackupSettings weekly = BackupSettings(frequency: BackupFrequency.weekly, folder: '/f');
      expect(weekly.copyWith(lastAt: DateTime(2026, 1, 1)).isDue(DateTime(2026, 1, 7)), isFalse);
      expect(weekly.copyWith(lastAt: DateTime(2026, 1, 1)).isDue(DateTime(2026, 1, 8)), isTrue);

      await e.setSchedule(BackupFrequency.off);
      expect(store.pw, isNull);
      store.settings = const BackupSettings(frequency: BackupFrequency.daily, folder: '/f');
      await e.load();
      expect(await e.runIfDue(), isNull);
      expect(e.lastError, isNotNull);
      expect(BackupExport.passwordProblem('abc', 'abc'), isNotNull);
      expect(BackupExport.passwordProblem('abcdef', 'abcdeg'), isNotNull);
      expect(BackupExport.passwordProblem('abcdef', 'abcdef'), isNull);
    });
  });

  group('screen', () {
    testWidgets('back up now writes a locked file; export buttons are labelled', (WidgetTester tester) async {
      final SemanticsHandle sem = tester.ensureSemantics();
      tester.view.physicalSize = const Size(800, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final FamilySpace s = newSpace();
      await s.create(familyName: 'F', memberName: 'A');
      s.store.put('contacts', 'c1', <String, Object?>{'name': 'Ramesh'});
      final MemoryBackupFolder folder = MemoryBackupFolder();
      final BackupExport e = engineFor(s, MemorySettingsSource(), folder: folder);
      final List<String> shared = <String>[];
      await tester.pumpWidget(MaterialApp(
        home: BackupScreen(
          engine: e,
          defaultFolder: () async => '/docs/Backups',
          shareFile: (String p) async => shared.add(p),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Backup and export'), findsOneWidget);
      expect(find.text('Share'), findsOneWidget);
      expect(find.text('Undo'), findsOneWidget);

      await tester.tap(find.text('Back up now'));
      await tester.pump();
      expect(find.text('Use at least 6 characters'), findsOneWidget);
      expect(folder.files, isEmpty);

      await tester.enterText(find.byKey(const Key('backup-password')), 'family-secret');
      await tester.enterText(find.byKey(const Key('backup-confirm')), 'family-secret');
      await tester.runAsync(() async {
        await tester.tap(find.text('Back up now'));
        for (int i = 0; i < 100 && folder.files.isEmpty; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      });
      await tester.pump();
      expect(folder.files.length, 1);
      final String path = folder.files.keys.single;
      expect(path, startsWith('/docs/Backups/family-utility-backup-'));
      expect(BackupExport.isBackup(folder.files[path]!), isTrue);
      expect(find.textContaining('Backup saved to'), findsOneWidget);

      await tester.tap(find.text('Share'));
      await tester.pump();
      expect(shared, <String>[path]);

      final Finder csv = find.bySemanticsLabel('Export Family contacts as CSV');
      expect(csv, findsOneWidget);
      await tester.ensureVisible(find.text('Family contacts'));
      final Size size = tester.getSize(find.ancestor(of: find.text('CSV').first, matching: find.byType(TextButton)));
      expect(size.height, greaterThanOrEqualTo(44));
      expect(find.text('1 rows'), findsOneWidget);
      expect(find.text('Every week'), findsOneWidget);
      await tester.pumpAndSettle(const Duration(seconds: 1));
      sem.dispose();
    });
  });
}
