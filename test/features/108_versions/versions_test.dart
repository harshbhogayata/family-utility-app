import 'dart:io';

import 'package:family_utility_app/engines/platform/action_history.dart';
import 'package:family_utility_app/engines/platform/versions.dart';
import 'package:family_utility_app/engines/share/share_engine.dart';
import 'package:family_utility_app/tools/versions/versions_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A pretend phone disk shared by the trash and the versions folder.
class Disk {
  final Map<String, String> files = <String, String>{};
}

class FakeVersionStore implements VersionStore {
  FakeVersionStore(this.disk);

  final Disk disk;

  @override
  Future<(String, int)> keep(String path, String id) async {
    final String? data = disk.files[path];
    if (data == null) {
      throw FileSystemException('gone', path);
    }
    final String to = '/versions/$id-${baseName(path)}';
    disk.files[to] = data;
    return (to, data.length);
  }

  @override
  Future<void> putBack(String storedPath, String targetPath) async {
    disk.files[targetPath] = disk.files[storedPath]!;
  }

  @override
  Future<void> purge(String storedPath) async => disk.files.remove(storedPath);
}

class FakeBin implements TrashBin {
  FakeBin(this.disk);

  final Disk disk;

  @override
  Future<String> moveIn(String path, String id) async {
    final String? data = disk.files.remove(path);
    if (data == null) {
      throw FileSystemException('gone', path);
    }
    disk.files['/trash/$id'] = data;
    return '/trash/$id';
  }

  @override
  Future<String> moveOut(String trashedPath, String originalPath) async {
    disk.files[originalPath] = disk.files.remove(trashedPath)!;
    return originalPath;
  }

  @override
  Future<void> purge(String trashedPath) async => disk.files.remove(trashedPath);
}

class FakeSheet implements ShareSheet {
  final List<ShareRequest> requests = <ShareRequest>[];

  @override
  Future<ShareOutcome> share(ShareRequest request) async {
    requests.add(request);
    return const ShareOutcome(completed: true);
  }
}

class Rig {
  Rig() {
    versions.attach(history);
  }

  final Disk disk = Disk();
  final MemoryVersionIndexStore index = MemoryVersionIndexStore();
  late final Versions versions = Versions(store: FakeVersionStore(disk), index: index);
  late final ActionHistory history = ActionHistory(store: MemoryHistoryStore(), bin: FakeBin(disk));

  Future<void> compress() async {
    disk.files['/docs/form.pdf'] = 'ORIGINAL-BYTES';
    disk.files['/out/form-compressed.pdf'] = 'small';
    await history.record(
      toolId: 'compress-pdf',
      toolName: 'Compress PDF',
      inputs: <String>['/docs/form.pdf'],
      outputs: <String>['/out/form-compressed.pdf'],
    );
  }
}

