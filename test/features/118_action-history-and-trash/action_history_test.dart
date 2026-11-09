import 'dart:io';

import 'package:family_utility_app/app/theme.dart';
import 'package:family_utility_app/engines/platform/action_history.dart';
import 'package:family_utility_app/engines/share/share_engine.dart';
import 'package:family_utility_app/tools/history/history_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A trash bin that only keeps names, so the widget test does no real IO.
class FakeBin implements TrashBin {
  final Set<String> files = <String>{};
  final List<String> purged = <String>[];

  @override
  Future<String> moveIn(String path, String id) async {
    if (!files.remove(path)) {
      throw const FileSystemException('missing');
    }
    final String t = '/trash/$id-${baseName(path)}';
    files.add(t);
    return t;
  }

  @override
  Future<String> moveOut(String trashedPath, String originalPath) async {
    files.remove(trashedPath);
    final String back = freePath(originalPath, files.contains);
    files.add(back);
    return back;
  }

  @override
  Future<void> purge(String trashedPath) async {
    files.remove(trashedPath);
    purged.add(trashedPath);
  }
}

class FakeChooser implements RerunChooser {
  @override
  Future<List<String>> pick() async => <String>['/docs/new-scan.pdf'];
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
  group('ActionHistory engine', () {
    late DateTime clock;
    late FakeBin bin;
    late MemoryHistoryStore store;
    late ActionHistory h;

    setUp(() {
      clock = DateTime(2026, 11, 9, 10, 30);
      bin = FakeBin()..files.addAll(<String>['/docs/a.pdf', '/docs/b.pdf', '/out/merged.pdf']);
      store = MemoryHistoryStore();
      h = ActionHistory(store: store, bin: bin, clock: () => clock);
    });

    test('entries link input and output, newest first, and survive a reload', () async {
      await h.record(toolId: 'merge', toolName: 'Merge PDFs', inputs: <String>['/docs/a.pdf', '/docs/b.pdf'],
          outputs: <String>['/out/merged.pdf']);
      clock = clock.add(const Duration(minutes: 5));
      await h.record(toolId: 'compress', toolName: 'Compress', inputs: <String>['/out/merged.pdf'],
          outputs: <String>['/out/small.pdf']);
      expect(h.entries.map((HistoryEntry e) => e.toolId), <String>['compress', 'merge']);
      expect(h.entries.last.inputs, <String>['/docs/a.pdf', '/docs/b.pdf']);
      expect(h.entries.last.outputs, <String>['/out/merged.pdf']);

      final ActionHistory again = ActionHistory(store: store, bin: bin, clock: () => clock);
      await again.load();
      expect(again.entries, hasLength(2));
      expect(again.entries.last.toolName, 'Merge PDFs');
      expect(again.entries.last.at, DateTime(2026, 11, 9, 10, 30));
      expect(again.asText(), contains('09/11/2026 10:30  Merge PDFs: a.pdf, b.pdf → merged.pdf'));
    });

    test('undo moves outputs to the trash, never the inputs, and only once', () async {
      final HistoryEntry e = await h.record(
          toolId: 'merge', toolName: 'Merge PDFs', inputs: <String>['/docs/a.pdf'], outputs: <String>['/out/merged.pdf']);
      expect(await h.undo(e.id), isTrue);
      expect(h.entries.single.undone, isTrue);
      expect(h.trash.single.originalPath, '/out/merged.pdf');
      expect(bin.files, contains('/docs/a.pdf'));
      expect(bin.files, isNot(contains('/out/merged.pdf')));
      expect(await h.undo(e.id), isFalse);
      expect(h.trash, hasLength(1));
    });

    test('re-run gives the same tool with the new file', () async {
      final HistoryEntry e = await h.record(
          toolId: 'compress', toolName: 'Compress', inputs: <String>['/docs/a.pdf'], outputs: <String>['/o.pdf']);
      final RerunRequest r = h.rerun(e.id, <String>['/docs/b.pdf']);
      expect(r.toolId, 'compress');
      expect(r.inputs, <String>['/docs/b.pdf']);
      expect(r.from, e.id);
      expect(() => h.rerun(e.id, <String>[]), throwsArgumentError);
      expect(() => h.rerun('nope', <String>['/x']), throwsArgumentError);
    });

    test('trash keeps files 30 days, restores to the original place without overwriting', () async {
      final TrashItem t = (await h.delete('/docs/a.pdf'))!;
      expect(t.daysLeft(clock), 30);
      expect(t.expiresAt, clock.add(const Duration(days: 30)));
      bin.files.add('/docs/a.pdf'); // a new file took the name meanwhile
      expect(await h.restore(t.id), '/docs/a (2).pdf');
      expect(h.trash, isEmpty);

      await h.delete('/docs/b.pdf');
      clock = clock.add(const Duration(days: 29, hours: 23));
      expect(await h.purgeExpired(), 0);
      expect(h.trash.single.daysLeft(clock), 1);
      clock = clock.add(const Duration(hours: 1));
      expect(await h.purgeExpired(), 1);
      expect(h.trash, isEmpty);
      expect(bin.purged, hasLength(1));
    });

    test('deleting a missing file is a no-op; a damaged index loads empty', () async {
      expect(await h.delete('/nowhere.pdf'), isNull);
      store.value = '{not json';
      final ActionHistory broken = ActionHistory(store: store, bin: bin, clock: () => clock);
      await broken.load();
      expect(broken.entries, isEmpty);
      expect(broken.trash, isEmpty);
    });

    test('expired trash is purged on load', () async {
      await h.delete('/docs/a.pdf');
      clock = clock.add(const Duration(days: 31));
      final ActionHistory later = ActionHistory(store: store, bin: bin, clock: () => clock);
      await later.load();
      expect(later.trash, isEmpty);
    });

    test('the real trash bin moves files on disk and back', () async {
      final Directory tmp = await Directory.systemTemp.createTemp('trash');
      final File f = File('${tmp.path}/report.pdf')..writeAsStringSync('pdf');
      final DirectoryTrashBin real = DirectoryTrashBin(() async => Directory('${tmp.path}/trash'));
      final ActionHistory disk = ActionHistory(
        store: FileHistoryStore(() async => Directory('${tmp.path}/history')),
        bin: real,
        clock: () => clock,
      );
      final TrashItem t = (await disk.delete(f.path))!;
      expect(f.existsSync(), isFalse);
      expect(File(t.trashedPath).readAsStringSync(), 'pdf');
      expect(File('${tmp.path}/history/history.json').existsSync(), isTrue);
      expect(await disk.restore(t.id), f.path);
      expect(f.readAsStringSync(), 'pdf');
      await tmp.delete(recursive: true);
    });

    test('the engine has no network code', () {
      final String src = File('lib/engines/platform/action_history.dart').readAsStringSync();
      expect(src.contains('HttpClient'), isFalse);
      expect(src.contains('Socket'), isFalse);
    });
  });

