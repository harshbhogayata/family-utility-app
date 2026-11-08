import 'dart:async';

import 'package:flutter/material.dart';

import '../engines/privacy/on_device_mode.dart';
import '../engines/share/share_engine.dart';
import '../platform/on_device_mode_store.dart';
import '../platform/share_sheet.dart';
import '../tools/privacy/privacy_screen.dart';
import '../tools/qr_scanner/qr_scanner_screen.dart';
import 'tool_registry.dart';

/// Registers every tool with the registry and installs app-wide state.
/// Each feature adds its entry here so the home grid is driven by one list.
void bootstrap() {
  final OnDeviceMode mode = OnDeviceMode(const PrefsOnDeviceModeStore());
  OnDeviceMode.install(mode);
  // Default is on; a saved "off" is applied once preferences load.
  unawaited(mode.load());

  final ShareEngine share = ShareEngine(const SystemShareSheet(), const PrefsShareTargetStore());
  ShareEngine.install(share);
  unawaited(share.load());

  ToolRegistry.registerAll(<ToolEntry>[
    ToolEntry(
      id: 'qr-scanner',
      name: 'QR scanner',
      section: ToolSection.scan,
      icon: Icons.qr_code_scanner,
      featureNumber: 51,
      touches: const <DataTouch>{
        DataTouch.camera,
        DataTouch.contacts,
        DataTouch.calendar,
        DataTouch.clipboard,
        DataTouch.files,
      },
      builder: (BuildContext context) => const QrScannerScreen(),
    ),
    ToolEntry(
      id: 'on-device-mode',
      name: 'On-device mode',
      section: ToolSection.security,
      icon: Icons.shield_outlined,
      featureNumber: 59,
      touches: const <DataTouch>{},
      builder: (BuildContext context) => const PrivacyScreen(),
    ),
  ]);
}
