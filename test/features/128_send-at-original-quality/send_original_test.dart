import 'dart:io';

import 'package:family_utility_app/app/theme.dart';
import 'package:family_utility_app/engines/share/original_quality.dart';
import 'package:family_utility_app/engines/share/share_engine.dart';
import 'package:family_utility_app/tools/send_original/send_original_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeSheet implements ShareSheet {
  final List<ShareRequest> requests = <ShareRequest>[];
  bool complete = true;

  @override
  Future<ShareOutcome> share(ShareRequest request) async {
    requests.add(request);
    return complete
        ? const ShareOutcome(completed: true, target: 'com.whatsapp/com.whatsapp.ContactPicker')
        : const ShareOutcome.dismissed();
  }
}

class FakeChooser implements MediaChooser {
  FakeChooser(this.media);
  final List<PickedMedia> media;

  @override
  Future<List<PickedMedia>> pick() async => media;
}

/// In memory, so the widget test does no real IO.
class FakeSaver implements OriginalSaver {
  final List<String> saved = <String>[];

  @override
  Future<String> save(PickedMedia media) async {
    final String p = '/saved/${media.name}';
    saved.add(p);
    return p;
  }

  @override
  Future<void> remove(String savedPath) async => saved.remove(savedPath);
}

const PickedMedia photo = PickedMedia(path: '/cache/abc123.jpg', name: 'IMG_2041.jpg', size: 4 * 1024 * 1024);
const PickedMedia video = PickedMedia(path: '/cache/v.mp4', name: 'Birthday.mp4', size: 300 * 1024 * 1024);
const PickedMedia huge = PickedMedia(path: '/cache/h.mov', name: 'Wedding.mov', size: 3 * 1024 * 1024 * 1024);

