import 'dart:async';

import 'package:flutter/foundation.dart';

import '../family/family_space.dart';
import '../family/family_store.dart';

/// Feature 095 — Birthdays and anniversaries.
///
/// Dates typed in or read from the phone's contacts, kept in the family
/// store so the whole family sees them; a reminder 7 days and 1 day ahead;
/// gift ideas attached to each person; and a drafted wish to send. Nothing
/// is uploaded.

enum OccasionKind {
  birthday('Birthday'),
  anniversary('Anniversary');

  const OccasionKind(this.label);
  final String label;

  static OccasionKind byName(Object? n) =>
      OccasionKind.values.firstWhere((OccasionKind k) => k.name == n, orElse: () => OccasionKind.birthday);
}

class Occasion {
  const Occasion({
    required this.id,
    required this.name,
    required this.kind,
    required this.month,
    required this.day,
    this.year,
    this.gifts = const <String>[],
    this.phone = '',
  });

  final String id;
  final String name;
  final OccasionKind kind;
  final int month;
  final int day;

  /// Year of birth or of the wedding, when known.
  final int? year;
  final List<String> gifts;
  final String phone;

  /// The next date on or after [from]'s day. 29 February falls on
  /// 28 February in other years.
  DateTime nextFrom(DateTime from) {
    final DateTime today = DateTime(from.year, from.month, from.day);
    DateTime on(int y) {
      final DateTime d = DateTime(y, month, day);
      return d.month == month ? d : DateTime(y, month + 1, 0);
    }

    final DateTime d = on(today.year);
    return d.isBefore(today) ? on(today.year + 1) : d;
  }

  /// Age or years married on [on], when the year is known.
  int? yearsOn(DateTime on) => year == null ? null : on.year - year!;

  Map<String, Object?> toFields() => <String, Object?>{
        'name': name,
        'kind': kind.name,
        'month': month,
        'day': day,
        if (year != null) 'year': year,
        'gifts': gifts,
        if (phone.isNotEmpty) 'phone': phone,
      };

  static Occasion fromRecord(FamilyRecord r) {
    final Map<String, Object?> f = r.fields;
    int intOf(Object? o, int d) => o is num ? o.toInt() : d;
    final Object? y = f['year'];
    final Object? g = f['gifts'];
    return Occasion(
      id: r.id,
      name: '${f['name'] ?? ''}',
      kind: OccasionKind.byName(f['kind']),
      month: intOf(f['month'], 1),
      day: intOf(f['day'], 1),
      year: y is num ? y.toInt() : null,
      gifts: g is List ? g.whereType<String>().toList() : const <String>[],
      phone: '${f['phone'] ?? ''}',
    );
  }

  Occasion withGifts(List<String> next) =>
      Occasion(id: id, name: name, kind: kind, month: month, day: day, year: year, gifts: next, phone: phone);
}

/// A date read from a phone contact.
class ContactDate {
  const ContactDate({required this.name, required this.kind, required this.month, required this.day, this.year, this.phone = ''});
  final String name;
  final OccasionKind kind;
  final int month;
  final int day;
  final int? year;
  final String phone;
}

/// Reads birthdays and anniversaries from the phone's contacts.
abstract interface class ContactDatesSource {
  Future<List<ContactDate>> read();
}

class NoContactDates implements ContactDatesSource {
  const NoContactDates();
  @override
  Future<List<ContactDate>> read() async => const <ContactDate>[];
}

/// A reminder the platform should show.
class OccasionReminder {
  const OccasionReminder({required this.id, required this.at, required this.title, required this.body, required this.payload});
  final int id;
  final DateTime at;
  final String title;
  final String body;
  final String payload;
}

abstract interface class OccasionReminderScheduler {
  Future<void> replaceAll(List<OccasionReminder> reminders);
}

class NoOccasionReminders implements OccasionReminderScheduler {
  const NoOccasionReminders();
  @override
  Future<void> replaceAll(List<OccasionReminder> reminders) async {}
}

