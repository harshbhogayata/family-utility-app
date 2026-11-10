import 'dart:convert';
import 'dart:typed_data';

import 'package:family_utility_app/engines/records/health_readings.dart';
import 'package:family_utility_app/engines/records/health_summary.dart';
import 'package:family_utility_app/engines/records/medicine_reminders.dart';
import 'package:family_utility_app/engines/records/reports_vault.dart';
import 'package:family_utility_app/records/health_summary/health_summary_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final DateTime now = DateTime(2026, 3, 20, 9);

List<Medicine> meds() => const <Medicine>[
      Medicine(id: 'm1', memberId: 'me', name: 'Metformin 500', times: <int>[480, 1200], note: 'after food'),
      Medicine(id: 'm2', memberId: 'dad', name: 'Amlodipine 5', times: <int>[540]),
    ];

List<HealthReading> readings() => <HealthReading>[
      HealthReading(id: 'r1', kind: ReadingKind.bp, at: DateTime(2026, 3, 18, 8), systolic: 130, diastolic: 85, pulse: 72),
      HealthReading(id: 'r2', kind: ReadingKind.bp, at: DateTime(2026, 3, 19, 8), systolic: 140, diastolic: 90),
      HealthReading(id: 'r3', kind: ReadingKind.sugar, at: DateTime(2026, 3, 19, 7), sugar: 110, context: SugarContext.fasting),
      // Too old for the summary.
      HealthReading(id: 'r0', kind: ReadingKind.bp, at: DateTime(2025, 6, 1), systolic: 180, diastolic: 110),
    ];

List<LabReport> reports() => <LabReport>[
      LabReport(id: 'a', title: 'Old lab', date: DateTime(2025, 9, 1), fileName: 'a.pdf', values: const <String, ReportValue>{
        'HbA1c': ReportValue(7.4, '%'),
        'TSH': ReportValue(2.1, 'mIU/L'),
      }),
      LabReport(id: 'b', title: 'City Lab', date: DateTime(2026, 2, 10), fileName: 'b.pdf', values: const <String, ReportValue>{
        'HbA1c': ReportValue(6.8, '%'),
      }),
    ];

String pdfText(Uint8List b) => latin1.decode(b);

