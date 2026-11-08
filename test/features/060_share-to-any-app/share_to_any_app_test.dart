import 'package:family_utility_app/app/theme.dart';
import 'package:family_utility_app/app/widgets/result_bar.dart';
import 'package:family_utility_app/engines/share/share_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pretends to be the system sheet and records what it was asked to send.
class FakeSheet implements ShareSheet {
  final List<ShareRequest> requests = <ShareRequest>[];
  String? nextTarget;
  bool complete = true;

  @override
  Future<ShareOutcome> share(ShareRequest request) async {
    requests.add(request);
    return complete ? ShareOutcome(completed: true, target: nextTarget) : const ShareOutcome.dismissed();
  }
}

void main() {
  group('MimeTypes', () {
    test('maps the file kinds the app produces to the right MIME type', () {
      expect(MimeTypes.fromPath('/a/b/merged.PDF'), 'application/pdf');
      expect(MimeTypes.fromPath('photo.jpg'), 'image/jpeg');
      expect(MimeTypes.fromPath('photo.jpeg'), 'image/jpeg');
      expect(MimeTypes.fromPath('scan.png'), 'image/png');
      expect(MimeTypes.fromPath('pic.heic'), 'image/heic');
      expect(MimeTypes.fromPath('clip.mp4'), 'video/mp4');
      expect(MimeTypes.fromPath('song.mp3'), 'audio/mpeg');
      expect(
        MimeTypes.fromPath('letter.docx'),
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      );
      expect(MimeTypes.fromPath('sheet.xlsx'),
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
      expect(MimeTypes.fromPath('bundle.zip'), 'application/zip');
      expect(MimeTypes.fromPath('card.vcf'), 'text/vcard');
      expect(MimeTypes.fromPath('notes.txt'), 'text/plain');
    });

    test('unknown or missing extensions fall back to octet-stream', () {
      expect(MimeTypes.fromPath('mystery.xyz'), MimeTypes.fallback);
      expect(MimeTypes.fromPath('noext'), MimeTypes.fallback);
      expect(MimeTypes.fromPath('trailing.'), MimeTypes.fallback);
      expect(MimeTypes.extensionOf(r'C:\Users\me\file.PNG'), 'png');
      expect(MimeTypes.isKnown('a.pdf'), isTrue);
      expect(MimeTypes.isKnown('a.bin'), isFalse);
    });
  });

  group('ShareRequest', () {
    test('advertises one type, a family, or anything', () {
      expect(const ShareRequest(text: 'hi').mimeType, 'text/plain');
      expect(ShareRequest(files: <ShareFile>[ShareFile('a.pdf'), ShareFile('b.pdf')]).mimeType,
          'application/pdf');
      expect(ShareRequest(files: <ShareFile>[ShareFile('a.jpg'), ShareFile('b.png')]).mimeType,
          'image/*');
      expect(ShareRequest(files: <ShareFile>[ShareFile('a.jpg'), ShareFile('b.pdf')]).mimeType,
          '*/*');
    });

    test('a file carries its own name and type', () {
      final ShareFile f = ShareFile('/tmp/out/result.pdf');
      expect(f.name, 'result.pdf');
      expect(f.mimeType, 'application/pdf');
      expect(ShareFile('/x/y.bin', mimeType: 'image/png', name: 'z.png').mimeType, 'image/png');
    });
  });

  group('ShareTarget labels', () {
    test('known apps get their everyday names', () {
      expect(const ShareTarget('com.whatsapp/com.whatsapp.ContactPicker').label, 'WhatsApp');
      expect(const ShareTarget('com.google.android.gm/.ComposeActivity').label, 'Gmail');
      expect(const ShareTarget('com.google.android.apps.docs/x').label, 'Drive');
      expect(const ShareTarget('org.telegram.messenger/x').label, 'Telegram');
      expect(const ShareTarget('net.whatsapp.WhatsApp.ShareExtension').label, 'WhatsApp');
      expect(const ShareTarget('com.apple.UIKit.activity.Mail').label, 'Mail');
    });

    test('unknown apps get a readable fallback', () {
      expect(const ShareTarget('com.example.coolapp/.Share').label, 'Coolapp');
      expect(const ShareTarget('com.someco.android/.Share').label, 'Someco');
      expect(const ShareTarget('weird').label, 'Weird');
    });
  });

  group('ShareEngine', () {
    late FakeSheet sheet;
    late MemoryShareTargetStore store;
    late ShareEngine engine;

    setUp(() {
      sheet = FakeSheet();
      store = MemoryShareTargetStore();
      engine = ShareEngine(sheet, store);
    });

    test('shareFiles sends every file with its MIME type', () async {
      sheet.nextTarget = 'com.whatsapp/x';
      final ShareOutcome out = await engine.shareFiles(<String>['/r/a.pdf', '/r/b.jpg'], text: 'here');
      expect(out.completed, isTrue);
      final ShareRequest sent = sheet.requests.single;
      expect(sent.files.map((ShareFile f) => f.mimeType), <String>['application/pdf', 'image/jpeg']);
      expect(sent.text, 'here');
      expect(sent.mimeType, '*/*');
    });

    test('remembers the last targets, newest first, no duplicates, max five', () async {
      for (final String t in <String>[
        'com.whatsapp/x',
        'com.google.android.gm/x',
        'com.whatsapp/x',
        'org.telegram.messenger/x',
        'com.google.android.apps.docs/x',
        'com.slack/x',
        'com.dropbox.android/x',
      ]) {
        sheet.nextTarget = t;
        await engine.shareText('hi');
      }
      final List<String> labels = engine.recents.value.map((ShareTarget t) => t.label).toList();
      expect(labels, <String>['Dropbox', 'Slack', 'Drive', 'Telegram', 'WhatsApp']);
      expect(labels.length, ShareEngine.keep);
      expect(await store.read(), engine.recents.value.map((ShareTarget t) => t.raw).toList());
    });

    test('a dismissed sheet or an unknown target is not remembered', () async {
      sheet.complete = false;
      sheet.nextTarget = 'com.whatsapp/x';
      await engine.shareText('hi');
      expect(engine.recents.value, isEmpty);
      sheet.complete = true;
      sheet.nextTarget = null;
      await engine.shareText('hi');
      expect(engine.recents.value, isEmpty);
    });

    test('load restores the saved history and forgetAll clears it', () async {
      final ShareEngine e2 = ShareEngine(sheet, MemoryShareTargetStore(<String>['com.whatsapp/x']));
      await e2.load();
      expect(e2.recents.value.single.label, 'WhatsApp');
      await e2.forgetAll();
      expect(e2.recents.value, isEmpty);
    });
  });

  group('ResultBar', () {
    testWidgets('shows where the last shares went and keeps 44 px targets', (WidgetTester tester) async {
      final FakeSheet sheet = FakeSheet();
      final ShareEngine engine = ShareEngine(sheet, MemoryShareTargetStore());
      ShareEngine.install(engine);
      int shares = 0;
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: const SizedBox.expand(),
          bottomNavigationBar: ResultBar(
            onShare: () => shares++,
            onSave: () {},
            onUndo: () {},
          ),
        ),
      ));
      expect(find.byKey(const Key('recent-share-targets')), findsNothing);

      sheet.nextTarget = 'com.whatsapp/x';
      await engine.shareText('a');
      sheet.nextTarget = 'com.google.android.gm/x';
      await engine.shareText('b');
      await tester.pump();
      expect(find.text('Last shared to Gmail, WhatsApp'), findsOneWidget);

      await tester.tap(find.byKey(const Key('result-share')));
      expect(shares, 1);
      for (final String key in <String>['result-share', 'result-save', 'result-undo']) {
        expect(tester.getSize(find.byKey(Key(key))).height, greaterThanOrEqualTo(44));
      }
      expect(find.text('Share'), findsOneWidget);
    });
  });
}
