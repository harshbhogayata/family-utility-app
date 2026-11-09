import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../security/secure_notes.dart';

/// Feature 096 — Saved addresses and autofill profile.
///
/// Name, date of birth, phone, email, any number of saved addresses and the
/// person's own extra fields (Aadhaar-style IDs stay in 057 Secure notes).
/// Everything is one AES-256-GCM blob through 057's [NoteCipher] and
/// [NoteBlobStore], so nothing leaves the phone. Values copy to the clipboard
/// in one tap (cleared after a short while), and [AutofillProfileBook.suggestionsFor]
/// maps a PDF form field name ("applicant_name", "DOB", "Pin Code") to the
/// right value for 009 Fill forms.

@immutable
class SavedAddress {
  const SavedAddress({
    required this.id,
    this.label = 'Home',
    this.line1 = '',
    this.line2 = '',
    this.city = '',
    this.state = '',
    this.pincode = '',
    this.country = 'India',
  });

  final String id;
  final String label;
  final String line1;
  final String line2;
  final String city;
  final String state;
  final String pincode;
  final String country;

  SavedAddress copyWith({
    String? label,
    String? line1,
    String? line2,
    String? city,
    String? state,
    String? pincode,
    String? country,
  }) =>
      SavedAddress(
        id: id,
        label: label ?? this.label,
        line1: line1 ?? this.line1,
        line2: line2 ?? this.line2,
        city: city ?? this.city,
        state: state ?? this.state,
        pincode: pincode ?? this.pincode,
        country: country ?? this.country,
      );

  bool get isEmpty =>
      line1.trim().isEmpty && line2.trim().isEmpty && city.trim().isEmpty && state.trim().isEmpty && pincode.trim().isEmpty;

  /// "12 MG Road, Indiranagar, Bengaluru, Karnataka 560038, India".
  String get oneLine {
    final String statePin = <String>[state.trim(), pincode.trim()].where((String s) => s.isNotEmpty).join(' ');
    return <String>[line1.trim(), line2.trim(), city.trim(), statePin, country.trim()]
        .where((String s) => s.isNotEmpty)
        .join(', ');
  }

  /// One part per line, as on an envelope.
  String get multiLine {
    final String cityLine = <String>[
      city.trim(),
      <String>[state.trim(), pincode.trim()].where((String s) => s.isNotEmpty).join(' '),
    ].where((String s) => s.isNotEmpty).join(', ');
    return <String>[line1.trim(), line2.trim(), cityLine, country.trim()].where((String s) => s.isNotEmpty).join('\n');
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'label': label,
        'line1': line1,
        'line2': line2,
        'city': city,
        'state': state,
        'pincode': pincode,
        'country': country,
      };

  static SavedAddress fromJson(Map<String, Object?> j) => SavedAddress(
        id: (j['id'] as String?) ?? SecureNotes.newId(),
        label: (j['label'] as String?) ?? 'Home',
        line1: (j['line1'] as String?) ?? '',
        line2: (j['line2'] as String?) ?? '',
        city: (j['city'] as String?) ?? '',
        state: (j['state'] as String?) ?? '',
        pincode: (j['pincode'] as String?) ?? '',
        country: (j['country'] as String?) ?? '',
      );

  @override
  bool operator ==(Object other) => other is SavedAddress && jsonEncode(toJson()) == jsonEncode(other.toJson());

  @override
  int get hashCode => jsonEncode(toJson()).hashCode;
}

/// A labelled value the person added themselves ("Father's name", "PAN").
@immutable
class CustomField {
  const CustomField({required this.label, required this.value});

  final String label;
  final String value;

  Map<String, Object?> toJson() => <String, Object?>{'label': label, 'value': value};

  static CustomField fromJson(Map<String, Object?> j) =>
      CustomField(label: (j['label'] as String?) ?? '', value: (j['value'] as String?) ?? '');

  @override
  bool operator ==(Object other) => other is CustomField && other.label == label && other.value == value;

  @override
  int get hashCode => Object.hash(label, value);
}

