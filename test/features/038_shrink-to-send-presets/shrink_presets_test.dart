import 'dart:typed_data';

import 'package:family_utility_app/app/theme.dart';
import 'package:family_utility_app/engines/share/shrink_presets.dart';
import 'package:family_utility_app/tools/shrink_to_send/shrink_to_send_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeBackend implements ShrinkBackend {
  final List<String> calls = <String>[];

  @override
  Future<ShrinkOutcome> pdf(Uint8List input, int target) async {
    calls.add('pdf $target');
    return ShrinkOutcome(kind: ShrinkKind.pdf, before: input.length, after: target - 1, reached: true, bytes: Uint8List(10), extension: 'pdf');
  }

  @override
  Future<ShrinkOutcome> image(Uint8List input, int target) async {
    calls.add('image $target');
    return ShrinkOutcome(kind: ShrinkKind.image, before: input.length, after: target - 1, reached: true, bytes: Uint8List(10), extension: 'jpg');
  }

  @override
  Future<ShrinkOutcome> video(String path, int target, String label) async {
    calls.add('video $target');
    return ShrinkOutcome(kind: ShrinkKind.video, before: 80 * 1000 * 1000, after: target - 1, reached: true, outputPath: '/tmp/v.mp4', extension: 'mp4');
  }
}

class FakeFiles implements ShrinkFiles {
  FakeFiles(this.picked, {this.size = 30 * 1000 * 1000});

  final String picked;
  final int size;
  final List<String> written = <String>[];

  @override
  Future<String?> pick() async => picked;

  @override
  Future<Uint8List> read(String path) async => Uint8List(size);

  @override
  Future<String> write(String name, Uint8List bytes) async {
    written.add('/shrunk/$name');
    return '/shrunk/$name';
  }

  @override
  Future<void> remove(String path) async => written.remove(path);
}

Future<Uint8List> Function(String) reader(int size) => (String _) async => Uint8List(size);

void main() {
  group('engine', () {
    test('each file type goes to its own engine', () async {
      final FakeBackend b = FakeBackend();
      final ShrinkPresets p = ShrinkPresets(backend: b, store: MemoryShrinkPresetStore());
      final ShrinkPreset email = p.presets.first;
      expect(email.targetBytes, 25 * 1000 * 1000);
      await p.run('/a/report.PDF', email, reader(30 * 1000 * 1000));
      await p.run('/a/photo.jpeg', email, reader(30 * 1000 * 1000));
      await p.run('/a/trip.mp4', email, reader(0));
      expect(b.calls, <String>['pdf 25000000', 'image 25000000', 'video 25000000']);
      await expectLater(p.run('/a/notes.docx', email, reader(10)), throwsA(isA<ShrinkError>()));
      expect(ShrinkKinds.of('/x/clip.MOV'), ShrinkKind.video);
    });

    test('a file already under the limit is left alone', () async {
      final FakeBackend b = FakeBackend();
      final ShrinkPresets p = ShrinkPresets(backend: b, store: MemoryShrinkPresetStore());
      final ShrinkOutcome o = await p.run('/a/small.pdf', p.presets.first, reader(1000));
      expect(o.unchanged, isTrue);
      expect(b.calls, isEmpty);
    });

    test('the list is editable and saved', () async {
      final MemoryShrinkPresetStore store = MemoryShrinkPresetStore();
      final ShrinkPresets p = ShrinkPresets(backend: FakeBackend(), store: store);
      await p.put(const ShrinkPreset(id: 'passport', label: 'Passport form (50 KB)', targetBytes: 50 * 1024));
      final (ShrinkPreset, int)? gone = await p.remove('whatsapp');
      expect(gone!.$2, 1);
      await p.move(0, 2);

      final ShrinkPresets again = ShrinkPresets(backend: FakeBackend(), store: store);
      await again.load();
      expect(again.presets.map((ShrinkPreset x) => x.id), <String>['whatsapp-doc', 'form', 'email', 'passport']);
      await again.insert(gone.$1, gone.$2);
      expect(again.presets[1].id, 'whatsapp');
      await expectLater(again.put(const ShrinkPreset(id: 'x', label: 'Tiny', targetBytes: 10)), throwsA(isA<ShrinkError>()));
      await again.reset();
      expect(again.presets, defaultShrinkPresets);
    });
  });

  group('screen', () {
    Future<void> open(WidgetTester tester, ShrinkPresets p, FakeFiles files) async {
      tester.view.physicalSize = const Size(1200, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(theme: buildAppTheme(), home: ShrinkToSendScreen(presets: p, files: files)));
    }

    testWidgets('one tap shrinks a PDF for email; Undo removes the file', (WidgetTester tester) async {
      final FakeBackend b = FakeBackend();
      final FakeFiles files = FakeFiles('/docs/report.pdf');
      await open(tester, ShrinkPresets(backend: b, store: MemoryShrinkPresetStore()), files);
      await tester.tap(find.byKey(const Key('shrink-pick')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('preset-email')));
      await tester.pump(const Duration(milliseconds: 10));
      await tester.pump(const Duration(milliseconds: 10));
      expect(b.calls, <String>['pdf 25000000']);
      expect(files.written, <String>['/shrunk/report-small.pdf']);
      expect(find.textContaining('30.0 MB →'), findsOneWidget);
      expect(tester.getSize(find.byKey(const Key('preset-email'))).height, greaterThanOrEqualTo(44));

      await tester.tap(find.byKey(const Key('result-undo')));
      await tester.pump();
      expect(files.written, isEmpty);
    });

    testWidgets('edit: remove a preset and put it back, add a new one', (WidgetTester tester) async {
      final ShrinkPresets p = ShrinkPresets(backend: FakeBackend(), store: MemoryShrinkPresetStore());
      await open(tester, p, FakeFiles('/docs/a.pdf'));
      await tester.tap(find.byKey(const Key('presets-edit')));
      await tester.pump();
      expect(find.byTooltip('Remove WhatsApp (16 MB)'), findsOneWidget);
      await tester.tap(find.byKey(const Key('preset-delete-whatsapp')));
      await tester.pump();
      expect(find.byKey(const Key('preset-whatsapp')), findsNothing);
      await tester.tap(find.byKey(const Key('result-undo')));
      await tester.pump();
      expect(find.byKey(const Key('preset-whatsapp')), findsOneWidget);

      await tester.tap(find.byKey(const Key('preset-add')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('preset-name')), 'Exam form');
      await tester.enterText(find.byKey(const Key('preset-size')), '100');
      await tester.tap(find.byKey(const Key('preset-kb')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('preset-ok')));
      await tester.pumpAndSettle();
      expect(p.presets.last.label, 'Exam form');
      expect(p.presets.last.targetBytes, 100 * 1024);
    });
  });
}
