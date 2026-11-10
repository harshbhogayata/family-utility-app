import 'package:flutter_contacts/flutter_contacts.dart';

import '../engines/records/contacts_backup.dart';

/// Feature 103: the phone's address book through flutter_contacts.
class PhoneContactsSource implements ContactsSource {
  const PhoneContactsSource();

  @override
  Future<bool> allowed({required bool write}) => FlutterContacts.requestPermission(readonly: !write);

  @override
  Future<List<BackupContact>> readAll() async {
    final List<Contact> all = await FlutterContacts.getContacts(withProperties: true, withPhoto: true);
    return all
        .map((Contact c) => BackupContact(
              id: c.id,
              first: c.name.first,
              last: c.name.last,
              display: c.displayName,
              phones: c.phones.map((Phone p) => p.number).toList(),
              emails: c.emails.map((Email e) => e.address).toList(),
              org: c.organizations.isEmpty ? '' : c.organizations.first.company,
              photo: c.photo,
            ))
        .toList();
  }

  @override
  Future<void> insert(BackupContact b) async {
    final Contact c = Contact();
    c.name.first = b.first.isEmpty && b.last.isEmpty ? b.name : b.first;
    c.name.last = b.last;
    c.phones = b.phones.map((String p) => Phone(p)).toList();
    c.emails = b.emails.map((String e) => Email(e)).toList();
    if (b.org.isNotEmpty) {
      c.organizations = <Organization>[Organization(company: b.org)];
    }
    c.photo = b.photo;
    await c.insert();
  }

  @override
  Future<void> update(BackupContact b) async {
    final Contact? c = await FlutterContacts.getContact(b.id, withProperties: true, withPhoto: true);
    if (c == null) {
      return;
    }
    final Set<String> have = c.phones.map((Phone p) => ContactsBackup.phoneKey(p.number)).toSet();
    for (final String p in b.phones) {
      if (have.add(ContactsBackup.phoneKey(p))) {
        c.phones.add(Phone(p));
      }
    }
    final Set<String> mails = c.emails.map((Email e) => e.address.toLowerCase()).toSet();
    for (final String e in b.emails) {
      if (mails.add(e.toLowerCase())) {
        c.emails.add(Email(e));
      }
    }
    if (c.organizations.isEmpty && b.org.isNotEmpty) {
      c.organizations = <Organization>[Organization(company: b.org)];
    }
    if ((c.photo == null || c.photo!.isEmpty) && b.photo != null) {
      c.photo = b.photo;
    }
    await c.update();
  }
}
