import 'dart:io';

import 'package:family_utility_app/app/theme.dart';
import 'package:family_utility_app/engines/platform/action_history.dart';
import 'package:family_utility_app/engines/platform/file_manager.dart';
import 'package:family_utility_app/engines/share/share_engine.dart';
import 'package:family_utility_app/platform/files_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// An in-memory disk: paths to contents, plus folders.
class MemorySource implements FileSource {
  MemorySource({Map<String, String>? files, Set<String>? dirs})
      : files = files ?? <String, String>{},
        dirs = dirs ?? <String>{};

  final Map<String, String> files;
  final Set<String> dirs;
  final Map<String, DateTime> times = <String, DateTime>{};

  @override
  Future<List<FileNode>> list(String dir) async {
    if (!dirs.contains(dir)) {
      throw FileSystemException('no such folder', dir);
    }
    final List<FileNode> out = <FileNode>[];
    for (final String d in dirs) {
      if (parentOf(d) == dir && d != dir) {
        out.add(FileNode(path: d, isDir: true, modified: DateTime(2026)));
      }
    }
    files.forEach((String p, String c) {
      if (parentOf(p) == dir) {
        out.add(FileNode(path: p, isDir: false, size: c.length, modified: times[p] ?? DateTime(2026)));
      }
    });
    return out;
  }

  @override
  Future<FileNode?> stat(String path) async {
    if (dirs.contains(path)) {
      return FileNode(path: path, isDir: true, modified: DateTime(2026));
    }
    final String? c = files[path];
    return c == null ? null : FileNode(path: path, isDir: false, size: c.length, modified: DateTime(2026));
  }

  @override
  Future<String?> readText(String path, int maxBytes) async => files[path];

  @override
  Future<void> rename(String from, String to) async {
    final String? c = files.remove(from);
    if (c == null) {
      throw FileSystemException('missing', from);
    }
    files[to] = c;
  }

  @override
  Future<void> createFolder(String path) async => dirs.add(path);
}

/// Trash on top of the same in-memory disk.
class MemoryBin implements TrashBin {
  MemoryBin(this.src);
  final MemorySource src;

  @override
  Future<String> moveIn(String path, String id) async {
    final String t = '/trash/$id-${baseName(path)}';
    await src.rename(path, t);
    return t;
  }

  @override
  Future<String> moveOut(String trashedPath, String originalPath) async {
    final String back = freePath(originalPath, src.files.containsKey);
    await src.rename(trashedPath, back);
    return back;
  }

  @override
  Future<void> purge(String trashedPath) async => src.files.remove(trashedPath);
}

class FakeSheet implements ShareSheet {
  final List<ShareRequest> requests = <ShareRequest>[];

  @override
  Future<ShareOutcome> share(ShareRequest request) async {
    requests.add(request);
    return const ShareOutcome(completed: true);
  }
}

MemorySource disk() => MemorySource(
      dirs: <String>{'/app', '/app/Bills', '/app/Photos', '/trash'},
      files: <String, String>{
        '/app/notes.txt': 'Plumber number 98200 call before Diwali',
        '/app/zeta.pdf': '%PDF big file here',
        '/app/alpha.jpg': 'jpg',
        '/app/Bills/power-oct.pdf': '%PDF',
        '/app/Bills/water.csv': 'month,amount\nOct,450',
      },
    );

FileManager manager(MemorySource src, {ActionHistory? h}) => FileManager(
      source: src,
      history: h ?? ActionHistory(store: MemoryHistoryStore(), bin: MemoryBin(src)),
      store: MemoryFileManagerStore(),
      roots: const <FileRoot>[FileRoot('App files', '/app')],
    );

