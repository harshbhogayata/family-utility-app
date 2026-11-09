import 'package:family_utility_app/app/widgets/related_items_strip.dart';
import 'package:family_utility_app/engines/platform/cross_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const RecordRef receipt = RecordRef('receipt', 'r1');
const RecordRef warranty = RecordRef('warranty', 'w1');
const RecordRef fridge = RecordRef('appliance', 'a1');
const RecordRef visit = RecordRef('visit', 'v1');
const RecordRef rx = RecordRef('prescription', 'p1');

CrossLinks withKinds(CrossLinks l, Map<String, String> titles) {
  for (final MapEntry<String, String> k in <String, String>{
    'warranty': 'Warranty',
    'appliance': 'Appliance',
    'receipt': 'Receipt',
    'visit': 'Visit',
    'prescription': 'Prescription',
  }.entries) {
    l.registerKind(SimpleRecordKind(k.key, k.value, (String id) => titles['${k.key}/$id']));
  }
  return l;
}

void main() {
  group('engine', () {
    test('two-way links by id, related items in kind order, undo', () {
      final Map<String, String> titles = <String, String>{
        'receipt/r1': 'Croma bill',
        'warranty/w1': 'LG 2-year',
        'appliance/a1': 'Fridge',
        'visit/v1': 'Dr Mehta',
        'prescription/p1': 'Antibiotics',
      };
      final CrossLinks l = withKinds(CrossLinks(), titles);
      expect(l.link(receipt, fridge), isTrue);
      expect(l.link(receipt, warranty), isTrue);
      expect(l.link(warranty, receipt), isFalse, reason: 'already linked');
      expect(l.link(receipt, receipt), isFalse);
      expect(l.link(visit, rx), isTrue);

      expect(l.related(receipt).map((RelatedItem i) => '${i.noun}: ${i.title}'),
          <String>['Warranty: LG 2-year', 'Appliance: Fridge']);
      expect(l.related(warranty).single.ref, receipt);
      expect(l.related(rx).single.title, 'Dr Mehta');
      expect(l.related(fridge).single.noun, 'Receipt');

      expect(l.unlink(fridge, receipt), isTrue);
      expect(l.related(receipt).length, 1);
      expect(l.undo(), isTrue);
      expect(l.areLinked(receipt, fridge), isTrue);
      expect(l.undo(), isFalse);

      // A deleted record stops showing, and forget drops its links.
      titles.remove('warranty/w1');
      expect(l.related(receipt).single.title, 'Fridge');
      expect(l.linkedTo(receipt), <RecordRef>[fridge, warranty]);
      expect(l.forget(warranty), 1);
      expect(l.linkedTo(receipt), <RecordRef>[fridge]);
      expect(l.undo(), isTrue);
      expect(l.areLinked(warranty, receipt), isTrue);

      expect(RecordRef.parse('visit/v/1'), const RecordRef('visit', 'v/1'));
      expect(RecordRef.parse('nope'), isNull);
      expect(RecordRef.parse('/x'), isNull);
    });

    test('links survive a restart', () async {
      final MemoryCrossLinkStorage store = MemoryCrossLinkStorage();
      final CrossLinks a = CrossLinks(storage: store);
      a.link(receipt, warranty);
      a.link(visit, rx);
      await Future<void>.delayed(Duration.zero);
      expect(store.saved, <List<String>>[
        <String>['prescription/p1', 'visit/v1'],
        <String>['receipt/r1', 'warranty/w1'],
      ]);
      final CrossLinks b = CrossLinks(storage: store);
      await b.load();
      expect(b.areLinked(warranty, receipt), isTrue);
      expect(b.areLinked(rx, visit), isTrue);
      expect(b.linkedTo(receipt), <RecordRef>[warranty]);
    });
  });

  testWidgets('strip shows related chips, labelled, 44 px, and opens them', (WidgetTester tester) async {
    final SemanticsHandle sem = tester.ensureSemantics();
    final CrossLinks l = withKinds(CrossLinks(), <String, String>{
      'warranty/w1': 'LG 2-year',
      'appliance/a1': 'Fridge',
    });
    l.link(receipt, warranty);
    l.link(receipt, fridge);
    final List<RecordRef> opened = <RecordRef>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(
          children: <Widget>[
            RelatedItemsStrip(record: receipt, links: l, onOpen: opened.add),
            RelatedItemsStrip(record: visit, links: l, onOpen: opened.add),
          ],
        ),
      ),
    ));
    expect(find.text('Related'), findsOneWidget, reason: 'a record with no links shows no strip');
    expect(find.bySemanticsLabel('Open Warranty: LG 2-year'), findsOneWidget);
    expect(find.bySemanticsLabel('Open Appliance: Fridge'), findsOneWidget);
    expect(tester.getSize(find.byType(ActionChip).first).height, greaterThanOrEqualTo(44));
    await tester.tap(find.text('Appliance · Fridge'));
    expect(opened, <RecordRef>[fridge]);

    l.unlink(receipt, fridge);
    await tester.pump();
    expect(find.text('Appliance · Fridge'), findsNothing);
    sem.dispose();
  });
}
