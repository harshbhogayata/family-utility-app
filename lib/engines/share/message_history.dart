import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Feature 129 — Recover deleted messages.
///
/// When the person turns it on, a notification listener on the phone keeps
/// the text of WhatsApp message notifications, and new WhatsApp media is
/// copied into the app as it arrives. If the sender later deletes a message
/// for everyone, the copy kept here is still readable. Everything stays in
/// the app's own folder; nothing is uploaded.

/// Packages whose notifications are kept.
const Set<String> watchedApps = <String>{'com.whatsapp', 'com.whatsapp.w4b'};

/// What WhatsApp shows in place of a message the sender deleted.
const List<String> deletionMarkers = <String>[
  'this message was deleted',
  'this message was deleted.',
  'deleted message',
];

bool isDeletionMarker(String text) {
  final String t = text.replaceAll(RegExp(r'[^\p{L}\p{N} .]', unicode: true), '').trim().toLowerCase();
  return deletionMarkers.contains(t);
}

final RegExp _summaryText = RegExp(r'^\d+ (new )?messages?( from \d+ chats?)?$', caseSensitive: false);

/// Lines like "3 new messages" that are notification summaries, not messages.
bool isSummaryText(String text) => _summaryText.hasMatch(text.trim());

@immutable
class HistoryMessage {
  const HistoryMessage({
    required this.app,
    required this.chat,
    required this.sender,
    required this.text,
    required this.at,
    this.deleted = false,
  });

  factory HistoryMessage.fromJson(Map<String, Object?> j) => HistoryMessage(
        app: '${j['app'] ?? ''}',
        chat: '${j['chat'] ?? ''}',
        sender: '${j['sender'] ?? ''}',
        text: '${j['text'] ?? ''}',
        at: DateTime.fromMillisecondsSinceEpoch((j['at'] as num?)?.toInt() ?? 0),
        deleted: j['deleted'] == true,
      );

  final String app;
  final String chat;
  final String sender;
  final String text;
  final DateTime at;

  /// The sender deleted it after it arrived; [text] is the kept original.
  final bool deleted;

  /// Same chat, same sender, same moment: the same message, even after
  /// WhatsApp swaps its text for the deletion notice.
  String get key => '$app|$chat|$sender|${at.millisecondsSinceEpoch}';

  HistoryMessage markDeleted() =>
      HistoryMessage(app: app, chat: chat, sender: sender, text: text, at: at, deleted: true);

  Map<String, Object?> toJson() => <String, Object?>{
        'app': app,
        'chat': chat,
        'sender': sender,
        'text': text,
        'at': at.millisecondsSinceEpoch,
        if (deleted) 'deleted': true,
      };

  @override
  String toString() => '${chat == sender ? sender : '$chat › $sender'}: $text';
}

/// Turns one raw notification (as the listener wrote it) into messages.
///
/// A conversation notification carries a `messages` list; an older-style one
/// only a title and text.
List<HistoryMessage> messagesFromEvent(Map<String, Object?> e) {
  final String app = '${e['app'] ?? ''}';
  if (!watchedApps.contains(app)) {
    return const <HistoryMessage>[];
  }
  final String title = '${e['title'] ?? ''}'.trim();
  final String conversation = '${e['conversation'] ?? ''}'.trim();
  final int posted = (e['posted'] as num?)?.toInt() ?? 0;
  final List<HistoryMessage> out = <HistoryMessage>[];
  final Object? raw = e['messages'];
  if (raw is List && raw.isNotEmpty) {
    for (final Object? m in raw) {
      if (m is! Map) {
        continue;
      }
      final String sender = '${m['sender'] ?? ''}'.trim();
      final String text = '${m['text'] ?? ''}'.trim();
      final int at = (m['time'] as num?)?.toInt() ?? posted;
      final String chat = conversation.isNotEmpty ? conversation : (sender.isNotEmpty ? sender : title);
      if (text.isEmpty || isSummaryText(text)) {
        continue;
      }
      out.add(HistoryMessage(
        app: app,
        chat: chat,
        sender: sender.isNotEmpty ? sender : chat,
        text: text,
        at: DateTime.fromMillisecondsSinceEpoch(at),
      ));
    }
    return out;
  }
  final String text = '${e['text'] ?? ''}'.trim();
  if (title.isEmpty || text.isEmpty || isSummaryText(text) || title == 'WhatsApp' || title == 'WhatsApp Business') {
    return out;
  }
  out.add(HistoryMessage(
    app: app,
    chat: conversation.isNotEmpty ? conversation : title,
    sender: title,
    text: text,
    at: DateTime.fromMillisecondsSinceEpoch(posted),
  ));
  return out;
}

