import 'package:flutter/foundation.dart';

/// Feature 059 — On-device mode.
///
/// One global switch, default on, that keeps every tool local. Tools that
/// need the network declare it on their registry entry; while the switch is
/// on they are greyed out with a reason instead of opening. Nothing here
/// talks to the network itself.

/// What a tool touches on the phone. Shown on the privacy screen so the
/// person can see exactly what each tool reads or writes.
enum DataTouch {
  files('Files you pick', 'Reads the files you choose and writes results to the app folder'),
  camera('Camera', 'Only while the tool is open; frames are decoded on the phone'),
  photos('Photos', 'Reads photos you pick; saves results to your gallery when you ask'),
  contacts('Contacts', 'Only when you tap Save to contacts'),
  calendar('Calendar', 'Only when you tap Add to calendar'),
  clipboard('Clipboard', 'Only when you tap Copy, or paste into the app'),
  microphone('Microphone', 'Only while recording'),
  location('Location', 'Only for family features you turn on'),
  lan('Home Wi-Fi', 'Talks only to devices on the same Wi-Fi; nothing goes to the internet'),
  network('Network', 'Needed for this tool; off in on-device mode');

  const DataTouch(this.label, this.explanation);

  final String label;
  final String explanation;
}

/// Where the switch is remembered between launches.
abstract class OnDeviceModeStore {
  /// Null when nothing was saved yet (first run keeps the default: on).
  Future<bool?> read();

  Future<void> write(bool on);
}

/// In-memory store for tests and as the safe default before bootstrap.
class MemoryOnDeviceModeStore implements OnDeviceModeStore {
  MemoryOnDeviceModeStore([this._value]);

  bool? _value;

  @override
  Future<bool?> read() async => _value;

  @override
  Future<void> write(bool on) async => _value = on;
}

/// The switch. Listen to it like any [ValueListenable]; true means on.
class OnDeviceMode extends ValueNotifier<bool> {
  OnDeviceMode(this._store) : super(true);

  final OnDeviceModeStore _store;

  /// Default on. A saved value overrides it; a store failure keeps the default.
  Future<void> load() async {
    try {
      final bool? saved = await _store.read();
      if (saved != null) {
        value = saved;
      }
    } catch (_) {
      // Keep the default (on). Never let a storage hiccup turn privacy off.
    }
  }

  bool get isOn => value;

  Future<void> set(bool on) async {
    value = on;
    try {
      await _store.write(on);
    } catch (_) {
      // The in-memory value still applies for this launch.
    }
  }

  /// Whether a tool that [needsNetwork] may open right now.
  bool allows({required bool needsNetwork}) => !needsNetwork || !value;

  /// The one shared switch. Bootstrap installs the persistent store.
  static OnDeviceMode instance = OnDeviceMode(MemoryOnDeviceModeStore());

  static void install(OnDeviceMode mode) {
    instance = mode;
  }
}