void main() {
  group('OriginalQuality', () {
    test('photos and videos are wrapped as documents with their own name', () {
      expect(photo.isPhoto, isTrue);
      expect(video.isVideo, isTrue);
      final ShareFile p = OriginalQuality.asDocument(photo);
      expect(p.mimeType, 'application/octet-stream');
      expect(p.mimeType.startsWith('image/'), isFalse, reason: 'image/* gets recompressed');
      expect(p.name, 'IMG_2041.jpg');
      expect(p.path, '/cache/abc123.jpg');
      expect(OriginalQuality.asDocument(video).mimeType, 'application/octet-stream');
    });

    test('files over the 2 GB WhatsApp limit are flagged', () {
      expect(OriginalQuality.tooBig(<PickedMedia>[photo, video, huge]), <PickedMedia>[huge]);
      expect(OriginalQuality.formatSize(4 * 1024 * 1024), '4.0 MB');
      expect(OriginalQuality.formatSize(3 * 1024 * 1024 * 1024), '3.0 GB');
      expect(OriginalQuality.formatSize(2048), '2 KB');
      expect(OriginalQuality.formatSize(10), '10 B');
    });

    test('send hands every file to the sheet as a document, skipping oversize ones', () async {
      final FakeSheet sheet = FakeSheet();
      final ShareEngine engine = ShareEngine(sheet, MemoryShareTargetStore());
      final SendOriginalResult r = await SendOriginal(engine).send(<PickedMedia>[photo, video, huge]);
      expect(r.sent, isTrue);
      expect(r.count, 2);
      expect(r.skipped, <PickedMedia>[huge]);
      final ShareRequest req = sheet.requests.single;
      expect(req.files.map((ShareFile f) => f.name), <String>['IMG_2041.jpg', 'Birthday.mp4']);
      expect(req.mimeType, 'application/octet-stream');
      expect(engine.recents.value.first.label, 'WhatsApp');
    });

    test('a dismissed sheet reports not sent; only oversize files never open the sheet', () async {
      final FakeSheet sheet = FakeSheet()..complete = false;
      final SendOriginal s = SendOriginal(ShareEngine(sheet, MemoryShareTargetStore()));
      final SendOriginalResult r = await s.send(<PickedMedia>[photo]);
      expect(r.sent, isFalse);
      expect(r.count, 0);
      final SendOriginalResult none = await s.send(<PickedMedia>[huge]);
      expect(none.sent, isFalse);
      expect(sheet.requests, hasLength(1));
    });

    test('Save copies the exact bytes without overwriting; remove deletes the copy', () async {
      final Directory tmp = await Directory.systemTemp.createTemp('orig');
      final File src = File('${tmp.path}/abc.jpg')..writeAsBytesSync(<int>[1, 2, 3, 4, 5]);
      final DirectoryOriginalSaver saver = DirectoryOriginalSaver(() async => Directory('${tmp.path}/originals'));
      final PickedMedia m = PickedMedia(path: src.path, name: 'IMG_1.jpg', size: 5);
      final String a = await saver.save(m);
      final String b = await saver.save(m);
      expect(a.endsWith('/originals/IMG_1.jpg'), isTrue);
      expect(b.endsWith('/originals/IMG_1 (2).jpg'), isTrue);
      expect(File(a).readAsBytesSync(), <int>[1, 2, 3, 4, 5]);
      await saver.remove(b);
      expect(File(b).existsSync(), isFalse);
      expect(File(a).existsSync(), isTrue);
      await tmp.delete(recursive: true);
    });

    test('the engine has no network code', () {
      final String src = File('lib/engines/share/original_quality.dart').readAsStringSync();
      expect(src.contains('HttpClient'), isFalse);
      expect(src.contains('package:http'), isFalse);
      expect(src.contains('Socket'), isFalse);
    });
  });

  group('screen', () {
    testWidgets('pick, Send original, then Save and Undo', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final FakeSheet sheet = FakeSheet();
      final FakeSaver saver = FakeSaver();
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: SendOriginalScreen(
          chooser: FakeChooser(<PickedMedia>[photo, video]),
          saver: saver,
          share: ShareEngine(sheet, MemoryShareTargetStore()),
        ),
      ));

      expect(find.text('Send at original quality'), findsOneWidget);
      final FilledButton send = tester.widget<FilledButton>(find.byKey(const Key('original-send')));
      expect(send.onPressed, isNull, reason: 'nothing picked yet');

      await tester.tap(find.byKey(const Key('original-pick')));
      await tester.pumpAndSettle();
      expect(find.text('IMG_2041.jpg'), findsOneWidget);
      expect(find.text('Birthday.mp4'), findsOneWidget);
      expect(find.textContaining('goes as a document'), findsNWidgets(2));

      await tester.tap(find.byKey(const Key('original-send')));
      await tester.pumpAndSettle();
      expect(sheet.requests, hasLength(1));
      expect(sheet.requests.single.files.every((ShareFile f) => f.mimeType == 'application/octet-stream'), isTrue);
      expect(find.text('Sent 2 as documents, full quality.'), findsOneWidget);

      for (final String key in <String>['original-pick', 'original-send', 'result-share', 'result-save', 'result-undo']) {
        expect(tester.getSize(find.byKey(Key(key))).height, greaterThanOrEqualTo(44), reason: key);
      }
      expect(find.byWidgetPredicate((Widget w) => w is Icon && w.semanticLabel == 'Photo'), findsOneWidget);
      expect(find.byWidgetPredicate((Widget w) => w is Icon && w.semanticLabel == 'Video'), findsOneWidget);

      await tester.tap(find.byKey(const Key('result-save')));
      await tester.pumpAndSettle();
      expect(saver.saved, <String>['/saved/IMG_2041.jpg', '/saved/Birthday.mp4']);

      await tester.tap(find.byKey(const Key('result-undo')));
      await tester.pumpAndSettle();
      expect(saver.saved, isEmpty);

      await tester.tap(find.byKey(const Key('result-undo')));
      await tester.pumpAndSettle();
      expect(find.text('IMG_2041.jpg'), findsNothing);
      expect(find.byKey(const Key('original-status')), findsNothing);
    });
  });
}
