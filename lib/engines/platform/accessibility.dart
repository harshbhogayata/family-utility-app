import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';

/// Feature 109 — Accessibility.
///
/// Dark mode (or follow the phone), text up to 200% of normal size (the
/// phone's own setting, plus an in-app boost, capped at 200%), and a
/// one-hand layout that lowers each screen so its top half is within
/// thumb reach; primary actions already sit in the bottom result bar.

enum AppThemeChoice {
  system('Follow the phone'),
  light('Light'),
  dark('Dark');

  const AppThemeChoice(this.label);
  final String label;
}

@immutable
class AccessibilitySettings {
  const AccessibilitySettings({
    this.theme = AppThemeChoice.system,
    this.textBoost = 1.0,
    this.oneHand = false,
  });

  final AppThemeChoice theme;

  /// Extra text size on top of the phone's setting, 1.0 to 2.0.
  final double textBoost;
  final bool oneHand;

  /// The largest text scale the app allows.
  static const double maxTextScale = 2.0;

  /// The text scale to use, given the phone's own: boosted, then capped.
  double textScaleFor(double phoneScale) =>
      (phoneScale * textBoost).clamp(1.0, maxTextScale).toDouble();

  AccessibilitySettings copyWith({AppThemeChoice? theme, double? textBoost, bool? oneHand}) => AccessibilitySettings(
        theme: theme ?? this.theme,
        textBoost: (textBoost ?? this.textBoost).clamp(1.0, maxTextScale).toDouble(),
        oneHand: oneHand ?? this.oneHand,
      );

  String encode() => jsonEncode(<String, Object?>{'theme': theme.name, 'text': textBoost, 'oneHand': oneHand});

  static AccessibilitySettings decode(String? text) {
    if (text == null || text.isEmpty) {
      return const AccessibilitySettings();
    }
    try {
      final Object? j = jsonDecode(text);
      if (j is! Map<String, Object?>) {
        return const AccessibilitySettings();
      }
      final Object? t = j['text'];
      return const AccessibilitySettings().copyWith(
        theme: AppThemeChoice.values.firstWhere((AppThemeChoice c) => c.name == j['theme'],
            orElse: () => AppThemeChoice.system),
        textBoost: t is num ? t.toDouble() : 1.0,
        oneHand: j['oneHand'] == true,
      );
    } catch (_) {
      return const AccessibilitySettings();
    }
  }

  String describe() => 'Theme: ${theme.label}\n'
      'Text size: ${(textBoost * 100).round()}% of the phone\'s setting, up to ${(maxTextScale * 100).round()}%\n'
      'One-hand layout: ${oneHand ? 'on' : 'off'}\n';

  @override
  bool operator ==(Object other) =>
      other is AccessibilitySettings &&
      other.theme == theme &&
      other.textBoost == textBoost &&
      other.oneHand == oneHand;

  @override
  int get hashCode => Object.hash(theme, textBoost, oneHand);
}

abstract class AccessibilityStore {
  Future<String?> read();

  Future<void> write(String value);
}

class MemoryAccessibilityStore implements AccessibilityStore {
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String v) async => value = v;
}

class AccessibilityPrefs extends ValueNotifier<AccessibilitySettings> {
  AccessibilityPrefs(this._store) : super(const AccessibilitySettings());

  final AccessibilityStore _store;
  AccessibilitySettings? _before;

  bool get canUndo => _before != null;

  Future<void> load() async {
    try {
      value = AccessibilitySettings.decode(await _store.read());
    } catch (_) {
      value = const AccessibilitySettings();
    }
  }

  Future<void> set(AccessibilitySettings next) async {
    if (next == value) {
      return;
    }
    _before = value;
    value = next;
    try {
      await _store.write(next.encode());
    } catch (_) {
      // Kept for this run; saved next time.
    }
  }

  Future<bool> undo() async {
    final AccessibilitySettings? b = _before;
    if (b == null) {
      return false;
    }
    await set(b);
    _before = null;
    return true;
  }

  static AccessibilityPrefs instance = AccessibilityPrefs(MemoryAccessibilityStore());

  static void install(AccessibilityPrefs p) => instance = p;
}

/// WCAG relative luminance and contrast ratio.
double relativeLuminance(Color c) {
  double ch(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double contrastRatio(Color a, Color b) {
  final double la = relativeLuminance(a);
  final double lb = relativeLuminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}