void main() {
  group('FileManager engine', () {
    test('folders first, then the chosen sort', () async {
      final MemorySource src = disk();
      src.times['/app/alpha.jpg'] = DateTime(2026, 1, 3);
      src.times['/app/zeta.pdf'] = DateTime(2026, 1, 1);
      src.times['/app/notes.txt'] = DateTime(2026, 1, 2);
      final FileManager fm = manager(src);
      List<String> names(List<FileNode> l) => l.map((FileNode n) => n.name).toList();
      expect(names(await fm.list('/app')), <String>['Bills', 'Photos', 'alpha.jpg', 'notes.txt', 'zeta.pdf']);
      expect(names(await fm.list('/app', by: SortBy.date)), <String>['Bills', 'Photos', 'zeta.pdf', 'notes.txt', 'alpha.jpg']);
      expect(names(await fm.list('/app', by: SortBy.size, ascending: false)).sublist(2),
          <String>['notes.txt', 'zeta.pdf', 'alpha.jpg']);
      expect(names(await fm.list('/app', by: SortBy.type)).sublist(2), <String>['alpha.jpg', 'zeta.pdf', 'notes.txt']);
    });

    test('rename checks the name, refuses clashes and keeps recents in step', () async {
      final MemorySource src = disk();
      final FileManager fm = manager(src);
      await fm.touch('/app/notes.txt');
      await fm.toggleFavourite('/app/notes.txt');
      final String to = await fm.rename('/app/notes.txt', 'plumber.txt');
      expect(to, '/app/plumber.txt');
      expect(src.files.containsKey('/app/plumber.txt'), isTrue);
      expect(fm.recents, <String>['/app/plumber.txt']);
      expect(fm.favourites, <String>{'/app/plumber.txt'});
      expect(fm.history.entries.first.toolName, 'Rename');
      expect(fm.history.entries.first.inputs, <String>['/app/notes.txt']);
      expect(() => fm.rename('/app/plumber.txt', 'zeta.pdf'), throwsStateError);
      expect(() => fm.rename('/app/plumber.txt', '../x'), throwsArgumentError);
      expect(() => fm.rename('/app/plumber.txt', '  '), throwsArgumentError);
      expect(validateName('ok name.pdf'), isNull);
    });

    test('move never overwrites; delete goes to the trash and restores', () async {
      final MemorySource src = disk()..files['/app/Bills/alpha.jpg'] = 'other';
      final FileManager fm = manager(src);
      final String moved = await fm.moveTo('/app/alpha.jpg', '/app/Bills');
      expect(moved, '/app/Bills/alpha (2).jpg');
      expect(src.files['/app/Bills/alpha.jpg'], 'other');
      expect(await fm.moveTo(moved, '/app/Bills'), moved, reason: 'same folder is a no-op');

      final TrashItem t = (await fm.delete('/app/zeta.pdf'))!;
      expect(src.files.containsKey('/app/zeta.pdf'), isFalse);
      expect(fm.history.trash.single.originalPath, '/app/zeta.pdf');
      expect(t.daysLeft(fm.history.now), 30);
      expect(await fm.history.restore(t.id), '/app/zeta.pdf');
      expect(src.files['/app/zeta.pdf'], '%PDF big file here');
    });

    test('search finds names and words inside text files, case-insensitive', () async {
      final FileManager fm = manager(disk());
      final List<SearchHit> byName = await fm.search('/app', 'POWER');
      expect(byName.single.node.name, 'power-oct.pdf');
      expect(byName.single.inName, isTrue);
      final List<SearchHit> inside = await fm.search('/app', 'plumber');
      expect(inside.single.node.name, 'notes.txt');
      expect(inside.single.inName, isFalse);
      expect(inside.single.snippet, contains('Plumber number'));
      expect(await fm.search('/app', 'plumber', inContent: false), isEmpty);
      expect((await fm.search('/app', 'oct')).map((SearchHit h) => h.node.name), contains('water.csv'));
      expect(await fm.search('/app', '   '), isEmpty);
      expect(await fm.search('/missing', 'x'), isEmpty, reason: 'unreadable folders are skipped');
    });

    test('recents and favourites persist', () async {
      final MemorySource src = disk();
      final MemoryFileManagerStore store = MemoryFileManagerStore();
      final ActionHistory h = ActionHistory(store: MemoryHistoryStore(), bin: MemoryBin(src));
      final FileManager a = FileManager(source: src, history: h, store: store);
      for (int i = 0; i < 40; i++) {
        await a.touch('/app/f$i');
      }
      await a.touch('/app/f5');
      await a.toggleFavourite('/app/notes.txt');
      final FileManager b = FileManager(source: src, history: h, store: store);
      await b.load();
      expect(b.recents.first, '/app/f5');
      expect(b.recents, hasLength(FileManager.keepRecents));
      expect(b.favourites, <String>{'/app/notes.txt'});
      expect(await b.toggleFavourite('/app/notes.txt'), isFalse);
    });

    test('the real disk source lists, reads and renames', () async {
      final Directory tmp = await Directory.systemTemp.createTemp('fm');
      File('${tmp.path}/a.txt').writeAsStringSync('hello world');
      const LocalFileSource src = LocalFileSource();
      expect((await src.list(tmp.path)).single.name, 'a.txt');
      expect(await src.readText('${tmp.path}/a.txt', 5), 'hello');
      await src.rename('${tmp.path}/a.txt', '${tmp.path}/b.txt');
      expect(await src.stat('${tmp.path}/a.txt'), isNull);
      expect((await src.stat('${tmp.path}/b.txt'))!.size, 11);
      await src.createFolder('${tmp.path}/sub');
      expect((await src.stat('${tmp.path}/sub'))!.isDir, isTrue);
      await tmp.delete(recursive: true);
    });

    test('the engine has no network code', () {
      final String src = File('lib/engines/platform/file_manager.dart').readAsStringSync();
      expect(src.contains('HttpClient'), isFalse);
      expect(src.contains('Socket'), isFalse);
    });
  });

  group('Files tab', () {
    testWidgets('browse, open with, rename, delete and Undo', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final MemorySource src = disk();
      final FileManager fm = manager(src);
      final FakeSheet sheet = FakeSheet();
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: FilesScreen(manager: fm, share: ShareEngine(sheet, MemoryShareTargetStore())),
      ));

      expect(find.text('Recents, favourites and folders.'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey<String>('root-App files')));
      await tester.pumpAndSettle();
      expect(find.text('Bills'), findsOneWidget);
      expect(find.text('notes.txt'), findsOneWidget);
      for (final String key in <String>['files-up', 'files-sort', 'files-new-folder', 'result-share', 'result-save', 'result-undo']) {
        expect(tester.getSize(find.byKey(ValueKey<String>(key))).height, greaterThanOrEqualTo(44), reason: key);
      }
      expect(tester.getSize(find.byKey(const ValueKey<String>('file-notes.txt'))).height, greaterThanOrEqualTo(44));

      // Open with: goes to the share sheet and into recents.
      await tester.tap(find.text('notes.txt'));
      await tester.pumpAndSettle();
      expect(sheet.requests.single.files.single.path, '/app/notes.txt');
      expect(fm.recents, <String>['/app/notes.txt']);

      // Rename through the menu.
      await tester.tap(find.byKey(const ValueKey<String>('file-menu-notes.txt')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rename').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('rename-field')), 'plumber.txt');
      await tester.tap(find.byKey(const Key('rename-ok')));
      await tester.pumpAndSettle();
      expect(find.text('plumber.txt'), findsOneWidget);
      expect(src.files.containsKey('/app/plumber.txt'), isTrue);

      // Undo the rename.
      await tester.tap(find.byKey(const Key('result-undo')));
      await tester.pumpAndSettle();
      expect(src.files.containsKey('/app/notes.txt'), isTrue);
      expect(find.text('notes.txt'), findsOneWidget);

      // Delete to the trash, then Undo restores it.
      await tester.tap(find.byKey(const ValueKey<String>('file-menu-zeta.pdf')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(find.text('zeta.pdf'), findsNothing);
      expect(fm.history.trash, hasLength(1));
      await tester.tap(find.byKey(const Key('result-undo')));
      await tester.pumpAndSettle();
      expect(find.text('zeta.pdf'), findsOneWidget);
      expect(fm.history.trash, isEmpty);

      // Search by content.
      await tester.enterText(find.byKey(const Key('files-search')), 'diwali');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(find.text('1 found'), findsOneWidget);
      expect(find.textContaining('before Diwali'), findsOneWidget);

      // Save marks the last file acted on (the restored one) as a favourite.
      await tester.tap(find.byKey(const Key('result-save')));
      await tester.pumpAndSettle();
      expect(fm.favourites, contains('/app/zeta.pdf'));
    });
  });
}
