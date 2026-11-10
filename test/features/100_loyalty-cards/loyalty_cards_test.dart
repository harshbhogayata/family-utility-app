import 'package:family_utility_app/engines/family/family_identity.dart';
import 'package:family_utility_app/engines/family/family_space.dart';
import 'package:family_utility_app/engines/family/family_store.dart';
import 'package:family_utility_app/engines/family/family_sync.dart';
import 'package:family_utility_app/engines/records/loyalty_cards.dart';
import 'package:family_utility_app/records/loyalty_cards/loyalty_card_screen.dart';
import 'package:family_utility_app/records/loyalty_cards/loyalty_cards_screen.dart';
import 'package:family_utility_app/records/loyalty_cards/loyalty_scan_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart' as ms;

FamilySpace newSpace() => FamilySpace(
      identityStore: MemoryFamilyIdentityStore(),
      storage: MemoryFamilyStoreStorage(),
      transportsFor: (FamilyIdentity _) => <FamilySyncTransport>[],
    );

LoyaltyCards make() => LoyaltyCards(space: newSpace(), soloStore: FamilyStore(deviceId: 'me'), now: () => DateTime(2026, 3, 20, 10));

class FakeBrightness implements ScreenBrightness {
  FakeBrightness(this.level);
  double? level;
  final List<double?> sets = <double?>[];
  @override
  Future<double?> current() async => level;
  @override
  Future<void> set(double? l) async {
    sets.add(l);
    level = l;
  }
}

