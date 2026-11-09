import 'dart:convert';
import 'dart:io';

import 'package:family_utility_app/app/theme.dart';
import 'package:family_utility_app/engines/security/app_lock.dart';
import 'package:family_utility_app/engines/share/message_history.dart';
import 'package:family_utility_app/engines/share/share_engine.dart';
import 'package:family_utility_app/tools/deleted_messages/deleted_messages_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final DateTime now = DateTime(2026, 11, 9, 12);
final int t1 = DateTime(2026, 11, 9, 9, 15).millisecondsSinceEpoch;
final int t2 = DateTime(2026, 11, 9, 9, 16).millisecondsSinceEpoch;

String event({String app = 'com.whatsapp', String conversation = '', String title = 'Mom', List<Map<String, Object>>? messages, String text = ''}) =>
    jsonEncode(<String, Object>{
      'app': app,
      'title': title,
      'conversation': conversation,
      'text': text,
      'posted': t2,
      'messages': messages ?? <Map<String, Object>>[],
    });

Map<String, Object> msg(String sender, String text, int time) =>
    <String, Object>{'sender': sender, 'text': text, 'time': time};

class FakeListener implements ListenerPlatform {
  FakeListener(this.state);
  ListenerAccess state;
  int opened = 0;

  @override
  Future<ListenerAccess> access() async => state;

  @override
  Future<void> openSettings() async {
    opened++;
    state = ListenerAccess.granted;
  }
}

class FakeFolders implements MediaFolders {
  final List<MediaFile> wa = <MediaFile>[];
  final List<MediaFile> kept = <MediaFile>[];

  @override
  Future<List<MediaFile>> whatsapp() async => List<MediaFile>.of(wa);

  @override
  Future<List<MediaFile>> rescued() async => List<MediaFile>.of(kept);

  @override
  Future<MediaFile> copy(MediaFile source) async {
    final MediaFile c = MediaFile(path: '/kept/${source.name}', name: source.name, size: source.size, modified: source.modified);
    kept.add(c);
    return c;
  }

  @override
  Future<void> remove(String path) async => kept.removeWhere((MediaFile f) => f.path == path);
}

class FakeSheet implements ShareSheet {
  final List<ShareRequest> requests = <ShareRequest>[];

  @override
  Future<ShareOutcome> share(ShareRequest request) async {
    requests.add(request);
    return const ShareOutcome(completed: true);
  }
}