/// Adds [incoming] to [kept]: new messages are stored once; a deletion
/// notice marks the kept original as deleted instead of replacing it.
List<HistoryMessage> mergeMessages(List<HistoryMessage> kept, Iterable<HistoryMessage> incoming) {
  final Map<String, HistoryMessage> byKey = <String, HistoryMessage>{
    for (final HistoryMessage m in kept) m.key: m,
  };
  for (final HistoryMessage m in incoming) {
    final HistoryMessage? old = byKey[m.key];
    if (isDeletionMarker(m.text)) {
      if (old != null && !old.deleted && !isDeletionMarker(old.text)) {
        byKey[m.key] = old.markDeleted();
      }
      // A deletion of something never seen has nothing to recover.
      continue;
    }
    if (old == null) {
      byKey[m.key] = m;
    }
  }
  final List<HistoryMessage> out = byKey.values.toList()
    ..sort((HistoryMessage a, HistoryMessage b) => b.at.compareTo(a.at));
  return out;
}

/// A text file of [messages], oldest first, for Save and Share.
String exportText(List<HistoryMessage> messages) {
  String two(int v) => v.toString().padLeft(2, '0');
  final List<HistoryMessage> sorted = List<HistoryMessage>.of(messages)
    ..sort((HistoryMessage a, HistoryMessage b) => a.at.compareTo(b.at));
  final StringBuffer b = StringBuffer();
  for (final HistoryMessage m in sorted) {
    final DateTime t = m.at;
    b.writeln('[${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}] '
        '$m${m.deleted ? '  (deleted by sender)' : ''}');
  }
  return b.toString();
}

/// Where the history and its on/off switches live. Behind an interface so
/// tests need no phone.
abstract class HistoryStore {
  /// Lines the listener appended since the last call; the inbox is emptied.
  Future<List<String>> takeInbox();

  Future<String?> readArchive();
  Future<void> writeArchive(String json);

  Future<bool> flag(String name);
  Future<void> setFlag(String name, bool on);
}

class MemoryHistoryStore implements HistoryStore {
  final List<String> inbox = <String>[];
  String? archive;
  final Set<String> flags = <String>{};

  @override
  Future<List<String>> takeInbox() async {
    final List<String> out = List<String>.of(inbox);
    inbox.clear();
    return out;
  }

  @override
  Future<String?> readArchive() async => archive;

  @override
  Future<void> writeArchive(String json) async => archive = json;

  @override
  Future<bool> flag(String name) async => flags.contains(name);

  @override
  Future<void> setFlag(String name, bool on) async => on ? flags.add(name) : flags.remove(name);
}

/// The folder the Android listener writes to: `message_history/` in the
/// app's documents folder. A flag is an empty file the listener checks.
class FolderHistoryStore implements HistoryStore {
  FolderHistoryStore(this.root);

  final Directory root;

  File get _inbox => File('${root.path}/inbox.jsonl');
  File get _archive => File('${root.path}/archive.json');

  @override
  Future<List<String>> takeInbox() async {
    if (!_inbox.existsSync()) {
      return const <String>[];
    }
    final File taken = await _inbox.rename('${root.path}/inbox.reading');
    final List<String> lines = await taken.readAsLines();
    await taken.delete();
    return lines;
  }

  @override
  Future<String?> readArchive() async => _archive.existsSync() ? _archive.readAsString() : null;

  @override
  Future<void> writeArchive(String json) async {
    await root.create(recursive: true);
    await _archive.writeAsString(json, flush: true);
  }

  @override
  Future<bool> flag(String name) async => File('${root.path}/$name').existsSync();

  @override
  Future<void> setFlag(String name, bool on) async {
    final File f = File('${root.path}/$name');
    if (on) {
      await root.create(recursive: true);
      await f.writeAsString('');
    } else if (f.existsSync()) {
      await f.delete();
    }
  }
}