@immutable
class AutofillProfile {
  const AutofillProfile({
    this.firstName = '',
    this.middleName = '',
    this.lastName = '',
    this.dateOfBirth,
    this.phone = '',
    this.email = '',
    this.addresses = const <SavedAddress>[],
    this.custom = const <CustomField>[],
  });

  final String firstName;
  final String middleName;
  final String lastName;
  final DateTime? dateOfBirth;
  final String phone;
  final String email;
  final List<SavedAddress> addresses;
  final List<CustomField> custom;

  static const AutofillProfile empty = AutofillProfile();

  String get fullName =>
      <String>[firstName.trim(), middleName.trim(), lastName.trim()].where((String s) => s.isNotEmpty).join(' ');

  bool get isEmpty =>
      fullName.isEmpty &&
      dateOfBirth == null &&
      phone.trim().isEmpty &&
      email.trim().isEmpty &&
      addresses.every((SavedAddress a) => a.isEmpty) &&
      custom.isEmpty;

  /// The first address, or the one labelled [label] when given.
  SavedAddress? address([String? label]) {
    if (addresses.isEmpty) {
      return null;
    }
    if (label != null) {
      for (final SavedAddress a in addresses) {
        if (a.label.toLowerCase() == label.toLowerCase()) {
          return a;
        }
      }
    }
    return addresses.first;
  }

  AutofillProfile copyWith({
    String? firstName,
    String? middleName,
    String? lastName,
    DateTime? dateOfBirth,
    bool clearDateOfBirth = false,
    String? phone,
    String? email,
    List<SavedAddress>? addresses,
    List<CustomField>? custom,
  }) =>
      AutofillProfile(
        firstName: firstName ?? this.firstName,
        middleName: middleName ?? this.middleName,
        lastName: lastName ?? this.lastName,
        dateOfBirth: clearDateOfBirth ? null : (dateOfBirth ?? this.dateOfBirth),
        phone: phone ?? this.phone,
        email: email ?? this.email,
        addresses: addresses ?? this.addresses,
        custom: custom ?? this.custom,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'v': 1,
        'first': firstName,
        'middle': middleName,
        'last': lastName,
        'dob': dateOfBirth == null ? null : formatIsoDate(dateOfBirth!),
        'phone': phone,
        'email': email,
        'addresses': addresses.map((SavedAddress a) => a.toJson()).toList(),
        'custom': custom.map((CustomField c) => c.toJson()).toList(),
      };

  static AutofillProfile fromJson(Map<String, Object?> j) {
    final Object? dob = j['dob'];
    final Object? addrs = j['addresses'];
    final Object? cus = j['custom'];
    return AutofillProfile(
      firstName: (j['first'] as String?) ?? '',
      middleName: (j['middle'] as String?) ?? '',
      lastName: (j['last'] as String?) ?? '',
      dateOfBirth: dob is String ? DateTime.tryParse(dob) : null,
      phone: (j['phone'] as String?) ?? '',
      email: (j['email'] as String?) ?? '',
      addresses: addrs is List<Object?>
          ? addrs.whereType<Map<String, Object?>>().map(SavedAddress.fromJson).toList()
          : const <SavedAddress>[],
      custom: cus is List<Object?>
          ? cus.whereType<Map<String, Object?>>().map(CustomField.fromJson).toList()
          : const <CustomField>[],
    );
  }

  /// Every filled value, labelled, for the share / save text.
  String toPlainText() {
    final List<String> out = <String>[];
    void add(String label, String value) {
      if (value.trim().isNotEmpty) {
        out.add('$label: ${value.trim()}');
      }
    }

    add('Name', fullName);
    if (dateOfBirth != null) {
      add('Date of birth', formatDayMonthYear(dateOfBirth!));
    }
    add('Phone', phone);
    add('Email', email);
    for (final SavedAddress a in addresses) {
      add('${a.label} address', a.oneLine);
    }
    for (final CustomField c in custom) {
      add(c.label, c.value);
    }
    return out.join('\n');
  }

  @override
  bool operator ==(Object other) => other is AutofillProfile && jsonEncode(toJson()) == jsonEncode(other.toJson());

