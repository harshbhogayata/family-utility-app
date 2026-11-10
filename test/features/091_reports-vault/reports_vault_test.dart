import 'dart:convert';
import 'dart:typed_data';

import 'package:family_utility_app/engines/family/document_vault.dart';
import 'package:family_utility_app/engines/records/reports_vault.dart';
import 'package:family_utility_app/engines/security/private_vault.dart';
import 'package:family_utility_app/engines/security/secure_notes.dart';
import 'package:family_utility_app/records/reports/reports_vault_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeReader implements ReportTextReader {
  FakeReader(this.text);
  final String text;
  @override
  Future<String> read(Uint8List image) async => text;
}

void main() {
  group('engine', () {
    test('stored encrypted, reloads, values tagged and charted, undo', () async {
      final MemoryKeyStore keys = MemoryKeyStore();
      final MemoryDocumentBlobStore blobs = MemoryDocumentBlobStore();
      final ReportsVault v = ReportsVault(
        cipher: VaultCipher(keys),
        blobs: blobs,
        reader: FakeReader('Test Result Unit\nHbA1c 7.2 %\nGlucose, fasting 132 mg/dL'),
        now: () => DateTime(2026, 3, 20, 10),
      );
      await v.load();
      final Uint8List file = Uint8List.fromList(utf8.encode('SECRET LAB REPORT'));
      final LabReport a = await v.add(bytes: file, fileName: 'march.jpg', title: 'Diabetes panel', date: DateTime(2026, 3, 1));
      expect(a.values['HbA1c']!.value, 7.2);
      expect(a.values['HbA1c']!.unit, '%');
      expect(a.values['Glucose']!.value, 132);

      // Nothing readable at rest.
      for (final Uint8List stored in blobs.files.values) {
        expect(utf8.decode(stored, allowMalformed: true), isNot(contains('SECRET')));
        expect(utf8.decode(stored, allowMalformed: true), isNot(contains('HbA1c')));
      }
      expect(await v.open(a.id), file);

      final LabReport b = await v.add(bytes: Uint8List.fromList(<int>[1, 2, 3]), fileName: 'dec.pdf', date: DateTime(2025, 12, 1));
      expect(b.values, isEmpty); // PDFs are not read by OCR
      expect(await v.tagValue(b.id, 'HbA1c', 8.1, unit: '%'), isTrue);
      expect(await v.tagValue(b.id, ' ', 1), isFalse);
      expect(v.series('HbA1c'), <(DateTime, double)>[(DateTime(2025, 12, 1), 8.1), (DateTime(2026, 3, 1), 7.2)]);
      expect(v.tags, <String>['Glucose', 'HbA1c']);
      expect(v.seriesText('HbA1c'), 'HbA1c over time\n- 1 Dec 2025: 8.1 %\n- 1 Mar 2026: 7.2 %\n');

      expect(await v.remove(a.id), isTrue);
      expect(v.series('HbA1c').length, 1);
      expect(await v.undo(), isTrue);
      expect(v.series('HbA1c').length, 2);
      expect(await v.open(a.id), file);

      final ReportsVault again = ReportsVault(cipher: VaultCipher(keys), blobs: blobs);
      await again.load();
      expect(again.reports.map((LabReport r) => r.title).toList(), <String>['Diabetes panel', 'Lab report']);
      expect(again.series('HbA1c').length, 2);

      final ReportsVault otherKey = ReportsVault(cipher: VaultCipher(MemoryKeyStore()), blobs: blobs);
      await otherKey.load();
      expect(otherKey.reports, isEmpty);
    });

    test('finds values on OCR lines', () {
      final Map<String, ReportValue> f = ReportsVault.findValues('TSH 3.25 uIU/mL\nHDL Cholesterol 48 mg/dL\nVitamin D 18.4 ng/mL');
      expect(f['TSH']!.value, 3.25);
      expect(f['HDL']!.value, 48);
      expect(f['Vitamin D']!.unit, 'ng/mL');
    });
  });

  testWidgets('screen: add report, tag value, chart, share, undo; 44 px', (WidgetTester tester) async {
    final SemanticsHandle sem = tester.ensureSemantics();
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final ReportsVault v = ReportsVault(cipher: VaultCipher(MemoryKeyStore()), blobs: MemoryDocumentBlobStore());
    await tester.runAsync(v.load);
    final List<String> shared = <String>[];
    final List<String> files = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: ReportsVaultScreen(
        vault: v,
        pick: () async => (bytes: Uint8List.fromList(<int>[9, 9, 9]), name: 'jan.pdf'),
        share: (String t) async => shared.add(t),
        save: (String t, String n) async => '/x/$n',
        shareFile: (Uint8List b, String n) async => files.add(n),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('rv-add')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('rv-title')), 'Sugar test');
    await tester.enterText(find.byKey(const Key('rv-date')), '05/01/2026');
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('rv-save')));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
    final LabReport r = v.reports.single;
    expect(find.text('Sugar test'), findsOneWidget);
    expect(tester.getSize(find.byKey(Key('rv-tagvalue-${r.id}'))).height, greaterThanOrEqualTo(44));

    await tester.tap(find.byKey(Key('rv-tagvalue-${r.id}')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('rv-tag-name')), 'HbA1c');
    await tester.enterText(find.byKey(const Key('rv-tag-value')), '6.9');
    await tester.enterText(find.byKey(const Key('rv-tag-unit')), '%');
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('rv-tag-save')));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
    expect(find.text('HbA1c: 6.9 %'), findsOneWidget);
    expect(find.byKey(const Key('rv-chart')), findsOneWidget);
    expect(find.text('1 result, latest 6.9 % on 5 Jan 2026'), findsOneWidget);

    await tester.tap(find.byKey(const Key('result-share')));
    await tester.pumpAndSettle();
    expect(shared.last, contains('- 5 Jan 2026: 6.9 %'));

    await tester.runAsync(() async {
      await tester.tap(find.byKey(Key('rv-open-${r.id}')));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
    expect(files, <String>['jan.pdf']);

    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('result-undo')));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
    expect(find.text('HbA1c: 6.9 %'), findsNothing);
    await tester.pumpAndSettle(const Duration(seconds: 5));
    sem.dispose();
  });
}
