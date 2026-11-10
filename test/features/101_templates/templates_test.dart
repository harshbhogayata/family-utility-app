import 'dart:typed_data';

import 'package:family_utility_app/engines/pdf/text_to_pdf.dart';
import 'package:family_utility_app/engines/records/autofill_profile.dart';
import 'package:family_utility_app/engines/records/templates.dart';
import 'package:family_utility_app/engines/share/share_engine.dart';
import 'package:family_utility_app/records/templates/templates_screen.dart';
import 'package:family_utility_app/tools/text_to_pdf/text_to_pdf_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeRenderer implements TextPageRenderer {
  final List<String> texts = <String>[];

  @override
  Future<List<GreyPage>> render(String text, TextPdfOptions o) async {
    texts.add(text);
    return <GreyPage>[GreyPage(width: 4, height: 4, pixels: Uint8List(16)..fillRange(0, 16, 255), widthPt: o.page.$1, heightPt: o.page.$2)];
  }
}

class FakeFiles implements TextPdfFiles {
  final Map<String, Uint8List> written = <String, Uint8List>{};

  @override
  Future<String?> paste() async => null;

  @override
  Future<String> write(String name, Uint8List bytes) async {
    written['/converted/$name'] = bytes;
    return '/converted/$name';
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

const AutofillProfile asha = AutofillProfile(
  firstName: 'Asha',
  lastName: 'Mehta',
  phone: '98450 12345',
  email: 'asha@example.com',
  addresses: <SavedAddress>[
    SavedAddress(id: 'h', line1: '12 MG Road', city: 'Pune', state: 'Maharashtra', pincode: '411001'),
  ],
);

void main() {
  group('engine', () {
    test('ten templates, every field in English and Hindi, every placeholder known', () {
      expect(Templates.all.length, 10);
      expect(Templates.all.map((DocTemplate t) => t.id).toSet().length, 10);
      final RegExp devanagari = RegExp('[ऀ-ॿ]');
      for (final DocTemplate t in Templates.all) {
        expect(devanagari.hasMatch(t.titleHi), isTrue, reason: t.id);
        expect(devanagari.hasMatch(t.bodyHi), isTrue, reason: t.id);
        final Set<String> keys = t.fields.map((TemplateField f) => f.key).toSet();
        expect(keys.length, t.fields.length, reason: '${t.id} has a repeated field');
        for (final TemplateField f in t.fields) {
          expect(f.en.trim(), isNotEmpty);
          expect(devanagari.hasMatch(f.hi), isTrue, reason: '${t.id}.${f.key}');
        }
        for (final TemplateLang l in TemplateLang.values) {
          final Set<String> used = RegExp(r'\{([A-Za-z]+)\}').allMatches(t.body(l)).map((Match m) => m.group(1)!).toSet()..remove('blank');
          expect(used, keys, reason: '${t.id} ${l.name}: every field is used and nothing else');
          final String out = Templates.fill(t, l, <String, String>{for (final String k in keys) k: 'x'});
          expect(out.contains('{'), isFalse, reason: '${t.id} ${l.name}');
        }
      }
    });

    test('prefilled from the saved profile; blanks become a line to write on', () {
      final DocTemplate rent = Templates.byId('rent-receipt')!;
      final Map<String, String> v = Templates.prefill(rent, asha, DateTime(2026, 1, 20));
      expect(v['tenant'], 'Asha Mehta');
      expect(v['property'], '12 MG Road\nPune, Maharashtra 411001\nIndia');
      expect(v['date'], '20 Jan 2026');
      expect(v['landlord'], '');
      final String en = Templates.fill(rent, TemplateLang.en, <String, String>{...v, 'amount': '18,000', 'month': 'January 2026'});
      expect(en, contains('Received from Asha Mehta the sum of ₹18,000 towards rent for January 2026'));
      expect(en, contains('Landlord: ${Templates.blank}'));
      final String hi = Templates.fill(rent, TemplateLang.hi, <String, String>{...v, 'amount': '18,000', 'month': 'जनवरी 2026'});
      expect(hi, contains('Asha Mehta से जनवरी 2026 माह के किराये के रूप में ₹18,000 प्राप्त हुए'));

      final DocTemplate noc = Templates.byId('noc')!;
      expect(Templates.prefill(noc, asha, DateTime(2026, 1, 20))['place'], 'Pune');
      expect(Templates.prefill(noc, AutofillProfile.empty, DateTime(2026, 1, 20))['name'], '');
      final DocTemplate resume = Templates.byId('resume')!;
      expect(
        Templates.prefill(resume, AutofillProfile(firstName: 'Ravi', dateOfBirth: DateTime(1990, 3, 5)), DateTime(2026))['dob'],
        '5 Mar 1990',
      );
    });

    test('PDF through Text to PDF, named after the template and person', () async {
      final FakeRenderer r = FakeRenderer();
      final DocTemplate t = Templates.byId('leave')!;
      final TextPdfResult pdf = await Templates.toPdf(t, TemplateLang.hi, <String, String>{'name': 'Asha Mehta', 'reason': 'बुखार'},
          maker: TextPdfMaker(renderer: r));
      expect(pdf.name, 'Leave application (Hindi) - Asha Mehta.pdf');
      expect(pdf.pages, 1);
      expect(String.fromCharCodes(pdf.bytes.sublist(0, 5)), '%PDF-');
      expect(r.texts.single, contains('विषय: अवकाश हेतु प्रार्थना पत्र'));
      expect(r.texts.single, contains('क्योंकि बुखार।'));
    });
  });

  testWidgets('screen: pick, prefilled, Hindi, make PDF, share, undo; 44 px', (WidgetTester tester) async {
    final SemanticsHandle sem = tester.ensureSemantics();
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final FakeFiles files = FakeFiles();
    final FakeRenderer renderer = FakeRenderer();
    final FakeSheet sheet = FakeSheet();
    await tester.pumpWidget(MaterialApp(
      home: TemplatesScreen(
        profile: () => asha,
        files: files,
        maker: TextPdfMaker(renderer: renderer),
        share: ShareEngine(sheet, MemoryShareTargetStore()),
        today: () => DateTime(2026, 1, 20),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(ListTile), findsNWidgets(10));
    expect(tester.getSize(find.byKey(const Key('template-rent-receipt'))).height, greaterThanOrEqualTo(44));
    await tester.tap(find.byKey(const Key('template-rent-receipt')));
    await tester.pumpAndSettle();

    expect(find.text('Filled 3 from your saved profile.'), findsOneWidget);
    expect(tester.widget<TextField>(find.byKey(const Key('template-field-tenant'))).controller!.text, 'Asha Mehta');
    await tester.enterText(find.byKey(const Key('template-field-landlord')), 'R. K. Shah');
    await tester.enterText(find.byKey(const Key('template-field-amount')), '18,000');
    await tester.pumpAndSettle();
    expect(tester.widget<SelectableText>(find.byKey(const Key('template-preview'))).data, contains('Landlord: R. K. Shah'));

    await tester.tap(find.text('हिन्दी'));
    await tester.pumpAndSettle();
    expect(find.text('किराया रसीद'), findsOneWidget);
    expect(find.text('मकान मालिक का नाम'), findsOneWidget);

    expect(tester.getSize(find.byKey(const Key('template-make'))).height, greaterThanOrEqualTo(44));
    await tester.tap(find.byKey(const Key('template-make')));
    await tester.pumpAndSettle();
    expect(files.written.keys.single, '/converted/Rent receipt (Hindi) - Asha Mehta.pdf');
    expect(renderer.texts.single, contains('मकान मालिक: R. K. Shah'));

    await tester.tap(find.byKey(const Key('result-share')));
    await tester.pumpAndSettle();
    expect(sheet.requests.single.files.single.path, '/converted/Rent receipt (Hindi) - Asha Mehta.pdf');

    await tester.tap(find.byKey(const Key('result-undo')));
    await tester.pumpAndSettle();
    expect(files.written, isEmpty);
    expect(find.text('Removed the PDF; your entries are still here'), findsOneWidget);

    await tester.tap(find.byKey(const Key('template-clear')));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byKey(const Key('template-field-tenant'))).controller!.text, '');
    await tester.tap(find.byKey(const Key('result-undo')));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byKey(const Key('template-field-tenant'))).controller!.text, 'Asha Mehta');
    await tester.pumpAndSettle(const Duration(seconds: 5));
    sem.dispose();
  });
}
