import 'dart:io';
import 'dart:typed_data';

import 'package:family_utility_app/app/theme.dart';
import 'package:family_utility_app/app/widgets/save_anywhere_sheet.dart';
import 'package:family_utility_app/engines/share/save_anywhere.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakePlatform implements SavePlatform {
  final Map<String, Uint8List> files = <String, Uint8List>{};
  String? nextPick = '/sdcard/Family';
  final List<String?> pickStarts = <String?>[];

  @override
  Future<String> filesFolder() async => '/app/Saved';

  @override
  Future<String> downloadsFolder() async => '/sdcard/Download';

  @override
  Future<String?> pickFolder({String? initialFolder}) async {
    pickStarts.add(initialFolder);
    return nextPick;
  }

  @override
  Future<bool> exists(String path) async => files.containsKey(path);

  @override
  Future<void> write(String path, Uint8List bytes) async => files[path] = bytes;
}

final Uint8List bytes = Uint8List.fromList(<int>[1, 2, 3]);

void main() {
  group('SaveAnywhere engine', () {
    test('new tools default to Files; save remembers per tool and persists', () async {
      final FakePlatform p = FakePlatform();
      final MemorySaveChoiceStore store = MemorySaveChoiceStore();
      final SaveAnywhere s = SaveAnywhere(platform: p, store: store);
      expect(s.lastFor('crop').destination, SaveDestination.files);

      final String path = await s.save(
        toolId: 'crop',
        destination: SaveDestination.downloads,
        folder: (await s.folderFor('crop', SaveDestination.downloads))!,
        name: 'beach-crop.jpg',
        bytes: bytes,
      );
      expect(path, '/sdcard/Download/beach-crop.jpg');
      expect(p.files[path], bytes);
      expect(s.lastFor('crop').destination, SaveDestination.downloads);
      expect(s.lastFor('compress').destination, SaveDestination.files, reason: 'per tool');

      final SaveAnywhere again = SaveAnywhere(platform: p, store: store);
      await again.load();
      expect(again.lastFor('crop').destination, SaveDestination.downloads);
    });

    test('never overwrites: picks a free name; cleans unsafe names', () async {
      final FakePlatform p = FakePlatform();
      final SaveAnywhere s = SaveAnywhere(platform: p, store: MemorySaveChoiceStore());
      p.files['/app/Saved/a.pdf'] = bytes;
      p.files['/app/Saved/a (2).pdf'] = bytes;
      expect(await s.finalPath('/app/Saved/', 'a.pdf'), '/app/Saved/a (3).pdf');
      expect(SaveAnywhere.safeName('../../etc/pass?wd'), 'pass_wd');
      expect(SaveAnywhere.safeName('  '), 'file');
      expect(SaveAnywhere.shortPath('/a/b/c/d/e.jpg'), '…/c/d/e.jpg');
    });

    test('custom folder is remembered and reopens the picker there', () async {
      final FakePlatform p = FakePlatform();
      final SaveAnywhere s = SaveAnywhere(platform: p, store: MemorySaveChoiceStore());
      expect(await s.folderFor('crop', SaveDestination.custom), isNull);
      final String folder = (await s.pickFolder('crop'))!;
      await s.save(toolId: 'crop', destination: SaveDestination.custom, folder: folder, name: 'x.png', bytes: bytes);
      expect(await s.folderFor('crop', SaveDestination.custom), '/sdcard/Family');
      await s.pickFolder('crop');
      expect(p.pickStarts, <String?>[null, '/sdcard/Family']);
    });

    test('a broken store is ignored', () async {
      final MemorySaveChoiceStore store = MemorySaveChoiceStore()..value = '{not json';
      final SaveAnywhere s = SaveAnywhere(platform: FakePlatform(), store: store);
      await s.load();
      expect(s.lastFor('crop').destination, SaveDestination.files);
    });

    test('no network code', () {
      for (final String f in <String>['lib/engines/share/save_anywhere.dart', 'lib/platform/save_platform.dart']) {
        final String src = File(f).readAsStringSync();
        expect(src.contains('HttpClient'), isFalse, reason: f);
        expect(src.contains('Socket'), isFalse, reason: f);
      }
    });
  });

  group('sheet', () {
    Future<String?> open(WidgetTester tester, SaveAnywhere s) async {
      String? result;
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: Builder(
          builder: (BuildContext context) => Scaffold(
            body: Center(
              child: TextButton(
                key: const Key('open'),
                onPressed: () async {
                  result = await showSaveAnywhereSheet(context,
                      saver: s, toolId: 'crop', fileName: 'beach-crop.jpg', bytes: bytes);
                },
                child: const Text('Save'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.byKey(const Key('open')));
      await tester.pumpAndSettle();
      return result;
    }

    testWidgets('shows the final path, remembers the last choice, 44 px targets', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final FakePlatform p = FakePlatform();
      final SaveAnywhere s = SaveAnywhere(platform: p, store: MemorySaveChoiceStore());

      await open(tester, s);
      expect(find.text('Will save as /app/Saved/beach-crop.jpg'), findsOneWidget);
      expect(find.text('Files · last used'), findsOneWidget);

      await tester.tap(find.byKey(const Key('save-to-downloads')));
      await tester.pumpAndSettle();
      expect(find.text('Will save as /sdcard/Download/beach-crop.jpg'), findsOneWidget);

      for (final String key in <String>['save-to-files', 'save-to-downloads', 'save-to-custom', 'save-cancel', 'save-confirm']) {
        expect(tester.getSize(find.byKey(Key(key))).height, greaterThanOrEqualTo(44), reason: key);
      }

      await tester.tap(find.byKey(const Key('save-confirm')));
      await tester.pumpAndSettle();
      expect(p.files.keys, <String>['/sdcard/Download/beach-crop.jpg']);
      expect(find.byKey(const Key('save-confirm')), findsNothing, reason: 'sheet closed');

      // Next time it opens on Downloads, with a free name.
      await tester.tap(find.byKey(const Key('open')));
      await tester.pumpAndSettle();
      expect(find.text('Downloads · last used'), findsOneWidget);
      expect(find.text('Will save as /sdcard/Download/beach-crop (2).jpg'), findsOneWidget);

      // Custom: picks a folder and shows the path there.
      await tester.tap(find.byKey(const Key('save-to-custom')));
      await tester.pumpAndSettle();
      expect(find.text('Will save as /sdcard/Family/beach-crop.jpg'), findsOneWidget);
      await tester.tap(find.byKey(const Key('save-confirm')));
      await tester.pumpAndSettle();
      expect(p.files.containsKey('/sdcard/Family/beach-crop.jpg'), isTrue);
      expect(s.lastFor('crop'), const SaveChoice(SaveDestination.custom, folder: '/sdcard/Family'));
    });

    testWidgets('cancel writes nothing', (WidgetTester tester) async {
      final FakePlatform p = FakePlatform();
      final SaveAnywhere s = SaveAnywhere(platform: p, store: MemorySaveChoiceStore());
      await open(tester, s);
      await tester.tap(find.byKey(const Key('save-cancel')));
      await tester.pumpAndSettle();
      expect(p.files, isEmpty);
    });
  });
}
