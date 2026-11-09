import 'dart:io';
import 'dart:typed_data';

import 'package:family_utility_app/app/theme.dart';
import 'package:family_utility_app/app/tool_registry.dart';
import 'package:family_utility_app/engines/family/member_profiles.dart';
import 'package:family_utility_app/engines/platform/paste_anything.dart';
import 'package:family_utility_app/engines/platform/smart_suggestions.dart';
import 'package:family_utility_app/tools/tools_home.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const List<String> ids = <String>[
  'video-link',
  'audio-link',
  'download-queue',
  'qr-generator',
  'web-page-pdf',
  'text-to-pdf',
  'copy-result',
  'encrypt-file',
  'merge-pdf',
  'sign-pdf',
  'compress-pdf',
  'resize',
  'exif',
];

void registerTools() {
  ToolRegistry.clear();
  for (final String id in ids) {
    ToolRegistry.register(ToolEntry(
      id: id,
      name: 'Tool $id',
      section: ToolSection.pdf,
      icon: Icons.build,
      builder: (BuildContext _) => Scaffold(appBar: AppBar(title: Text('Open $id'))),
    ));
  }
}

void main() {
  group('classify', () {
    test('video links, web links, files, pictures and text', () {
      expect(PasteAnything.classify(text: ' https://youtu.be/abc ').kind, PasteKind.videoLink);
      expect(PasteAnything.classify(text: 'https://www.instagram.com/reel/x/').kind, PasteKind.videoLink);
      expect(PasteAnything.classify(text: 'https://cdn.site.in/clip.mp4').kind, PasteKind.videoLink);
      final PastedContent link = PasteAnything.classify(text: 'www.irctc.co.in/ticket');
      expect(link.kind, PasteKind.link);
      expect(link.text, 'https://www.irctc.co.in/ticket');
      final PastedContent file = PasteAnything.classify(text: '/storage/emulated/0/Download/bill.pdf');
      expect(file.kind, PasteKind.file);
      expect(file.fileKind, SuggestKind.pdf);
      expect(PasteAnything.classify(text: 'file:///sdcard/DCIM/a%20b.jpg').path, '/sdcard/DCIM/a b.jpg');
      expect(PasteAnything.classify(text: 'Meet at 5, bring the form').kind, PasteKind.text);
      expect(PasteAnything.classify(text: 'see https://a.com and more').kind, PasteKind.text);
      expect(PasteAnything.classify(text: '/not a path').kind, PasteKind.text);
      expect(PasteAnything.classify(text: '   ').kind, PasteKind.empty);
      expect(PasteAnything.classify().kind, PasteKind.empty);
      expect(
        PasteAnything.classify(text: 'IMG_1.png', image: Uint8List.fromList(<int>[1, 2])).kind,
        PasteKind.image,
      );
    });

    test('labels are plain words', () {
      expect(PasteAnything.label(PasteAnything.classify(text: 'https://youtu.be/x')), 'video link');
      expect(PasteAnything.label(PasteAnything.classify(text: '/a/b.pdf')), 'PDF');
      expect(PasteAnything.label(PasteAnything.classify(image: Uint8List(3))), 'picture');
    });
  });

  group('tools', () {
    test('rule order, recent tools first, only available ones', () {
      final PastedContent link = PasteAnything.classify(text: 'https://example.com/page');
      expect(PasteAnything.tools(link), <String>['web-page-pdf', 'qr-generator', 'download-queue', 'video-link']);
      expect(
        PasteAnything.tools(link, history: <String>['download-queue', 'merge-pdf']).first,
        'download-queue',
      );
      expect(
        PasteAnything.tools(link, available: <String>{'qr-generator', 'video-link'}),
        <String>['qr-generator', 'video-link'],
      );
      expect(PasteAnything.tools(PasteAnything.classify(text: 'https://youtu.be/x')).first, 'video-link');
      expect(PasteAnything.tools(PasteAnything.classify(text: 'hello')).first, 'text-to-pdf');
      expect(PasteAnything.tools(const PastedContent.empty()), isEmpty);
    });

    test('files and pictures use the smart-suggestion rules', () {
      expect(
        PasteAnything.tools(PasteAnything.classify(text: '/x/y.pdf'), limit: 3),
        SmartSuggestions.suggest(SuggestKind.pdf, limit: 3),
      );
      expect(
        PasteAnything.tools(PasteAnything.classify(image: Uint8List(4)), limit: 2),
        SmartSuggestions.suggest(SuggestKind.image, limit: 2),
      );
    });

    test('read takes the clipboard once', () async {
      final MemoryPasteSource src = MemoryPasteSource(value: 'https://youtu.be/q');
      final PastedContent c = await PasteAnything.read(src);
      expect(c.kind, PasteKind.videoLink);
      expect(src.reads, 1);
    });

    test('the engine never reaches the network', () {
      for (final String path in <String>[
        'lib/engines/platform/paste_anything.dart',
        'lib/tools/paste_anything/paste_sheet.dart',
      ]) {
        final String src = File(path).readAsStringSync();
        expect(src, isNot(contains('HttpClient')), reason: path);
        expect(src, isNot(contains('package:http')), reason: path);
      }
    });
  });

  group('home screen', () {
    setUp(() {
      registerTools();
      MemberProfiles.install(MemberProfiles(MemoryProfileStore()));
    });

    tearDown(() {
      PasteAnything.source = const SystemPasteSource();
    });

    Future<void> pumpHome(WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(theme: buildAppTheme(), home: const Scaffold(body: ToolsHome())));
      await tester.pump();
    }

    testWidgets('paste a link: matching tools listed, tap opens one', (WidgetTester tester) async {
      PasteAnything.source = MemoryPasteSource(value: 'https://youtu.be/abc');
      await pumpHome(tester);
      expect(find.bySemanticsLabel(RegExp('Paste a link, text, picture or file')), findsOneWidget);
      await tester.tap(find.byKey(const Key('home-paste')));
      await tester.pumpAndSettle();
      expect(find.text('Pasted: video link'), findsOneWidget);
      expect(find.text('https://youtu.be/abc'), findsOneWidget);
      final List<String> shown = tester
          .widgetList<ListTile>(find.byWidgetPredicate((Widget w) => w is ListTile && w.key is ValueKey<String>))
          .map((ListTile t) => (t.key! as ValueKey<String>).value)
          .toList();
      expect(shown.first, 'paste-tool-video-link');
      expect(shown, contains('paste-tool-qr-generator'));
      await tester.tap(find.byKey(const ValueKey<String>('paste-tool-video-link')));
      await tester.pumpAndSettle();
      expect(find.text('Open video-link'), findsOneWidget);
    });

    testWidgets('an empty clipboard says so', (WidgetTester tester) async {
      PasteAnything.source = MemoryPasteSource();
      await pumpHome(tester);
      await tester.tap(find.byKey(const Key('home-paste')));
      await tester.pumpAndSettle();
      expect(find.text('The clipboard is empty'), findsOneWidget);
    });

    testWidgets('a recent tool moves up; targets are at least 44 px', (WidgetTester tester) async {
      PasteAnything.source = MemoryPasteSource(value: 'Pick up the kids at 4');
      await MemberProfiles.instance.recordRecent('qr-generator');
      await pumpHome(tester);
      expect(tester.getSize(find.byKey(const Key('home-paste'))).height, greaterThanOrEqualTo(44));
      await tester.tap(find.byKey(const Key('home-paste')));
      await tester.pumpAndSettle();
      expect(find.text('Pasted: text'), findsOneWidget);
      final Finder first = find.byKey(const ValueKey<String>('paste-tool-qr-generator'));
      final Finder second = find.byKey(const ValueKey<String>('paste-tool-text-to-pdf'));
      expect(tester.getTopLeft(first).dy, lessThan(tester.getTopLeft(second).dy));
      expect(tester.getSize(first).height, greaterThanOrEqualTo(44));
    });
  });
}
