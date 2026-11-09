import 'dart:async';

import 'package:flutter/material.dart';

import '../engines/platform/first_run.dart';
import '../engines/privacy/on_device_mode.dart';
import '../engines/security/app_lock.dart';
import '../engines/security/secure_notes.dart';
import '../engines/share/share_engine.dart';
import '../platform/first_run_store.dart';
import '../platform/lock_platform.dart';
import '../platform/on_device_mode_store.dart';
import '../platform/secure_notes_platform.dart';
import '../platform/share_sheet.dart';
import '../tools/app_lock/app_lock_settings_screen.dart';
import '../tools/phone_to_laptop/phone_to_laptop_screen.dart';
import '../tools/privacy/privacy_screen.dart';
import '../tools/qr_scanner/qr_scanner_screen.dart';
import '../tools/secure_notes/secure_notes_screen.dart';
import '../tools/send_original/send_original_screen.dart';
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

  final AppLock lock = AppLock(store: const SecureLockStore(), biometrics: PlatformBiometrics());
  AppLock.install(lock);
  unawaited(lock.load());

  final FirstRun firstRun = FirstRun(const PrefsFirstRunStore());
  FirstRun.install(firstRun);
  unawaited(firstRun.load());

  SecureNotes.install(SecureNotes(
    keyStore: const SecureKeyStore(),
    blobStore: const FileNoteBlobStore(),
    clipboard: const SystemClipboard(),
  ));

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
      id: 'app-lock',
      name: 'App lock',
      section: ToolSection.security,
      icon: Icons.lock_outline,
      featureNumber: 55,
      touches: const <DataTouch>{},
      builder: (BuildContext context) => const AppLockSettingsScreen(),
    ),
    ToolEntry(
      id: LockableIds.secureNotes,
      name: 'Secure notes',
      section: ToolSection.security,
      icon: Icons.sticky_note_2_outlined,
      featureNumber: 57,
      touches: const <DataTouch>{DataTouch.files, DataTouch.clipboard},
      builder: (BuildContext context) => const SecureNotesScreen(),
    ),
    ToolEntry(
      id: 'phone-to-laptop',
      name: 'Phone to laptop',
      section: ToolSection.share,
      icon: Icons.laptop_outlined,
      featureNumber: 62,
      touches: const <DataTouch>{DataTouch.files, DataTouch.lan},
      builder: (BuildContext context) => const PhoneToLaptopScreen(),
    ),
    ToolEntry(
      id: 'send-original',
      name: 'Send original',
      section: ToolSection.links,
      icon: Icons.high_quality_outlined,
      featureNumber: 128,
      builder: (BuildContext context) => const SendOriginalScreen(),
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