void main() {
  group('reading notifications', () {
    test('a conversation notification gives one message per line', () {
      final List<HistoryMessage> m = messagesFromEvent(jsonDecode(event(
        conversation: 'Family',
        messages: <Map<String, Object>>[msg('Mom', 'Dinner at 8', t1), msg('Dad', 'OK', t2)],
      )) as Map<String, Object?>);
      expect(m, hasLength(2));
      expect(m.first.chat, 'Family');
      expect(m.first.sender, 'Mom');
      expect(m.last.text, 'OK');
    });

    test('other apps and summary lines are ignored', () {
      expect(messagesFromEvent(jsonDecode(event(app: 'com.other', text: 'hi')) as Map<String, Object?>), isEmpty);
      expect(messagesFromEvent(jsonDecode(event(text: '3 new messages')) as Map<String, Object?>), isEmpty);
      expect(messagesFromEvent(jsonDecode(event(title: 'WhatsApp', text: 'x')) as Map<String, Object?>), isEmpty);
      expect(isSummaryText('12 messages from 4 chats'), isTrue);
      final List<HistoryMessage> plain = messagesFromEvent(jsonDecode(event(text: 'Call me')) as Map<String, Object?>);
      expect(plain.single.sender, 'Mom');
      expect(plain.single.chat, 'Mom');
    });

    test('a deletion notice keeps the original and marks it deleted', () {
      final HistoryMessage a = HistoryMessage(app: 'com.whatsapp', chat: 'Mom', sender: 'Mom', text: 'Secret', at: DateTime.fromMillisecondsSinceEpoch(t1));
      final HistoryMessage gone = HistoryMessage(app: 'com.whatsapp', chat: 'Mom', sender: 'Mom', text: '🚫 This message was deleted', at: a.at);
      final HistoryMessage orphan = HistoryMessage(app: 'com.whatsapp', chat: 'Mom', sender: 'Mom', text: 'This message was deleted', at: DateTime.fromMillisecondsSinceEpoch(t2));
      final List<HistoryMessage> out = mergeMessages(<HistoryMessage>[a], <HistoryMessage>[a, gone, orphan]);
      expect(out, hasLength(1));
      expect(out.single.text, 'Secret');
      expect(out.single.deleted, isTrue);
      expect(exportText(out), contains('Secret  (deleted by sender)'));
    });
  });

  group('history', () {
    test('opt-in: nothing is kept while it is off', () async {
      final MemoryHistoryStore store = MemoryHistoryStore();
      final MessageHistory h = MessageHistory(store);
      store.inbox.add(event(text: 'Hello'));
      expect(await h.refresh(now: now), isEmpty);
      await h.setOn(true);
      store.inbox.add(event(text: 'Hello'));
      expect((await h.refresh(now: now)).single.text, 'Hello');
      expect(store.inbox, isEmpty);
      await h.setMediaOn(true);
      await h.setOn(false);
      expect(await h.mediaOn(), isFalse);
    });

    test('old messages drop after keepDays and bad lines are skipped', () async {
      final MemoryHistoryStore store = MemoryHistoryStore();
      final MessageHistory h = MessageHistory(store, keepDays: 1);
      await h.setOn(true);
      store.inbox
        ..add(event(text: 'Fresh'))
        ..add('{"broken')
        ..add('');
      expect(await h.refresh(now: now), hasLength(1));
      expect(await h.refresh(now: now.add(const Duration(days: 3))), isEmpty);
    });

    test('folder store hands the inbox over once and keeps flags as files', () async {
      final Directory tmp = await Directory.systemTemp.createTemp('history');
      final FolderHistoryStore store = FolderHistoryStore(tmp);
      final MessageHistory h = MessageHistory(store);
      await h.setOn(true);
      expect(File('${tmp.path}/enabled').existsSync(), isTrue);
      File('${tmp.path}/inbox.jsonl').writeAsStringSync('${event(text: 'Hi')}\n');
      expect(await h.refresh(now: now), hasLength(1));
      expect(File('${tmp.path}/inbox.jsonl').existsSync(), isFalse);
      expect(await h.refresh(now: now), hasLength(1));
      await tmp.delete(recursive: true);
    });
  });

  group('media', () {
    test('new media is copied once; gone originals are flagged', () async {
      final FakeFolders f = FakeFolders();
      f.wa
        ..add(MediaFile(path: '/wa/IMG-1.jpg', name: 'IMG-1.jpg', size: 10, modified: now))
        ..add(MediaFile(path: '/wa/old.jpg', name: 'old.jpg', size: 10, modified: now.subtract(const Duration(days: 9))))
        ..add(MediaFile(path: '/wa/.nomedia', name: '.nomedia', size: 1, modified: now));
      final MediaRescue r = MediaRescue(f);
      expect(await r.rescueNew(now: now), hasLength(1));
      expect(await r.rescueNew(now: now), isEmpty);
      f.wa.removeWhere((MediaFile m) => m.name == 'IMG-1.jpg');
      final List<RescuedMedia> list = await r.list();
      expect(list.single.originalGone, isTrue);
    });
  });

  group('screen', () {
    Future<void> pump(WidgetTester tester, Widget w) async {
      await tester.pumpWidget(MaterialApp(theme: buildAppTheme(), home: w));
      await tester.pumpAndSettle();
    }

    testWidgets('off by default; turning on asks for notification access', (WidgetTester tester) async {
      final MemoryHistoryStore store = MemoryHistoryStore();
      final FakeListener l = FakeListener(ListenerAccess.needsGrant);
      await pump(
        tester,
        DeletedMessagesScreen(history: MessageHistory(store), media: MediaRescue(FakeFolders()), platform: l, now: () => now),
      );
      expect(find.textContaining('Off until you turn it on'), findsOneWidget);
      await tester.tap(find.byKey(const Key('history-on')));
      await tester.pumpAndSettle();
      expect(l.opened, 1);
      expect(store.flags, contains(MessageHistory.enabledFlag));
      expect(find.byKey(const Key('history-status')), findsOneWidget);
    });

    testWidgets('shows a deleted message; save, share and undo', (WidgetTester tester) async {
      final MemoryHistoryStore store = MemoryHistoryStore()..flags.add(MessageHistory.enabledFlag);
      store.inbox
        ..add(event(messages: <Map<String, Object>>[msg('Mom', 'Secret', t1), msg('Mom', 'Hi', t2)]))
        ..add(event(messages: <Map<String, Object>>[msg('Mom', 'This message was deleted', t1)]));
      final Map<String, String> saved = <String, String>{};
      final FakeSheet sheet = FakeSheet();
      final ShareEngine share = ShareEngine(sheet, MemoryShareTargetStore());
      await pump(
        tester,
        DeletedMessagesScreen(
          history: MessageHistory(store),
          media: MediaRescue(FakeFolders()),
          platform: FakeListener(ListenerAccess.granted),
          share: share,
          now: () => now,
          saveText: (String name, String text) async {
            saved[name] = text;
            return '/nowhere/$name';
          },
        ),
      );
      expect(find.text('Secret'), findsOneWidget);
      expect(find.text('Hi'), findsNothing);
      expect(find.bySemanticsLabel(RegExp(r'^Deleted message from Mom at .*: Secret$')), findsOneWidget);

      await tester.tap(find.byKey(const Key('history-only-deleted')));
      await tester.pumpAndSettle();
      expect(find.text('Hi'), findsOneWidget);
      await tester.tap(find.byKey(const Key('history-only-deleted')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('result-save')));
      await tester.pumpAndSettle();
      expect(saved.values.single, contains('Secret  (deleted by sender)'));
      await tester.tap(find.byKey(const Key('result-share')));
      await tester.pumpAndSettle();
      expect(sheet.requests.single.files.single.path, startsWith('/nowhere/Messages 2026-11-09'));

      await tester.tap(find.byKey(const Key('history-clear')));
      await tester.pumpAndSettle();
      expect(find.text('Secret'), findsNothing);
      await tester.tap(find.byKey(const Key('result-undo')));
      await tester.pumpAndSettle();
      expect(find.text('Secret'), findsOneWidget);
    });

    testWidgets('phones that cannot share notifications say so', (WidgetTester tester) async {
      await pump(
        tester,
        DeletedMessagesScreen(
          history: MessageHistory(MemoryHistoryStore()),
          media: MediaRescue(FakeFolders()),
          platform: FakeListener(ListenerAccess.unsupported),
          now: () => now,
        ),
      );
      expect(find.textContaining('does not let apps read'), findsOneWidget);
    });

    testWidgets('touch targets are at least 44 px', (WidgetTester tester) async {
      await pump(
        tester,
        DeletedMessagesScreen(
          history: MessageHistory(MemoryHistoryStore()),
          media: MediaRescue(FakeFolders()),
          platform: FakeListener(ListenerAccess.granted),
          now: () => now,
        ),
      );
      for (final String k in <String>['history-on', 'history-refresh']) {
        final Size s = tester.getSize(find.byKey(Key(k)));
        expect(s.height, greaterThanOrEqualTo(44), reason: k);
      }
    });
  });

  test('the tool can carry its own lock', () {
    expect(LockableIds.labels[LockableIds.deletedMessages], 'Recover deleted messages');
  });
}
