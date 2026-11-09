import 'dart:convert';
import 'dart:typed_data';

import 'package:family_utility_app/engines/convert/batch_convert.dart';
import 'package:family_utility_app/engines/convert/convert_registry.dart';
import 'package:family_utility_app/engines/convert/file_kind.dart';
import 'package:family_utility_app/engines/platform/background_jobs.dart';
import 'package:family_utility_app/tools/batch_convert/batch_convert_screen.dart';
import 'package:family_utility_app/tools/convert_anything/convert_anything_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

Uint8List smallPng(int r) {
  final img.Image im = img.Image(width: 6, height: 4);
  img.fill(im, color: img.ColorRgb8(r, 30, 60));
  return img.encodePng(im);
}

BatchFile file(String name, Uint8List bytes, {List<String>? reads}) => BatchFile(
      name: name,
      kind: sniffFileKind(bytes),
      read: () async {
        reads?.add(name);
        return bytes;
      },
    );

List<BatchFile> mixed({List<String>? reads}) => <BatchFile>[
      file('a.png', smallPng(10), reads: reads),
      file('list.csv', Uint8List.fromList(utf8.encode('name,age\nAsha,9\nRavi,12\n')), reads: reads),
      file('broken.png', Uint8List.fromList(<int>[0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 1, 2, 3, 4, 5]), reads: reads),
      file('b.png', smallPng(200), reads: reads),
    ];

class FakeSink implements ConvertSink {
  final Map<String, ConvertOutput> files = <String, ConvertOutput>{};

  @override
  Future<String> write(ConvertOutput out) async {
    final String p = '/converted/${out.name}';
    files[p] = out;
    return p;
  }

  @override
  Future<void> remove(String path) async => files.remove(path);
}

class FakeChooser implements BatchFileChooser {
  FakeChooser(this.files);

  final List<BatchFile> files;

  @override
  Future<List<BatchFile>> pick() async => files;
}

