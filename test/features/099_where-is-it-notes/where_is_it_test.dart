import 'package:family_utility_app/engines/family/family_identity.dart';
import 'package:family_utility_app/engines/family/family_space.dart';
import 'package:family_utility_app/engines/family/family_store.dart';
import 'package:family_utility_app/engines/family/family_sync.dart';
import 'package:family_utility_app/engines/platform/one_search.dart';
import 'package:family_utility_app/engines/records/where_is_it.dart';
import 'package:family_utility_app/records/where_is_it/where_is_it_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

FamilySpace newSpace() => FamilySpace(
      identityStore: MemoryFamilyIdentityStore(),
      storage: MemoryFamilyStoreStorage(),
      transportsFor: (FamilyIdentity _) => <FamilySyncTransport>[],
    );

int _tick = 0;
DateTime clock() => DateTime(2026, 3, 20, 10).add(Duration(minutes: _tick++));

void main() {
  group('engine', () {
    test('add, search by any word, moved it, delete and undo, text; private without a family', () async {
      final WhereIsIt w = WhereIsIt(space: newSpace(), privateStore: FamilyStore(deviceId: 'me'), now: clock);
      expect(w.canShare, isFalse);
      expect(w.add(item: ' ', place: 'x'), isNull);
      final WhereNote key = w.add(item: 'Spare car key', place: 'Bedroom cupboard, top shelf', detail: 'In the blue box', shared: true)!;
      final WhereNote album = w.add(item: 'Wedding album', place: 'Loft, left trunk', photo: '/nowhere/p.jpg')!;
      expect(key.shared, isFalse);
      expect(w.setShared(key.id, true), isFalse);
      expect(w.all.map((WhereNote n) => n.item).toList(), <String>['Wedding album', 'Spare car key']);
      expect(w.search('key').single.id, key.id);
      expect(w.search('cupb').single.id, key.id);
      expect(w.search('blue').single.id, key.id);
      expect(w.search('trunk').single.id, album.id);
      expect(w.search('passport'), isEmpty);

      expect(w.edit(key.id, place: 'Drawer by the door'), isTrue);
      expect(w.byId(key.id)!.place, 'Drawer by the door');
      expect(w.all.first.id, key.id);
      expect(w.undo(), isTrue);
      expect(w.byId(key.id)!.place, 'Bedroom cupboard, top shelf');

      expect(w.remove(album.id), isTrue);
      expect(w.byId(album.id), isNull);
      expect(w.undo(), isTrue);
      expect(w.byId(album.id)!.photo, '/nowhere/p.jpg');
      expect(w.toText(), contains('- Spare car key: Bedroom cupboard, top shelf (In the blue box)'));

      final List<SearchDoc> docs = await w.collect();
      expect(docs.map((SearchDoc d) => d.ref), contains('where:${key.id}'));
      expect(SearchIndex(docs).query('album').single.doc.title, 'Wedding album');
    });

    test('shared notes reach the family; private ones do not; share and unshare undo', () async {
      final FamilySpace a = newSpace();
      await a.create(familyName: 'Shahs', memberName: 'Asha');
      final FamilyStore mine = FamilyStore(deviceId: 'a');
      final WhereIsIt w = WhereIsIt(space: a, privateStore: mine, now: clock);
      expect(w.canShare, isTrue);
      final WhereNote passports = w.add(item: 'Passports', place: 'Locker, second drawer', shared: true)!;
      final WhereNote diary = w.add(item: 'Diary', place: 'Under the bed')!;
      expect(passports.shared, isTrue);
      expect(a.store.get(WhereIsIt.collection, passports.id), isNotNull);
      expect(a.store.get(WhereIsIt.collection, diary.id), isNull);
      expect(mine.get(WhereIsIt.collection, diary.id), isNotNull);

      final FamilySpace b = newSpace();
      await b.create(familyName: 'x', memberName: 'Ravi');
      b.store.mergeAll(a.store.allRecords);
      final WhereIsIt other = WhereIsIt(space: b, privateStore: FamilyStore(deviceId: 'b'));
      expect(other.all.single.item, 'Passports');

      expect(w.setShared(diary.id, true), isTrue);
      expect(a.store.get(WhereIsIt.collection, diary.id), isNotNull);
      expect(mine.get(WhereIsIt.collection, diary.id), isNull);
      expect(w.byId(diary.id)!.shared, isTrue);
      expect(w.undo(), isTrue);
      expect(a.store.get(WhereIsIt.collection, diary.id), isNull);
      expect(w.byId(diary.id)!.shared, isFalse);
      expect(w.all.length, 2);
    });
  });

  testWidgets('screen: note with photo, search, moved it, share, delete, undo; 44 px', (WidgetTester tester) async {
    final SemanticsHandle sem = tester.ensureSemantics();
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final FamilySpace space = newSpace();
    await tester.runAsync(() => space.create(familyName: 'Shahs', memberName: 'Asha'));
    final WhereIsIt w = WhereIsIt(space: space, privateStore: FamilyStore(deviceId: 'me'), now: clock);
    w.add(item: 'Wedding album', place: 'Loft, left trunk');
    final List<String> shared = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: WhereIsItScreen(
        notes: w,
        takePhoto: () async => '/not/on/this/phone.jpg',
        share: (String t) async => shared.add(t),
        save: (String t, String n) async => '/x/$n',
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('wi-add')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('wi-item')), 'Spare car key');
    await tester.enterText(find.byKey(const Key('wi-place')), 'Bedroom cupboard, top shelf');
    await tester.tap(find.byKey(const Key('wi-photo')));
    await tester.pumpAndSettle();
    expect(find.text('Retake photo'), findsOneWidget);
    await tester.tap(find.byKey(const Key('wi-shared')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('wi-save')));
    await tester.pumpAndSettle();
    final WhereNote key = w.all.firstWhere((WhereNote n) => n.item == 'Spare car key');
    expect(key.shared, isTrue);
    expect(key.photo, '/not/on/this/phone.jpg');
    expect(find.text('Photo is on the phone that took it'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Shared with the family')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('wi-search')), 'cupboard');
    await tester.pumpAndSettle();
    expect(find.text('Wedding album'), findsNothing);
    expect(find.text('Spare car key'), findsOneWidget);

    final Finder moved = find.byKey(Key('wi-edit-${key.id}'));
    expect(tester.getSize(moved).height, greaterThanOrEqualTo(44));
    await tester.tap(moved);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('wi-place')), 'Drawer by the door');
    await tester.tap(find.byKey(const Key('wi-save')));
    await tester.pumpAndSettle();
    expect(w.byId(key.id)!.place, 'Drawer by the door');
    expect(find.text('Spare car key'), findsNothing); // the search no longer matches
    expect(find.text('Nothing matches "cupboard".'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('wi-search')), '');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('result-undo')));
    await tester.pumpAndSettle();
    expect(find.text('Bedroom cupboard, top shelf'), findsOneWidget);

    await tester.tap(find.byKey(Key('wi-delete-${key.id}')));
    await tester.pumpAndSettle();
    expect(find.text('Spare car key'), findsNothing);
    await tester.tap(find.byKey(const Key('result-undo')));
    await tester.pumpAndSettle();
    expect(find.text('Spare car key'), findsOneWidget);

    await tester.tap(find.byKey(const Key('result-share')));
    await tester.pumpAndSettle();
    expect(shared.single, contains('- Spare car key: Bedroom cupboard, top shelf · shared'));
    expect(shared.single, contains('- Wedding album: Loft, left trunk'));
    await tester.pumpAndSettle(const Duration(seconds: 5));
    sem.dispose();
  });
}