  group('screen', () {
    testWidgets('undo, re-run, restore, and Share / Save / Undo', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final DateTime now = DateTime(2026, 11, 9, 10, 30);
      final FakeBin bin = FakeBin()..files.addAll(<String>['/docs/a.pdf', '/out/merged.pdf', '/docs/old.jpg']);
      final ActionHistory h = ActionHistory(store: MemoryHistoryStore(), bin: bin, clock: () => now);
      final HistoryEntry e = await h.record(
          toolId: 'merge', toolName: 'Merge PDFs', inputs: <String>['/docs/a.pdf'], outputs: <String>['/out/merged.pdf']);
      await h.delete('/docs/old.jpg');
      final List<RerunRequest> reruns = <RerunRequest>[];
      final List<String> savedLogs = <String>[];
      final FakeSheet sheet = FakeSheet();

      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: HistoryScreen(
          history: h,
          chooser: FakeChooser(),
          launcher: (BuildContext c, RerunRequest r) async => reruns.add(r),
          saveLog: (String text) async {
            savedLogs.add(text);
            return '/docs/action-history.txt';
          },
          share: ShareEngine(sheet, MemoryShareTargetStore()),
        ),
      ));

      expect(find.text('Merge PDFs'), findsOneWidget);
      expect(find.text('In: a.pdf'), findsOneWidget);
      expect(find.text('Out: merged.pdf'), findsOneWidget);
      for (final String key in <String>['history-undo-${e.id}', 'history-rerun-${e.id}', 'result-share', 'result-save', 'result-undo']) {
        expect(tester.getSize(find.byKey(ValueKey<String>(key))).height, greaterThanOrEqualTo(44), reason: key);
      }

      await tester.tap(find.byKey(ValueKey<String>('history-rerun-${e.id}')));
      await tester.pumpAndSettle();
      expect(reruns.single.toolId, 'merge');
      expect(reruns.single.inputs, <String>['/docs/new-scan.pdf']);

      await tester.tap(find.byKey(ValueKey<String>('history-undo-${e.id}')));
      await tester.pumpAndSettle();
      expect(find.text('Merge PDFs · undone'), findsOneWidget);
      expect(h.trash.map((TrashItem t) => t.name), <String>['merged.pdf', 'old.jpg']);

      await tester.tap(find.byKey(const ValueKey<String>('result-share')));
      await tester.pumpAndSettle();
      expect(sheet.requests.single.text, contains('Merge PDFs (undone)'));
      await tester.tap(find.byKey(const ValueKey<String>('result-save')));
      await tester.pumpAndSettle();
      expect(savedLogs, hasLength(1));

      await tester.tap(find.byKey(const Key('tab-trash')));
      await tester.pumpAndSettle();
      expect(find.text('old.jpg'), findsOneWidget);
      expect(find.textContaining('30 days left'), findsNWidgets(2));
      final String oldId = h.trash.firstWhere((TrashItem t) => t.name == 'old.jpg').id;
      expect(tester.getSize(find.byKey(ValueKey<String>('trash-restore-$oldId'))).height, greaterThanOrEqualTo(44));
      await tester.tap(find.byKey(ValueKey<String>('trash-restore-$oldId')));
      await tester.pumpAndSettle();
      expect(find.text('old.jpg'), findsNothing);
      expect(bin.files, contains('/docs/old.jpg'));

      await tester.tap(find.byKey(const Key('result-undo')));
      await tester.pumpAndSettle();
      expect(find.text('old.jpg'), findsOneWidget, reason: 'Undo puts the restored file back in the trash');
      expect(bin.files, isNot(contains('/docs/old.jpg')));
    });
  });
}