void main() {
  group('engine', () {
    test('a recorded run keeps the original in the output\'s version list', () async {
      final Rig r = Rig();
      await r.compress();
      final List<FileVersion> list = r.versions.versionsOf('/out/form-compressed.pdf');
      expect(list, hasLength(1));
      expect(list.single.label, 'Original before Compress PDF');
      expect(list.single.sourceName, 'form.pdf');
      expect(list.single.size, 'ORIGINAL-BYTES'.length);
      expect(r.versions.files, <String>['/out/form-compressed.pdf']);

      // The person edits or deletes the source afterwards; the kept copy stays.
      r.disk.files['/docs/form.pdf'] = 'changed';
      await r.history.delete('/docs/form.pdf');
      expect(r.disk.files[list.single.storedPath], 'ORIGINAL-BYTES');
    });

    test('roll back puts the original back and keeps the result, so it can roll forward', () async {
      final Rig r = Rig();
      await r.compress();
      final FileVersion original = r.versions.versionsOf('/out/form-compressed.pdf').single;
      final FileVersion? before = await r.versions.rollBack(original.id);
      expect(r.disk.files['/out/form-compressed.pdf'], 'ORIGINAL-BYTES');
      expect(before!.label, 'Before roll back');
      expect(r.versions.versionsOf('/out/form-compressed.pdf').map((FileVersion v) => v.label),
          <String>['Before roll back', 'Original before Compress PDF']);

      await r.versions.rollBack(before.id);
      expect(r.disk.files['/out/form-compressed.pdf'], 'small');
      expect(await r.versions.rollBack('nope'), isNull);
    });

    test('originals are kept through soft deletes and go only when the trash is emptied', () async {
      final Rig r = Rig();
      await r.compress();
      final String stored = r.versions.all.single.storedPath;
      await r.history.delete('/out/form-compressed.pdf');
      expect(r.versions.all, hasLength(1));
      expect(r.disk.files.containsKey(stored), isTrue);

      await r.history.emptyTrash();
      expect(r.versions.all, isEmpty);
      expect(r.disk.files.keys.where((String k) => k.startsWith('/versions/')), isEmpty);
    });

    test('a missing input is skipped; a rename keeps nothing', () async {
      final Rig r = Rig();
      r.disk.files['/a/new.txt'] = 'x';
      await r.history.record(
        toolId: 'files',
        toolName: 'Rename',
        inputs: <String>['/a/old.txt'],
        outputs: <String>['/a/new.txt'],
      );
      expect(r.versions.all, isEmpty);
    });

    test('the index survives a restart', () async {
      final Rig r = Rig();
      await r.compress();
      final Versions again = Versions(store: FakeVersionStore(r.disk), index: r.index);
      await again.load();
      expect(again.versionsOf('/out/form-compressed.pdf').single.label, 'Original before Compress PDF');

      r.index.value = '{broken';
      final Versions damaged = Versions(store: FakeVersionStore(r.disk), index: r.index);
      await damaged.load();
      expect(damaged.all, isEmpty);
    });

    test('a failing hook never breaks history', () async {
      final ActionHistory h = ActionHistory(store: MemoryHistoryStore(), bin: FakeBin(Disk()))
        ..onRecorded = (HistoryEntry e) async => throw StateError('boom')
        ..onTrashEmptied = () async => throw StateError('boom');
      final HistoryEntry e =
          await h.record(toolId: 't', toolName: 'T', inputs: <String>['/a'], outputs: <String>['/b']);
      expect(h.entries.single.id, e.id);
      await h.emptyTrash();
    });
  });

  testWidgets('screen: list, roll back with Share / Save / Undo', (WidgetTester tester) async {
    final Rig r = Rig();
    await tester.runAsync(r.compress);
    final FakeSheet sheet = FakeSheet();
    await tester.pumpWidget(MaterialApp(
      home: VersionsScreen(versions: r.versions, share: ShareEngine(sheet, MemoryShareTargetStore())),
    ));

    final Finder file = find.byKey(const Key('versions-file-/out/form-compressed.pdf'));
    expect(file, findsOneWidget);
    expect(tester.getSize(file).height, greaterThanOrEqualTo(44));
    await tester.tap(file);
    await tester.pumpAndSettle();

    final FileVersion original = r.versions.all.single;
    expect(find.text('Original before Compress PDF'), findsOneWidget);
    expect(find.bySemanticsLabel('Roll back form-compressed.pdf to Original before Compress PDF'), findsOneWidget);
    final Finder roll = find.byKey(Key('rollback-${original.id}'));
    expect(tester.getSize(roll).height, greaterThanOrEqualTo(44));

    await tester.tap(roll);
    await tester.pumpAndSettle();
    expect(r.disk.files['/out/form-compressed.pdf'], 'ORIGINAL-BYTES');
    expect(find.byKey(const Key('versions-result')), findsOneWidget);

    await tester.tap(find.byKey(const Key('result-share')));
    await tester.pumpAndSettle();
    expect(sheet.requests.single.files.single.path, '/out/form-compressed.pdf');

    await tester.tap(find.byKey(const Key('result-undo')));
    await tester.pumpAndSettle();
    expect(r.disk.files['/out/form-compressed.pdf'], 'small');
    expect(find.byKey(const Key('versions-result')), findsNothing);
  });

  testWidgets('screen: empty state explains when versions appear', (WidgetTester tester) async {
    final Rig r = Rig();
    await tester.pumpWidget(MaterialApp(home: VersionsScreen(versions: r.versions)));
    expect(find.byKey(const Key('versions-empty')), findsOneWidget);
  });
}