class MessageHistory {
  MessageHistory(this.store, {this.keepDays = 30});

  /// Flag files the Android listener reads.
  static const String enabledFlag = 'enabled';
  static const String mediaFlag = 'rescue_media';

  final HistoryStore store;
  final int keepDays;

  Future<bool> isOn() => store.flag(enabledFlag);

  /// Opt-in: nothing is kept until this is turned on.
  Future<void> setOn(bool on) async {
    await store.setFlag(enabledFlag, on);
    if (!on) {
      await store.setFlag(mediaFlag, false);
    }
  }

  Future<bool> mediaOn() => store.flag(mediaFlag);
  Future<void> setMediaOn(bool on) => store.setFlag(mediaFlag, on);

  Future<List<HistoryMessage>> _archive() async {
    final String? raw = await store.readArchive();
    if (raw == null || raw.isEmpty) {
      return <HistoryMessage>[];
    }
    try {
      final Object? data = jsonDecode(raw);
      if (data is! List) {
        return <HistoryMessage>[];
      }
      return <HistoryMessage>[
        for (final Object? m in data)
          if (m is Map<String, Object?>) HistoryMessage.fromJson(m),
      ];
    } on FormatException {
      return <HistoryMessage>[];
    }
  }

  Future<void> _write(List<HistoryMessage> all) =>
      store.writeArchive(jsonEncode(<Map<String, Object?>>[for (final HistoryMessage m in all) m.toJson()]));

  /// Folds new notifications into the kept history, drops anything older
  /// than [keepDays], and returns it newest first.
  Future<List<HistoryMessage>> refresh({DateTime? now}) async {
    final List<String> lines = await store.takeInbox();
    final List<HistoryMessage> incoming = <HistoryMessage>[];
    if (await isOn()) {
      for (final String line in lines) {
        if (line.trim().isEmpty) {
          continue;
        }
        try {
          final Object? e = jsonDecode(line);
          if (e is Map<String, Object?>) {
            incoming.addAll(messagesFromEvent(e));
          }
        } on FormatException {
          // A half-written line from a killed listener; skip it.
        }
      }
    }
    final DateTime cutoff = (now ?? DateTime.now()).subtract(Duration(days: keepDays));
    final List<HistoryMessage> all = mergeMessages(await _archive(), incoming)
        .where((HistoryMessage m) => m.at.isAfter(cutoff))
        .toList();
    await _write(all);
    return all;
  }

  Future<void> replaceAll(List<HistoryMessage> all) => _write(all);
}

// ---------------------------------------------------------------- media

@immutable
class MediaFile {
  const MediaFile({required this.path, required this.name, required this.size, required this.modified});

  final String path;
  final String name;
  final int size;
  final DateTime modified;
}

@immutable
class RescuedMedia {
  const RescuedMedia({required this.file, required this.originalGone});

  final MediaFile file;

  /// No longer in WhatsApp's folder: deleted there, kept here.
  final bool originalGone;
}

/// WhatsApp's media folders and the app's copies. Behind an interface.
abstract class MediaFolders {
  Future<List<MediaFile>> whatsapp();
  Future<List<MediaFile>> rescued();
  Future<MediaFile> copy(MediaFile source);
  Future<void> remove(String path);
}

class MediaRescue {
  MediaRescue(this.folders, {this.window = const Duration(days: 2), this.maxBytes = 100 * 1024 * 1024});

  final MediaFolders folders;

  /// Only files newer than this are copied (older ones were already seen).
  final Duration window;
  final int maxBytes;

  static bool isMedia(String name) {
    if (name.startsWith('.')) {
      return false;
    }
    final int dot = name.lastIndexOf('.');
    final String ext = dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
    return const <String>{
      'jpg', 'jpeg', 'png', 'webp', 'gif', 'mp4', '3gp', 'mkv', 'webm', 'opus', 'ogg', 'm4a', 'mp3', 'aac', 'pdf',
    }.contains(ext);
  }

