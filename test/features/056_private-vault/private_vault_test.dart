import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:family_utility_app/app/theme.dart';
import 'package:family_utility_app/engines/security/private_vault.dart';
import 'package:family_utility_app/engines/security/secure_notes.dart';
import 'package:family_utility_app/engines/share/share_engine.dart';
import 'package:family_utility_app/tools/private_vault/private_vault_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget app(Widget home) => MaterialApp(theme: buildAppTheme(), home: home);

Uint8List bytesOf(String s) => Uint8List.fromList(utf8.encode(s));

bool containsBytes(Uint8List hay, List<int> needle) {
  for (int i = 0; i + needle.length <= hay.length; i++) {
    int j = 0;
    while (j < needle.length && hay[i + j] == needle[j]) {
      j++;
    }
    if (j == needle.length) {
      return true;
    }
  }
  return false;
}

class FakeFiles implements VaultFiles {
  List<VaultPick> next = <VaultPick>[];
  bool? lastPhotos;
  final Map<String, Uint8List> written = <String, Uint8List>{};

  @override
  Future<List<VaultPick>> pick({required bool photos}) async {
    lastPhotos = photos;
    return next;
  }

  @override
  Future<String> writeTemp(String name, Uint8List bytes) async {
    written['/tmp/$name'] = bytes;
    return '/tmp/$name';
  }

  @override
  Future<String> save(String name, Uint8List bytes) async {
    written['/exports/$name'] = bytes;
    return '/exports/$name';
  }

  @override
  Future<void> remove(String path) async => written.remove(path);
}

class FakeSheet implements ShareSheet {
  final List<ShareRequest> requests = <ShareRequest>[];

  @override
  Future<ShareOutcome> share(ShareRequest request) async {
    requests.add(request);
    return const ShareOutcome(completed: true);
  }
}