  @override
  int get hashCode => jsonEncode(toJson()).hashCode;
}

String _two(int n) => n.toString().padLeft(2, '0');

/// 1990-04-07
String formatIsoDate(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${_two(d.month)}-${_two(d.day)}';

/// 07/04/1990 — the way Indian forms ask for it.
String formatDayMonthYear(DateTime d) => '${_two(d.day)}/${_two(d.month)}/${d.year}';

/// What a form field can be filled with.
enum ProfileKey {
  fullName,
  firstName,
  middleName,
  lastName,
  dateOfBirth,
  phone,
  email,
  address,
  addressLine1,
  addressLine2,
  city,
  state,
  pincode,
  country,
}

/// One value offered for a form field, best first.
@immutable
class AutofillSuggestion {
  const AutofillSuggestion({required this.label, required this.value, this.key});

  final String label;
  final String value;

  /// Null for the person's own custom fields.
  final ProfileKey? key;

  @override
  bool operator ==(Object other) =>
      other is AutofillSuggestion && other.label == label && other.value == value && other.key == key;

  @override
  int get hashCode => Object.hash(label, value, key);

  @override
  String toString() => 'AutofillSuggestion($label: $value)';
}

/// Maps a form field's name or caption to a [ProfileKey]. Pure, so 009 and
/// tests can use it without a profile.
abstract final class FormFieldMatcher {
  static String normalise(String name) => name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  static bool _any(String n, List<String> parts) => parts.any(n.contains);

  /// Null when the field is about someone else (father, spouse, nominee) or
  /// is not something the profile knows.
  static ProfileKey? keyFor(String fieldName) {
    final String n = normalise(fieldName);
    if (n.isEmpty) {
      return null;
    }
    if (_any(n, <String>['father', 'mother', 'spouse', 'husband', 'wife', 'guardian', 'nominee', 'parent', 'emergency', 'reference', 'username', 'filename', 'company', 'employer', 'school', 'bank'])) {
      return null;
    }
    if (_any(n, <String>['email', 'mail'])) {
      return ProfileKey.email;
    }
    if (_any(n, <String>['dob', 'birth', 'dateofb'])) {
      return ProfileKey.dateOfBirth;
    }
    if (_any(n, <String>['phone', 'mobile', 'cell', 'contactno', 'contactnumber', 'whatsapp']) || n == 'tel' || n.startsWith('tel')) {
      return ProfileKey.phone;
    }
    if (_any(n, <String>['pincode', 'zip', 'postal', 'postcode']) || n == 'pin') {
      return ProfileKey.pincode;
    }
    if (_any(n, <String>['city', 'town', 'village'])) {
      return ProfileKey.city;
    }
    if (_any(n, <String>['state', 'province'])) {
      return ProfileKey.state;
    }
    if (n.contains('country') || n == 'nation') {
      return ProfileKey.country;
    }
    if (_any(n, <String>['line2', 'address2', 'addr2', 'locality', 'area'])) {
      return ProfileKey.addressLine2;
    }
    if (_any(n, <String>['line1', 'address1', 'addr1', 'street', 'house', 'flat'])) {
      return ProfileKey.addressLine1;
    }
    if (_any(n, <String>['address', 'addr', 'residence'])) {
      return ProfileKey.address;
    }
    if (_any(n, <String>['firstname', 'givenname', 'forename']) || n == 'fname') {
      return ProfileKey.firstName;
    }
    if (n.contains('middlename') || n == 'mname') {
      return ProfileKey.middleName;
    }
    if (_any(n, <String>['lastname', 'surname', 'familyname']) || n == 'lname') {
      return ProfileKey.lastName;
    }
    if (n.contains('name')) {
      return ProfileKey.fullName;
    }
    return null;
  }
}

/// Where the profile blob lives; 057's key store and cipher protect it.
class AutofillProfileBook extends ChangeNotifier {
  AutofillProfileBook({
    required KeyStore keyStore,
    required NoteBlobStore blobStore,
    required ClipboardSink clipboard,
    this.clearClipboardAfter = const Duration(seconds: 60),
  })  : _cipher = NoteCipher(keyStore),
        _blobs = blobStore,
        _clipboard = clipboard;

  final NoteCipher _cipher;
  final NoteBlobStore _blobs;
  final ClipboardSink _clipboard;
  final Duration clearClipboardAfter;

  AutofillProfile _profile = AutofillProfile.empty;
  final List<AutofillProfile> _undo = <AutofillProfile>[];
  bool _loaded = false;
  String? _loadError;
  Timer? _clearTimer;
  String? _lastCopied;

  AutofillProfile get profile => _profile;
  bool get isLoaded => _loaded;
  String? get loadError => _loadError;
  bool get canUndo => _undo.isNotEmpty;

  Future<void> load() async {
    try {
      final String? blob = await _blobs.read();
      if (blob != null && blob.isNotEmpty) {
        final Object? parsed = jsonDecode(await _cipher.decrypt(blob));
        if (parsed is Map<String, Object?>) {
          _profile = AutofillProfile.fromJson(parsed);
        }
      }
      _loadError = null;
    } catch (e) {
      _loadError = 'Could not read the profile on this phone: $e';
      _profile = AutofillProfile.empty;
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> _persist() async {
    await _blobs.write(await _cipher.encrypt(jsonEncode(_profile.toJson())));
    notifyListeners();
  }

  /// Replaces the profile; the old one can come back with [undo].
  Future<void> save(AutofillProfile next) async {
    if (next == _profile) {
      return;
    }
    _undo.add(_profile);
    if (_undo.length > 20) {
      _undo.removeAt(0);
    }
    _profile = next;
    await _persist();
  }

  Future<SavedAddress> addAddress({String label = 'Home'}) async {
    final SavedAddress a = SavedAddress(id: SecureNotes.newId(), label: label);
    await save(_profile.copyWith(addresses: <SavedAddress>[..._profile.addresses, a]));
    return a;
  }

  Future<void> putAddress(SavedAddress address) async {
    final List<SavedAddress> list = List<SavedAddress>.of(_profile.addresses);
    final int i = list.indexWhere((SavedAddress a) => a.id == address.id);
    if (i < 0) {
      list.add(address);
    } else {
      list[i] = address;
    }
    await save(_profile.copyWith(addresses: list));
  }

  Future<void> removeAddress(String id) =>
      save(_profile.copyWith(addresses: _profile.addresses.where((SavedAddress a) => a.id != id).toList()));

  /// Puts back the profile from before the last change.
  Future<bool> undo() async {
    if (_undo.isEmpty) {
      return false;
    }
    _profile = _undo.removeLast();
    await _persist();
    return true;
  }

  /// One-tap copy; cleared after [clearClipboardAfter] unless something else
  /// was copied since.
  Future<void> copy(String value) async {
    await _clipboard.set(value);
    _lastCopied = value;
    _clearTimer?.cancel();
    _clearTimer = Timer(clearClipboardAfter, () {
      unawaited(_clearIfStillOurs());
    });
  }

  Future<void> _clearIfStillOurs() async {
    final String? current = await _clipboard.get();
    if (current != null && current == _lastCopied) {
      await _clipboard.clear();
    }
    _lastCopied = null;
  }

  /// The profile value for [key], from the address labelled [addressLabel]
  /// (or the first) for address parts. Empty when not filled in.
  String valueOf(ProfileKey key, {String? addressLabel}) {
    final AutofillProfile p = _profile;
    final SavedAddress? a = p.address(addressLabel);
    switch (key) {
      case ProfileKey.fullName:
        return p.fullName;
      case ProfileKey.firstName:
        return p.firstName.trim();
      case ProfileKey.middleName:
        return p.middleName.trim();
      case ProfileKey.lastName:
        return p.lastName.trim();
      case ProfileKey.dateOfBirth:
        return p.dateOfBirth == null ? '' : formatDayMonthYear(p.dateOfBirth!);
      case ProfileKey.phone:
        return p.phone.trim();
      case ProfileKey.email:
        return p.email.trim();
      case ProfileKey.address:
        return a?.oneLine ?? '';
      case ProfileKey.addressLine1:
        return a?.line1.trim() ?? '';
      case ProfileKey.addressLine2:
        return a?.line2.trim() ?? '';
      case ProfileKey.city:
        return a?.city.trim() ?? '';
      case ProfileKey.state:
        return a?.state.trim() ?? '';
      case ProfileKey.pincode:
        return a?.pincode.trim() ?? '';
      case ProfileKey.country:
        return a?.country.trim() ?? '';
    }
  }

  /// What 009 Fill forms offers for a field: the matched profile value first
  /// (with every saved address for address parts), then a custom field whose
  /// label matches the field name. Empty values are left out.
  List<AutofillSuggestion> suggestionsFor(String fieldName) {
    final List<AutofillSuggestion> out = <AutofillSuggestion>[];
    final String n = FormFieldMatcher.normalise(fieldName);
    for (final CustomField c in _profile.custom) {
      final String l = FormFieldMatcher.normalise(c.label);
      if (l.isNotEmpty && (n == l || (l.length >= 4 && n.contains(l))) && c.value.trim().isNotEmpty) {
        out.add(AutofillSuggestion(label: c.label, value: c.value.trim()));
      }
    }
    final ProfileKey? key = FormFieldMatcher.keyFor(fieldName);
    if (key != null) {
      const Set<ProfileKey> addressParts = <ProfileKey>{
        ProfileKey.address,
        ProfileKey.addressLine1,
        ProfileKey.addressLine2,
        ProfileKey.city,
        ProfileKey.state,
        ProfileKey.pincode,
        ProfileKey.country,
      };
      final List<AutofillSuggestion> matched = <AutofillSuggestion>[];
      if (addressParts.contains(key)) {
        for (final SavedAddress a in _profile.addresses) {
          final String v = valueOf(key, addressLabel: a.label);
          if (v.isNotEmpty && !matched.any((AutofillSuggestion s) => s.value == v)) {
            matched.add(AutofillSuggestion(label: a.label, value: v, key: key));
          }
        }
      } else {
        final String v = valueOf(key);
        if (v.isNotEmpty) {
          matched.add(AutofillSuggestion(label: _labelOf(key), value: v, key: key));
          if (key == ProfileKey.dateOfBirth) {
            matched.add(AutofillSuggestion(
              label: 'Date of birth (YYYY-MM-DD)',
              value: formatIsoDate(_profile.dateOfBirth!),
              key: key,
            ));
          }
        }
      }
      // A custom field the person named exactly after the field wins; the
      // profile's own value follows.
      out.addAll(matched);
    }
    return out;
  }

  /// The best value for a field, or null.
  String? valueFor(String fieldName) {
    final List<AutofillSuggestion> s = suggestionsFor(fieldName);
    return s.isEmpty ? null : s.first.value;
  }

  static String _labelOf(ProfileKey k) {
    switch (k) {
      case ProfileKey.fullName:
        return 'Full name';
      case ProfileKey.firstName:
        return 'First name';
      case ProfileKey.middleName:
        return 'Middle name';
      case ProfileKey.lastName:
        return 'Last name';
      case ProfileKey.dateOfBirth:
        return 'Date of birth';
      case ProfileKey.phone:
        return 'Phone';
      case ProfileKey.email:
        return 'Email';
      case ProfileKey.address:
        return 'Address';
      case ProfileKey.addressLine1:
        return 'Address line 1';
      case ProfileKey.addressLine2:
        return 'Address line 2';
      case ProfileKey.city:
        return 'City';
      case ProfileKey.state:
        return 'State';
      case ProfileKey.pincode:
        return 'PIN code';
      case ProfileKey.country:
        return 'Country';
    }
  }

  @override
  void dispose() {
    _clearTimer?.cancel();
    super.dispose();
  }

  static AutofillProfileBook instance = AutofillProfileBook(
    keyStore: MemoryKeyStore(),
    blobStore: MemoryNoteBlobStore(),
    clipboard: MemoryClipboard(),
  );

  static void install(AutofillProfileBook book) => instance = book;
}
