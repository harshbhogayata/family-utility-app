import 'dart:io';
import 'dart:typed_data';

import 'package:family_utility_app/app/bootstrap.dart';
import 'package:family_utility_app/app/tool_registry.dart';
import 'package:family_utility_app/engines/platform/background_jobs.dart';
import 'package:family_utility_app/engines/platform/batch_everywhere.dart';
import 'package:family_utility_app/engines/share/share_engine.dart';
import 'package:family_utility_app/tools/batch/batch_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

Uint8List png(int r) {
  final img.Image im = img.Image(width: 8, height: 6);
  img.fill(im, color: img.ColorRgb8(r, 30, 60));
  return img.encodePng(im);
}

final Uint8List broken = Uint8List.fromList(<int>[0x89, 0x50, 0x4e, 0x47, 1, 2, 3]);

class FakeIo implements BatchIo {
  FakeIo(this.inputs);

  final List<BatchInput> inputs;
  final Map<String, BatchOutput> written = <String, BatchOutput>{};
  final List<List<String>> asked = <List<String>>[];

  @override
  Future<List<BatchInput>> pick(List<String> extensions) async {
    asked.add(extensions);
    return inputs;
  }

  @override
  Future<String> write(BatchOutput output) async {
    final String p = '/batch/${output.name}';
    written[p] = output;
    return p;
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

/// Feature number of each tool folder that has a picker, for the audit.
const Map<String, int> folderFeature = <String, int>{
  'archives': 29,
  'split_pdf': 3,
  'protect_pdf': 11,
  'batch': 107,
  'batch_convert': 31,
  'compress_images': 34,
  'compress_pdf': 32,
  'compress_video': 36,
  'convert_anything': 30,
  'copy_result': 66,
  'crop': 41,
  'heic': 25,
  'history': 118,
  'id_card': 44,
  'images_to_pdf': 21,
  'merge_pdf': 2,
  'pdf_to_images': 22,
  'pdf_viewer': 1,
  'phone_to_laptop': 62,
  'qr_generator': 52,
  'raster': 27,
  'send_original': 128,
  'shrink_to_send': 38,
  'sign_pdf': 10,
  'zip': 37,
};

/// The argument text of every `FilePicker.platform.pickFiles(...)` call.
List<String> pickCalls(String source) {
  final List<String> out = <String>[];
  const String marker = 'FilePicker.platform.pickFiles(';
  int at = source.indexOf(marker);
  while (at >= 0) {
    int depth = 1;
    int i = at + marker.length;
    while (i < source.length && depth > 0) {
      if (source[i] == '(') {
        depth++;
      } else if (source[i] == ')') {
        depth--;
      }
      i++;
    }
    out.add(source.substring(at + marker.length, i - 1));
    at = source.indexOf(marker, i);
  }
  return out;
}

void main() {
  group('policy', () {
    test('every tool in the real grid says how it takes many files', () {
      ToolRegistry.clear();
      bootstrap();
      expect(BatchPolicy.violations(ToolRegistry.all), isEmpty);
      expect(ToolRegistry.byId(BatchPolicy.batchToolId), isNotNull);
      ToolRegistry.clear();
    });

    test('every Batch action belongs to a tool routed to the Batch screen', () {
      for (final BatchAction a in BatchActions.all) {
        final BatchSupport? s = BatchPolicy.byFeature[a.feature];
        expect(s?.kind, BatchKind.viaBatch, reason: a.id);
        expect(s?.via, BatchPolicy.batchToolId, reason: a.id);
      }
      final Set<int> routed = <int>{
        for (final MapEntry<int, BatchSupport> e in BatchPolicy.byFeature.entries)
          if (e.value.via == BatchPolicy.batchToolId) e.key,
      };
      expect(routed, BatchActions.all.map((BatchAction a) => a.feature).toSet());
    });

    test('violations catch a missing entry, a reasonless single and a bad via', () {
      ToolEntry t(String id, int? n) => ToolEntry(
            id: id,
            name: id,
            section: ToolSection.platform,
            icon: Icons.build_outlined,
            featureNumber: n,
            builder: (BuildContext _) => const SizedBox(),
          );
      final List<String> v = BatchPolicy.violations(<ToolEntry>[t('merge', 2), t('mystery', 999), t('nonum', null)]);
      expect(v, hasLength(2));
      expect(v.any((String s) => s.startsWith('mystery')), isTrue);
      // compress-pdf points at the Batch screen, which is not in this grid.
      expect(BatchPolicy.violations(<ToolEntry>[t('compress-pdf', 32)]).single, contains('missing tool batch'));
    });

    test('every single-file picker in lib/tools is a declared exception', () {
      final Directory tools = Directory('lib/tools');
      for (final FileSystemEntity f in tools.listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) {
          continue;
        }
        final String src = f.readAsStringSync();
        final List<String> calls = pickCalls(src);
        if (calls.isEmpty) {
          continue;
        }
        final List<String> parts = f.path.replaceAll('\\', '/').split('/');
        final String folder = parts[parts.lastIndexOf('tools') + 1];
        final int? feature = folderFeature[folder];
        expect(feature, isNotNull, reason: '${f.path} has a picker but no feature in the audit map');
        final BatchSupport? s = BatchPolicy.byFeature[feature];
        expect(s, isNotNull, reason: 'feature $feature has no batch entry');
        final bool anyMulti = calls.any((String c) => c.contains('allowMultiple: true'));
        final bool anySingle = calls.any((String c) => !c.contains('allowMultiple'));
        if (s!.kind == BatchKind.multiPicker) {
          expect(anyMulti, isTrue, reason: '${f.path}: multi-select tool with no multi-select picker');
        } else if (anySingle) {
          expect(s.kind, isIn(<BatchKind>[BatchKind.single, BatchKind.viaBatch]), reason: f.path);
        }
      }
    });
  });

  group('runner', () {
    test('keeps going past a broken file, groups results and shares once', () async {
      final BackgroundJobs jobs = BackgroundJobs(NoopJobHost());
      final List<String> written = <String>[];
      final BatchReport r = await BatchRunner(jobs: jobs).run(
        'Resize',
        <BatchInput>[
          BatchInput('/p/a.png', png(10)),
          BatchInput('/p/bad.png', broken),
          BatchInput('/p/b.png', png(200)),
        ],
        BatchActions.resizeHalf.step,
        (BatchOutput o) async {
          written.add(o.name);
          return '/out/${o.name}';
        },
      );
      expect(r.items, hasLength(3));
      expect(r.done.map((BatchItem i) => i.input), <String>['a.png', 'b.png']);
      expect(r.failed.single.input, 'bad.png');
      expect(r.summary, '2 of 3 done, 1 failed');
      expect(written, <String>['a-resized.png', 'b-resized.png']);
      final img.Image out = img.decodePng(r.done.first.outputs.first.bytes)!;
      expect((out.width, out.height), (4, 3));
      expect(r.groups.map((BatchGroup g) => g.title), <String>['PNG', 'Failed']);
      final ShareRequest share = r.shareRequest();
      expect(share.files.map((ShareFile f) => f.path), <String>['/out/a-resized.png', '/out/b-resized.png']);
      expect(jobs.jobs.single.state, JobState.done);
    });

    test('groups by output type', () {
      final BatchReport r = BatchReport(<BatchItem>[
        BatchItem.done('x.pdf', <BatchOutput>[BatchOutput('x.pdf', Uint8List(1))], const <String>['/x.pdf']),
        BatchItem.done('y.jpeg', <BatchOutput>[BatchOutput('y.jpeg', Uint8List(1))], const <String>['/y.jpeg']),
        BatchItem.done('z.jpg', <BatchOutput>[BatchOutput('z.jpg', Uint8List(1))], const <String>['/z.jpg']),
      ]);
      expect(r.groups.map((BatchGroup g) => '${g.title}:${g.items.length}'), <String>['JPG:2', 'PDF:1']);
      expect(r.summary, '3 of 3 done');
    });

    test('cancelling stops before the next file and keeps what is done', () async {
      final BackgroundJobs jobs = BackgroundJobs(NoopJobHost());
      int calls = 0;
      final BatchReport r = await BatchRunner(jobs: jobs).run(
        'Strip',
        <BatchInput>[BatchInput('/a.png', png(1)), BatchInput('/b.png', png(2)), BatchInput('/c.png', png(3))],
        (BatchInput i) async {
          calls++;
          jobs.cancel(jobs.jobs.first.id);
          return BatchActions.stripExif.step(i);
        },
        (BatchOutput o) async => '/out/${o.name}',
      );
      expect(calls, 1);
      expect(r.cancelled, isTrue);
      expect(r.done.single.outputs.single.name, 'a-clean.png');
      expect(r.summary, '1 of 1 done, stopped');
    });

    test('actions only accept their own file types', () {
      expect(BatchActions.compressPdf.accepts('/x/A.PDF'), isTrue);
      expect(BatchActions.compressPdf.accepts('/x/a.png'), isFalse);
      expect(BatchActions.stripExif.accepts('/x/a.jpeg'), isTrue);
      expect(BatchActions.stripExif.accepts('/x/noext'), isFalse);
    });
  });

  testWidgets('Batch screen: many files in, grouped results, one share, undo', (WidgetTester tester) async {
    final FakeIo io = FakeIo(<BatchInput>[
      BatchInput('/p/one.png', png(10)),
      BatchInput('/p/two.png', png(90)),
      BatchInput('/p/three.png', png(160)),
      BatchInput('/p/notes.txt', Uint8List(3)),
    ]);
    final FakeSheet sheet = FakeSheet();
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: BatchScreen(
        io: io,
        runner: BatchRunner(jobs: BackgroundJobs(NoopJobHost())),
        share: ShareEngine(sheet, MemoryShareTargetStore()),
      ),
    ));

    await tester.tap(find.byKey(const Key('batch-action-resize')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('batch-pick')));
    await tester.pump();
    expect(io.asked.single, <String>['jpg', 'jpeg', 'png']);
    expect(find.text('3 files picked · change'), findsOneWidget);
    expect(find.text('notes.txt'), findsNothing);

    final Size pick = tester.getSize(find.byKey(const Key('batch-pick')));
    expect(pick.height, greaterThanOrEqualTo(44));
    expect(find.bySemanticsLabel(RegExp('Resize photos to 50%')), findsOneWidget);

    await tester.tap(find.byKey(const Key('batch-run')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();

    expect(find.text('3 of 3 done'), findsOneWidget);
    expect(find.byKey(const Key('batch-group-PNG')), findsOneWidget);
    expect(io.written.keys, hasLength(3));

    await tester.tap(find.byKey(const Key('result-share')));
    await tester.pumpAndSettle();
    expect(sheet.requests, hasLength(1));
    expect(sheet.requests.single.files, hasLength(3));

    await tester.tap(find.byKey(const Key('result-undo')));
    await tester.pumpAndSettle();
    expect(io.written, isEmpty);
    expect(find.byKey(const Key('batch-run')), findsOneWidget);
  });
}
