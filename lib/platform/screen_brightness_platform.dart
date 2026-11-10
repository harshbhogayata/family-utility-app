import 'package:flutter/foundation.dart';

import '../engines/records/loyalty_cards.dart';
import '../engines/video/video_player_engine.dart';

/// 100: full brightness for a card at the till. Reuses the window-only
/// brightness channel the video player (130) already has natively; the
/// system setting is never touched.
class WindowScreenBrightness implements ScreenBrightness {
  WindowScreenBrightness({PlayerPlatform? platform}) : _p = platform ?? PlayerPlatform.instance;

  final PlayerPlatform _p;

  @override
  Future<double?> current() async {
    // Android: clearing the window override hands brightness back to the
    // system (auto-brightness included). iOS has no override, so the old
    // level is put back by hand.
    if (defaultTargetPlatform == TargetPlatform.android) {
      return null;
    }
    return _p.brightness();
  }

  @override
  Future<void> set(double? level) => _p.setBrightness(level);
}
