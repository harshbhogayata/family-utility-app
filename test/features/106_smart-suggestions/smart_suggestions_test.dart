import 'package:family_utility_app/app/theme.dart';
import 'package:family_utility_app/app/tool_registry.dart';
import 'package:family_utility_app/engines/convert/file_kind.dart';
import 'package:family_utility_app/engines/family/member_profiles.dart';
import 'package:family_utility_app/engines/platform/smart_suggestions.dart';
import 'package:family_utility_app/tools/smart_suggestions/suggestions_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void registerTools(List<String> ids) {
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
  group('rules', () {
    test('kind from the file name', () {
      expect(SmartSuggestions.kindForName('/a/Bill.PDF'), SuggestKind.pdf);
      expect(SmartSuggestions.kindForName('/a/IMG_1.jpeg'), SuggestKind.image);
      expect(SmartSuggestions.kindForName('IMG_2.HEIC'), SuggestKind.heic);
      expect(SmartSuggestions.kindForName('/a/sheet.xlsx'), SuggestKind.sheet);
      expect(SmartSuggestions.kindForName('/a/clip.mp4'), SuggestKind.video);
      expect(SmartSuggestions.kindForName('/a/.hidden'), SuggestKind.other);
      expect(SmartSuggestions.kindForName('/a/noext'), SuggestKind.other);
      expect(SmartSuggestions.kindForName('/a.b/noext'), SuggestKind.other);
    });

    test('kind from the detected bytes covers every FileKind', () {
      for (final FileKind k in FileKind.values) {
        expect(SmartSuggestions.rules[SmartSuggestions.kindForFileKind(k)], isNotEmpty, reason: k.name);
      }
      expect(SmartSuggestions.kindForFileKind(FileKind.png), SuggestKind.image);
      expect(SmartSuggestions.kindForFileKind(FileKind.pdf), SuggestKind.pdf);
    });

    test('a PDF suggests merge, sign, compress; a photo suggests resize, remove metadata', () {
      expect(SmartSuggestions.forPath('/x/a.pdf', limit: 3), <String>['merge-pdf', 'sign-pdf', 'compress-pdf']);
      expect(SmartSuggestions.forPath('/x/a.jpg', limit: 2), <String>['resize', 'exif']);
    });

    test('history moves used tools to the front, newest first', () {
      expect(
        SmartSuggestions.suggest(
          SuggestKind.pdf,
          history: <String>['resize', 'split-pdf', 'compress-pdf', 'split-pdf'],
          limit: 4,
        ),
        <String>['split-pdf', 'compress-pdf', 'merge-pdf', 'sign-pdf'],
      );
    });

    test('only available tools are offered', () {
      expect(
        SmartSuggestions.suggest(SuggestKind.pdf, available: <String>{'sign-pdf', 'split-pdf'}),
        <String>['sign-pdf', 'split-pdf'],
      );
      expect(SmartSuggestions.suggest(SuggestKind.pdf, available: <String>{}), isEmpty);
    });

    test('every rule names a real tool id once', () {
      for (final MapEntry<SuggestKind, List<String>> e in SmartSuggestions.rules.entries) {
        expect(e.value.toSet().length, e.value.length, reason: e.key.name);
      }
      expect(SmartSuggestions.rules.keys.toSet(), SuggestKind.values.toSet());
    });
  });

  group('suggestions bar', () {
    setUp(() {
      ToolRegistry.clear();
      MemberProfiles.install(MemberProfiles(MemoryProfileStore()));
    });

    testWidgets('shows labelled chips, follows history and opens the tool', (WidgetTester tester) async {
      registerTools(<String>['merge-pdf', 'sign-pdf', 'compress-pdf', 'split-pdf', 'resize']);
      await MemberProfiles.instance.recordRecent('split-pdf');
      final SemanticsHandle semantics = tester.ensureSemantics();

      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: const Scaffold(body: SuggestionsBar(path: '/files/bill.pdf', limit: 3)),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Suggested for this PDF'), findsOneWidget);
      List<String> shown() => tester
          .widgetList<ActionChip>(find.byType(ActionChip))
          .map((ActionChip c) => (c.key! as ValueKey<String>).value)
          .toList();
      expect(shown(), <String>['suggest-split-pdf', 'suggest-merge-pdf', 'suggest-sign-pdf']);
      for (final String id in <String>['split-pdf', 'merge-pdf', 'sign-pdf']) {
        expect(tester.getSize(find.byKey(ValueKey<String>('suggest-$id'))).height, greaterThanOrEqualTo(44));
      }
      expect(find.bySemanticsLabel(RegExp('Tool sign-pdf')), findsWidgets);

      await tester.tap(find.byKey(const ValueKey<String>('suggest-sign-pdf')));
      await tester.pumpAndSettle();
      expect(find.text('Open sign-pdf'), findsOneWidget);
      expect(MemberProfiles.instance.active.recents.first, 'sign-pdf');

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(shown().first, 'suggest-sign-pdf');
      semantics.dispose();
    });

    testWidgets('nothing to suggest shows nothing', (WidgetTester tester) async {
      registerTools(<String>['resize']);
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: const Scaffold(body: SuggestionsBar(path: '/files/bill.pdf')),
      ));
      expect(find.byKey(const Key('smart-suggestions')), findsNothing);
    });
  });
}
