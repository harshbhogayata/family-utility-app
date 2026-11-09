import 'package:family_utility_app/engines/family/family_identity.dart';
import 'package:family_utility_app/engines/family/family_roles.dart';
import 'package:family_utility_app/engines/family/family_space.dart';
import 'package:family_utility_app/engines/family/family_store.dart';
import 'package:family_utility_app/engines/family/family_sync.dart';
import 'package:family_utility_app/family/roles/family_roles_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

FamilySpace newSpace() => FamilySpace(
      identityStore: MemoryFamilyIdentityStore(),
      storage: MemoryFamilyStoreStorage(),
      transportsFor: (FamilyIdentity _) => <FamilySyncTransport>[],
    );

void main() {
  group('engine', () {
    test('defaults: child cannot see money or vault; guest reads a few sections', () async {
      final FamilySpace s = newSpace();
      await s.create(familyName: 'Shahs', memberName: 'Asha');
      final FamilyRoles r = FamilyRoles(space: s);
      expect(r.myRole, FamilyRole.adult);
      expect(r.iManage, isTrue);
      for (final String sec in FamilySections.all) {
        expect(r.access(FamilyRole.adult, sec), SectionAccess.write);
      }
      expect(r.access(FamilyRole.child, FamilySections.money), SectionAccess.none);
      expect(r.access(FamilyRole.child, FamilySections.vault), SectionAccess.none);
      expect(r.access(FamilyRole.child, FamilySections.shopping), SectionAccess.write);
      expect(r.access(FamilyRole.child, FamilySections.documents), SectionAccess.read);
      expect(r.access(FamilyRole.guest, FamilySections.calendar), SectionAccess.read);
      expect(r.access(FamilyRole.guest, FamilySections.money), SectionAccess.none);
    });

    test('roles per member, last adult kept, per-section rules, undo', () async {
      final FamilySpace s = newSpace();
      final FamilyIdentity me = await s.create(familyName: 'Shahs', memberName: 'Asha');
      s.store.put(FamilySpace.members, 'kid', <String, Object?>{'name': 'Riya'});
      s.store.put(FamilySpace.members, 'aunt', <String, Object?>{'name': 'Meena'});
      final FamilyRoles r = FamilyRoles(space: s);

      expect(r.setRole('kid', FamilyRole.child), isTrue);
      expect(r.setRole('aunt', FamilyRole.guest), isTrue);
      expect(r.roleOf('kid'), FamilyRole.child);
      expect(r.canSee('kid', FamilySections.money), isFalse);
      expect(r.canSee('kid', FamilySections.calendar), isTrue);
      expect(r.canEdit('aunt', FamilySections.shopping), isFalse);
      expect(r.canSee('aunt', FamilySections.shopping), isTrue);
      expect(r.canEdit(me.deviceId, FamilySections.vault), isTrue);
      expect(r.setRole(me.deviceId, FamilyRole.child), isFalse, reason: 'last adult');
      expect(r.setRole('nobody', FamilyRole.child), isFalse);

      expect(r.setAccess(FamilyRole.child, FamilySections.money, SectionAccess.read), isTrue);
      expect(r.canSee('kid', FamilySections.money), isTrue);
      expect(r.canEdit('kid', FamilySections.money), isFalse);
      expect(r.setAccess(FamilyRole.adult, FamilySections.money, SectionAccess.none), isFalse);
      expect(r.undo(), isTrue);
      expect(r.canSee('kid', FamilySections.money), isFalse);
      expect(r.undo(), isFalse);

      // The rules travel with the family store, so another phone agrees.
      final FamilyStore other = FamilyStore(deviceId: 'other');
      other.mergeAll(s.store.allRecords);
      final FamilySpace twin = newSpace();
      await twin.create(familyName: 'x', memberName: 'y');
      twin.store.mergeAll(s.store.allRecords);
      expect(FamilyRoles(space: twin).roleOf('kid'), FamilyRole.child);

      expect(r.toText(), contains('Riya: Child'));
      expect(r.toText(), contains('Money: Hidden'));
    });
  });

  testWidgets('screen: change a role and a rule, undo, controls are 44 px', (WidgetTester tester) async {
    final SemanticsHandle sem = tester.ensureSemantics();
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final FamilySpace s = newSpace();
    await s.create(familyName: 'Shahs', memberName: 'Asha');
    s.store.put(FamilySpace.members, 'kid', <String, Object?>{'name': 'Riya'});
    final FamilyRoles r = FamilyRoles(space: s);
    String? shared;
    await tester.pumpWidget(MaterialApp(
      home: FamilyRolesScreen(roles: r, share: (String t) async => shared = t, save: (String _) async => '/x'),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Riya'), findsOneWidget);

    await tester.tap(find.byKey(const Key('role-kid')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Child').last);
    await tester.pumpAndSettle();
    expect(r.roleOf('kid'), FamilyRole.child);

    final Finder money = find.byKey(const Key('access-child-money'));
    await tester.ensureVisible(money);
    expect(tester.getSize(money).height, greaterThanOrEqualTo(44));
    await tester.tap(money);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Read').last);
    await tester.pumpAndSettle();
    expect(r.access(FamilyRole.child, FamilySections.money), SectionAccess.read);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(r.access(FamilyRole.child, FamilySections.money), SectionAccess.none);

    await tester.tap(find.text('Share'));
    await tester.pumpAndSettle();
    expect(shared, contains('Riya: Child'));
    await tester.pumpAndSettle(const Duration(seconds: 5));
    sem.dispose();
  });
}
