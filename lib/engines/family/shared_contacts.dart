import 'package:flutter/foundation.dart';

import '../platform/home_widgets.dart';
import 'family_space.dart';
import 'family_store.dart';

/// Feature 075 — Shared contacts.
///
/// Plumber, electrician, doctor, neighbour: kept in the family store's
/// `contacts` collection so every family phone has the same list. Up to
/// three can be pinned to the speed-dial row of the home widget (112).
/// Nothing leaves the family's phones; Call and WhatsApp hand the number to
/// the phone's own apps.

abstract final class ContactTags {
  static const String other = 'Other';

  static const List<String> presets = <String>[
    'Family', 'Doctor', 'Plumber', 'Electrician', 'Neighbour', 'School', 'Emergency', other, //
  ];
}

@immutable
class SharedContact {
  const SharedContact({
    required this.id,
    required this.name,
    required this.phone,
    required this.tags,
    required this.speedDial,
    required this.addedBy,
  });

  final String id;
  final String name;
  final String phone;
  final List<String> tags;
  final bool speedDial;
  final String addedBy;

  /// Digits with a leading + kept, as the dialler wants.
  String get dialable => SpeedDialEntry(label: name, number: phone).dialable;

  /// tel: link for one-tap call.
  Uri get callUri => Uri(scheme: 'tel', path: dialable);

  /// wa.me link. A 10-digit number without a country code is taken as an
  /// Indian mobile (+91), the app's home market.
  Uri get whatsAppUri {
    String d = dialable.replaceAll('+', '');
    if (!dialable.startsWith('+') && d.length == 10) {
      d = '91$d';
    }
    if (d.startsWith('0') && d.length == 11) {
      d = '91${d.substring(1)}';
    }
    return Uri.parse('https://wa.me/$d');
  }

  Map<String, Object?> toFields() => <String, Object?>{
        'name': name,
        'phone': phone,
        'tags': tags,
        if (speedDial) 'speedDial': true,
        'by': addedBy,
      };

  static SharedContact fromRecord(FamilyRecord r) {
    final Map<String, Object?> f = r.fields;
    final Object? t = f['tags'];
    final List<String> tags = <String>[
      if (t is List)
        for (final Object? x in t)
          if (x is String && x.isNotEmpty) x,
    ];
    return SharedContact(
      id: r.id,
      name: '${f['name'] ?? ''}',
      phone: '${f['phone'] ?? ''}',
      tags: tags.isEmpty ? const <String>[ContactTags.other] : tags,
      speedDial: f['speedDial'] == true,
      addedBy: '${f['by'] ?? r.writer}',
    );
  }
}

/// Why an add or pin did not happen.
enum ContactOutcome { added, missingName, badNumber, duplicate, speedDialFull }

class SharedContacts extends ChangeNotifier {
  SharedContacts({FamilySpace? space, DateTime Function()? now})
      : _space = space,
        _now = now ?? DateTime.now;

  static const String collection = 'contacts';

  final FamilySpace? _space;
  final DateTime Function() _now;
  int _seq = 0;
  Map<String, Map<String, Object?>?>? _undo;

  FamilySpace get space => _space ?? FamilySpace.instance;
  FamilyStore get store => space.store;
  String get me => space.identity?.deviceId ?? 'local';
  bool get canUndo => _undo != null;