void main() {
  group('engine', () {
    test('check digits, format guess, normalise', () {
      expect(LoyaltyCards.checkDigit('400638133393'), 1);
      expect(LoyaltyCards.normalise('400638133393', CardFormat.ean13), '4006381333931');
      expect(LoyaltyCards.normalise('4006 3813 3393 1', CardFormat.ean13), '4006381333931');
      expect(LoyaltyCards.normalise('4006381333932', CardFormat.ean13), isNull);
      expect(LoyaltyCards.normalise('036000291452', CardFormat.upcA), '036000291452');
      expect(LoyaltyCards.normalise('96385074', CardFormat.ean8), '96385074');
      expect(LoyaltyCards.normalise('12345', CardFormat.itf), isNull);
      expect(LoyaltyCards.normalise('ab-12', CardFormat.code39), 'AB-12');
      expect(LoyaltyCards.normalise('  ', CardFormat.code128), isNull);
      expect(LoyaltyCards.guessFormat('4006381333931'), CardFormat.ean13);
      expect(LoyaltyCards.guessFormat('036000291452'), CardFormat.upcA);
      expect(LoyaltyCards.guessFormat('DM-778812'), CardFormat.code128);
      expect(LoyaltyCards.formatByName('ean13'), CardFormat.ean13);
      expect(cardFormatFor(ms.BarcodeFormat.ean13), CardFormat.ean13);
      expect(cardFormatFor(ms.BarcodeFormat.qrCode), CardFormat.qr);
      expect(cardFormatFor(ms.BarcodeFormat.code93), CardFormat.code128);
    });

    test('add, most used first, search, rename, delete and undo, text', () {
      final LoyaltyCards c = make();
      expect(c.add(storeName: ' ', number: '123'), isNull);
      expect(c.add(storeName: 'Big Bazaar', number: '4006381333932', format: CardFormat.ean13), isNull);
      final LoyaltyCard dmart = c.add(storeName: 'DMart', number: '4006381333931')!;
      final LoyaltyCard shoppers = c.add(storeName: 'Shoppers Stop', number: 'SS 99812', note: "Mum's card")!;
      expect(dmart.format, CardFormat.ean13);
      expect(shoppers.format, CardFormat.code128);
      expect(c.all.map((LoyaltyCard x) => x.store).toList(), <String>['DMart', 'Shoppers Stop']);
      c.markShown(shoppers.id);
      expect(c.all.first.store, 'Shoppers Stop');
      expect(c.search('dm').single.id, dmart.id);
      expect(c.search('99812').single.id, shoppers.id);

      expect(c.rename(dmart.id, 'DMart Ready'), isTrue);
      expect(c.undo(), isTrue);
      expect(c.byId(dmart.id)!.store, 'DMart');
      expect(c.remove(dmart.id), isTrue);
      expect(c.all.length, 1);
      expect(c.undo(), isTrue);
      expect(c.byId(dmart.id)!.number, '4006381333931');
      expect(c.undo(), isFalse);
      expect(c.toText(), contains("- Shoppers Stop: SS 99812 (Code 128) · Mum's card"));
      expect(c.toText(), contains('- DMart: 4006381333931 (EAN-13)'));
    });

    test('shared with the family', () async {
      final FamilySpace a = newSpace();
      await a.create(familyName: 'Shahs', memberName: 'Asha');
      LoyaltyCards(space: a).add(storeName: 'Reliance Smart', number: '96385074');
      final FamilySpace b = newSpace();
      await b.create(familyName: 'x', memberName: 'Ravi');
      b.store.mergeAll(a.store.allRecords);
      expect(LoyaltyCards(space: b).all.single.format, CardFormat.ean8);
    });
  });

  testWidgets('screen: scan, add, show at full brightness, restore, delete, undo, share; 44 px', (WidgetTester tester) async {
    final SemanticsHandle sem = tester.ensureSemantics();
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final LoyaltyCards c = make();
    final FakeBrightness light = FakeBrightness(0.4);
    final List<String> shared = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: LoyaltyCardsScreen(
        cards: c,
        scan: (BuildContext _) async => const ScannedCard('4006381333931', CardFormat.ean13),
        brightness: light,
        share: (String t) async => shared.add(t),
        save: (String t, String n) async => '/x/$n',
      ),
    ));
    await tester.pumpAndSettle();

    expect(tester.getSize(find.byKey(const Key('lc-scan'))).height, greaterThanOrEqualTo(44));
    await tester.tap(find.byKey(const Key('lc-scan')));
    await tester.pumpAndSettle();
    expect(find.text('Card scanned'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('lc-store')), 'DMart');
    await tester.tap(find.byKey(const Key('lc-save')));
    await tester.pumpAndSettle();
    final LoyaltyCard dmart = c.all.single;
    expect(find.text('4006381333931 · EAN-13'), findsOneWidget);

    // A typed number with a wrong check digit is refused.
    await tester.tap(find.byTooltip('Type a card number'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('lc-store')), 'Bad');
    await tester.enterText(find.byKey(const Key('lc-number-field')), '4006381333932');
    await tester.tap(find.byKey(const Key('lc-save')));
    await tester.pumpAndSettle();
    expect(c.all.length, 1);
    await tester.pumpAndSettle(const Duration(seconds: 5));

    await tester.tap(find.text('DMart'));
    await tester.pumpAndSettle();
    expect(find.byType(LoyaltyCardScreen), findsOneWidget);
    expect(find.byKey(const Key('lc-barcode')), findsOneWidget);
    expect(find.byKey(const Key('lc-barcode-error')), findsNothing);
    expect(find.bySemanticsLabel('DMart card barcode, number 4006381333931'), findsOneWidget);
    expect(light.sets, <double?>[1.0]);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(light.sets, <double?>[1.0, 0.4]);
    expect(c.byId(dmart.id)!.uses, greaterThan(0));

    final Finder del = find.byKey(Key('lc-delete-${dmart.id}'));
    expect(tester.getSize(del).height, greaterThanOrEqualTo(44));
    await tester.tap(del);
    await tester.pumpAndSettle();
    expect(c.all, isEmpty);
    await tester.tap(find.byKey(const Key('result-undo')));
    await tester.pumpAndSettle();
    expect(find.text('DMart'), findsOneWidget);

    await tester.tap(find.byKey(const Key('result-share')));
    await tester.pumpAndSettle();
    expect(shared.single, contains('- DMart: 4006381333931 (EAN-13)'));
    await tester.pumpAndSettle(const Duration(seconds: 5));
    sem.dispose();
  });

  testWidgets('every format draws without error', (WidgetTester tester) async {
    const Map<CardFormat, String> samples = <CardFormat, String>{
      CardFormat.code128: 'DM-778812',
      CardFormat.ean13: '4006381333931',
      CardFormat.ean8: '96385074',
      CardFormat.upcA: '036000291452',
      CardFormat.code39: 'AB-12',
      CardFormat.itf: '12345678',
      CardFormat.codabar: '123456',
      CardFormat.qr: 'https://example.com/card/1',
      CardFormat.pdf417: 'CARD 1234',
      CardFormat.dataMatrix: 'CARD 1234',
      CardFormat.aztec: 'CARD 1234',
    };
    for (final MapEntry<CardFormat, String> e in samples.entries) {
      await tester.pumpWidget(MaterialApp(
        home: LoyaltyCardScreen(
          card: LoyaltyCard(id: 'x', store: 'S', number: e.value, format: e.key),
          brightness: const NoScreenBrightness(),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('lc-barcode-error')), findsNothing, reason: '${e.key}');
    }
  });
}