void main() {
  late MemoryKeyStore realKeys;
  late MemoryKeyStore decoyKeys;
  late MemoryVaultBackend backend;
  late MemoryVaultSettingsStore settings;
  late PrivateVault vault;

  PrivateVault fresh() => PrivateVault(
        realKeys: realKeys,
        decoyKeys: decoyKeys,
        backend: backend,
        settingsStore: settings,
      );

  setUp(() {
    realKeys = MemoryKeyStore();
    decoyKeys = MemoryKeyStore();
    backend = MemoryVaultBackend();
    settings = MemoryVaultSettingsStore();
    vault = fresh();
  });

  group('engine', () {
    test('files and names are encrypted at rest with the stored key', () async {
      await vault.load();
      await vault.setPin('2468');
      expect(vault.isOpen, isTrue);
      final Uint8List photo = bytesOf('JPEG secret beach photo');
      final VaultItem item = await vault.add('beach.jpg', photo);
      expect(item.kind, VaultItemKind.photo);
      expect(await realKeys.readKey(), hasLength(32));

      for (final MapEntry<String, Uint8List> e in backend.files.entries) {
        expect(containsBytes(e.value, utf8.encode('secret beach')), isFalse, reason: e.key);
        expect(containsBytes(e.value, utf8.encode('beach.jpg')), isFalse, reason: e.key);
        expect(e.key, isNot(contains('beach')));
      }
      expect(settings.value, isNot(contains('2468')));

      // Same key, new engine: the PIN opens it and the bytes come back.
      final PrivateVault again = fresh();
      await again.load();
      expect(again.isOpen, isFalse);
      expect(await again.open('2468'), isNull);
      expect(again.items.single.name, 'beach.jpg');
      expect(await again.read(again.items.single), photo);

      // Another key: the index cannot be read, nothing crashes.
      final PrivateVault stranger = PrivateVault(
        realKeys: MemoryKeyStore(),
        decoyKeys: MemoryKeyStore(),
        backend: backend,
        settingsStore: settings,
      );
      await stranger.load();
      expect(await stranger.open('2468'), isNull);
      expect(stranger.items, isEmpty);
      expect(stranger.indexError, isNotNull);
    });

    test('a changed file fails to open', () async {
      await vault.load();
      await vault.setPin('2468');
      final VaultItem item = await vault.add('id.pdf', bytesOf('%PDF aadhaar'));
      expect(item.kind, VaultItemKind.file);
      final Uint8List stored = backend.files['real/${item.id}']!;
      stored[14] ^= 0xFF;
      expect(() => vault.read(item), throwsA(anything));
    });

    test('the decoy PIN opens a separate, empty vault with its own key', () async {
      await vault.load();
      await vault.setPin('2468');
      await vault.add('beach.jpg', bytesOf('real photo'));
      await vault.setDecoyPin('1357');
      expect(vault.hasDecoy, isTrue);
      vault.close();

      expect(await vault.open('1357'), isNull);
      expect(vault.isOpen, isTrue);
      expect(vault.openSpace, VaultSpace.decoy);
      expect(vault.items, isEmpty);
      // Nothing about the real vault leaks into the decoy.
      expect(vault.hasDecoy, isFalse);
      expect(() => vault.setDecoyPin('9999'), throwsA(isA<VaultPinError>()));
      expect(() => vault.clearDecoyPin(), throwsA(isA<VaultPinError>()));
      expect(() => vault.setPin('9999'), throwsA(isA<VaultPinError>()));

      // Things added in the decoy stay in the decoy.
      await vault.add('cat.jpg', bytesOf('decoy cat'));
      expect(decoyKeys.readKey(), completion(hasLength(32)));
      expect(await decoyKeys.readKey(), isNot(await realKeys.readKey()));
      vault.close();

      expect(await vault.open('2468'), isNull);
      expect(vault.items.map((VaultItem i) => i.name), <String>['beach.jpg']);
      vault.close();
      expect(await vault.open('1357'), isNull);
      expect(vault.items.map((VaultItem i) => i.name), <String>['cat.jpg']);
    });

    test('decoy and vault PINs must differ; PINs are 4 to 6 digits', () async {
      await vault.load();
      expect(() => vault.setPin('12'), throwsA(isA<VaultPinError>()));
      expect(() => vault.setPin('12ab'), throwsA(isA<VaultPinError>()));
      await vault.setPin('2468');
      expect(() => vault.setDecoyPin('2468'), throwsA(isA<VaultPinError>()));
      await vault.setDecoyPin('1357');
      expect(() => vault.setPin('1357'), throwsA(isA<VaultPinError>()));
      await vault.clearDecoyPin();
      expect(vault.hasDecoy, isFalse);
      vault.close();
      expect(await vault.open('1357'), VaultOpenFailure.wrongPin);
    });

    test('five wrong PINs lock the vault for a while', () async {
      DateTime now = DateTime(2026, 11, 9, 12);
      vault = PrivateVault(
        realKeys: realKeys,
        decoyKeys: decoyKeys,
        backend: backend,
        settingsStore: settings,
        now: () => now,
      );
      await vault.load();
      expect(await vault.open('1111'), VaultOpenFailure.notSetUp);
      await vault.setPin('2468');
      vault.close();
      for (int i = 0; i < PrivateVault.maxAttempts - 1; i++) {
        expect(await vault.open('0000'), VaultOpenFailure.wrongPin);
      }
      expect(await vault.open('0000'), VaultOpenFailure.lockedOut);
      expect(await vault.open('2468'), VaultOpenFailure.lockedOut);
      now = now.add(PrivateVault.lockoutFor + const Duration(seconds: 1));
      expect(await vault.open('2468'), isNull);
    });

    test('undo reverses the last add and the last remove', () async {
      await vault.load();
      await vault.setPin('2468');
      expect(vault.canUndo, isFalse);
      final VaultItem a = await vault.add('a.png', bytesOf('aaa'));
      expect(await vault.undo(), contains('a.png'));
      expect(vault.items, isEmpty);
      expect(backend.files.containsKey('real/${a.id}'), isFalse);

      final VaultItem b = await vault.add('b.png', bytesOf('bbb'));
      await vault.remove(b);
      expect(vault.items, isEmpty);
      expect(await vault.undo(), contains('b.png'));
      expect(await vault.read(vault.items.single), bytesOf('bbb'));
      expect(await vault.undo(), isNull);
    });

    test('vault is out of backups unless chosen; the choice survives a restart', () async {
      await vault.load();
      await vault.setPin('2468');
      expect(vault.includeInBackups, isFalse);
      expect(backend.includedInBackups, isFalse);
      await vault.setIncludeInBackups(true);
      expect(backend.includedInBackups, isTrue);

      final MemoryVaultBackend restarted = MemoryVaultBackend();
      final PrivateVault again = PrivateVault(
        realKeys: realKeys,
        decoyKeys: decoyKeys,
        backend: restarted,
        settingsStore: settings,
      );
      await again.load();
      expect(again.includeInBackups, isTrue);
      expect(restarted.includedInBackups, isTrue);
    });

    test('Android backup rules exclude the vault folder; files are marked .nomedia', () {
      for (final String path in <String>[
        'android/app/src/main/res/xml/backup_rules.xml',
        'android/app/src/main/res/xml/data_extraction_rules.xml',
      ]) {
        final String xml = File(path).readAsStringSync();
        expect(xml, contains('<exclude domain="file" path="vault" />'), reason: path);
      }
      final String manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
      expect(manifest, contains('android:fullBackupContent="@xml/backup_rules"'));
      expect(manifest, contains('android:dataExtractionRules="@xml/data_extraction_rules"'));
      final String platform = File('lib/platform/vault_platform.dart').readAsStringSync();
      expect(platform, contains('.nomedia'));
      expect(File('ios/Runner/AppDelegate.swift').readAsStringSync(), contains('isExcludedFromBackup'));
    });
  });

  group('screen', () {
    late FakeFiles files;
    late FakeSheet sheet;
    late ShareEngine share;

    setUp(() {
      files = FakeFiles();
      sheet = FakeSheet();
      share = ShareEngine(sheet, MemoryShareTargetStore());
    });

    Future<void> pumpVault(WidgetTester tester) async {
      await tester.pumpWidget(app(PrivateVaultScreen(vault: vault, files: files, share: share)));
      await tester.pumpAndSettle();
    }

    testWidgets('set PIN, add photos, share and save a copy, remove and undo', (WidgetTester tester) async {
      await pumpVault(tester);
      expect(find.text('Set a vault PIN'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('vault-pin')), '2468');
      await tester.enterText(find.byKey(const Key('vault-pin-confirm')), '2469');
      await tester.tap(find.byKey(const Key('vault-set-pin')));
      await tester.pumpAndSettle();
      expect(find.text('The two PINs do not match.'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('vault-pin-confirm')), '2468');
      await tester.tap(find.byKey(const Key('vault-set-pin')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('vault-empty')), findsOneWidget);
      expect(find.byKey(const Key('result-share')), findsOneWidget);
      expect(find.byKey(const Key('result-save')), findsOneWidget);
      expect(find.byKey(const Key('result-undo')), findsOneWidget);

      files.next = <VaultPick>[VaultPick('beach.jpg', bytesOf('beach'))];
      await tester.tap(find.byKey(const Key('vault-add-photos')));
      await tester.pumpAndSettle();
      expect(files.lastPhotos, isTrue);
      expect(find.text('beach.jpg'), findsOneWidget);
      expect(find.textContaining('Delete the original from your gallery'), findsOneWidget);

      await tester.tap(find.byKey(const Key('result-share')));
      await tester.pumpAndSettle();
      expect(sheet.requests, hasLength(1));
      expect(files.written['/tmp/beach.jpg'], bytesOf('beach'));

      await tester.tap(find.byKey(const Key('result-save')));
      await tester.pumpAndSettle();
      expect(files.written['/exports/beach.jpg'], bytesOf('beach'));

      await tester.tap(find.byKey(const Key('vault-remove-beach.jpg')));
      await tester.pumpAndSettle();
      expect(find.text('beach.jpg'), findsNothing);
      await tester.tap(find.byKey(const Key('result-undo')));
      await tester.pumpAndSettle();
      expect(find.text('beach.jpg'), findsOneWidget);

      await tester.tap(find.byKey(const Key('vault-lock')));
      await tester.pumpAndSettle();
      expect(find.text('Enter your vault PIN'), findsOneWidget);
      expect(find.text('beach.jpg'), findsNothing);

      // Leaving the screen drops the plain share copy.
      await tester.pumpWidget(app(const SizedBox()));
      expect(files.written.containsKey('/tmp/beach.jpg'), isFalse);
    });

    testWidgets('decoy PIN opens an empty vault whose settings hide the decoy', (WidgetTester tester) async {
      await vault.load();
      await vault.setPin('2468');
      await vault.add('real.jpg', bytesOf('real'));
      await vault.setDecoyPin('1357');
      vault.close();

      await pumpVault(tester);
      await tester.enterText(find.byKey(const Key('vault-pin')), '0000');
      await tester.tap(find.byKey(const Key('vault-open')));
      await tester.pumpAndSettle();
      expect(find.text('Wrong PIN.'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('vault-pin')), '1357');
      await tester.tap(find.byKey(const Key('vault-open')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('vault-empty')), findsOneWidget);
      expect(find.text('real.jpg'), findsNothing);

      await tester.tap(find.byKey(const Key('vault-settings')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('vault-backups')), findsOneWidget);
      expect(find.byKey(const Key('vault-decoy-pin')), findsNothing);
      expect(find.textContaining('decoy'), findsNothing);
    });

    testWidgets('real vault settings: decoy PIN and backups switch', (WidgetTester tester) async {
      await vault.load();
      await vault.setPin('2468');
      await pumpVault(tester);
      await tester.tap(find.byKey(const Key('vault-settings')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('vault-decoy-pin')), '1357');
      await tester.tap(find.byKey(const Key('vault-save-decoy')));
      await tester.pumpAndSettle();
      expect(find.text('Decoy PIN set'), findsOneWidget);
      expect(vault.hasDecoy, isTrue);

      await tester.tap(find.byKey(const Key('vault-backups')));
      await tester.pumpAndSettle();
      expect(vault.includeInBackups, isTrue);
      expect(backend.includedInBackups, isTrue);
    });

    testWidgets('touch targets are at least 44 px and labelled', (WidgetTester tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await vault.load();
      await vault.setPin('2468');
      await vault.add('scan.pdf', bytesOf('%PDF'));
      await pumpVault(tester);
      for (final String k in <String>[
        'vault-add-photos',
        'vault-add-files',
        'vault-remove-scan.pdf',
        'vault-lock',
        'vault-settings',
        'result-share',
        'result-save',
        'result-undo',
      ]) {
        final Size s = tester.getSize(find.byKey(Key(k)));
        expect(s.height, greaterThanOrEqualTo(44), reason: k);
        expect(s.width, greaterThanOrEqualTo(44), reason: k);
      }
      expect(find.byTooltip('Remove scan.pdf from the vault'), findsOneWidget);
      expect(find.byTooltip('Lock the vault'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Add photos')), findsWidgets);
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      handle.dispose();
    });
  });
}