  /// Sorted by name.
  List<SharedContact> get contacts {
    final List<SharedContact> out = store.list(collection).map(SharedContact.fromRecord).toList()
      ..sort((SharedContact a, SharedContact b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return out;
  }

  SharedContact? contact(String id) {
    final FamilyRecord? r = store.get(collection, id);
    return r == null ? null : SharedContact.fromRecord(r);
  }

  /// Every tag in use, presets first.
  List<String> get tagsInUse {
    final Set<String> used = <String>{for (final SharedContact c in contacts) ...c.tags};
    return <String>[
      for (final String t in ContactTags.presets)
        if (used.contains(t)) t,
      ...(used.where((String t) => !ContactTags.presets.contains(t)).toList()..sort()),
    ];
  }

  /// Contacts with [tag] (all when null) whose name, number or tag matches
  /// [query].
  List<SharedContact> filter({String? tag, String query = ''}) {
    final String q = query.trim().toLowerCase();
    return contacts.where((SharedContact c) {
      if (tag != null && !c.tags.contains(tag)) {
        return false;
      }
      if (q.isEmpty) {
        return true;
      }
      final String digits = q.replaceAll(RegExp(r'[^0-9]'), '');
      return c.name.toLowerCase().contains(q) ||
          (digits.length >= 3 && c.dialable.contains(digits)) ||
          c.tags.any((String t) => t.toLowerCase().contains(q));
    }).toList();
  }

  List<SharedContact> get speedDial => contacts.where((SharedContact c) => c.speedDial).toList();

  /// The pinned contacts as the widget's speed-dial row.
  List<SpeedDialEntry> get speedDialEntries => <SpeedDialEntry>[
        for (final SharedContact c in speedDial) SpeedDialEntry(label: c.name, number: c.dialable),
      ];

  ContactOutcome add(String name, String phone, {List<String> tags = const <String>[], bool speedDial = false}) {
    final String n = name.trim();
    if (n.isEmpty) {
      return ContactOutcome.missingName;
    }
    final SpeedDialEntry probe = SpeedDialEntry(label: n, number: phone);
    if (!probe.isValid) {
      return ContactOutcome.badNumber;
    }
    if (contacts.any((SharedContact c) => c.dialable == probe.dialable)) {
      return ContactOutcome.duplicate;
    }
    if (speedDial && this.speedDial.length >= WidgetSnapshot.maxSpeedDial) {
      return ContactOutcome.speedDialFull;
    }
    final List<String> clean = <String>[
      for (final String t in tags)
        if (t.trim().isNotEmpty) t.trim(),
    ];
    final DateTime t = _now();
    final SharedContact c = SharedContact(
      id: '$me-${t.microsecondsSinceEpoch}-${_seq++}',
      name: n,
      phone: phone.trim(),
      tags: clean.isEmpty ? const <String>[ContactTags.other] : clean,
      speedDial: speedDial,
      addedBy: me,
    );
    _write(<String, Map<String, Object?>?>{c.id: c.toFields()});
    return ContactOutcome.added;
  }

  /// Pins or unpins for the widget; false when the row is full.
  bool setSpeedDial(String id, bool on) {
    final SharedContact? c = contact(id);
    if (c == null || c.speedDial == on) {
      return false;
    }
    if (on && speedDial.length >= WidgetSnapshot.maxSpeedDial) {
      return false;
    }
    final Map<String, Object?> f = Map<String, Object?>.of(c.toFields());
    if (on) {
      f['speedDial'] = true;
    } else {
      f.remove('speedDial');
    }
    _write(<String, Map<String, Object?>?>{id: f});
    return true;
  }

  bool remove(String id) {
    if (contact(id) == null) {
      return false;
    }
    _write(<String, Map<String, Object?>?>{id: null});
    return true;
  }

  bool undo() {
    final Map<String, Map<String, Object?>?>? u = _undo;
    if (u == null) {
      return false;
    }
    _undo = null;
    u.forEach(_set);
    notifyListeners();
    return true;
  }

  void _write(Map<String, Map<String, Object?>?> changes) {
    _undo = <String, Map<String, Object?>?>{
      for (final String id in changes.keys) id: store.get(collection, id)?.fields,
    };
    changes.forEach(_set);
    notifyListeners();
  }

  void _set(String id, Map<String, Object?>? fields) {
    if (fields == null) {
      store.delete(collection, id);
    } else {
      store.put(collection, id, fields);
    }
  }

  /// The list as plain text, grouped by tag.
  String toText() {
    final StringBuffer b = StringBuffer('Family contacts\n');
    for (final String tag in tagsInUse) {
      b.write('\n$tag\n');
      for (final SharedContact c in filter(tag: tag)) {
        b.write('${c.name}: ${c.phone}${c.speedDial ? ' (speed dial)' : ''}\n');
      }
    }
    return b.toString();
  }

  static SharedContacts instance = SharedContacts();

  static void install(SharedContacts c) => instance = c;
}
