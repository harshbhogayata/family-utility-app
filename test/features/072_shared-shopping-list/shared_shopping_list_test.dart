import 'package:family_utility_app/app/theme.dart';
import 'package:family_utility_app/engines/family/family_identity.dart';
import 'package:family_utility_app/engines/family/family_space.dart';
import 'package:family_utility_app/engines/family/family_store.dart';
import 'package:family_utility_app/engines/family/family_sync.dart';
import 'package:family_utility_app/engines/family/shared_shopping_list.dart';
import 'package:family_utility_app/family/shopping/shared_shopping_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

FamilySpace newSpace() => FamilySpace(
      identityStore: MemoryFamilyIdentityStore(),
      storage: MemoryFamilyStoreStorage(),
      transportsFor: (FamilyIdentity _) => <FamilySyncTransport>[],
    );

void main() {
  group('engine', () {
    test('add with quantity, aisle guess, tick shows who and when, untick, undo', () async {
      final FamilySpace s = newSpace();
      await s.create(familyName: 'Shahs', memberName: 'Asha');
      final SharedShoppingList list = SharedShoppingList(space: s, now: () => DateTime(2026, 11, 9, 18, 5));

      final ShoppingItem milk = list.add('2 L milk')!;
      expect(milk.name, 'milk');
      expect(milk.quantity, '2 L');
      expect(milk.aisle, 'Dairy & eggs');
      final ShoppingItem soap = list.add('Soap', quantity: '3')!;
      expect(soap.quantity, '3');
      expect(soap.aisle, 'Household');
      expect(list.add('Birthday candles')!.aisle, ShoppingAisles.other);
      expect(list.add('   '), isNull);

      expect(list.tick(milk.id), isTrue);
      final ShoppingItem t = list.item(milk.id)!;
      expect(t.ticked, isTrue);
      expect(list.memberName(t.tickedBy!), 'Asha');
      expect(t.tickedAt, DateTime(2026, 11, 9, 18, 5));
      expect(list.tick(milk.id), isFalse);

      expect(list.untick(milk.id), isTrue);
      expect(list.item(milk.id)!.ticked, isFalse);
      expect(list.undo(), isTrue);
      expect(list.item(milk.id)!.ticked, isTrue);

      expect(list.clearTicked(), 1);
      expect(list.item(milk.id), isNull);
      expect(list.undo(), isTrue);
      expect(list.item(milk.id), isNotNull);
    });

    test('grouped in aisle order, to-buy first; text for sharing', () async {
      final FamilySpace s = newSpace();
      await s.create(familyName: 'F', memberName: 'A');
      int minute = 0;
      final SharedShoppingList list = SharedShoppingList(space: s, now: () => DateTime(2026, 11, 9, 10, minute++));
      list.add('Detergent');
      final ShoppingItem bread = list.add('Bread')!;
      list.add('Eggs', quantity: '12');
      list.add('Onions');
      list.add('Pav');
      list.tick(bread.id);

      final List<MapEntry<String, List<ShoppingItem>>> g = list.grouped();
      expect(g.map((MapEntry<String, List<ShoppingItem>> e) => e.key),
          <String>['Fruit & veg', 'Dairy & eggs', 'Bakery', 'Household']);
      expect(g[2].value.map((ShoppingItem i) => i.name), <String>['Pav', 'Bread']);
      final String text = list.toText();
      expect(text, contains('[ ] Eggs (12)'));
      expect(text, contains('[x] Bread'));
    });

    test('a tick on one phone reaches the other', () async {
      final FamilyStore a = FamilyStore(deviceId: 'phone-a');
      final FamilyStore b = FamilyStore(deviceId: 'phone-b');
      a.put(SharedShoppingList.collection, 'x', <String, Object?>{'name': 'Rice', 'aisle': 'Grains & staples', 'by': 'phone-a'});
      b.mergeAll(a.allRecords);
      b.put(SharedShoppingList.collection, 'x', <String, Object?>{
        ...b.get(SharedShoppingList.collection, 'x')!.fields,
        'tickedBy': 'phone-b',
        'tickedAt': '2026-11-09T18:00:00.000',
      });
      a.mergeAll(b.allRecords);
      expect(ShoppingItem.fromRecord(a.get(SharedShoppingList.collection, 'x')!).tickedBy, 'phone-b');
    });
  });

  testWidgets('add, tick, see who ticked, share, save, undo', (WidgetTester tester) async {
    final FamilySpace s = newSpace();
    await tester.runAsync(() => s.create(familyName: 'Shahs', memberName: 'Asha'));
    final SharedShoppingList list = SharedShoppingList(space: s, now: () => DateTime(2026, 11, 9, 18, 5));
    String? shared;
    String? saved;
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: SharedShoppingScreen(
        list: list,
        share: (String t) async => shared = t,
        save: (String t) async {
          saved = t;
          return '/docs/Shopping list.txt';
        },
      ),
    ));

    await tester.enterText(find.widgetWithText(TextField, 'Add an item'), 'Tomatoes');
    await tester.enterText(find.widgetWithText(TextField, 'Qty'), '1 kg');
    await tester.tap(find.byTooltip('Add to list'));
    await tester.pumpAndSettle();

    expect(find.text('Fruit & veg'), findsOneWidget);
    expect(find.text('Tomatoes · 1 kg'), findsOneWidget);
    expect(find.text('Added by Asha'), findsOneWidget);
    expect(tester.getSize(find.byType(CheckboxListTile)).height, greaterThanOrEqualTo(44));
    expect(tester.getSize(find.byTooltip('Add to list')).height, greaterThanOrEqualTo(44));

    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    expect(find.text('Ticked by Asha at 18:05'), findsOneWidget);
    expect(list.items.single.ticked, isTrue);

    await tester.tap(find.byKey(const Key('result-share')));
    await tester.pumpAndSettle();
    expect(shared, contains('[x] Tomatoes (1 kg)'));
    await tester.tap(find.byKey(const Key('result-save')));
    await tester.pumpAndSettle();
    expect(saved, isNotNull);
    expect(find.text('Saved to /docs/Shopping list.txt'), findsOneWidget);

    await tester.tap(find.byKey(const Key('result-undo')));
    await tester.pumpAndSettle();
    expect(list.items.single.ticked, isFalse);
    expect(find.text('Added by Asha'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });
}
