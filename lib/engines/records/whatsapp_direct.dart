import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Feature 102 — WhatsApp direct.
///
/// Opens a chat with a number that is not saved in contacts, through a
/// wa.me link the phone hands to WhatsApp. The last numbers used are kept
/// in the app's own folder on this phone; nothing is uploaded.

abstract interface class RecentNumberStore {
  Future<List<String>> load();
  Future<void> save(List<String> numbers);
}

class MemoryRecentNumberStore implements RecentNumberStore {
  List<String> saved = <String>[];
  @override
  Future<List<String>> load() async => List<String>.of(saved);
  @override
  Future<void> save(List<String> numbers) async => saved = List<String>.of(numbers);
}

/// whatsapp_recent.json in the app's private folder.
class FileRecentNumberStore implements RecentNumberStore {
  FileRecentNumberStore(this.folder);
  final Future<Directory> Function() folder;

  Future<File> _file() async => File('${(await folder()).path}/whatsapp_recent.json');

  @override
  Future<List<String>> load() async {
    final File f = await _file();
    if (!f.existsSync()) {
      return <String>[];
    }
    final Object? json = jsonDecode(await f.readAsString());
    return json is List ? json.whereType<String>().toList() : <String>[];
  }

  @override
  Future<void> save(List<String> numbers) async {
    final File f = await _file();
    await f.parent.create(recursive: true);
    await f.writeAsString(jsonEncode(numbers));
  }
}

/// Opens a link outside the app (WhatsApp, or the browser if it is missing).
abstract interface class LinkOpener {
  Future<bool> open(Uri uri);
}

class WhatsAppDirect extends ChangeNotifier {
  WhatsAppDirect({RecentNumberStore? store, LinkOpener? opener, this.defaultCountry = '91', this.keep = 10})
      : _store = store ?? MemoryRecentNumberStore(),
        _opener = opener;

  final RecentNumberStore _store;
  final LinkOpener? _opener;

  /// Added in front of a 10-digit number typed without a country code.
  final String defaultCountry;
  final int keep;
  final List<String> _recent = <String>[];
  List<String>? _undo;

  /// Newest first, digits with country code.
  List<String> get recent => List<String>.unmodifiable(_recent);

  Future<void> load() async {
    try {
      _recent
        ..clear()
        ..addAll(await _store.load());
    } catch (e) {
      debugPrint('whatsapp recent load: $e');
    }
    notifyListeners();
  }

  /// "+91 98765-43210", "098765 43210" or "9876543210" become
  /// "919876543210"; null when it cannot be a phone number.
  String? normalise(String input) {
    final String t = input.trim();
    if (t.isEmpty || RegExp(r'[A-Za-z]').hasMatch(t)) {
      return null;
    }
    String d = t.replaceAll(RegExp(r'\D'), '');
    if (!t.startsWith('+')) {
      if (d.startsWith('00')) {
        d = d.substring(2);
      } else if (d.length == 11 && d.startsWith('0')) {
        d = '$defaultCountry${d.substring(1)}';
      } else if (d.length == 10) {
        d = '$defaultCountry$d';
      }
    }
    if (d.length < 8 || d.length > 15 || d.startsWith('0')) {
      return null;
    }
    return d;
  }

  /// https://wa.me/919876543210?text=Hello
  Uri? link(String number, {String message = ''}) {
    final String? n = normalise(number);
    if (n == null) {
      return null;
    }
    return Uri.https('wa.me', '/$n', message.trim().isEmpty ? null : <String, String>{'text': message.trim()});
  }

  /// Remembers [number] at the top of the recent list.
  void remember(String number) {
    final String? n = normalise(number);
    if (n == null) {
      return;
    }
    _undo = List<String>.of(_recent);
    _recent
      ..remove(n)
      ..insert(0, n);
    while (_recent.length > keep) {
      _recent.removeLast();
    }
    _changed();
  }

  bool forget(String number) {
    if (!_recent.contains(number)) {
      return false;
    }
    _undo = List<String>.of(_recent);
    _recent.remove(number);
    _changed();
    return true;
  }

  bool undo() {
    final List<String>? u = _undo;
    if (u == null) {
      return false;
    }
    _undo = null;
    _recent
      ..clear()
      ..addAll(u);
    _changed();
    return true;
  }

  void _changed() {
    notifyListeners();
    unawaited(_store.save(List<String>.of(_recent)).catchError((Object e) => debugPrint('whatsapp recent save: $e')));
  }

  /// Opens the chat; false when the number is not valid or nothing opened.
  Future<bool> openChat(String number, {String message = ''}) async {
    final Uri? uri = link(number, message: message);
    final LinkOpener? o = _opener;
    if (uri == null || o == null) {
      return false;
    }
    remember(number);
    return o.open(uri);
  }

  /// "+91 98765 43210" for display.
  static String pretty(String digits) {
    if (digits.length == 12 && digits.startsWith('91')) {
      return '+91 ${digits.substring(2, 7)} ${digits.substring(7)}';
    }
    return '+$digits';
  }

  static WhatsAppDirect instance = WhatsAppDirect();
  static void install(WhatsAppDirect w) => instance = w;
}
