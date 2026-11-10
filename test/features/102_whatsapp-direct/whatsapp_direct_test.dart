import 'package:family_utility_app/engines/records/whatsapp_direct.dart';
import 'package:family_utility_app/records/whatsapp_direct/whatsapp_direct_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeOpener implements LinkOpener {
  final List<Uri> opened = <Uri>[];
  @override
  Future<bool> open(Uri uri) async {
    opened.add(uri);
    return true;
  }
}

void main() {
  group('engine', () {
    test('numbers normalise with the country code', () {
      final WhatsAppDirect w = WhatsAppDirect();
      expect(w.normalise('+91 98765-43210'), '919876543210');
      expect(w.normalise('98765 43210'), '919876543210');
      expect(w.normalise('098765 43210'), '919876543210');
      expect(w.normalise('0044 20 7946 0958'), '442079460958');
      expect(w.normalise('+1 (415) 555-0100'), '14155550100');
      expect(w.normalise('12345'), isNull);
      expect(w.normalise('call me'), isNull);
      expect(w.normalise(''), isNull);
      expect(w.link('9876543210').toString(), 'https://wa.me/919876543210');
      final Uri withText = w.link('9876543210', message: 'Hi, is the flat available?')!;
      expect(withText.path, '/919876543210');
      expect(withText.queryParameters['text'], 'Hi, is the flat available?');
      expect(WhatsAppDirect.pretty('919876543210'), '+91 98765 43210');
    });

    test('opens wa.me, keeps recent numbers locally, forget and undo', () async {
      final FakeOpener opener = FakeOpener();
      final MemoryRecentNumberStore store = MemoryRecentNumberStore();
      final WhatsAppDirect w = WhatsAppDirect(store: store, opener: opener, keep: 3);
      expect(await w.openChat('98765 43210'), isTrue);
      expect(opener.opened.single.host, 'wa.me');
      expect(await w.openChat('bad'), isFalse);
      await w.openChat('+44 20 7946 0958');
      await w.openChat('9876543210');
      expect(w.recent, <String>['919876543210', '442079460958']);
      w.remember('+1 415 555 0100');
      w.remember('+61 2 9999 0000');
      expect(w.recent.length, 3);
      expect(w.forget('442079460958'), isFalse, reason: 'dropped past the limit');
      expect(w.forget(w.recent.first), isTrue);
      expect(w.undo(), isTrue);
      expect(w.recent.first, '61299990000');
      await Future<void>.delayed(Duration.zero);
      final WhatsAppDirect again = WhatsAppDirect(store: store);
      await again.load();
      expect(again.recent, w.recent);
    });
  });

  testWidgets('screen: open chat, recent, copy and share link, undo; 44 px', (WidgetTester tester) async {
    final SemanticsHandle sem = tester.ensureSemantics();
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final FakeOpener opener = FakeOpener();
    final WhatsAppDirect w = WhatsAppDirect(opener: opener);
    String? shared;
    String? copied;
    await tester.pumpWidget(MaterialApp(
      home: WhatsAppDirectScreen(direct: w, share: (String l) async => shared = l, copy: (String l) async => copied = l),
    ));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('wa-number')), '12');
    await tester.tap(find.byKey(const Key('wa-open')));
    await tester.pumpAndSettle();
    expect(opener.opened, isEmpty);

    await tester.enterText(find.byKey(const Key('wa-number')), '98765 43210');
    await tester.enterText(find.byKey(const Key('wa-message')), 'Hello');
    await tester.tap(find.byKey(const Key('wa-open')));
    await tester.pumpAndSettle();
    expect(opener.opened.single.toString(), 'https://wa.me/919876543210?text=Hello');
    expect(find.descendant(of: find.byKey(const Key('wa-recent-919876543210')), matching: find.text('+91 98765 43210')), findsOneWidget);
    expect(tester.getSize(find.byKey(const Key('wa-open'))).height, greaterThanOrEqualTo(44));
    expect(find.byTooltip('Forget this number'), findsOneWidget);

    await tester.tap(find.byKey(const Key('result-save')));
    await tester.pumpAndSettle();
    expect(copied, 'https://wa.me/919876543210?text=Hello');
    await tester.tap(find.byKey(const Key('result-share')));
    await tester.pumpAndSettle();
    expect(shared, copied);

    await tester.tap(find.byTooltip('Forget this number'));
    await tester.pumpAndSettle();
    expect(w.recent, isEmpty);
    await tester.tap(find.byKey(const Key('result-undo')));
    await tester.pumpAndSettle();
    expect(w.recent, <String>['919876543210']);
    await tester.pumpAndSettle(const Duration(seconds: 5));
    sem.dispose();
  });
}
