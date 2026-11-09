import 'package:family_utility_app/app/strings_scope.dart';
import 'package:family_utility_app/app/widgets/result_bar.dart';
import 'package:family_utility_app/engines/family/member_profiles.dart';
import 'package:family_utility_app/engines/platform/app_strings.dart';
import 'package:family_utility_app/tools/language/language_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('engine', () {
    test('seven languages, every key translated, placeholders kept', () {
      expect(AppStrings.languages, <String>['en', 'hi', 'ta', 'te', 'bn', 'mr', 'gu']);
      for (final String code in AppStrings.languages) {
        expect(ProfileLanguages.isKnown(code), isTrue, reason: code);
        expect(AppStrings.missingKeys(code), isEmpty, reason: code);
        for (final String key in StringKeys.all) {
          final String en = AppStrings.english.get(key);
          final String s = AppStrings.forCode(code).get(key);
          expect(AppStrings.placeholders(s)..sort(), AppStrings.placeholders(en)..sort(), reason: '$code $key');
        }
      }
      // Every profile language has strings.
      for (final String code in ProfileLanguages.names.keys) {
        expect(AppStrings.catalog.containsKey(code), isTrue, reason: code);
      }
    });

    test('lookups, placeholders and English fallback', () {
      final AppStrings ta = AppStrings.forCode('ta');
      expect(ta.share, 'பகிர்');
      expect(AppStrings.forCode('hi').tabFamily, 'परिवार');
      expect(AppStrings.forCode('gu').save, 'સેવ કરો');
      expect(AppStrings.forCode('bn').lastSharedTo('WhatsApp'), contains('WhatsApp'));
      expect(AppStrings.forCode('xx').code, 'en');
      expect(AppStrings.forCode('xx').share, 'Share');
      expect(ta.get('no.such.key'), 'no.such.key');
      expect(ta.languageName, contains('Tamil'));
    });

    test('the choice is per profile and survives a reload', () async {
      final MemoryProfileStore store = MemoryProfileStore();
      final MemberProfiles p = MemberProfiles(store);
      await p.load();
      final MemberProfile asha = (await p.add('Asha', language: 'te'))!;
      await p.setLanguage(p.active.id, 'mr');
      expect(AppStrings.forProfile(p.active).code, 'mr');
      expect(await p.switchTo(asha.id), SwitchOutcome.switched);
      expect(AppStrings.forProfile(p.active).tabTools, 'టూల్స్');

      final MemberProfiles again = MemberProfiles(store);
      await again.load();
      expect(again.active.id, asha.id);
      expect(again.byId('me')!.language, 'mr');
      expect(again.active.language, 'te');
    });
  });

  Widget host(MemberProfiles p, Widget home) => MaterialApp(
        builder: (BuildContext context, Widget? child) => ProfileStringsScope(profiles: p, child: child!),
        home: home,
      );

  testWidgets('picking Tamil changes the app strings; Undo brings English back', (WidgetTester tester) async {
    final SemanticsHandle sem = tester.ensureSemantics();
    final MemberProfiles p = MemberProfiles(MemoryProfileStore());
    String? shared;
    await tester.pumpWidget(host(p, LanguageScreen(profiles: p, share: (String t) async => shared = t)));
    await tester.pumpAndSettle();

    expect(find.text('Share'), findsOneWidget);
    expect(find.byType(RadioListTile<String>), findsNWidgets(7));
    for (final String code in AppStrings.languages) {
      final Size s = tester.getSize(find.byKey(Key('language-$code')));
      expect(s.height, greaterThanOrEqualTo(44), reason: code);
    }
    expect(find.bySemanticsLabel(RegExp('Tamil')), findsWidgets);

    await tester.tap(find.byKey(const Key('language-ta')));
    await tester.pumpAndSettle();
    expect(p.active.language, 'ta');
    expect(find.text('பகிர்'), findsOneWidget);
    expect(find.text('சேமி'), findsOneWidget);
    expect(find.text('செயல்தவிர்'), findsOneWidget);

    await tester.tap(find.byKey(const Key('result-share')));
    await tester.pumpAndSettle();
    expect(shared, contains('Tamil'));

    await tester.tap(find.byKey(const Key('result-undo')));
    await tester.pumpAndSettle();
    expect(p.active.language, 'en');
    expect(find.text('Share'), findsOneWidget);
    sem.dispose();
  });

  testWidgets('tabs follow the active profile', (WidgetTester tester) async {
    final MemberProfiles p = MemberProfiles(MemoryProfileStore());
    await p.setLanguage('me', 'hi');
    await tester.pumpWidget(host(
      p,
      Scaffold(
        body: Builder(builder: (BuildContext context) {
          final AppStrings t = AppStringsScope.of(context);
          return Text('${t.tabTools}|${t.tabFamily}');
        }),
        bottomNavigationBar: ResultBar(onShare: () {}, onSave: () {}, onUndo: () {}),
      ),
    ));
    await tester.pump();
    expect(find.text('टूल्स|परिवार'), findsOneWidget);
    expect(find.text('शेयर करें'), findsOneWidget);

    final MemberProfile ravi = (await p.add('Ravi', language: 'bn'))!;
    await p.switchTo(ravi.id);
    await tester.pump();
    expect(find.text('টুলস|পরিবার'), findsOneWidget);
  });
}
