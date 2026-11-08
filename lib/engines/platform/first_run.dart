import 'package:flutter/foundation.dart';

/// Feature 111 — No login.
///
/// There is nothing to sign up for. The only thing the app remembers about
/// a first run is whether the one-time welcome card was dismissed, and
/// [AccountPolicy] is the written rule (checked in CI) that no sign-in,
/// sign-up or account screen may ever appear.

abstract class FirstRunStore {
  /// True once the welcome card was dismissed.
  Future<bool> readWelcomeDone();

  Future<void> writeWelcomeDone();
}

class MemoryFirstRunStore implements FirstRunStore {
  MemoryFirstRunStore([this._done = false]);

  bool _done;

  @override
  Future<bool> readWelcomeDone() async => _done;

  @override
  Future<void> writeWelcomeDone() async => _done = true;
}

/// Whether to show the one-time "no account needed" card. True until the
/// store says it was dismissed; a store failure leaves it hidden, so a
/// hiccup never puts a card between the person and the first tool.
class FirstRun extends ValueNotifier<bool> {
  FirstRun(this._store) : super(false);

  final FirstRunStore _store;

  bool get showWelcome => value;

  Future<void> load() async {
    try {
      value = !await _store.readWelcomeDone();
    } catch (_) {
      value = false;
    }
  }

  Future<void> dismiss() async {
    value = false;
    try {
      await _store.writeWelcomeDone();
    } catch (_) {
      // Shown again next launch at worst.
    }
  }

  static FirstRun instance = FirstRun(MemoryFirstRunStore(true));

  static void install(FirstRun f) {
    instance = f;
  }
}

/// The no-account rule, as data the CI test checks against lib/ and pubspec.
abstract final class AccountPolicy {
  /// Words that would only appear on an account screen.
  static const List<String> forbiddenCopy = <String>[
    'Sign in',
    'Sign up',
    'Log in',
    'Login',
    'Create account',
    'Create an account',
    'Forgot password',
    'Verify your email',
    'Enter OTP',
  ];

  /// Packages that exist to put an account or a vendor server in the app.
  static const List<String> forbiddenPackages = <String>[
    'firebase_auth',
    'firebase_core',
    'firebase_analytics',
    'google_sign_in',
    'sign_in_with_apple',
    'supabase',
    'amplify',
    'sentry',
    'mixpanel',
    'amplitude',
    'google_mobile_ads',
    'onesignal',
  ];

  /// Copy that is allowed even though it contains a forbidden word
  /// (talking about the rule itself, or a device-level action).
  static const List<String> allowedPhrases = <String>[
    'No sign-up',
    'no sign-up',
    'no login',
    'No login',
    'nothing to sign up for',
    'Nothing to sign up for',
    'sign-in screens',
  ];

  static List<String> violationsInSource(String path, String source) {
    String text = source;
    for (final String ok in allowedPhrases) {
      text = text.replaceAll(ok, '');
    }
    final List<String> out = <String>[];
    for (final String word in forbiddenCopy) {
      if (text.contains(word)) {
        out.add('$path contains "$word"');
      }
    }
    return out;
  }

  static List<String> violationsInPubspec(String pubspec) {
    final List<String> out = <String>[];
    for (final String pkg in forbiddenPackages) {
      if (RegExp('^\\s+$pkg[a-z_]*:', multiLine: true).hasMatch(pubspec)) {
        out.add('pubspec declares $pkg');
      }
    }
    return out;
  }
}
