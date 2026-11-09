import 'dart:async';
import 'dart:typed_data';

import 'package:family_utility_app/app/theme.dart';
import 'package:family_utility_app/engines/share/copy_result.dart';
import 'package:family_utility_app/tools/copy_result/copy_result_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

Uint8List png() {
  final img.Image im = img.Image(width: 8, height: 8);
  img.fill(im, color: img.ColorRgb8(10, 120, 200));
  return img.encodePng(im);
}

/// A scheduler the test fires by hand.
class ManualScheduler {
  final List<void Function()> pending = <void Function()>[];
  Duration? lastDelay;

  Timer call(Duration after, void Function() cb) {
    lastDelay = after;
    pending.add(cb);
    return _FakeTimer();
  }

  Future<void> fireAll() async {
    final List<void Function()> run = List<void Function()>.of(pending);
    pending.clear();
    for (final void Function() cb in run) {
      cb();
    }
    await Future<void>.delayed(Duration.zero);
  }
}

class _FakeTimer implements Timer {
  bool _active = true;

  @override
  void cancel() => _active = false;

  @override
  bool get isActive => _active;

  @override
  int get tick => 0;
}

class FakeFiles implements CopyFiles {
  final Map<String, Uint8List> written = <String, Uint8List>{};

  @override
  Future<Uint8List?> pickImage() async => png();

  @override
  Future<String> write(String name, Uint8List bytes) async {
    final String p = '/copied/$name';
    written[p] = bytes;
    return p;
  }

  @override
  Future<void> remove(String path) async => written.remove(path);
}

