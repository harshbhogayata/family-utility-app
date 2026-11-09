import 'dart:convert';

import 'package:family_utility_app/app/theme.dart';
import 'package:family_utility_app/engines/family/change_log.dart';
import 'package:family_utility_app/engines/family/family_space.dart';
import 'package:family_utility_app/engines/family/family_store.dart';
import 'package:family_utility_app/family/changes/change_log_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

FamilyStore phone(String id, String name, {int start = 1000}) {
  int t = start;
  final FamilyStore s = FamilyStore(
    deviceId: id,
    now: () => DateTime.fromMillisecondsSinceEpoch(t += 1000),
    saveDelay: Duration.zero,
  );
  s.put(FamilySpace.members, id, <String, Object?>{'name': name});
  return s;
}

void main() {
  group('engine', () {
    test('every change keeps author and time; capped at the last 20', () {
      final FamilyStore a = phone('dev-a', 'Asha');
      for (int i = 0; i < 30; i++) {
        a.put('shopping', 'milk', <String, Object?>{'name': 'Milk', 'qty': '$i'});
      }
      final FamilyRecord r = a.raw('shopping', 'milk')!;
      expect(r.history.length, FamilyRecord.keepChanges);
      final List<ChangeLogEntry> log = ChangeLog(a).forRecord('shopping', 'milk');
      expect(log.length, FamilyRecord.keepChanges);
      expect(log.first.state.fields['qty'], '29');
      expect(log.first.before!.fields['qty'], '28');
      expect(log.first.author, 'Asha');
      expect(log.first.kind, ChangeKind.changed);
      expect(log.first.line, 'Asha changed Milk in Shopping');
      expect(log.first.at.millisecondsSinceEpoch, r.wallMillis);
      // Newest first, strictly ordered.
      for (int i = 1; i < log.length; i++) {
        expect(log[i].state.wallMillis, lessThan(log[i - 1].state.wallMillis));
      }
    });

    test('add, change and remove read as such; undo puts each back', () {
      final FamilyStore a = phone('dev-a', 'Asha');
      final ChangeLog log = ChangeLog(a);
      a.put('board', 'n1', <String, Object?>{'title': 'Pay rent'});
      a.put('board', 'n1', <String, Object?>{'title': 'Pay rent by 5th'});
      a.delete('board', 'n1');
      List<ChangeLogEntry> e = log.forRecord('board', 'n1');
      expect(e.map((ChangeLogEntry x) => x.kind).toList(),
          <ChangeKind>[ChangeKind.removed, ChangeKind.changed, ChangeKind.added]);
      expect(e.first.label, 'Pay rent by 5th');

      // Undo the removal: the note comes back as it was.
      expect(log.undo(e.first), isTrue);
      expect(a.get('board', 'n1')!.fields['title'], 'Pay rent by 5th');

      // Undo the edit: back to the first wording.
      e = log.forRecord('board', 'n1');
      final ChangeLogEntry edit = e.firstWhere((ChangeLogEntry x) => x.kind == ChangeKind.changed);
      expect(log.undo(edit), isTrue);
      expect(a.get('board', 'n1')!.fields['title'], 'Pay rent');

      // Undo the add: gone again. The undo itself is in the log.
      final ChangeLogEntry added = log.forRecord('board', 'n1').last;
      expect(added.kind, ChangeKind.added);
      expect(log.undo(added), isTrue);
      expect(a.get('board', 'n1'), isNull);
      expect(log.forRecord('board', 'n1').first.kind, ChangeKind.removed);
      expect(log.undo(added), isFalse);
    });

    test('history and authors travel between phones and merge', () {
      final FamilyStore a = phone('dev-a', 'Asha');
      final FamilyStore b = phone('dev-b', 'Bala', start: 500000);
      b.mergeAll(a.allRecords);
      a.mergeAll(b.allRecords);
      a.put('shopping', 'eggs', <String, Object?>{'name': 'Eggs'});
      b.mergeAll(a.allRecords);
      b.put('shopping', 'eggs', <String, Object?>{'name': 'Eggs', 'done': true});
      a.mergeAll(b.allRecords);

      final List<ChangeLogEntry> onA = ChangeLog(a).forRecord('shopping', 'eggs');
      expect(onA.map((ChangeLogEntry e) => e.author).toList(), <String>['Bala', 'Asha']);
      expect(onA.first.line, 'Bala changed Eggs in Shopping');

      // Two offline edits: the loser is kept in the log, not lost.
      a.put('shopping', 'eggs', <String, Object?>{'name': 'Eggs x12'});
      b.put('shopping', 'eggs', <String, Object?>{'name': 'Brown eggs'});
      a.mergeAll(b.allRecords);
      b.mergeAll(a.allRecords);
      final List<String> namesA =
          ChangeLog(a).forRecord('shopping', 'eggs').map((ChangeLogEntry e) => '${e.state.fields['name']}').toList();
      final List<String> namesB =
          ChangeLog(b).forRecord('shopping', 'eggs').map((ChangeLogEntry e) => '${e.state.fields['name']}').toList();
      expect(namesA, namesB);
      expect(namesA, containsAll(<String>['Eggs x12', 'Brown eggs']));

      // The wire format round-trips the history.
      final FamilyRecord r = a.raw('shopping', 'eggs')!;
      final FamilyRecord back =
          FamilyRecord.fromJson(jsonDecode(jsonEncode(r.toJson())) as Map<String, Object?>);
      expect(back.history.length, r.history.length);
      expect(back.history.first.writer, r.history.first.writer);

      // A record from an older phone (no history) still reads.
      final FamilyRecord old = FamilyRecord.fromJson(<String, Object?>{
        'c': 'x',
        'i': '1',
        'f': <String, Object?>{'name': 'Old'},
        'v': <String, Object?>{},
        'w': 1,
        'd': 'z',
      });
      expect(old.history, isEmpty);
    });

    test('family-wide log is newest first and describes itself', () {
      final FamilyStore a = phone('dev-a', 'Asha');
      a.put('calendar', 'e1', <String, Object?>{'title': 'Dentist'});
      a.put('contacts', 'c1', <String, Object?>{'name': 'Plumber'});
      final List<ChangeLogEntry> all = ChangeLog(a).all();
      expect(all.first.label, 'Plumber');
      expect(all[1].label, 'Dentist');
      final String text = ChangeLog(a).describe();
      expect(text, contains('Asha added Plumber in Contacts'));
      expect(text, contains('Asha added Dentist in Calendar'));
    });
  });

  group('screen', () {
    testWidgets('lists changes, undoes one, shares and saves', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1000, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final FamilyStore a = phone('dev-a', 'Asha');
      a.put('shopping', 'milk', <String, Object?>{'name': 'Milk'});
      a.put('shopping', 'milk', <String, Object?>{'name': 'Milk', 'done': true});
      final List<String> shared = <String>[];
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: ChangeLogScreen(
          store: a,
          share: (String t) async {
            shared.add(t);
            return null;
          },
          save: (String t) async => '/docs/Family change log.txt',
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Asha changed Milk in Shopping'), findsOneWidget);
      expect(find.text('Asha added Milk in Shopping'), findsOneWidget);
      expect(find.byTooltip('Undo: Asha changed Milk'), findsOneWidget);

      await tester.tap(find.byKey(const Key('undo-change-0')));
      await tester.pumpAndSettle();
      expect(a.get('shopping', 'milk')!.fields['done'], isNull);
      expect(find.text('Put back: Milk'), findsOneWidget);
      expect(tester.getSize(find.byKey(const Key('undo-change-0'))).height, greaterThanOrEqualTo(44));

      await tester.tap(find.byKey(const Key('result-share')));
      await tester.pumpAndSettle();
      expect(shared.single, contains('Asha changed Milk in Shopping'));

      await tester.tap(find.byKey(const Key('result-save')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Saved to'), findsOneWidget);

      // The bar's Undo takes back the newest change (the undo just made).
      await tester.tap(find.byKey(const Key('result-undo')));
      await tester.pumpAndSettle();
      expect(a.get('shopping', 'milk')!.fields['done'], true);
      await tester.pump(const Duration(seconds: 1));
    });
  });
}