class Occasions extends ChangeNotifier {
  Occasions({
    FamilySpace? space,
    FamilyStore? soloStore,
    OccasionReminderScheduler reminders = const NoOccasionReminders(),
    ContactDatesSource contacts = const NoContactDates(),
    DateTime Function()? now,
    this.remindHour = 9,
  })  : _space = space,
        _solo = soloStore,
        _scheduler = reminders,
        _contacts = contacts,
        _now = now ?? DateTime.now;

  static const String collection = 'occasions';
  static const String payloadPrefix = 'occ:';
  static const int idBase = 950000;
  static const List<int> daysAhead = <int>[7, 1];

  final FamilySpace? _space;
  final FamilyStore? _solo;
  final OccasionReminderScheduler _scheduler;
  final ContactDatesSource _contacts;
  final DateTime Function() _now;
  final int remindHour;
  int _seq = 0;

  FamilySpace get space => _space ?? FamilySpace.instance;
  FamilyStore get store => space.inFamily ? space.store : (_solo ?? space.store);

  List<Occasion> get all => store.list(collection).map(Occasion.fromRecord).toList();

  Occasion? byId(String id) {
    final FamilyRecord? r = store.get(collection, id);
    return r == null ? null : Occasion.fromRecord(r);
  }

  /// Everything, soonest first from today.
  List<Occasion> get upcoming {
    final DateTime now = _now();
    return all
      ..sort((Occasion a, Occasion b) {
        final int c = a.nextFrom(now).compareTo(b.nextFrom(now));
        return c != 0 ? c : a.name.compareTo(b.name);
      });
  }

  int daysUntil(Occasion o) {
    final DateTime n = _now();
    final DateTime today = DateTime(n.year, n.month, n.day);
    final DateTime next = o.nextFrom(today);
    return DateTime.utc(next.year, next.month, next.day).difference(DateTime.utc(today.year, today.month, today.day)).inDays;
  }

  final List<(String, Map<String, Object?>?)> _undo = <(String, Map<String, Object?>?)>[];

  void _remember(Iterable<String> ids) {
    _undo
      ..clear()
      ..addAll(ids.map((String id) => (id, store.get(collection, id)?.fields)));
  }

  void _changed() {
    notifyListeners();
    unawaited(reschedule());
  }

  static bool validDate(int month, int day) {
    if (month < 1 || month > 12 || day < 1) {
      return false;
    }
    return day <= DateTime(2024, month + 1, 0).day; // 2024 is a leap year
  }

  Occasion? add({required String name, required OccasionKind kind, required int month, required int day, int? year, String phone = '', List<String> gifts = const <String>[]}) {
    if (name.trim().isEmpty || !validDate(month, day) || (year != null && (year < 1900 || year > _now().year))) {
      return null;
    }
    final String id = 'o${_now().microsecondsSinceEpoch}-${_seq++}';
    final Occasion o = Occasion(id: id, name: name.trim(), kind: kind, month: month, day: day, year: year, gifts: gifts, phone: phone);
    _remember(<String>[id]);
    store.put(collection, id, o.toFields());
    _changed();
    return o;
  }

  bool remove(String id) {
    if (byId(id) == null) {
      return false;
    }
    _remember(<String>[id]);
    store.delete(collection, id);
    _changed();
    return true;
  }

  bool addGift(String id, String idea) {
    final Occasion? o = byId(id);
    if (o == null || idea.trim().isEmpty) {
      return false;
    }
    _remember(<String>[id]);
    store.put(collection, id, o.withGifts(<String>[...o.gifts, idea.trim()]).toFields());
    _changed();
    return true;
  }

  bool removeGift(String id, int index) {
    final Occasion? o = byId(id);
    if (o == null || index < 0 || index >= o.gifts.length) {
      return false;
    }
    _remember(<String>[id]);
    store.put(collection, id, o.withGifts(List<String>.of(o.gifts)..removeAt(index)).toFields());
    _changed();
    return true;
  }