void main() {
  group('engine', () {
    test('targets list every format, with how many files can become it', () {
      final BatchConverter b = BatchConverter(registry: ConvertRegistry.builtIn(), jobs: BackgroundJobs(NoopJobHost()))
        ..setFiles(mixed());
      expect(mixed().map((BatchFile f) => f.kind).toList(),
          <FileKind>[FileKind.png, FileKind.csv, FileKind.png, FileKind.png]);
      final List<BatchTarget> t = b.targets();
      expect(t.first.kind, FileKind.zip);
      expect(t.first.count, 4);
      final BatchTarget jpg = t.firstWhere((BatchTarget x) => x.kind == FileKind.jpeg);
      expect(jpg.count, 3);
      expect(jpg.label, 'JPG image');
      expect(t.any((BatchTarget x) => x.kind == FileKind.json), isTrue);
      expect(t.any((BatchTarget x) => x.kind == FileKind.png), isFalse, reason: 'PNGs are already PNG; the CSV cannot be');
    });

    test('one job, progress per file, failures reported and the batch carries on', () async {
      final NoopJobHost host = NoopJobHost();
      final BackgroundJobs jobs = BackgroundJobs(host);
      final List<String> reads = <String>[];
      final BatchConverter b = BatchConverter(registry: ConvertRegistry.builtIn(), jobs: jobs)..setFiles(mixed(reads: reads));
      final List<String> seen = <String>[];
      b.addListener(() => seen.add(b.files.map((BatchFile f) => f.state.name[0]).join()));
      final FakeSink sink = FakeSink();

      final BatchResult r = await b.run(FileKind.jpeg, sink.write);

      expect(r.done, 2);
      expect(r.failed, 2);
      expect(r.summary, '2 converted, 2 failed');
      expect(sink.files.keys.toList(), <String>['/converted/a.jpg', '/converted/b.jpg']);
      expect(sniffFileKind(sink.files['/converted/b.jpg']!.bytes), FileKind.jpeg);
      expect(b.files.map((BatchFile f) => f.state).toList(), <BatchItemState>[
        BatchItemState.done,
        BatchItemState.failed,
        BatchItemState.failed,
        BatchItemState.done,
      ]);
      expect(b.files[1].error, 'CSV files cannot become JPG.');
      expect(b.files[2].statusLine, startsWith('Failed: '));
      expect(b.files[3].statusLine, 'Done · b.jpg');
      // The CSV is never read: no converter for it. Files are read one by one.
      expect(reads, <String>['a.png', 'broken.png', 'b.png']);
      // Per-file progress was published as the batch went.
      expect(seen, contains('dwww'));
      expect(seen, contains('drww'));
      expect(seen, contains('dfrw'));
      // Exactly one background job, finished.
      expect(jobs.jobs.length, 1);
      expect(jobs.jobs.single.title, 'Convert 4 files to JPG');
      expect(jobs.jobs.single.state, JobState.done);
      expect(host.log.first, 'start 1');
      expect(host.log, contains('finished 1 done'));
      expect(b.running, isFalse);
    });

    test('cancel stops before the next file and keeps what was made', () async {
      final BackgroundJobs jobs = BackgroundJobs(NoopJobHost());
      final BatchConverter b = BatchConverter(registry: ConvertRegistry.builtIn(), jobs: jobs)..setFiles(mixed());
      final FakeSink sink = FakeSink();
      bool asked = false;
      b.addListener(() {
        if (!asked && b.files.first.state == BatchItemState.done) {
          asked = true;
          jobs.cancel(jobs.jobs.first.id);
        }
      });
      final BatchResult r = await b.run(FileKind.zip, sink.write);
      expect(r.cancelled, isTrue);
      expect(r.done, 1);
      expect(r.summary, startsWith('Stopped: 1 converted'));
      expect(sink.files.length, 1);
      expect(b.files[1].error, 'cancelled');
    });

    test('an empty batch is refused', () async {
      final BatchConverter b = BatchConverter(registry: ConvertRegistry.builtIn(), jobs: BackgroundJobs(NoopJobHost()));
      await expectLater(b.run(FileKind.jpeg, FakeSink().write), throwsA(isA<ConvertException>()));
    });
  });

  testWidgets('screen: pick, choose a format, convert all, share and undo', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final FakeSink sink = FakeSink();
    final BatchConverter b = BatchConverter(registry: ConvertRegistry.builtIn(), jobs: BackgroundJobs(NoopJobHost()));
    await tester.pumpWidget(MaterialApp(
      home: BatchConvertScreen(chooser: FakeChooser(mixed()), sink: sink, converter: b),
    ));
    expect(find.text('Choose files'), findsOneWidget);

    await tester.tap(find.byKey(const Key('batch-pick')));
    await tester.pumpAndSettle();
    expect(find.text('4 files picked'), findsOneWidget);
    expect(find.text('JPG image (3 of 4)'), findsOneWidget);
    expect(find.text('ZIP archive'), findsOneWidget);

    await tester.tap(find.byKey(const Key('batch-target-jpg')));
    await tester.pumpAndSettle();
    expect(find.text('Convert all to JPG'), findsOneWidget);

    for (final String k in <String>['batch-pick', 'batch-run', 'batch-target-jpg']) {
      final Size s = tester.getSize(find.byKey(Key(k)));
      expect(s.height, greaterThanOrEqualTo(44), reason: k);
    }
    expect(find.byWidgetPredicate((Widget w) => w is Icon && w.semanticLabel == 'waiting'), findsNWidgets(4));

    await tester.ensureVisible(find.byKey(const Key('batch-run')));
    await tester.tap(find.byKey(const Key('batch-run')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();

    expect(find.textContaining('2 converted, 2 failed'), findsOneWidget);
    expect(find.text('PNG · Done · a.jpg'), findsOneWidget);
    expect(find.text('CSV · Failed: CSV files cannot become JPG.'), findsOneWidget);
    expect(sink.files.length, 2);

    await tester.tap(find.byKey(const Key('result-undo')));
    await tester.pumpAndSettle();
    expect(sink.files, isEmpty);
    expect(find.text('Removed 2 converted files'), findsOneWidget);
  });
}