void main() {
  group('sensitive detection', () {
    test('OTPs, card numbers, PAN, Aadhaar and passwords are sensitive', () {
      expect(SensitiveText.looksSensitive('482913'), isTrue);
      expect(SensitiveText.looksSensitive('Your OTP is 4829 for login'), isTrue);
      expect(SensitiveText.looksSensitive('4111 1111 1111 1111'), isTrue);
      expect(SensitiveText.looksSensitive('PAN ABCDE1234F'), isTrue);
      expect(SensitiveText.looksSensitive('2345 6789 0123'), isTrue);
      expect(SensitiveText.looksSensitive('wifi password: hunter2'), isTrue);
    });

    test('ordinary text is not', () {
      expect(SensitiveText.looksSensitive('Buy milk and bread'), isFalse);
      expect(SensitiveText.looksSensitive('https://example.com/a'), isFalse);
      expect(SensitiveText.looksSensitive(''), isFalse);
      expect(SensitiveText.luhn('4111111111111112'), isFalse);
    });
  });

  group('engine', () {
    test('text copies as text and stays when not sensitive', () async {
      final MemoryClipboardBackend cb = MemoryClipboardBackend();
      final ManualScheduler s = ManualScheduler();
      final CopyResult e = CopyResult(cb, schedule: s.call);
      final CopyOutcome out = await e.copy(const CopyText('Buy milk'));
      expect(out.ok, isTrue);
      expect(out.willClear, isFalse);
      expect(cb.text, 'Buy milk');
      expect(s.pending, isEmpty);
    });

    test('sensitive text clears after 60 s', () async {
      final MemoryClipboardBackend cb = MemoryClipboardBackend();
      final ManualScheduler s = ManualScheduler();
      final DateTime t0 = DateTime(2026, 1, 1, 9);
      final CopyResult e = CopyResult(cb, schedule: s.call, now: () => t0);
      final CopyOutcome out = await e.copy(const CopyText('482913'));
      expect(out.willClear, isTrue);
      expect(out.clearsAt, t0.add(const Duration(seconds: 60)));
      expect(s.lastDelay, const Duration(seconds: 60));
      expect(out.message, contains('60 s'));
      await s.fireAll();
      expect(cb.text, '');
      expect(cb.clears, 1);
    });

    test('a later copy elsewhere is not wiped', () async {
      final MemoryClipboardBackend cb = MemoryClipboardBackend();
      final ManualScheduler s = ManualScheduler();
      final CopyResult e = CopyResult(cb, schedule: s.call);
      await e.copy(const CopyText('secret note', sensitive: true));
      cb.text = 'something the person copied in another app';
      await s.fireAll();
      expect(cb.text, 'something the person copied in another app');
      expect(cb.clears, 0);
    });

    test('images copy as images; unsupported phones say so', () async {
      final MemoryClipboardBackend cb = MemoryClipboardBackend();
      final ManualScheduler s = ManualScheduler();
      final CopyResult e = CopyResult(cb, schedule: s.call);
      final Uint8List bytes = png();
      final CopyOutcome out = await e.copy(CopyImage(bytes, sensitive: true));
      expect(out.ok, isTrue);
      expect(out.kind, 'image');
      expect(cb.image, bytes);
      expect(cb.text, isNull);
      await s.fireAll();
      expect(cb.image, isNull);

      final CopyResult none = CopyResult(MemoryClipboardBackend(supportsImages: false), schedule: s.call);
      final CopyOutcome no = await none.copy(CopyImage(bytes));
      expect(no.status, CopyStatus.unsupported);
      expect(no.message, contains('Share'));
    });

    test('undo puts the previous text back and cancels the clear', () async {
      final MemoryClipboardBackend cb = MemoryClipboardBackend()..text = 'before';
      final ManualScheduler s = ManualScheduler();
      final CopyResult e = CopyResult(cb, schedule: s.call);
      await e.copy(const CopyText('482913'));
      expect(e.canUndo, isTrue);
      expect(await e.undo(), isTrue);
      expect(cb.text, 'before');
      await s.fireAll();
      expect(cb.text, 'before');
      expect(e.canUndo, isFalse);
    });

    test('empty content is refused', () async {
      final CopyResult e = CopyResult(MemoryClipboardBackend());
      expect((await e.copy(const CopyText(''))).status, CopyStatus.empty);
      e.dispose();
    });
  });

  group('screen', () {
    Future<CopyResult> pump(WidgetTester tester, MemoryClipboardBackend cb, FakeFiles files) async {
      final CopyResult e = CopyResult(cb);
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: CopyResultScreen(engine: e, files: files),
      ));
      return e;
    }

    testWidgets('copies text, flags an OTP and counts down to clear', (WidgetTester tester) async {
      final MemoryClipboardBackend cb = MemoryClipboardBackend();
      final CopyResult e = await pump(tester, cb, FakeFiles());
      await tester.enterText(find.byKey(const Key('copy-text')), '482913');
      await tester.pump();
      expect(tester.widget<SwitchListTile>(find.byKey(const Key('copy-sensitive'))).value, isTrue);
      await tester.tap(find.byKey(const Key('copy-go')));
      await tester.pump();
      expect(cb.text, '482913');
      expect(find.byKey(const Key('copy-countdown')), findsOneWidget);
      await tester.pump(const Duration(seconds: 61));
      await tester.pump();
      expect(cb.text, '');
      expect(find.text('Clipboard cleared'), findsOneWidget);
      e.dispose();
    });

    testWidgets('copies a picture and saves it; undo restores', (WidgetTester tester) async {
      final MemoryClipboardBackend cb = MemoryClipboardBackend()..text = 'old';
      final FakeFiles files = FakeFiles();
      final CopyResult e = await pump(tester, cb, files);
      await tester.tap(find.byKey(const Key('copy-pick-image')));
      await tester.pump();
      expect(find.byKey(const Key('copy-image')), findsOneWidget);
      await tester.tap(find.byKey(const Key('copy-go')));
      await tester.pump();
      expect(cb.image, isNotNull);
      expect(find.text('Picture copied'), findsOneWidget);

      await tester.tap(find.byKey(const Key('result-save')));
      await tester.pump();
      expect(files.written.keys, contains('/copied/copied.png'));

      await tester.tap(find.byKey(const Key('result-undo')));
      await tester.pump();
      expect(cb.text, 'old');
      e.dispose();
    });

    testWidgets('touch targets and labels', (WidgetTester tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      final CopyResult e = await pump(tester, MemoryClipboardBackend(), FakeFiles());
      expect(tester.getSize(find.byKey(const Key('copy-go'))).height, greaterThanOrEqualTo(44));
      expect(tester.getSize(find.byKey(const Key('copy-pick-image'))).height, greaterThanOrEqualTo(44));
      expect(tester.getSize(find.byKey(const Key('copy-sensitive'))).height, greaterThanOrEqualTo(44));
      expect(find.bySemanticsLabel(RegExp('Copy')), findsWidgets);
      expect(find.bySemanticsLabel(RegExp('Sensitive')), findsWidgets);
      handle.dispose();
      e.dispose();
    });
  });
}
