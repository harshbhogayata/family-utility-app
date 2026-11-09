import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../app/widgets/result_bar.dart';
import '../../engines/records/autofill_profile.dart';
import '../../engines/share/share_engine.dart';

/// Feature 096 — name, date of birth, phone, email and saved addresses, kept
/// encrypted on this phone. Tap the copy button beside any value to paste it
/// into a form; 009 Fill forms offers the same values in PDF fields.
class AutofillProfileScreen extends StatefulWidget {
  const AutofillProfileScreen({super.key, this.book, this.share, this.save});

  final AutofillProfileBook? book;
  final Future<void> Function(String text)? share;
  final Future<String?> Function(String text)? save;

  @override
  State<AutofillProfileScreen> createState() => _AutofillProfileScreenState();
}

class _AutofillProfileScreenState extends State<AutofillProfileScreen> {
  AutofillProfileBook get _book => widget.book ?? AutofillProfileBook.instance;

  @override
  void initState() {
    super.initState();
    _book.addListener(_changed);
    if (!_book.isLoaded) {
      unawaited(_book.load());
    }
  }

  @override
  void dispose() {
    _book.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) {
      setState(() {});
    }
  }

  void _snack(String s) {
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(s)));
    }
  }

  Future<void> _copy(String label, String value) async {
    if (value.trim().isEmpty) {
      _snack('$label is empty');
      return;
    }
    await _book.copy(value.trim());
    _snack('$label copied');
  }

  Future<String?> _ask(String title, String initial, {TextInputType? keyboard, String? key}) {
    final TextEditingController c = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(title),
        content: TextField(
          key: Key(key ?? 'profile-input'),
          controller: c,
          autofocus: true,
          keyboardType: keyboard,
          decoration: InputDecoration(labelText: title),
          onSubmitted: (String v) => Navigator.of(context).pop(v),
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          FilledButton(
            key: const Key('profile-input-ok'),
            onPressed: () => Navigator.of(context).pop(c.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _editText(String label, String current, AutofillProfile Function(String v) apply,
      {TextInputType? keyboard}) async {
    final String? v = await _ask(label, current, keyboard: keyboard);
    if (v != null) {
      await _book.save(apply(v.trim()));
    }
  }

  Future<void> _editDob() async {
    final DateTime now = DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _book.profile.dateOfBirth ?? DateTime(now.year - 30),
      firstDate: DateTime(1900),
      lastDate: now,
      helpText: 'Date of birth',
    );
    if (picked != null) {
      await _book.save(_book.profile.copyWith(dateOfBirth: picked));
    }
  }

  Future<void> _editAddress(SavedAddress a) async {
    final Map<String, TextEditingController> c = <String, TextEditingController>{
      'Label': TextEditingController(text: a.label),
      'House, street': TextEditingController(text: a.line1),
      'Area, landmark': TextEditingController(text: a.line2),
      'City': TextEditingController(text: a.city),
      'State': TextEditingController(text: a.state),
      'PIN code': TextEditingController(text: a.pincode),
      'Country': TextEditingController(text: a.country),
    };
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Address'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              for (final MapEntry<String, TextEditingController> e in c.entries)
                TextField(
                  key: Key('address-${e.key}'),
                  controller: e.value,
                  keyboardType: e.key == 'PIN code' ? TextInputType.number : TextInputType.text,
                  decoration: InputDecoration(labelText: e.key),
                ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(
            key: const Key('address-ok'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (ok == true) {
      final String label = c['Label']!.text.trim();
      await _book.putAddress(a.copyWith(
        label: label.isEmpty ? 'Home' : label,
        line1: c['House, street']!.text.trim(),
        line2: c['Area, landmark']!.text.trim(),
        city: c['City']!.text.trim(),
        state: c['State']!.text.trim(),
        pincode: c['PIN code']!.text.trim(),
        country: c['Country']!.text.trim(),
      ));
    }
  }

  Future<void> _addAddress() async {
    final int n = _book.profile.addresses.length;
    final SavedAddress a = await _book.addAddress(label: n == 0 ? 'Home' : (n == 1 ? 'Work' : 'Address ${n + 1}'));
    await _editAddress(a);
  }

  Future<void> _addCustom() async {
    final String? label = await _ask('Field name (e.g. Father\'s name)', '', key: 'custom-label');
    if (label == null || label.trim().isEmpty) {
      return;
    }
    final String? value = await _ask(label.trim(), '', key: 'custom-value');
    if (value == null) {
      return;
    }
    await _book.save(_book.profile.copyWith(
      custom: <CustomField>[..._book.profile.custom, CustomField(label: label.trim(), value: value.trim())],
    ));
  }

  Future<void> _undo() async {
    _snack(await _book.undo() ? 'Undone' : 'Nothing to undo');
  }

  Future<void> _share() async {
    final String text = _book.profile.toPlainText();
    if (text.isEmpty) {
      _snack('Nothing to share yet');
      return;
    }
    final Future<void> Function(String)? s = widget.share;
    if (s != null) {
      await s(text);
    } else {
      await ShareEngine.instance.shareText(text, subject: 'My details');
    }
  }

  Future<void> _save() async {
    final String text = _book.profile.toPlainText();
    if (text.isEmpty) {
      _snack('Nothing to save yet');
      return;
    }
    String? where;
    try {
      final Future<String?> Function(String)? s = widget.save;
      if (s != null) {
        where = await s(text);
      } else {
        final Directory dir = await getApplicationDocumentsDirectory();
        final File f = File('${dir.path}/My-details.txt');
        await f.writeAsString(text);
        where = f.path;
      }
    } catch (_) {
      where = null;
    }
    _snack(where == null ? 'Could not save' : 'Saved to $where');
  }

  Widget _row(String label, String value, {required String id, required VoidCallback onEdit}) {
    final bool empty = value.trim().isEmpty;
    return ListTile(
      key: Key('profile-$id'),
      contentPadding: EdgeInsets.zero,
      minTileHeight: 56,
      title: Text(label),
      subtitle: Text(empty ? 'Tap to add' : value),
      onTap: onEdit,
      trailing: IconButton(
        key: Key('copy-$id'),
        tooltip: 'Copy $label',
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        icon: const Icon(Icons.copy_outlined),
        onPressed: empty ? null : () => unawaited(_copy(label, value)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AutofillProfile p = _book.profile;
    return Scaffold(
      appBar: AppBar(title: const Text('My details')),
      bottomNavigationBar: ResultBar(
        onShare: () => unawaited(_share()),
        onSave: () => unawaited(_save()),
        onUndo: () => unawaited(_undo()),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.lock_outline, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Encrypted on this phone. Never uploaded.', style: text.bodySmall),
              ),
            ],
          ),
          if (_book.loadError != null) Text(_book.loadError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          const SizedBox(height: 8),
          Text('Name', style: text.titleMedium),
          _row('Full name', p.fullName, id: 'full-name', onEdit: () => _snack('Edit first, middle and last name below')),
          _row('First name', p.firstName, id: 'first-name', onEdit: () => unawaited(_editText('First name', p.firstName, (String v) => _book.profile.copyWith(firstName: v)))),
          _row('Middle name', p.middleName, id: 'middle-name', onEdit: () => unawaited(_editText('Middle name', p.middleName, (String v) => _book.profile.copyWith(middleName: v)))),
          _row('Last name', p.lastName, id: 'last-name', onEdit: () => unawaited(_editText('Last name', p.lastName, (String v) => _book.profile.copyWith(lastName: v)))),
          const SizedBox(height: 8),
          Text('Contact', style: text.titleMedium),
          _row('Date of birth', p.dateOfBirth == null ? '' : formatDayMonthYear(p.dateOfBirth!), id: 'dob', onEdit: () => unawaited(_editDob())),
          _row('Phone', p.phone, id: 'phone', onEdit: () => unawaited(_editText('Phone', p.phone, (String v) => _book.profile.copyWith(phone: v), keyboard: TextInputType.phone))),
          _row('Email', p.email, id: 'email', onEdit: () => unawaited(_editText('Email', p.email, (String v) => _book.profile.copyWith(email: v), keyboard: TextInputType.emailAddress))),
          const SizedBox(height: 8),
          Text('Addresses', style: text.titleMedium),
          for (final SavedAddress a in p.addresses)
            Card(
              key: Key('address-card-${a.id}'),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Semantics(
                        button: true,
                        label: '${a.label} address: ${a.oneLine}. Tap to edit',
                        child: ExcludeSemantics(
                          child: InkWell(
                            onTap: () => unawaited(_editAddress(a)),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(minHeight: 48),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  Text(a.label, style: text.titleSmall),
                                  Text(a.isEmpty ? 'Tap to fill in' : a.multiLine),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      key: Key('copy-address-${a.id}'),
                      tooltip: 'Copy ${a.label} address',
                      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                      icon: const Icon(Icons.copy_outlined),
                      onPressed: a.isEmpty ? null : () => unawaited(_copy('${a.label} address', a.oneLine)),
                    ),
                    IconButton(
                      tooltip: 'Delete ${a.label} address',
                      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => unawaited(_book.removeAddress(a.id)),
                    ),
                  ],
                ),
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const Key('add-address'),
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: () => unawaited(_addAddress()),
              icon: const Icon(Icons.add_location_alt_outlined),
              label: const Text('Add address'),
            ),
          ),
          const SizedBox(height: 8),
          Text('More fields', style: text.titleMedium),
          for (int i = 0; i < p.custom.length; i++)
            _row(p.custom[i].label, p.custom[i].value, id: 'custom-$i', onEdit: () {
              final int at = i;
              unawaited(_editText(p.custom[at].label, p.custom[at].value, (String v) {
                final List<CustomField> list = List<CustomField>.of(_book.profile.custom);
                list[at] = CustomField(label: list[at].label, value: v);
                return _book.profile.copyWith(custom: list);
              }));
            }),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const Key('add-custom'),
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: () => unawaited(_addCustom()),
              icon: const Icon(Icons.add),
              label: const Text('Add a field'),
            ),
          ),
        ],
      ),
    );
  }
}