  /// Copies recent WhatsApp media the app does not have yet; returns copies.
  Future<List<MediaFile>> rescueNew({DateTime? now}) async {
    final DateTime since = (now ?? DateTime.now()).subtract(window);
    final Set<String> have = <String>{for (final MediaFile f in await folders.rescued()) '${f.name}:${f.size}'};
    final List<MediaFile> out = <MediaFile>[];
    for (final MediaFile f in await folders.whatsapp()) {
      if (!isMedia(f.name) || f.size <= 0 || f.size > maxBytes || f.modified.isBefore(since)) {
        continue;
      }
      if (have.add('${f.name}:${f.size}')) {
        try {
          out.add(await folders.copy(f));
        } on FileSystemException {
          // Deleted between listing and copying.
        }
      }
    }
    return out;
  }

  /// The app's copies, newest first, flagged when WhatsApp no longer has them.
  Future<List<RescuedMedia>> list() async {
    final Set<String> there = <String>{for (final MediaFile f in await folders.whatsapp()) f.name};
    final List<RescuedMedia> out = <RescuedMedia>[
      for (final MediaFile f in await folders.rescued()) RescuedMedia(file: f, originalGone: !there.contains(f.name)),
    ]..sort((RescuedMedia a, RescuedMedia b) => b.file.modified.compareTo(a.file.modified));
    return out;
  }
}

/// WhatsApp's media folders read straight from storage (what the listener
/// also copies from), and copies kept in `message_history/media`.
class PhoneMediaFolders implements MediaFolders {
  PhoneMediaFolders(this.root);

  final Directory root;

  static const List<String> sources = <String>[
    '/storage/emulated/0/Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Images',
    '/storage/emulated/0/Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Video',
    '/storage/emulated/0/Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Voice Notes',
    '/storage/emulated/0/Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Documents',
    '/storage/emulated/0/WhatsApp/Media/WhatsApp Images',
    '/storage/emulated/0/WhatsApp/Media/WhatsApp Video',
  ];

  Directory get _media => Directory('${root.path}/media');

  List<MediaFile> _list(Directory d, {bool deep = false}) {
    final List<MediaFile> out = <MediaFile>[];
    if (!d.existsSync()) {
      return out;
    }
    try {
      for (final FileSystemEntity e in d.listSync(recursive: deep)) {
        if (e is File) {
          final FileStat st = e.statSync();
          out.add(MediaFile(path: e.path, name: e.uri.pathSegments.last, size: st.size, modified: st.modified));
        }
      }
    } on FileSystemException {
      // No permission for this folder; it is skipped.
    }
    return out;
  }

  @override
  Future<List<MediaFile>> whatsapp() async {
    if (!Platform.isAndroid) {
      return const <MediaFile>[];
    }
    return <MediaFile>[for (final String s in sources) ..._list(Directory(s), deep: true)];
  }

  @override
  Future<List<MediaFile>> rescued() async => _list(_media);

  @override
  Future<MediaFile> copy(MediaFile source) async {
    await _media.create(recursive: true);
    final File out = await File(source.path).copy('${_media.path}/${source.name}');
    return MediaFile(path: out.path, name: source.name, size: source.size, modified: source.modified);
  }

  @override
  Future<void> remove(String path) async {
    final File f = File(path);
    if (f.existsSync()) {
      await f.delete();
    }
  }
}

// ---------------------------------------------------------------- platform

enum ListenerAccess { granted, needsGrant, unsupported }

/// Whether the phone lets the app read notifications.
abstract class ListenerPlatform {
  Future<ListenerAccess> access();
  Future<void> openSettings();
}

class PhoneListenerPlatform implements ListenerPlatform {
  const PhoneListenerPlatform();

  static const MethodChannel _channel = MethodChannel('app.family/message_history');

  @override
  Future<ListenerAccess> access() async {
    if (!Platform.isAndroid) {
      return ListenerAccess.unsupported;
    }
    try {
      final bool? on = await _channel.invokeMethod<bool>('access');
      return on == true ? ListenerAccess.granted : ListenerAccess.needsGrant;
    } on MissingPluginException {
      return ListenerAccess.unsupported;
    } on PlatformException {
      return ListenerAccess.needsGrant;
    }
  }

  @override
  Future<void> openSettings() async {
    try {
      await _channel.invokeMethod<void>('openSettings');
    } on MissingPluginException {
      // Nothing to open on this build.
    } on PlatformException {
      // Settings screen missing on this phone.
    }
  }
}