void main() {
  group('engine', () {
    test('composes only the chosen sections from the records', () {
      const HealthProfile p = HealthProfile(name: 'Asha', conditions: <String>['Type 2 diabetes'], allergies: <String>['Penicillin']);
      final List<SummaryBlock> all = HealthSummary.compose(profile: p, medicines: meds(), readings: readings(), reports: reports(), now: now);
      expect(all.map((SummaryBlock b) => b.section).toList(), SummarySection.values);
      expect(all[0].lines, <String>['Type 2 diabetes']);
      expect(all[1].lines, <String>['Penicillin']);
      expect(all[2].lines, <String>['Amlodipine 5 - 1 tablet at 09:00', 'Metformin 500 - 1 tablet at 08:00, 20:00 - after food']);
      final List<String> r = all[3].lines;
      expect(r.first, 'Blood pressure: 2 in the last 90 days, average 135/88 mmHg, systolic 130 to 140');
      expect(r[1], contains('2026-03-19 08:00'));
      expect(r.any((String l) => l.contains('180')), isFalse);
      expect(r.any((String l) => l.startsWith('Blood sugar: 1 in the last 90 days, average 110 mg/dL')), isTrue);
      expect(all[4].lines, <String>['HbA1c: 6.8 % (2026-02-10, City Lab)', 'TSH: 2.1 mIU/L (2025-09-01, Old lab)']);

      final List<SummaryBlock> some = HealthSummary.compose(
        profile: p.copyWith(sections: <SummarySection>{SummarySection.medicines, SummarySection.conditions}),
        medicines: const <Medicine>[],
        readings: const <HealthReading>[],
        reports: const <LabReport>[],
        now: now,
      );
      expect(some.map((SummaryBlock b) => b.section).toList(), <SummarySection>[SummarySection.conditions, SummarySection.medicines]);
      expect(some[1].lines, <String>['None recorded']);
    });

    test('PDF is a valid single page with the chosen text only', () {
      final HealthProfile p = HealthProfile(
        name: 'Asha (Mum)',
        born: DateTime(1960, 4, 1),
        conditions: const <String>['Hypertension'],
        sections: const <SummarySection>{SummarySection.conditions, SummarySection.medicines},
      );
      final List<SummaryBlock> blocks = HealthSummary.compose(profile: p, medicines: meds(), readings: readings(), reports: reports(), now: now);
      final Uint8List b = HealthSummary.pdf(profile: p, blocks: blocks, now: now);
      final String s = pdfText(b);
      expect(s.startsWith('%PDF-1.4'), isTrue);
      expect(s.trimRight().endsWith('%%EOF'), isTrue);
      expect(s, contains('/Count 1'));
      expect(s, contains('Health summary'));
      expect(s, contains(r'Asha \(Mum\), born 1960-04-01 \(age 65\)'));
      expect(s, contains('- Hypertension'));
      expect(s, contains('Metformin 500'));
      expect(s, isNot(contains('HbA1c')));
      expect(s, isNot(contains('Blood pressure')));
      // xref offsets point at objects.
      final int xref = int.parse(RegExp(r'startxref\n(\d+)').firstMatch(s)!.group(1)!);
      expect(s.substring(xref).startsWith('xref'), isTrue);
      expect(HealthSummary.fileName(p, now), 'Health summary - Asha (Mum) 2026-03-20.pdf');
    });

    test('long content flows onto more pages; long lines wrap', () {
      final HealthProfile p = HealthProfile(conditions: List<String>.generate(80, (int i) => 'Condition number $i'));
      final Uint8List b = HealthSummary.pdf(profile: p, blocks: HealthSummary.compose(profile: p, medicines: const <Medicine>[], readings: const <HealthReading>[], reports: const <LabReport>[], now: now), now: now);
      expect(pdfText(b), contains('/Count 2'));
      final List<String> w = HealthSummary.wrap(List<String>.filled(40, 'word').join(' '), 50);
      expect(w.length, greaterThan(1));
      expect(w.every((String l) => l.length <= 54), isTrue);
    });

    test('profile edits persist, dedupe and undo', () async {
      final MemoryHealthProfileStore store = MemoryHealthProfileStore();
      final HealthSummary s = HealthSummary(store: store);
      await s.load();
      expect(s.addCondition('Asthma, asthma; Hypertension'), 2);
      expect(s.addAllergy('Sulfa'), 1);
      s.setSection(SummarySection.reports, false);
      await Future<void>.delayed(Duration.zero);
      expect(store.saved.conditions, <String>['Asthma', 'Hypertension']);
      expect(store.saved.sections.contains(SummarySection.reports), isFalse);
      final HealthProfile back = HealthProfile.fromJson(jsonDecode(jsonEncode(store.saved.toJson())));
      expect(back.allergies, <String>['Sulfa']);
      expect(back.sections, store.saved.sections);
      expect(s.undo(), isTrue);
      expect(s.profile.sections.contains(SummarySection.reports), isTrue);
      expect(s.removeCondition('Asthma'), isTrue);
      expect(s.profile.conditions, <String>['Hypertension']);
      expect(s.undo(), isTrue);
      expect(s.undo(), isTrue);
      expect(s.undo(), isTrue);
      expect(s.undo(), isFalse);
      expect(s.profile.conditions, isEmpty);
    });
  });

  testWidgets('screen: pick sections, add conditions, preview, share and save PDF, undo; 44 px targets', (WidgetTester tester) async {
    final SemanticsHandle sem = tester.ensureSemantics();
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final HealthSummary summary = HealthSummary();
    Uint8List? shared;
    String? sharedName;
    String? savedName;
    await tester.pumpWidget(MaterialApp(
      home: HealthSummaryScreen(
        summary: summary,
        medicines: meds,
        members: () => const <String, String>{'me': 'Me', 'dad': 'Dad'},
        readings: readings,
        reports: reports,
        now: () => now,
        share: (Uint8List pdf, String name) async {
          shared = pdf;
          sharedName = name;
        },
        save: (Uint8List pdf, String name) async {
          savedName = name;
          return '/x/$name';
        },
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('summary-block-medicines')), findsOneWidget);
    expect(find.text('Metformin 500 - 1 tablet at 08:00, 20:00 - after food'), findsOneWidget);
    expect(find.text('HbA1c: 6.8 % (2026-02-10, City Lab)'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('summary-condition')), 'Type 2 diabetes');
    await tester.tap(find.byKey(const Key('summary-condition-add')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('condition-Type 2 diabetes')), findsOneWidget);

    await tester.tap(find.byKey(const Key('summary-section-reports')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('summary-block-reports')), findsNothing);
    expect(find.bySemanticsLabel(RegExp('Conditions: Type 2 diabetes')), findsOneWidget);

    await tester.tap(find.byKey(const Key('result-share')));
    await tester.pumpAndSettle();
    expect(sharedName, 'Health summary 2026-03-20.pdf');
    final String text = pdfText(shared!);
    expect(text, contains('Type 2 diabetes'));
    expect(text, isNot(contains('HbA1c')));

    await tester.tap(find.byKey(const Key('result-save')));
    await tester.pumpAndSettle();
    expect(savedName, 'Health summary 2026-03-20.pdf');
    expect(find.text('Saved to /x/Health summary 2026-03-20.pdf'), findsOneWidget);

    await tester.tap(find.byKey(const Key('result-undo')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('summary-block-reports')), findsOneWidget);

    expect(tester.getSize(find.byKey(const Key('summary-condition-add'))).height, greaterThanOrEqualTo(44));
    expect(tester.getSize(find.byKey(const Key('summary-section-medicines'))).height, greaterThanOrEqualTo(44));
    sem.dispose();
  });
}
