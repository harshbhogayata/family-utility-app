import 'package:family_utility_app/app/theme.dart';
import 'package:family_utility_app/engines/security/app_lock.dart';
import 'package:family_utility_app/tools/app_lock/app_lock_settings_screen.dart';
import 'package:family_utility_app/tools/app_lock/lock_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeBiometrics implements Biometrics {
  bool available = true;
  bool accept = true;
  int prompts = 0;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<bool> authenticate(String reason) async {
    prompts++;
    return accept;
  }
}

class FakeClock {
  DateTime now = DateTime(2026, 11, 8, 12);
  void advance(Duration d) => now = now.add(d);
}

Widget app(Widget home) => MaterialApp(theme: buildAppTheme(), home: home);

Future<void> typePin(WidgetTester tester, String pin) async {
  for (final String d in pin.split('')) {
    await tester.tap(find.byKey(ValueKey<String>('pin-$d')));
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

void main() {
  late MemoryLockStore store;
  late FakeBiometrics bio;
  late FakeClock clock;
  late AppLock lock;

  setUp(() {
    store = MemoryLockStore();
    bio = FakeBiometrics();
    clock = FakeClock();
    lock = AppLock(store: store, biometrics: bio, now: () => clock.now);
    AppLock.install(lock);
  });

  group('PinHasher', () {
    test('hashes are salted, stretched and never the PIN itself', () {
      final String salt = PinHasher.newSalt();
      final String h = PinHasher.hash('1234', salt);
      expect(h, isNot(contains('1234')));
      expect(h, isNot(PinHasher.hash('1234', PinHasher.newSalt())));
      expect(PinHasher.verify('1234', salt, h), isTrue);
      expect(PinHasher.verify('1235', salt, h), isFalse);
      expect(PinHasher.isValidPin('123'), isFalse);
      expect(PinHasher.isValidPin('12a4'), isFalse);
      expect(PinHasher.isValidPin('123456'), isTrue);
      expect(PinHasher.isValidPin('1234567'), isFalse);
    });
  });

  group('AppLock engine', () {
    test('off by default; setPin turns it on and stores only a hash', () async {
      await lock.load();
      expect(lock.isEnabled, isFalse);
      expect(lock.isLocked, isFalse);
      await lock.setPin('2468');
      expect(lock.isEnabled, isTrue);
      final LockSettings saved = (await store.read())!;
      expect(saved.enabled, isTrue);
      expect(saved.pinLength, 4);
      expect(saved.encode(), isNot(contains('2468')));
      expect(() => lock.setPin('12'), throwsArgumentError);
    });

    test('a fresh launch with a PIN starts locked; PIN unlocks; wrong PIN does not', () async {
      await lock.setPin('2468');
      final AppLock relaunch = AppLock(store: store, now: () => clock.now);
      await relaunch.load();
      expect(relaunch.isLocked, isTrue);
      expect(await relaunch.unlockWithPin('0000'), UnlockFailure.wrongPin);
      expect(relaunch.isLocked, isTrue);
      expect(await relaunch.unlockWithPin('2468'), isNull);
      expect(relaunch.isLocked, isFalse);
    });

    test('five wrong PINs lock out for 30 seconds, then the right PIN works', () async {
      await lock.setPin('2468');
      lock.lock();
      for (int i = 0; i < AppLock.maxAttempts - 1; i++) {
        expect(await lock.unlockWithPin('0000'), UnlockFailure.wrongPin);
      }
      expect(await lock.unlockWithPin('0000'), UnlockFailure.lockedOut);
      expect(lock.lockoutSecondsLeft, AppLock.lockoutFor.inSeconds);
      expect(await lock.unlockWithPin('2468'), UnlockFailure.lockedOut, reason: 'even the right PIN waits');
      expect(await lock.unlockWithBiometrics(), isFalse, reason: 'biometrics never bypass a lockout');
      clock.advance(AppLock.lockoutFor + const Duration(seconds: 1));
      expect(lock.lockoutSecondsLeft, 0);
      expect(await lock.unlockWithPin('2468'), isNull);
    });

    test('timeout: relocks only after the chosen time in the background', () async {
      await lock.setPin('2468');
      await lock.setTimeout(LockTimeout.fiveMinutes);
      expect(lock.isLocked, isFalse);
      lock.onBackground();
      clock.advance(const Duration(minutes: 2));
      lock.onForeground();
      expect(lock.isLocked, isFalse);
      lock.onBackground();
      clock.advance(const Duration(minutes: 5));
      lock.onForeground();
      expect(lock.isLocked, isTrue);

      await lock.unlockWithPin('2468');
      await lock.setTimeout(LockTimeout.immediately);
      lock.onBackground();
      lock.onForeground();
      expect(lock.isLocked, isTrue);
      expect((await store.read())!.timeout, LockTimeout.immediately);
    });

    test('biometrics unlock only when offered and confirmed', () async {
      await lock.setPin('2468');
      lock.lock();
      expect(await lock.unlockWithBiometrics(), isFalse, reason: 'not turned on yet');
      expect(bio.prompts, 0);
      await lock.setBiometrics(true);
      bio.accept = false;
      expect(await lock.unlockWithBiometrics(), isFalse);
      expect(lock.isLocked, isTrue);
      bio.accept = true;
      expect(await lock.unlockWithBiometrics(), isTrue);
      expect(lock.isLocked, isFalse);
    });

    test('per-tool locks ask once per unlock and survive a restart', () async {
      await lock.setPin('2468');
      expect(lock.needsUnlockFor(LockableIds.vault), isFalse);
      await lock.setToolLocked(LockableIds.vault, true);
      await lock.setToolLocked(LockableIds.records, true);
      expect(lock.needsUnlockFor(LockableIds.vault), isTrue);
      lock.markOpened(LockableIds.vault);
      expect(lock.needsUnlockFor(LockableIds.vault), isFalse);
      expect(lock.needsUnlockFor(LockableIds.records), isTrue);
      lock.lock();
      expect(lock.needsUnlockFor(LockableIds.vault), isTrue, reason: 'locking the app forgets tool unlocks');

      final AppLock relaunch = AppLock(store: store, now: () => clock.now);
      await relaunch.load();
      expect(relaunch.settings.lockedIds, <String>{LockableIds.vault, LockableIds.records});
      await relaunch.unlockWithPin('2468');
      expect(relaunch.needsUnlockFor(LockableIds.records), isTrue);
    });

    test('disable forgets the PIN but keeps the per-tool choices for next time', () async {
      await lock.setPin('2468');
      await lock.setToolLocked(LockableIds.vault, true);
      await lock.disable();
      expect(lock.isEnabled, isFalse);
      expect(lock.isLocked, isFalse);
      expect(lock.settings.pinHash, isNull);
      expect(lock.settings.lockedIds, contains(LockableIds.vault));
      expect(lock.needsUnlockFor(LockableIds.vault), isFalse, reason: 'no PIN, no lock');
    });

    test('settings round-trip through JSON', () {
      const LockSettings s = LockSettings(
        enabled: true,
        pinHash: 'h',
        salt: 's',
        pinLength: 6,
        biometrics: true,
        timeout: LockTimeout.oneHour,
        lockedIds: <String>{'b', 'a'},
      );
      final LockSettings back = LockSettings.decode(s.encode());
      expect(back.enabled, isTrue);
      expect(back.pinHash, 'h');
      expect(back.pinLength, 6);
      expect(back.biometrics, isTrue);
      expect(back.timeout, LockTimeout.oneHour);
      expect(back.lockedIds, <String>{'a', 'b'});
      expect(LockSettings.decode('garbage-free').enabled, isFalse);
    });
  });

  group('LockGate and LockScreen', () {
    testWidgets('a locked app shows the PIN pad, not the content, until the PIN is typed',
        (WidgetTester tester) async {
      await lock.setPin('2468');
      lock.lock();
      await tester.pumpWidget(app(const LockGate(child: Scaffold(body: Text('secret content')))));
      expect(find.text('secret content'), findsNothing);
      expect(find.byKey(const Key('app-lock-screen')), findsOneWidget);
      expect(find.text('Enter your PIN'), findsOneWidget);

      await typePin(tester, '1111');
      expect(find.text('Wrong PIN. Try again.'), findsOneWidget);
      expect(find.text('secret content'), findsNothing);

      await typePin(tester, '2468');
      expect(find.text('secret content'), findsOneWidget);
      expect(find.byKey(const Key('app-lock-screen')), findsNothing);
    });

    testWidgets('pad keys are at least 44 px and labelled for screen readers', (WidgetTester tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await lock.setPin('2468');
      await lock.setBiometrics(true);
      lock.lock();
      bio.accept = false;
      await tester.pumpWidget(app(const LockGate(child: SizedBox())));
      await tester.pumpAndSettle();
      for (final String d in <String>['0', '1', '5', '9']) {
        final Size size = tester.getSize(find.byKey(ValueKey<String>('pin-$d')));
        expect(size.height, greaterThanOrEqualTo(44));
        expect(size.width, greaterThanOrEqualTo(44));
      }
      expect(find.bySemanticsLabel('Delete last digit'), findsOneWidget);
      expect(find.bySemanticsLabel('Use fingerprint or face'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('digits entered')), findsOneWidget);
      handle.dispose();
    });

    testWidgets('biometrics are offered on the lock screen and unlock in one tap',
        (WidgetTester tester) async {
      await lock.setPin('2468');
      await lock.setBiometrics(true);
      lock.lock();
      bio.accept = false;
      await tester.pumpWidget(app(const LockGate(child: Text('secret content'))));
      await tester.pumpAndSettle();
      expect(bio.prompts, 1, reason: 'prompted once automatically');
      expect(find.text('secret content'), findsNothing);
      bio.accept = true;
      await tester.tap(find.byKey(const Key('pin-biometrics')));
      await tester.pumpAndSettle();
      expect(bio.prompts, 2);
      expect(find.text('secret content'), findsOneWidget);
    });

    testWidgets('backspace removes the last digit', (WidgetTester tester) async {
      await lock.setPin('2468');
      lock.lock();
      await tester.pumpWidget(app(const LockGate(child: SizedBox())));
      await typePin(tester, '24');
      await tester.tap(find.byKey(const Key('pin-backspace')));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel(RegExp('1 of 4 digits entered')), findsOneWidget);
    });
  });

  group('per-tool lock UI', () {
    testWidgets('a locked section shows Unlock, asks for the PIN, then shows content',
        (WidgetTester tester) async {
      await lock.setPin('2468');
      await lock.setToolLocked(LockableIds.records, true);
      await tester.pumpWidget(app(const Scaffold(
        body: LockedSection(id: LockableIds.records, child: Text('your records')),
      )));
      expect(find.text('your records'), findsNothing);
      await tester.tap(find.byKey(const ValueKey<String>('unlock-records')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Enter your PIN to open Records'), findsOneWidget);
      await typePin(tester, '2468');
      expect(find.text('your records'), findsOneWidget);
    });

    testWidgets('ensureUnlockedFor returns true straight away for unlocked tools',
        (WidgetTester tester) async {
      await lock.setPin('2468');
      bool? result;
      await tester.pumpWidget(app(Builder(
        builder: (BuildContext context) => TextButton(
          onPressed: () async => result = await ensureUnlockedFor(context, 'merge-pdf'),
          child: const Text('go'),
        ),
      )));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(result, isTrue);
    });
  });

  group('settings screen', () {
    testWidgets('turning the lock on asks for a PIN twice, then shows timeout and tool locks',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 4000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(app(const AppLockSettingsScreen()));
      await tester.pumpAndSettle();
      expect(find.text('Lock again'), findsNothing);

      await tester.tap(find.byKey(const Key('lock-enabled')));
      await tester.pumpAndSettle();
      expect(find.text('Choose a PIN'), findsOneWidget);
      await typePin(tester, '2468');
      await tester.tap(find.byKey(const Key('pin-next')));
      await tester.pumpAndSettle();
      expect(find.text('Repeat the PIN'), findsOneWidget);
      await typePin(tester, '2468');

      expect(lock.isEnabled, isTrue);
      expect(find.text('Lock again'), findsOneWidget);
      expect(find.text('Fingerprint or face'), findsOneWidget);

      await tester.ensureVisible(find.byKey(const ValueKey<String>('timeout-oneMinute')));
      await tester.tap(find.byKey(const ValueKey<String>('timeout-oneMinute')));
      await tester.pumpAndSettle();
      expect(lock.settings.timeout, LockTimeout.oneMinute);

      await tester.ensureVisible(find.byKey(const ValueKey<String>('tool-lock-${LockableIds.vault}')));
      await tester.tap(find.byKey(const ValueKey<String>('tool-lock-${LockableIds.vault}')));
      await tester.pumpAndSettle();
      expect(lock.settings.lockedIds, contains(LockableIds.vault));

      await tester.ensureVisible(find.byKey(const Key('lock-biometrics')));
      await tester.tap(find.byKey(const Key('lock-biometrics')));
      await tester.pumpAndSettle();
      expect(lock.settings.biometrics, isTrue);
    });

    testWidgets('mismatched PINs start over', (WidgetTester tester) async {
      await tester.pumpWidget(app(const AppLockSettingsScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('lock-enabled')));
      await tester.pumpAndSettle();
      await typePin(tester, '2468');
      await tester.tap(find.byKey(const Key('pin-next')));
      await tester.pumpAndSettle();
      await typePin(tester, '2469');
      expect(find.text('The PINs did not match. Start again.'), findsOneWidget);
      expect(find.text('Choose a PIN'), findsOneWidget);
      expect(lock.isEnabled, isFalse);
    });

    testWidgets('turning the lock off asks first', (WidgetTester tester) async {
      await lock.setPin('2468');
      await tester.pumpWidget(app(const AppLockSettingsScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('lock-enabled')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keep lock'));
      await tester.pumpAndSettle();
      expect(lock.isEnabled, isTrue);
      await tester.tap(find.byKey(const Key('lock-enabled')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Turn off'));
      await tester.pumpAndSettle();
      expect(lock.isEnabled, isFalse);
    });
  });
}
