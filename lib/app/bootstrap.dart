import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../engines/platform/action_history.dart';
import '../engines/platform/file_manager.dart';
import '../engines/platform/first_run.dart';
import '../engines/platform/one_search.dart';
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
import '../tools/compress_images/compress_images_screen.dart';
import '../tools/compress_pdf/compress_pdf_screen.dart';
import '../tools/crop/crop_screen.dart';
import '../tools/pdf_target_size/pdf_target_size_screen.dart';
import '../tools/history/history_screen.dart';
import '../tools/one_search/one_search_screen.dart';
import '../tools/pdf_viewer/pdf_viewer_screen.dart';
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

  Future<Directory> appFolder(String name) async {
    final Directory base = await getApplicationDocumentsDirectory();
    return Directory('${base.path}/$name');
  }

  final ActionHistory history = ActionHistory(
    store: FileHistoryStore(() => appFolder('history')),
    bin: DirectoryTrashBin(() => appFolder('trash')),
  );
  ActionHistory.install(history);
  unawaited(history.load());

  final FileManager files = FileManager(
    source: const LocalFileSource(),
    history: history,
    store: JsonFileManagerStore(() => appFolder('history')),
  );
  FileManager.install(files);
  unawaited(files.load());
  unawaited(_resolveRoots(files));

  SecureNotes.install(SecureNotes(
    keyStore: const SecureKeyStore(),
    blobStore: const FileNoteBlobStore(),
    clipboard: const SystemClipboard(),
  ));

  final OcrTextStore ocr = OcrTextStore(FileOcrBackend(() => appFolder('search')));
  OcrTextStore.install(ocr);
  unawaited(ocr.load());

  OneSearch.install(OneSearch(<SearchSource>[
    ToolSearchSource(() => ToolRegistry.all
        .map((ToolEntry t) => ToolInfo(id: t.id, name: t.name, section: t.section.label))
        .toList()),
    FileSearchSource(files),
    ocr,
    HistorySearchSource(history),
    RecordSearchSource(SecureNotes.instance),
  ]));

  ToolRegistry.registerAll(<ToolEntry>[
    ToolEntry(
      id: 'one-search',
      name: 'Search',
      section: ToolSection.platform,
      icon: Icons.search,
      featureNumber: 114,
      builder: (BuildContext context) => const OneSearchScreen(),
    ),
    ToolEntry(
      id: 'pdf-viewer',
      name: 'PDF viewer',
      section: ToolSection.pdf,
      icon: Icons.picture_as_pdf_outlined,
      featureNumber: 1,
      builder: (BuildContext context) => const PdfViewerScreen(),
    ),
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
      id: 'compress-pdf',
      name: 'Compress PDF',
      section: ToolSection.compress,
      icon: Icons.compress,
      featureNumber: 32,
      builder: (BuildContext context) => const CompressPdfScreen(),
    ),
    ToolEntry(
      id: 'pdf-target-size',
      name: 'PDF to target size',
      section: ToolSection.compress,
      icon: Icons.straighten,
      featureNumber: 33,
      builder: (BuildContext context) => const PdfTargetSizeScreen(),
    ),
    ToolEntry(
      id: 'compress-images',
      name: 'Compress images',
      section: ToolSection.compress,
      icon: Icons.photo_size_select_large_outlined,
      featureNumber: 34,
      builder: (BuildContext context) => const CompressImagesScreen(),
    ),
    ToolEntry(
      id: 'crop',
      name: 'Crop',
      section: ToolSection.image,
      icon: Icons.crop,
      featureNumber: 41,
      builder: (BuildContext context) => const CropScreen(),
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
      id: 'history',
      name: 'History and trash',
      section: ToolSection.platform,
      icon: Icons.history,
      featureNumber: 118,
      builder: (BuildContext context) => const HistoryScreen(),
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

/// App files always; the phone's shared storage on Android when it exists.
Future<void> _resolveRoots(FileManager files) async {
  try {
    final Directory docs = await getApplicationDocumentsDirectory();
    final List<FileRoot> roots = <FileRoot>[FileRoot('App files', docs.path)];
    if (Platform.isAndroid && Directory('/storage/emulated/0').existsSync()) {
      roots.add(const FileRoot('Phone storage', '/storage/emulated/0'));
    }
    files.setRoots(roots);
  } catch (_) {
    // No platform folders (tests): the Files tab shows no roots.
  }
}
