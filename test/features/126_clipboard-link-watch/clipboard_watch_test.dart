import 'package:family_utility_app/engines/download/clipboard_watch.dart';
import 'package:family_utility_app/engines/download/video_link.dart';
import 'package:family_utility_app/tools/clipboard_watch/clipboard_watch_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A clipboard that counts how often it was read.
class FakeClipboard implements ClipboardTextSource {
  FakeClipboard(this.text);

  String? text;
  int reads = 0;

  @override
  Future<String?> readText() async {
    reads++;
    return text;
  }
}

ClipboardLinkWatch _watch(FakeClipboard clip, {bool on = false}) =>
    ClipboardLinkWatch(source: clip, store: MemoryClipboardWatchStore(enabled: on));

void main() {
  group('supportedLink', () {
    final List<VideoExtractor> plugins = VideoExtractorRegistry.defaultPlugins();

    test('finds site links inside text', () {
      final LinkOffer? o = supportedLink('look https://www.instagram.com/reel/abc/ !', plugins);
      expect(o, isNotNull);
      expect(o!.site, 'Instagram');
      expect(o.url.toString(), 'https://www.instagram.com/reel/abc/');
      expect(supportedLink('https://youtu.be/xyz', plugins)!.site, isNotEmpty);
    });

    test('ignores other links and plain text', () {
      expect(supportedLink('https://example.com/file.mp4', plugins), isNull);
      expect(supportedLink('my bank PIN is 1234', plugins), isNull);
      expect(supportedLink(null, plugins), isNull);
    });
  });

  group('ClipboardLinkWatch', () {
    test('is opt-in: never reads the clipboard while off', () async {
      final FakeClipboard clip = FakeClipboard('https://www.instagram.com/reel/abc/');
      final ClipboardLinkWatch w = _watch(clip);
      await w.load();
      expect(w.enabled, isFalse);
      expect(await w.check(), isNull);
      expect(clip.reads, 0);
    });

    test('offers a supported link once, keeps nothing else', () async {
      final FakeClipboard clip = FakeClipboard('https://x.com/a/status/1');
      final ClipboardLinkWatch w = _watch(clip);
      await w.setEnabled(true);
      final LinkOffer? first = await w.check();
      expect(first, isNotNull);
      expect(await w.check(), isNull, reason: 'same copy is not offered twice');

      clip.text = 'a private note';
      expect(await w.check(), isNull);
      expect(w.offer!.url.toString(), 'https://x.com/a/status/1');

      final LinkOffer? taken = w.accept();
      expect(taken, isNotNull);
      expect(w.offer, isNull);
      w.restore(taken!);
      expect(w.offer, isNotNull);

      await w.setEnabled(false);
      expect(w.offer, isNull);
    });

    test('remembers the switch', () async {
      final MemoryClipboardWatchStore store = MemoryClipboardWatchStore();
      final ClipboardLinkWatch w = ClipboardLinkWatch(source: FakeClipboard(null), store: store);
      await w.setEnabled(true);
      expect(store.enabled, isTrue);
      final ClipboardLinkWatch again = ClipboardLinkWatch(source: FakeClipboard(null), store: store);
      await again.load();
      expect(again.enabled, isTrue);
    });
  });

  testWidgets('screen: switch on, check, save, undo', (WidgetTester tester) async {
    final FakeClipboard clip = FakeClipboard('https://www.pinterest.com/pin/123/');
    final ClipboardLinkWatch w = _watch(clip);
    Uri? saved;
    await tester.pumpWidget(MaterialApp(
      home: ClipboardWatchScreen(watch: w, onSave: (BuildContext c, Uri u) => saved = u),
    ));

    await tester.tap(find.byKey(const Key('clipboard-watch-switch')));
    await tester.pumpAndSettle();
    expect(w.enabled, isTrue);

    await tester.tap(find.byKey(const Key('clipboard-watch-check')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('clipboard-watch-offer')), findsOneWidget);
    expect(find.byKey(const Key('clipboard-watch-share')), findsOneWidget);
    expect(tester.getSize(find.byKey(const Key('clipboard-watch-save'))).height, greaterThanOrEqualTo(44));

    await tester.tap(find.byKey(const Key('clipboard-watch-save')));
    await tester.pumpAndSettle();
    expect(saved.toString(), 'https://www.pinterest.com/pin/123/');
    expect(find.byKey(const Key('clipboard-watch-offer')), findsNothing);

    await tester.tap(find.byKey(const Key('clipboard-watch-undo')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('clipboard-watch-offer')), findsOneWidget);
  });

  testWidgets('bubble offers Save', (WidgetTester tester) async {
    bool tapped = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (BuildContext context) => TextButton(
            onPressed: () => showLinkOfferBubble(
              ScaffoldMessenger.of(context),
              LinkOffer(Uri.parse('https://youtu.be/xyz'), 'YouTube'),
              () => tapped = true,
            ),
            child: const Text('go'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('Copied YouTube link. Save it?'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(tapped, isTrue);
  });
}
