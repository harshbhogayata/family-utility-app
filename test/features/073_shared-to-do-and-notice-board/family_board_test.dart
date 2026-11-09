import 'package:family_utility_app/app/theme.dart';
import 'package:family_utility_app/engines/family/family_board.dart';
import 'package:family_utility_app/engines/family/family_identity.dart';
import 'package:family_utility_app/engines/family/family_space.dart';
import 'package:family_utility_app/engines/family/family_store.dart';
import 'package:family_utility_app/engines/family/family_sync.dart';
import 'package:family_utility_app/family/board/family_board_screen.dart';
import 'package:family_utility_app/family/family_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

FamilySpace newSpace() => FamilySpace(
      identityStore: MemoryFamilyIdentityStore(),
      storage: MemoryFamilyStoreStorage(),
      transportsFor: (FamilyIdentity _) => <FamilySyncTransport>[],
    );

void main() {
  group('engine', () {
    test('tasks with owner, due date and done state; order; undo', () async {
      final FamilySpace s = newSpace();
      await s.create(familyName: 'Shahs', memberName: 'Asha');
      int minute = 0;
      final FamilyBoard b = FamilyBoard(space: s, now: () => DateTime(2026, 11, 9, 9, minute++));
      s.store.put(FamilySpace.members, 'ravi-phone', <String, Object?>{'name': 'Ravi'});

      expect(b.addTask('   '), isNull);
      final FamilyTask bills = b.addTask('Pay electricity bill', owner: 'ravi-phone', due: DateTime(2026, 11, 12, 15))!;
      final FamilyTask plants = b.addTask('Water plants')!;
      final FamilyTask gas = b.addTask('Book gas cylinder', due: DateTime(2026, 11, 8))!;
      expect(bills.owner, 'ravi-phone');
      expect(bills.due, DateTime(2026, 11, 12));
      expect(b.memberName(plants.owner), 'Asha');
      expect(b.task(gas.id)!.overdueOn(DateTime(2026, 11, 9)), isTrue);
      expect(b.tasks.map((FamilyTask t) => t.title), <String>['Book gas cylinder', 'Pay electricity bill', 'Water plants']);

      expect(b.setDone(gas.id, true), isTrue);
      expect(b.setDone(gas.id, true), isFalse);
      final FamilyTask done = b.task(gas.id)!;
      expect(done.done, isTrue);
      expect(b.memberName(done.doneBy!), 'Asha');
      expect(done.overdueOn(DateTime(2026, 11, 9)), isFalse);
      expect(b.tasks.last.id, gas.id);

      expect(b.reassign(plants.id, 'ravi-phone'), isTrue);
      expect(b.undo(), isTrue);
      expect(b.task(plants.id)!.owner, s.identity!.deviceId);

      expect(b.clearDone(), 1);
      expect(b.task(gas.id), isNull);
      expect(b.undo(), isTrue);
      expect(b.task(gas.id)!.done, isTrue);

      final String text = b.toText();
      expect(text, contains('[ ] Pay electricity bill · Ravi · due 2026-11-12'));
      expect(text, contains('[x] Book gas cylinder · Asha'));
    });

    test('notes pin to the family screen, unpin, remove, undo', () async {
      final FamilySpace s = newSpace();
      await s.create(familyName: 'F', memberName: 'A');
      int minute = 0;
      final FamilyBoard b = FamilyBoard(space: s, now: () => DateTime(2026, 11, 9, 9, minute++));
      final FamilyNote wifi = b.addNote('Wi-Fi password is on the fridge')!;
      final FamilyNote maid = b.addNote('Maid off on Sunday', pinned: false)!;
      expect(b.addNote(''), isNull);
      expect(FamilyBoard.pinnedIn(s.store).map((FamilyNote n) => n.id), <String>[wifi.id]);
      expect(b.notes.first.id, wifi.id);

      expect(b.setPinned(maid.id, true), isTrue);
      expect(FamilyBoard.pinnedIn(s.store).map((FamilyNote n) => n.id), <String>[maid.id, wifi.id]);
      expect(b.removeNote(wifi.id), isTrue);
      expect(b.note(wifi.id), isNull);
      expect(b.undo(), isTrue);
      expect(b.note(wifi.id)!.pinned, isTrue);
      expect(b.toText(), contains('* Wi-Fi password is on the fridge'));
    });

    test('a done tick on one phone reaches the other', () {
      final FamilyStore a = FamilyStore(deviceId: 'phone-a');
      final FamilyStore c = FamilyStore(deviceId: 'phone-b');
      a.put(FamilyBoard.tasksCollection, 't', <String, Object?>{'title': 'Fix tap', 'owner': 'phone-b', 'by': 'phone-a'});
      c.mergeAll(a.allRecords);
      c.put(FamilyBoard.tasksCollection, 't', <String, Object?>{
        ...c.get(FamilyBoard.tasksCollection, 't')!.fields,
        'doneBy': 'phone-b',
        'doneAt': '2026-11-09T18:00:00.000',
      });
      a.mergeAll(c.allRecords);
      final FamilyTask t = FamilyTask.fromRecord(a.get(FamilyBoard.tasksCollection, 't')!);
      expect(t.done, isTrue);
      expect(t.owner, 'phone-b');
    });
  });

  testWidgets('add a task with a due date, tick it, pin a note, share, save, undo', (WidgetTester tester) async {
    final FamilySpace s = newSpace();
    await tester.runAsync(() => s.create(familyName: 'Shahs', memberName: 'Asha'));
    final FamilyBoard b = FamilyBoard(space: s);
    String? shared;
    String? saved;
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: FamilyBoardScreen(
        board: b,
        share: (String t) async => shared = t,
        save: (String t) async {
          saved = t;
          return '/docs/Family board.txt';
        },
        pickDate: (BuildContext c, DateTime initial) async => DateTime(2030, 1, 5),
      ),
    ));

    await tester.enterText(find.widgetWithText(TextField, 'Pin a note'), 'Keys under the mat');
    await tester.tap(find.byTooltip('Pin note'));
    await tester.pumpAndSettle();
    expect(find.text('Keys under the mat'), findsOneWidget);
    expect(b.notes.single.pinned, isTrue);

    await tester.enterText(find.widgetWithText(TextField, 'Add a task'), 'Renew car insurance');
    await tester.tap(find.text('Due date'));
    await tester.pumpAndSettle();
    expect(find.text('Due 5 Jan'), findsOneWidget);
    await tester.tap(find.byTooltip('Add task'));
    await tester.pumpAndSettle();
    expect(find.text('Renew car insurance'), findsOneWidget);
    expect(find.text('Asha · Due 5 Jan'), findsOneWidget);
    expect(tester.getSize(find.byType(CheckboxListTile)).height, greaterThanOrEqualTo(44));
    expect(tester.getSize(find.byTooltip('Add task')).height, greaterThanOrEqualTo(44));

    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    expect(b.tasks.single.done, isTrue);
    expect(find.text('Asha · Due 5 Jan · Done by Asha'), findsOneWidget);

    await tester.tap(find.byKey(const Key('result-share')));
    await tester.pumpAndSettle();
    expect(shared, contains('[x] Renew car insurance · Asha · due 2030-01-05'));
    expect(shared, contains('* Keys under the mat'));
    await tester.tap(find.byKey(const Key('result-save')));
    await tester.pumpAndSettle();
    expect(saved, isNotNull);
    expect(find.text('Saved to /docs/Family board.txt'), findsOneWidget);

    await tester.tap(find.byKey(const Key('result-undo')));
    await tester.pumpAndSettle();
    expect(b.tasks.single.done, isFalse);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('pinned notes show on the Family screen', (WidgetTester tester) async {
    final FamilySpace s = newSpace();
    await tester.runAsync(() => s.create(familyName: 'Shahs', memberName: 'Asha'));
    FamilyBoard(space: s).addNote('School closed Friday');
    await tester.pumpWidget(MaterialApp(theme: buildAppTheme(), home: Scaffold(body: FamilyScreen(space: s))));
    await tester.pumpAndSettle();
    expect(find.text('School closed Friday'), findsOneWidget);
    expect(find.byType(Card), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });
}
