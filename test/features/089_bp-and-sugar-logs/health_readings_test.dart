import 'dart:convert';
import 'dart:typed_data';

import 'package:family_utility_app/engines/records/health_readings.dart';
import 'package:family_utility_app/records/health_log/health_log_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('engine', () {
    test('one-line entries parse as BP or sugar', () {
      final ParsedReading bp = HealthLog.parse('128/84 72')!;
      expect(bp.kind, ReadingKind.bp);
      expect(bp.systolic, 128);
      expect(bp.diastolic, 84);
      expect(bp.pulse, 72);
      expect(HealthLog.parse('bp 130 85 after walk')!.note, 'walk');
      expect(HealthLog.parse('120 80')!.kind, ReadingKind.bp);

      final ParsedReading f = HealthLog.parse('110 fasting')!;
      expect(f.kind, ReadingKind.sugar);
      expect(f.sugar, 110);
      expect(f.context, SugarContext.fasting);
      expect(HealthLog.parse('sugar 160 after lunch')!.context, SugarContext.afterMeal);
      expect(HealthLog.parse('ppbs 150')!.context, SugarContext.afterMeal);
      expect(HealthLog.parse('140 mg/dl')!.kind, ReadingKind.sugar);
      expect(HealthLog.parse('95', prefer: ReadingKind.sugar)!.sugar, 95);
      expect(HealthLog.parse('95', prefer: ReadingKind.bp), isNull);
      expect(HealthLog.parse('80/120'), isNull);
      expect(HealthLog.parse('hello'), isNull);
    });

    test('bands follow common adult reference ranges', () {
      HealthReading bp(int s, int d) => HealthReading(id: 'x', kind: ReadingKind.bp, at: DateTime(2026), systolic: s, diastolic: d);
      HealthReading sg(int v, SugarContext c) => HealthReading(id: 'x', kind: ReadingKind.sugar, at: DateTime(2026), sugar: v, context: c);
      expect(bp(115, 75).band, ReadingBand.normal);
      expect(bp(124, 78).band, ReadingBand.elevated);
      expect(bp(140, 90).band, ReadingBand.high);
      expect(bp(85, 55).band, ReadingBand.low);
      expect(sg(95, SugarContext.fasting).band, ReadingBand.normal);
      expect(sg(110, SugarContext.fasting).band, ReadingBand.elevated);
      expect(sg(130, SugarContext.fasting).band, ReadingBand.high);
      expect(sg(130, SugarContext.afterMeal).band, ReadingBand.normal);
      expect(sg(210, SugarContext.random).band, ReadingBand.high);
      expect(sg(60, SugarContext.random).band, ReadingBand.low);
    });

    test('range, summary, undo, saved and reloaded', () async {
      DateTime now = DateTime(2026, 3, 1, 8);
      final MemoryHealthReadingStore store = MemoryHealthReadingStore();
      final HealthLog log = HealthLog(store: store, now: () => now);
      log.quickAdd('120/80 70');
      now = DateTime(2026, 3, 2, 8);
      log.quickAdd('140/90');
      now = DateTime(2026, 3, 2, 9);
      log.quickAdd('110 fasting');
      now = DateTime(2026, 3, 10, 8);
      log.addBp(systolic: 130, diastolic: 85);
      expect(log.addBp(systolic: 80, diastolic: 120), isNull);
      expect(log.addSugar(mgdl: 5), isNull);

      final List<HealthReading> r = log.inRange(ReadingKind.bp, DateTime(2026, 3, 1), DateTime(2026, 3, 2));
      expect(r.map((HealthReading x) => x.systolic).toList(), <int>[120, 140]);
      final ({int count, int avg, int min, int max, int avgDia}) s = HealthLog.summary(r)!;
      expect(s.count, 2);
      expect(s.avg, 130);
      expect(s.avgDia, 85);
      expect(s.min, 120);
      expect(s.max, 140);
      expect(log.inRange(ReadingKind.sugar, DateTime(2026, 3, 1), DateTime(2026, 3, 31)).single.sugar, 110);

      expect(log.remove(log.all.first.id), isTrue);
      expect(log.all.length, 3);
      expect(log.undo(), isTrue);
      expect(log.all.length, 4);
      expect(log.undo(), isFalse);

      await Future<void>.delayed(Duration.zero);
      final HealthLog again = HealthLog(store: store);
      await again.load();
      expect(again.all.length, 4);
      expect(again.all.last.pulse, 70);
      expect(again.all.firstWhere((HealthReading x) => x.kind == ReadingKind.sugar).context, SugarContext.fasting);
    });

    test('PDF of a date range is a well-formed PDF with the readings', () {
      final HealthLog log = HealthLog(now: () => DateTime(2026, 3, 1, 8));
      for (int i = 0; i < 70; i++) {
        log.addBp(systolic: 120 + i % 20, diastolic: 80, pulse: 70, note: 'arm (left) ₹', at: DateTime(2026, 3, 1).add(Duration(hours: i * 6)));
      }
      final List<HealthReading> rs = log.inRange(ReadingKind.bp, DateTime(2026, 3, 1), DateTime(2026, 3, 31));
      final Uint8List pdf = HealthPdf.build(kind: ReadingKind.bp, readings: rs, from: DateTime(2026, 3, 1), to: DateTime(2026, 3, 31), person: 'Asha');
      final String s = latin1.decode(pdf);
      expect(s.startsWith('%PDF-1.4'), isTrue);
      expect(s.trimRight().endsWith('%%EOF'), isTrue);
      expect(s, contains('Blood pressure log'));
      expect(s, contains('Asha - 2026-03-01 to 2026-03-31'));
      expect(s, contains('70 readings'));
      expect(s, contains(r'arm \(left\) ?'));
      // 70 rows do not fit on one A4 page.
      expect(RegExp(r'/Type /Page ').allMatches(s).length, greaterThan(1));
      // xref offsets point at their objects.
      final int xref = int.parse(RegExp(r'startxref\n(\d+)').firstMatch(s)!.group(1)!);
      expect(s.substring(xref, xref + 4), 'xref');
      final RegExpMatch first = RegExp(r'0000000000 65535 f \n(\d{10})').firstMatch(s)!;
      expect(s.substring(int.parse(first.group(1)!)).startsWith('1 0 obj'), isTrue);
      expect(HealthPdf.fileName(ReadingKind.sugar, DateTime(2026, 3, 1), DateTime(2026, 3, 31)),
          'Sugar readings 2026-03-01 to 2026-03-31.pdf');

      final String empty = latin1.decode(HealthPdf.build(kind: ReadingKind.sugar, readings: const <HealthReading>[], from: DateTime(2026), to: DateTime(2026)));
      expect(empty, contains('No readings in this range.'));
    });
  });

  testWidgets('screen: quick entry, chart, range, PDF share and save, undo; 44 px targets', (WidgetTester tester) async {
    final SemanticsHandle sem = tester.ensureSemantics();
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    DateTime clock() => DateTime(2026, 3, 20, 9);
    final HealthLog log = HealthLog(now: clock);
    Uint8List? shared;
    String? sharedName;
    String? savedName;
    await tester.pumpWidget(MaterialApp(
      home: HealthLogScreen(
        log: log,
        now: clock,
        share: (Uint8List pdf, String name) async {
          shared = pdf;
          sharedName = name;
        },
        save: (Uint8List pdf, String name) async {
          savedName = name;
          return '/x/$name';
        },
        pickRange: (BuildContext c, DateTimeRange cur) async => DateTimeRange(start: DateTime(2026, 3, 15), end: DateTime(2026, 3, 20)),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('2026-02-19 to 2026-03-20'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('health-entry')), '132/86 74');
    await tester.tap(find.byKey(const Key('health-add')));
    await tester.pumpAndSettle();
    expect(log.all.single.systolic, 132);
    expect(find.text('132/86 · 74 bpm'), findsOneWidget);
    expect(find.text('1 readings · average 132/86'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Blood pressure trend chart')), findsOneWidget);

    await tester.tap(find.text('Sugar'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('health-entry')), '108');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(log.all.first.kind, ReadingKind.sugar);
    expect(find.text('108 mg/dL random'), findsOneWidget);

    await tester.tap(find.byKey(const Key('health-range')));
    await tester.pumpAndSettle();
    expect(find.text('2026-03-15 to 2026-03-20'), findsOneWidget);

    await tester.tap(find.byKey(const Key('result-share')));
    await tester.pumpAndSettle();
    expect(sharedName, 'Sugar readings 2026-03-15 to 2026-03-20.pdf');
    expect(latin1.decode(shared!), contains('Blood sugar log'));

    await tester.tap(find.byKey(const Key('result-save')));
    await tester.pumpAndSettle();
    expect(savedName, sharedName);

    await tester.tap(find.byKey(const Key('result-undo')));
    await tester.pumpAndSettle();
    expect(log.all.length, 1);
    expect(find.text('No readings in this range.'), findsOneWidget);

    expect(tester.getSize(find.byKey(const Key('health-add'))).height, greaterThanOrEqualTo(44));
    expect(tester.getSize(find.byKey(const Key('health-range'))).height, greaterThanOrEqualTo(44));
    await tester.pumpAndSettle(const Duration(seconds: 5));
    sem.dispose();
  });
}
