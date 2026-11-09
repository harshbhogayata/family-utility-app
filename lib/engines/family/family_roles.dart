import 'package:flutter/foundation.dart';

import 'family_space.dart';
import 'family_store.dart';

/// Feature 070 — Family roles.
///
/// Every member is an adult, a child or a guest. Each role has read, write
/// or no access per section; the table lives in the family store's `roles`
/// collection so every phone applies the same rules. A child cannot see
/// money or the vault until an adult changes that.

enum FamilyRole {
  adult('Adult'),
  child('Child'),
  guest('Guest');

  const FamilyRole(this.label);
  final String label;

  static FamilyRole byName(Object? name) =>
      FamilyRole.values.firstWhere((FamilyRole r) => r.name == name, orElse: () => FamilyRole.adult);
}

enum SectionAccess {
  none('Hidden'),
  read('Read'),
  write('Edit');

  const SectionAccess(this.label);
  final String label;

  static SectionAccess? byName(Object? name) {
    for (final SectionAccess a in SectionAccess.values) {
      if (a.name == name) {
        return a;
      }
    }
    return null;
  }
}

/// The sections roles cover.
abstract final class FamilySections {
  static const String calendar = 'calendar';
  static const String shopping = 'shopping';
  static const String contacts = 'contacts';
  static const String board = 'board';
  static const String documents = 'documents';
  static const String location = 'location';
  static const String money = 'money';
  static const String vault = 'vault';

  static const Map<String, String> labels = <String, String>{
    calendar: 'Calendar',
    shopping: 'Shopping list',
    contacts: 'Contacts',
    board: 'To-do and notices',
    documents: 'Documents',
    location: 'Location',
    money: 'Money',
    vault: 'Vault',
  };

  static List<String> get all => labels.keys.toList();
}

class FamilyRoles extends ChangeNotifier {
  FamilyRoles({FamilySpace? space}) : _space = space;

  final FamilySpace? _space;
  FamilySpace get space => _space ?? FamilySpace.instance;
  FamilyStore get store => space.store;

  static const String collection = 'roles';
  static const String roleField = 'role';

  /// Rules before anyone changes them.
  static SectionAccess defaultAccess(FamilyRole role, String section) {
    switch (role) {
      case FamilyRole.adult:
        return SectionAccess.write;
      case FamilyRole.child:
        if (section == FamilySections.money || section == FamilySections.vault) {
          return SectionAccess.none;
        }
        if (section == FamilySections.documents || section == FamilySections.location) {
          return SectionAccess.read;
        }
        return SectionAccess.write;
      case FamilyRole.guest:
        if (section == FamilySections.calendar ||
            section == FamilySections.shopping ||
            section == FamilySections.contacts) {
          return SectionAccess.read;
        }
        return SectionAccess.none;
    }
  }

  /// A member's role. The family's first member is always an adult.
  FamilyRole roleOf(String memberId) {
    final FamilyRecord? m = store.get(FamilySpace.members, memberId);
    if (m == null) {
      return FamilyRole.guest;
    }
    return FamilyRole.byName(m.fields[roleField]);
  }

  FamilyRole get myRole {
    final String? me = space.identity?.deviceId;
    return me == null ? FamilyRole.adult : roleOf(me);
  }

  SectionAccess access(FamilyRole role, String section) {
    final FamilyRecord? r = store.get(collection, role.name);
    return SectionAccess.byName(r?.fields[section]) ?? defaultAccess(role, section);
  }

  bool canSee(String memberId, String section) => access(roleOf(memberId), section) != SectionAccess.none;
  bool canEdit(String memberId, String section) => access(roleOf(memberId), section) == SectionAccess.write;

  /// What this phone's member may do.
  bool iCanSee(String section) => access(myRole, section) != SectionAccess.none;
  bool iCanEdit(String section) => access(myRole, section) == SectionAccess.write;

  /// Only adults change roles and rules.
  bool get iManage => myRole == FamilyRole.adult;

  _Undo? _undo;

  /// Sets a member's role. False when not allowed or it would leave the
  /// family with no adult.
  bool setRole(String memberId, FamilyRole role) {
    final FamilyRecord? m = store.get(FamilySpace.members, memberId);
    if (m == null || !iManage) {
      return false;
    }
    final FamilyRole old = roleOf(memberId);
    if (old == role) {
      return false;
    }
    if (old == FamilyRole.adult) {
      final int adults = space.memberRecords.where((FamilyRecord r) => FamilyRole.byName(r.fields[roleField]) == FamilyRole.adult).length;
      if (adults <= 1) {
        return false;
      }
    }
    _undo = _Undo(FamilySpace.members, memberId, m.fields);
    store.put(FamilySpace.members, memberId, <String, Object?>{...m.fields, roleField: role.name});
    notifyListeners();
    return true;
  }

  /// Changes one cell of the table. Adults always keep write access.
  bool setAccess(FamilyRole role, String section, SectionAccess a) {
    if (!iManage || role == FamilyRole.adult || access(role, section) == a) {
      return false;
    }
    final FamilyRecord? r = store.get(collection, role.name);
    final Map<String, Object?> old = r?.fields ?? const <String, Object?>{};
    _undo = _Undo(collection, role.name, r == null ? null : old);
    store.put(collection, role.name, <String, Object?>{...old, section: a.name});
    notifyListeners();
    return true;
  }

  bool undo() {
    final _Undo? u = _undo;
    if (u == null) {
      return false;
    }
    _undo = null;
    final Map<String, Object?>? f = u.fields;
    if (f == null) {
      store.delete(u.collection, u.id);
    } else {
      store.put(u.collection, u.id, f);
    }
    notifyListeners();
    return true;
  }

  /// The table as text, for Share and Save.
  String toText() {
    final StringBuffer b = StringBuffer('Family roles\n');
    for (final FamilyRecord m in space.memberRecords) {
      b.writeln('${m.fields['name'] ?? 'Member'}: ${roleOf(m.id).label}');
    }
    for (final FamilyRole role in FamilyRole.values) {
      b.writeln();
      b.writeln(role.label);
      for (final String s in FamilySections.all) {
        b.writeln('  ${FamilySections.labels[s]}: ${access(role, s).label}');
      }
    }
    return b.toString();
  }

  static FamilyRoles? _instance;
  static FamilyRoles get instance => _instance ??= FamilyRoles();
  static void install(FamilyRoles r) => _instance = r;
}

class _Undo {
  _Undo(this.collection, this.id, this.fields);
  final String collection;
  final String id;
  final Map<String, Object?>? fields;
}