  /// Adds contacts' dates that are not here yet (same name and kind).
  /// Returns how many were added; one undo removes them all.
  Future<int> importFromContacts() async {
    final List<ContactDate> found = await _contacts.read();
    final Set<String> have = all.map((Occasion o) => '${o.name.toLowerCase()}|${o.kind.name}').toSet();
    final List<String> added = <String>[];
    final List<(String, Map<String, Object?>)> puts = <(String, Map<String, Object?>)>[];
    for (final ContactDate c in found) {
      final String key = '${c.name.trim().toLowerCase()}|${c.kind.name}';
      if (c.name.trim().isEmpty || !validDate(c.month, c.day) || have.contains(key)) {
        continue;
      }
      have.add(key);
      final String id = 'o${_now().microsecondsSinceEpoch}-${_seq++}';
      added.add(id);
      puts.add((id, Occasion(id: id, name: c.name.trim(), kind: c.kind, month: c.month, day: c.day, year: c.year, phone: c.phone).toFields()));
    }
    if (puts.isEmpty) {
      return 0;
    }
    _remember(added);
    for (final (String, Map<String, Object?>) p in puts) {
      store.put(collection, p.$1, p.$2);
    }
    _changed();
    return puts.length;
  }

  bool undo() {
    if (_undo.isEmpty) {
      return false;
    }
    for (final (String, Map<String, Object?>?) u in _undo) {
      if (u.$2 == null) {
        store.delete(collection, u.$1);
      } else {
        store.put(collection, u.$1, u.$2!);
      }
    }
    _undo.clear();
    _changed();
    return true;
  }

  static String ordinal(int n) {
    final int t = n % 100;
    if (t >= 11 && t <= 13) {
      return '${n}th';
    }
    switch (n % 10) {
      case 1:
        return '${n}st';
      case 2:
        return '${n}nd';
      case 3:
        return '${n}rd';
      default:
        return '${n}th';
    }
  }

  /// A short wish to send or edit.
  String draftWish(Occasion o) {
    final DateTime on = o.nextFrom(_now());
    final int? years = o.yearsOn(on);
    final String nth = years != null && years > 0 ? '${ordinal(years)} ' : '';
    final String first = o.name.split(' ').first;
    if (o.kind == OccasionKind.birthday) {
      return 'Happy ${nth}birthday, $first! Wishing you good health, lots of laughter and a wonderful year ahead.';
    }
    return 'Happy ${nth}anniversary, $first! Wishing you both many more years of love and togetherness.';
  }

  static int _id(String key) {
    int h = 0;
    for (final int c in key.codeUnits) {
      h = (h * 31 + c) & 0x3FFFF;
    }
    return idBase + h;
  }

  /// Reminders 7 days and 1 day before each next date, at [remindHour],
  /// that are still ahead, soonest first.
  List<OccasionReminder> reminders() {
    final DateTime now = _now();
    final List<OccasionReminder> out = <OccasionReminder>[];
    for (final Occasion o in all) {
      final DateTime next = o.nextFrom(now);
      for (final int d in daysAhead) {
        final DateTime at = DateTime(next.year, next.month, next.day - d, remindHour);
        if (!at.isAfter(now)) {
          continue;
        }
        final String when = d == 1 ? 'tomorrow' : 'in $d days';
        final List<String> gifts = o.gifts;
        out.add(OccasionReminder(
          id: _id('${o.id}@$d'),
          at: at,
          title: "${o.name}'s ${o.kind.label.toLowerCase()} $when",
          body: gifts.isEmpty ? 'Tap to draft a wish' : 'Gift ideas: ${gifts.join(', ')}',
          payload: '$payloadPrefix${o.id}',
        ));
      }
    }
    out.sort((OccasionReminder a, OccasionReminder b) => a.at.compareTo(b.at));
    return out;
  }

  Future<void> reschedule() async {
    try {
      await _scheduler.replaceAll(reminders());
    } catch (e) {
      debugPrint('occasion reminders: $e');
    }
  }

  static const List<String> months = <String>['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  static String dateLabel(Occasion o) => '${o.day} ${months[o.month - 1]}${o.year == null ? '' : ' ${o.year}'}';

  /// Plain-text list of the next dates, to share.
  String toText() {
    final StringBuffer b = StringBuffer('Birthdays and anniversaries\n');
    for (final Occasion o in upcoming) {
      b.write('- ${dateLabel(o)}: ${o.name} (${o.kind.label})${o.gifts.isEmpty ? '' : ' · gifts: ${o.gifts.join(', ')}'}\n');
    }
    return b.toString();
  }

  static Occasions instance = Occasions();
  static void install(Occasions o) => instance = o;
}
