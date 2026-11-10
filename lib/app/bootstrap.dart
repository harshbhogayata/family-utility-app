import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../engines/platform/accessibility.dart';
import '../engines/platform/action_history.dart';
import '../engines/platform/versions.dart';
import '../engines/platform/file_manager.dart';
import '../engines/platform/first_run.dart';
import '../engines/platform/one_search.dart';
import '../engines/privacy/on_device_mode.dart';
import '../engines/security/app_lock.dart';
import '../engines/family/check_ins.dart';
import '../engines/family/document_vault.dart';
import '../engines/family/family_location.dart';
import '../engines/security/private_vault.dart';
import '../engines/security/secure_notes.dart';
import '../engines/records/autofill_profile.dart';
import '../engines/share/share_engine.dart';
import '../platform/first_run_store.dart';
import '../platform/guest_mode_store.dart';
import '../engines/platform/guest_mode.dart';
import '../platform/profile_store.dart';
import '../engines/family/member_profiles.dart';
import '../platform/lock_platform.dart';
import '../platform/on_device_mode_store.dart';
import '../platform/secure_notes_platform.dart';
import '../platform/accessibility_store.dart';
import '../platform/document_vault_platform.dart';
import '../platform/location_platform.dart';
import '../platform/vault_platform.dart';
import '../platform/share_sheet.dart';
import '../tools/app_lock/app_lock_settings_screen.dart';
import '../tools/fill_forms/fill_forms_screen.dart';
import '../tools/archives/archives_screen.dart';
import '../tools/images_to_pdf/images_to_pdf_screen.dart';
import '../tools/text_to_pdf/text_to_pdf_screen.dart';
import '../tools/web_page_pdf/web_page_pdf_screen.dart';
import '../engines/pdf/text_to_pdf.dart';
import '../tools/document_scanner/document_scanner_screen.dart';
import '../engines/image/scan_entry.dart';
import 'app.dart';
import '../engines/family/shared_calendar.dart';
import '../engines/family/shared_shopping_list.dart';
import '../engines/family/shared_contacts.dart';
import '../engines/platform/backup_export.dart';
import '../engines/platform/cross_links.dart';
import '../engines/family/family_roles.dart';
import '../family/roles/family_roles_screen.dart';
import '../platform/backup_platform.dart';
import '../tools/backup/backup_screen.dart';
import '../platform/calendar_platform.dart';
import '../tools/convert_anything/convert_anything_screen.dart';
import '../tools/unlock_pdf/unlock_pdf_screen.dart';
import '../tools/word_pdf/word_pdf_screen.dart';
import '../tools/resize/resize_screen.dart';
import '../tools/passport_photo/passport_photo_screen.dart';
import '../tools/id_card/id_card_screen.dart';
import '../tools/id_scan/id_scan_screen.dart';
import '../tools/pdf_to_images/pdf_to_images_screen.dart';
import '../tools/webp/webp_screen.dart';
import '../tools/raster/raster_screen.dart';
import '../tools/zip/zip_screen.dart';
import '../tools/exif/exif_screen.dart';
import '../tools/qr_generator/qr_generator_screen.dart';
import '../engines/image/exif_strip.dart';
import '../platform/strip_on_share_prefs.dart';
import '../tools/status_saver/status_saver_screen.dart';
import '../tools/deleted_messages/deleted_messages_screen.dart';
import '../engines/download/download_queue.dart';
import '../engines/privacy/offline_policy.dart';
import '../tools/download_queue/download_queue_screen.dart';
import '../engines/download/shared_link.dart';
import '../engines/download/video_link.dart';
import '../platform/video_notice_prefs.dart';
import '../tools/video_link/video_link_screen.dart';
import '../tools/audio_link/audio_link_screen.dart';
import '../tools/batch_convert/batch_convert_screen.dart';
import '../tools/batch/batch_screen.dart';
import '../tools/versions/versions_screen.dart';
import '../engines/image/heic_convert.dart';
import '../engines/share/shared_files.dart';
import '../engines/share/open_with.dart';
import '../platform/default_app_prompt_store.dart';
import '../tools/open_with/opened_file_screen.dart';
import '../platform/heic_platform.dart';
import '../tools/heic/heic_screen.dart';
import '../engines/image/avif_convert.dart';
import '../platform/avif_platform.dart';
import '../tools/avif/avif_screen.dart';
import '../engines/download/clipboard_watch.dart';
import '../platform/clipboard_watch_platform.dart';
import '../tools/clipboard_watch/clipboard_watch_screen.dart';
import '../tools/merge_pdf/merge_pdf_screen.dart';
import '../tools/split_pdf/split_pdf_screen.dart';
import '../tools/extract_pages/extract_pages_screen.dart';
import '../tools/remove_pages/remove_pages_screen.dart';
import '../tools/reorder_pages/reorder_pages_screen.dart';
import '../tools/rotate_pages/rotate_pages_screen.dart';
import '../tools/protect_pdf/protect_pdf_screen.dart';
import '../tools/cloud/cloud_screen.dart';
import '../tools/exact_kb/exact_kb_screen.dart';
import '../engines/convert/convert_registry.dart';
import '../engines/convert/word_converters.dart';
import '../platform/pdfrx_text_source.dart';
import '../tools/compress_images/compress_images_screen.dart';
import '../tools/compress_pdf/compress_pdf_screen.dart';
import '../tools/crop/crop_screen.dart';
import '../tools/pdf_target_size/pdf_target_size_screen.dart';
import '../tools/print_to_pdf/print_to_pdf_screen.dart';
import '../tools/history/history_screen.dart';
import '../tools/one_search/one_search_screen.dart';
import '../tools/pdf_viewer/pdf_viewer_screen.dart';
import '../engines/pdf/pdf_text_search.dart';
import '../tools/pdf_search/pdf_search_screen.dart';
import '../tools/ocr_scan/ocr_scan_screen.dart';
import '../tools/clean_scan/clean_scan_screen.dart';
import '../tools/excel_pdf/excel_pdf_screen.dart';
import '../tools/powerpoint_pdf/powerpoint_pdf_screen.dart';
import '../engines/convert/slides.dart';
import '../tools/rotate_flip/rotate_flip_screen.dart';
import '../engines/convert/sheet_converters.dart';
import '../tools/redact/redact_screen.dart';
import '../tools/redact_pdf/redact_pdf_screen.dart';
import '../tools/page_numbers/page_numbers_screen.dart';
import '../tools/encrypt_file/encrypt_file_screen.dart';
import '../engines/image/scan_namer.dart';
import '../engines/image/one_tap_scan.dart';
import '../platform/mlkit_text_platform.dart';
import '../platform/scan_name_prefs.dart';
import '../tools/phone_to_laptop/phone_to_laptop_screen.dart';
import '../tools/nearby_share/nearby_share_screen.dart';
import '../tools/accessibility/accessibility_screen.dart';
import '../tools/custom_home/custom_home_screen.dart';
import '../tools/guest_mode/guest_mode_screen.dart';
import '../tools/language/language_screen.dart';
import '../engines/platform/home_widgets.dart';
import '../platform/speed_dial_store.dart';
import '../tools/home_widget/home_widget_screen.dart';
import '../tools/paste_anything/paste_sheet.dart';
import '../tools/privacy/privacy_screen.dart';
import '../tools/qr_scanner/qr_scanner_screen.dart';
import '../tools/private_vault/private_vault_screen.dart';
import '../tools/secure_notes/secure_notes_screen.dart';
import '../tools/send_original/send_original_screen.dart';
import '../tools/sign_pdf/sign_pdf_screen.dart';
import '../engines/share/save_anywhere.dart';
import '../platform/save_platform.dart';
import '../engines/share/copy_result.dart';
import '../platform/clipboard_platform.dart';
import '../tools/copy_result/copy_result_screen.dart';
import '../engines/platform/background_jobs.dart';
import '../platform/job_host_platform.dart';
import '../engines/platform/job_notifications.dart';
import '../tools/background_jobs/background_jobs_screen.dart';
import '../tools/compress_video/compress_video_screen.dart';
import '../tools/video_player/video_player_screen.dart';
import '../tools/shrink_to_send/shrink_to_send_screen.dart';
import '../engines/family/family_identity.dart';
import '../engines/family/family_space.dart';
import '../engines/family/family_store.dart';
import '../engines/family/family_sync.dart';
import '../engines/records/bills.dart';
import '../engines/records/doctor_visits.dart';
import '../platform/bill_platform.dart';
import '../engines/records/loans.dart';
import '../platform/loan_platform.dart';
import '../engines/records/elderly_care.dart';
import '../engines/records/receipt_vault.dart';
import '../engines/records/reports_vault.dart';
import '../engines/records/expense_tracker.dart';
import '../engines/records/health_readings.dart';
import '../engines/records/occasions.dart';
import '../engines/records/whatsapp_direct.dart';
import '../engines/records/shared_expenses.dart';
import '../engines/records/medicine_reminders.dart';
import '../platform/medicine_alarm_platform.dart';
import '../records/medicines/medicine_screen.dart';
import '../platform/occasion_platform.dart';
import '../platform/whatsapp_platform.dart';
import '../family/sync/lan_family_sync.dart';
import 'tool_registry.dart';

/// 113: main() attaches it once the binding is up; tests never do.
NotificationJobHost? jobNotificationHost;

/// 126: kept alive for the app's lifetime.
AppLifecycleListener? clipboardLifecycleListener;

/// Registers every tool with the registry and installs app-wide state.
/// Each feature adds its entry here so the home grid is driven by one list.
void bootstrap() {
  registerWordConverters(
    ConvertRegistry.instance,
    const PdfrxTextSource(),
    loadUnicodeFont: () async => (await rootBundle.load('assets/fonts/Inter.ttf')).buffer.asUint8List(),
  );

  // 019: Excel workbooks to PDF and PDF tables to workbooks.
  registerSheetConverters(
    ConvertRegistry.instance,
    const PdfrxTextSource(),
    loadUnicodeFont: () async => (await rootBundle.load('assets/fonts/Inter.ttf')).buffer.asUint8List(),
  );

  // 020: PowerPoint decks to PDF (slide per page) and PDFs to decks.
  registerSlideConverters(ConvertRegistry.instance, const PdfrxTextSource());

  // 025: HEIC through the phone's codec, also for Convert anything / Batch.
  registerHeicConverters(ConvertRegistry.instance, const PlatformHeicCodec());

  // 028: AVIF through the phone's codec (Android 12+, iOS 16+).
  registerAvifConverters(ConvertRegistry.instance, const PlatformAvifCodec(), support: platformAvifSupport());

  // 024: plain text files to PDF, drawn by the phone's text engine.
  ConvertRegistry.instance.register(const TextToPdfConverter());

  final OnDeviceMode mode = OnDeviceMode(const PrefsOnDeviceModeStore());
  OnDeviceMode.install(mode);
  // Default is on; a saved "off" is applied once preferences load.
  unawaited(mode.load());

  final ShareEngine share = ShareEngine(const SystemShareSheet(), const PrefsShareTargetStore());
  ShareEngine.install(share);
  share.prepare = StripOnShare(
    const PrefsStripOnShareStore(),
    () async => Directory('${Directory.systemTemp.path}/clean_share'),
  ).prepare;
  unawaited(share.load());

  final SaveAnywhere saver = SaveAnywhere(
    platform: const SystemSavePlatform(),
    store: const PrefsSaveChoiceStore(),
  );
  SaveAnywhere.install(saver);
  unawaited(saver.load());

  final NotificationJobHost jobHost = NotificationJobHost();
  final BackgroundJobs jobs = BackgroundJobs(jobHost);
  BackgroundJobs.install(jobs);

  // 113: a finished job's notification shares its files; Open shows the job.
  void whenNavigator(void Function(NavigatorState nav) f, [bool retry = true]) {
    final NavigatorState? nav = appNavigatorKey.currentState;
    if (nav != null) {
      f(nav);
    } else if (retry) {
      WidgetsBinding.instance.addPostFrameCallback((_) => whenNavigator(f, false));
    }
  }

  final JobNotifications jobNotices = JobNotifications(
    jobs: jobs,
    share: (List<String> paths) async {
      final List<String> present = paths.where((String p) => File(p).existsSync()).toList();
      if (present.isEmpty) {
        whenNavigator((NavigatorState nav) => unawaited(nav.push<void>(MaterialPageRoute<void>(
              builder: (BuildContext context) => const BackgroundJobsScreen(
                note: 'That file was moved or removed',
              ),
            ))));
        return;
      }
      await ShareEngine.instance.shareFiles(present);
    },
    open: (int id) => whenNavigator((NavigatorState nav) => unawaited(nav.push<void>(MaterialPageRoute<void>(
          builder: (BuildContext context) => BackgroundJobsScreen(highlight: id),
        )))),
  );
  JobNotifications.install(jobNotices);
  jobHost.onTap = (String? actionId, String? payload) async {
    // 088: dose alarms share the plugin; Taken / Snooze act, a tap opens.
    if (MedicineReminders.ownsPayload(payload)) {
      final bool acted = MedicineReminders.instance.handleTap(actionId, payload);
      if (!acted) {
        whenNavigator((NavigatorState nav) => unawaited(nav.push<void>(MaterialPageRoute<void>(
              builder: (BuildContext context) => const MedicineScreen(),
            ))));
      }
      return acted ? JobTapResult.ignored : JobTapResult.opened;
    }
    return jobNotices.handle(actionId, payload);
  };
  jobNotificationHost = jobHost;

  CopyResult.install(CopyResult(const SystemClipboardBackend()));

  final AppLock lock = AppLock(store: const SecureLockStore(), biometrics: PlatformBiometrics());
  AppLock.install(lock);
  unawaited(lock.load());

  // 069: one profile per family member, kept on the phone.
  final MemberProfiles profiles = MemberProfiles(const PrefsProfileStore());
  MemberProfiles.install(profiles);
  unawaited(profiles.load());

  // 109: dark mode, text size and one-hand layout.
  final AccessibilityPrefs accessibility = AccessibilityPrefs(const PrefsAccessibilityStore());
  AccessibilityPrefs.install(accessibility);
  unawaited(accessibility.load());

  // 119: guest mode survives a restart.
  final GuestMode guest = GuestMode(const PrefsGuestModeStore());
  GuestMode.install(guest);
  unawaited(guest.load());

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

  // 108: each recorded run keeps its originals until the trash is emptied.
  final Versions versions = Versions(
    store: DirectoryVersionStore(() => appFolder('versions')),
    index: FileVersionIndexStore(() => appFolder('versions')),
  )..attach(history);
  Versions.install(versions);
  unawaited(versions.load());

  final FileManager files = FileManager(
    source: const LocalFileSource(),
    history: history,
    store: JsonFileManagerStore(() => appFolder('history')),
  );
  FileManager.install(files);
  unawaited(files.load());
  unawaited(_resolveRoots(files));

  // 127: the download queue; on-device mode (059) keeps it waiting.
  final DownloadQueue downloads = DownloadQueue(
    fetcher: HttpDownloadFetcher(),
    store: FileDownloadQueueStore(() => appFolder('downloads')),
    defaultFolder: () async => (await appFolder('Downloads')).path,
    blockedReason: () {
      for (final ToolEntry t in ToolRegistry.all) {
        if (t.id == 'download-queue') {
          return NetworkGuard.blockedReason(t);
        }
      }
      return null;
    },
  );
  DownloadQueue.install(downloads);
  unawaited(downloads.load());

  // 068: the family space; Wi-Fi sync always, own-cloud folder when picked.
  final FamilySpace family = FamilySpace(
    identityStore: FileFamilyIdentityStore(() => appFolder('family')),
    storage: FileFamilyStoreStorage(() => appFolder('family')),
    transportsFor: (FamilyIdentity id) => <FamilySyncTransport>[
      LanFamilySync(),
      if (id.syncFolder != null) FolderFamilySync(id.syncFolder!),
    ],
  );
  FamilySpace.install(family);
  final Future<void> familyLoaded = family.load();
  unawaited(familyLoaded);

  // 088: medicines on the family store so allowed carers see them; on a
  // phone not in a family they stay in this phone's own store.
  final FamilyStore medicineSolo = FamilyStore(
    deviceId: MedicineReminders.soloMember,
    storage: FileFamilyStoreStorage(() => appFolder('medicines')),
  );
  final MedicineReminders medicines = MedicineReminders(
    space: family,
    soloStore: medicineSolo,
    alarms: NotificationMedicineAlarms(),
  );
  MedicineReminders.install(medicines);

  // 093: care circles for a parent, on the same store as the medicines.
  ElderlyCare.install(ElderlyCare(space: family, soloStore: medicineSolo, medicines: medicines));

  // 095: birthdays and anniversaries, reminders a week and a day ahead.
  final Occasions occasions = Occasions(
    space: family,
    soloStore: medicineSolo,
    reminders: NotificationOccasionReminders(),
    contacts: const PhoneContactDates(),
  );
  Occasions.install(occasions);
  unawaited(familyLoaded.then((_) => occasions.reschedule()));

  // 083: bills on the family store; reminders 3 days ahead and on the day.
  final Bills bills = Bills(space: family, soloStore: medicineSolo, reminders: NotificationBillReminders());
  Bills.install(bills);
  unawaited(Future.wait(<Future<void>>[medicineSolo.load(), familyLoaded]).then((_) => bills.reschedule()));
  // 087: loans; a reminder two days before each EMI and on the day.
  final Loans loans = Loans(space: family, soloStore: medicineSolo, reminders: NotificationLoanReminders());
  Loans.install(loans);
  unawaited(Future.wait(<Future<void>>[medicineSolo.load(), familyLoaded]).then((_) => loans.reschedule()));

  // 102: wa.me chats; recent numbers in the app's own folder.
  final WhatsAppDirect whatsapp =
      WhatsAppDirect(store: FileRecentNumberStore(() => appFolder('whatsapp')), opener: const UrlLinkOpener());
  WhatsAppDirect.install(whatsapp);
  unawaited(whatsapp.load());

  // 080: expenses and receipt photos in the app's own folder.
  final ExpenseTracker expenses = ExpenseTracker(store: FileExpenseStore(() => appFolder('expenses')));
  ExpenseTracker.install(expenses);
  unawaited(expenses.load());
  // 085: receipts with on-device OCR text, searchable; linked to expenses.
  final ReceiptVault receipts = ReceiptVault(
    store: FileReceiptStore(() => appFolder('receipts')),
    reader: const OcrReportTextReader(MlKitTextRecognizer()),
    expenses: expenses,
    // 050: a searchable scan already carries its text.
    pdfText: (String path) => PdfLibraryIndex.instance[path]?.pages.join('\n') ?? '',
  );
  ReceiptVault.install(receipts);
  unawaited(receipts.load());

  // 089: BP and sugar readings in the app's own folder.
  final HealthReadings healthLog = HealthReadings(store: FileHealthReadingStore(() => appFolder('health')));
  HealthReadings.install(healthLog);
  unawaited(healthLog.load());

  // 081: shared bills and settle-up, kept beside the ledger.
  final SharedExpenses shared = SharedExpenses(store: FileSharedExpenseStore(() => appFolder('expenses')));
  SharedExpenses.install(shared);
  unawaited(shared.load());
  unawaited(Future.wait(<Future<void>>[medicineSolo.load(), familyLoaded]).then((_) => medicines.reschedule()));

  // 071: shared calendar on the family store; reminders while the app runs.
  final SharedCalendar calendar = SharedCalendar(space: family);
  SharedCalendar.install(calendar);
  // 090: doctor visits; the next appointment goes on this calendar.
  DoctorVisits.install(DoctorVisits(space: family, soloStore: medicineSolo, calendar: calendar));
  // 072: shared shopping list on the same store.
  SharedShoppingList.install(SharedShoppingList(space: family));
  CalendarReminderWatcher.instance = CalendarReminderWatcher(calendar: calendar, sink: NotificationCalendarReminders());
  // 074: family documents encrypted on this phone; expiry reminders at
  // 30, 7 and 1 day, checked by CalendarReminderHost at start and hourly.
  final DocumentVault documents = DocumentVault(
    cipher: VaultCipher(const SecureVaultKeyStore('family_documents_key')),
    blobs: FileDocumentBlobStore(() => appFolder('family_documents')),
    space: family,
  );
  DocumentVault.install(documents);
  // 091: lab reports encrypted on this phone; values read by on-device OCR.
  final ReportsVault reports = ReportsVault(
    cipher: VaultCipher(const SecureVaultKeyStore('lab_reports_key')),
    blobs: FileDocumentBlobStore(() => appFolder('lab_reports')),
    reader: const OcrReportTextReader(MlKitTextRecognizer()),
  );
  ReportsVault.install(reports);
  unawaited(reports.load());
  // 076: live location on the family store; the 7-day trail stays here.
  final FamilyLocation location = FamilyLocation(
    space: family,
    history: FileLocationHistoryStore(() => appFolder('location')),
  );
  FamilyLocation.install(location);
  // 077: one-tap check-in; automatic on arriving at a family place.
  final CheckIns checkIns = CheckIns(location: location, space: family);
  CheckIns.install(checkIns);
  location.addListener(checkIns.onLatestFix);
  unawaited(location.load());
  LocationTracker.instance = LocationTracker(
    location: location,
    source: const GeolocatorPositionSource(),
    sink: NotificationPlaceEvents(),
  );
  DocumentReminderWatcher.instance = DocumentReminderWatcher(
    vault: documents,
    sink: NotificationDocumentReminders(),
    marks: FileDocumentReminderMarks(() => appFolder('family_documents')),
  );

  // 123: video from a link; one plugin per site, saved through the queue.
  VideoLinks.install(VideoLinkDownloader(
    pages: HttpPageFetcher(),
    notice: const PrefsNoticeStore(),
    blockedReason: () {
      for (final ToolEntry t in ToolRegistry.all) {
        if (t.id == 'video-link') {
          return NetworkGuard.blockedReason(t);
        }
      }
      return null;
    },
  ));
  final SharedLinkInbox inbox = SharedLinkInbox();
  SharedLinkInbox.install(inbox);
  void openShared(bool retry) {
    final NavigatorState? nav = appNavigatorKey.currentState;
    if (nav == null) {
      // Opened by the share: wait for the first frame, then try once more.
      if (retry) {
        WidgetsBinding.instance.addPostFrameCallback((_) => openShared(false));
      }
      return;
    }
    final String? text = inbox.take();
    if (text == null) {
      return;
    }
    unawaited(nav.push<void>(MaterialPageRoute<void>(
      builder: (BuildContext context) => VideoLinkScreen(initialText: text),
    )));
  }

  inbox.onLink = (String _) => openShared(true);

  // 025: pictures shared from Photos open the HEIC converter, in order.
  final SharedFilesInbox pictures = SharedFilesInbox();
  SharedFilesInbox.install(pictures);
  void openPictures(bool retry) {
    final NavigatorState? nav = appNavigatorKey.currentState;
    if (nav == null) {
      if (retry) {
        WidgetsBinding.instance.addPostFrameCallback((_) => openPictures(false));
      }
      return;
    }
    final List<String>? paths = pictures.take();
    if (paths == null) {
      return;
    }
    unawaited(nav.push<void>(MaterialPageRoute<void>(
      builder: (BuildContext context) => HeicScreen(initialPaths: paths),
    )));
  }

  pictures.onFiles = (List<String> _) => openPictures(true);

  // 065: a file opened from another app shows the tools that apply to it.
  final DefaultAppPrompt defaultPrompt = DefaultAppPrompt(const PrefsDefaultAppPromptStore());
  DefaultAppPrompt.install(defaultPrompt);
  unawaited(defaultPrompt.load());
  final OpenWithInbox opened = OpenWithInbox();
  OpenWithInbox.install(opened);
  void openOpened(bool retry) {
    final NavigatorState? nav = appNavigatorKey.currentState;
    if (nav == null) {
      if (retry) {
        WidgetsBinding.instance.addPostFrameCallback((_) => openOpened(false));
      }
      return;
    }
    final List<String>? paths = opened.take();
    if (paths == null) {
      return;
    }
    unawaited(nav.push<void>(MaterialPageRoute<void>(
      builder: (BuildContext context) => OpenedFileScreen(paths: paths),
    )));
  }

  opened.onFiles = (List<String> _) => openOpened(true);
  unawaited(opened.attach());
  if (Platform.isIOS) {
    // iOS copies files from "Open in" into Documents/Inbox.
    Future<void> scanIosInbox() async {
      try {
        final Directory docs = await getApplicationDocumentsDirectory();
        await opened.scanInbox('${docs.path}/Inbox');
      } catch (_) {
        // No documents folder: nothing to open.
      }
    }

    unawaited(scanIosInbox());
    AppLifecycleListener(onResume: () => unawaited(scanIosInbox()));
  }
  unawaited(pictures.attach());
  unawaited(inbox.attach());

  // 112: home-screen widget and quick-settings tile open the app on an action.
  final HomeWidgets homeWidgets = HomeWidgets(bridge: ChannelWidgetBridge(), store: const PrefsSpeedDialStore());
  HomeWidgets.install(homeWidgets);
  homeWidgets.onAction = (WidgetAction action) => whenNavigator((NavigatorState nav) {
        if (action == WidgetAction.paste) {
          unawaited(showPasteSheet(nav.context));
          return;
        }
        final String? id = action.toolId;
        final ToolEntry? tool = id == null ? null : ToolRegistry.byId(id);
        unawaited(nav.push<void>(MaterialPageRoute<void>(
          builder: tool?.builder ?? (BuildContext context) => const HomeWidgetScreen(),
        )));
      });
  unawaited(homeWidgets.load().then((_) => homeWidgets.attach()));
  if (Platform.isIOS) {
    // iOS widget taps are deep links (FlutterDeepLinkingEnabled).
    WidgetsBinding.instance.addObserver(_WidgetLinkObserver(homeWidgets));
    homeWidgets.handleRoute(WidgetsBinding.instance.platformDispatcher.defaultRouteName);
  }
  AppLifecycleListener(onResume: () => unawaited(homeWidgets.refresh()));

  // 075: family contacts pinned with the star become the widget's speed dial.
  final SharedContacts contacts = SharedContacts(space: family);
  SharedContacts.install(contacts);
  String lastDial = '';
  void syncDial() {
    final List<SpeedDialEntry> pinned = contacts.speedDialEntries;
    final String key = pinned.map((SpeedDialEntry e) => '${e.label}|${e.number}').join(',');
    if (key == lastDial) {
      return;
    }
    lastDial = key;
    unawaited(homeWidgets.setSpeedDial(pinned));
  }

  family.store.addListener(syncDial);

  // 070: adult, child and guest, with per-section read or write.
  FamilyRoles.install(FamilyRoles(space: family));

  // 122: records point at each other; family documents and calendar events
  // are the first kinds, the Records tab adds its own as they arrive.
  final CrossLinks links = CrossLinks(storage: FileCrossLinkStorage(() => appFolder('links')));
  CrossLinks.install(links);
  String? familyTitle(String collection, String id) {
    final FamilyRecord? r = family.store.get(collection, id);
    if (r == null) {
      return null;
    }
    final Object? t = r.fields['title'] ?? r.fields['name'] ?? r.fields['text'];
    return t == null ? collection : '$t';
  }

  links.registerKind(SimpleRecordKind('documents', 'Document', (String id) => familyTitle('documents', id)));
  links.registerKind(SimpleRecordKind('calendar', 'Event', (String id) => familyTitle('calendar', id)));
  unawaited(links.load());

  // 120: whole-app backup on a schedule, to the family's own folder.
  const Map<String, String> sectionNames = <String, String>{
    'members': 'Family members',
    'calendar': 'Calendar',
    'shopping': 'Shopping list',
    'contacts': 'Family contacts',
    'tasks': 'To-do',
    'notes': 'Notices',
    'documents': 'Documents',
    'places': 'Places',
    'checkins': 'Check-ins',
  };
  final BackupExport backup = BackupExport(
    parts: <BackupPart>[
      FamilyIdentityBackupPart(family),
      FamilyBackupPart(family.store),
      SettingsBackupPart(const PrefsSettingsSource()),
    ],
    sections: () => <ExportSection>[
      for (final MapEntry<String, String> e in sectionNames.entries)
        FamilyCollectionSection(family.store, e.key, e.value),
    ],
    folder: const IoBackupFolder(),
    settingsStore: const SecureBackupSettingsStore(),
  );
  BackupExport.install(backup);
  unawaited(backup.load().then((_) => backup.runIfDue()));
  AppLifecycleListener(onResume: () => unawaited(backup.runIfDue()));

  // 126: opt-in; looks at the clipboard only when the app comes to the front.
  final ClipboardLinkWatch watch = ClipboardLinkWatch(
    source: const SystemClipboardTextSource(),
    store: const PrefsClipboardWatchStore(),
  );
  ClipboardLinkWatch.install(watch);
  unawaited(watch.load());
  void openVideo(Uri url) {
    final NavigatorState? nav = appNavigatorKey.currentState;
    if (nav == null) {
      return;
    }
    unawaited(nav.push<void>(MaterialPageRoute<void>(
      builder: (BuildContext context) => VideoLinkScreen(initialText: url.toString()),
    )));
  }

  Future<void> offerCopiedLink() async {
    final LinkOffer? offer = await watch.check();
    final BuildContext? ctx = appNavigatorKey.currentContext;
    if (offer == null || ctx == null || !ctx.mounted) {
      return;
    }
    final ScaffoldMessengerState? messenger = ScaffoldMessenger.maybeOf(ctx);
    if (messenger == null) {
      return;
    }
    showLinkOfferBubble(messenger, offer, () {
      final LinkOffer? taken = watch.accept();
      if (taken != null) {
        openVideo(taken.url);
      }
    });
  }

  clipboardLifecycleListener?.dispose();
  clipboardLifecycleListener = AppLifecycleListener(onResume: () => unawaited(offerCopiedLink()));

  // 056: vault files encrypted with keys in Keystore / Keychain; the backup
  // choice decides which private folder holds them.
  PrivateVault.install(PrivateVault(
    realKeys: const SecureVaultKeyStore('private_vault_key'),
    decoyKeys: const SecureVaultKeyStore('private_vault_decoy_key'),
    backend: FileVaultBackend(),
    settingsStore: const SecureVaultSettingsStore(),
  ));

  SecureNotes.install(SecureNotes(
    keyStore: const SecureKeyStore(),
    blobStore: const FileNoteBlobStore(),
    clipboard: const SystemClipboard(),
  ));

  // 096: the autofill profile, encrypted with the notes key, never uploaded.
  final AutofillProfileBook autofill = AutofillProfileBook(
    keyStore: const SecureKeyStore(),
    blobStore: const FileProfileBlobStore(),
    clipboard: const SystemClipboard(),
  );
  AutofillProfileBook.install(autofill);
  unawaited(autofill.load());

  final OcrTextStore ocr = OcrTextStore(FileOcrBackend(() => appFolder('search')));
  OcrTextStore.install(ocr);
  unawaited(ocr.load());

  // 016: the text of every saved PDF, plus OCR'd scans, kept on the phone.
  final PdfLibraryIndex pdfIndex = PdfLibraryIndex(FilePdfIndexBackend(() => appFolder('search')));
  PdfLibraryIndex.install(pdfIndex);
  unawaited(pdfIndex.load().then((_) => pdfIndex.syncOcr(ocr.all)));
  ocr.addListener(() => pdfIndex.syncOcr(ocr.all));

  OneSearch.install(OneSearch(<SearchSource>[
    ToolSearchSource(() => ToolRegistry.all
        .map((ToolEntry t) => ToolInfo(id: t.id, name: t.name, section: t.section.label))
        .toList()),
    FileSearchSource(files),
    ocr,
    pdfIndex,
    HistorySearchSource(history),
    RecordSearchSource(SecureNotes.instance),
    receipts,
  ]));

  // 053: scans are named from their title and date, read on the phone.
  ScanAutoNamer.instance = ScanAutoNamer(
    recognizer: const MlKitTextRecognizer(),
    store: const PrefsScanNamePatternStore(),
  );
  // 054: one tap reads, compresses and names the scan.
  OneTapScan.instance = OneTapScan(recognizer: const MlKitTextRecognizer(), namer: ScanAutoNamer.instance!);

  // 047: other apps can open the scanner and get the saved scan back.
  ScanEntry(() async {
    final NavigatorState? nav = appNavigatorKey.currentState;
    if (nav == null) {
      return <String>[];
    }
    final List<String>? saved = await nav.push<List<String>>(
      MaterialPageRoute<List<String>>(builder: (BuildContext context) => DocumentScannerScreen(returnResult: true, autoNamer: ScanAutoNamer.instance, oneTap: OneTapScan.instance)),
    );
    return saved ?? <String>[];
  }).attach();

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
      id: 'pdf-search',
      name: 'Search inside PDFs',
      section: ToolSection.pdf,
      icon: Icons.manage_search,
      featureNumber: 16,
      builder: (BuildContext context) => const PdfSearchScreen(),
    ),
    ToolEntry(
      id: 'ocr-scan',
      name: 'OCR a scan',
      section: ToolSection.pdf,
      icon: Icons.document_scanner_outlined,
      featureNumber: 8,
      builder: (BuildContext context) => const OcrScanScreen(),
    ),
    ToolEntry(
      id: 'clean-scan',
      name: 'Remove blank pages',
      section: ToolSection.pdf,
      icon: Icons.auto_fix_high_outlined,
      featureNumber: 15,
      builder: (BuildContext context) => const CleanScanScreen(),
    ),
    ToolEntry(
      id: 'redact',
      name: 'Blur faces and numbers',
      section: ToolSection.image,
      icon: Icons.blur_on,
      featureNumber: 45,
      builder: (BuildContext context) => const RedactScreen(),
    ),
    ToolEntry(
      id: 'rotate-flip',
      name: 'Rotate and flip',
      section: ToolSection.image,
      icon: Icons.rotate_90_degrees_cw_outlined,
      featureNumber: 42,
      builder: (BuildContext context) => const RotateFlipScreen(),
    ),
    ToolEntry(
      id: 'merge-pdf',
      name: 'Merge PDF',
      section: ToolSection.pdf,
      icon: Icons.merge_type,
      featureNumber: 2,
      builder: (BuildContext context) => const MergePdfScreen(),
    ),
    ToolEntry(
      id: 'split-pdf',
      name: 'Split PDF',
      section: ToolSection.pdf,
      icon: Icons.call_split,
      featureNumber: 3,
      builder: (BuildContext context) => const SplitPdfScreen(),
    ),
    ToolEntry(
      id: 'extract-pages',
      name: 'Extract pages',
      section: ToolSection.pdf,
      icon: Icons.library_add_check_outlined,
      featureNumber: 4,
      builder: (BuildContext context) => const ExtractPagesScreen(),
    ),
    ToolEntry(
      id: 'remove-pages',
      name: 'Remove pages',
      section: ToolSection.pdf,
      icon: Icons.delete_sweep_outlined,
      featureNumber: 5,
      builder: (BuildContext context) => const RemovePagesScreen(),
    ),
    ToolEntry(
      id: 'reorder-pages',
      name: 'Reorder pages',
      section: ToolSection.pdf,
      icon: Icons.swap_vert,
      featureNumber: 6,
      builder: (BuildContext context) => const ReorderPagesScreen(),
    ),
    ToolEntry(
      id: 'rotate-pages',
      name: 'Rotate pages',
      section: ToolSection.pdf,
      icon: Icons.rotate_right,
      featureNumber: 7,
      builder: (BuildContext context) => const RotatePagesScreen(),
    ),
    ToolEntry(
      id: 'protect-pdf',
      name: 'Protect with password',
      section: ToolSection.pdf,
      icon: Icons.lock_outline,
      featureNumber: 11,
      builder: (BuildContext context) => const ProtectPdfScreen(),
    ),
    ToolEntry(
      id: 'unlock-pdf',
      name: 'Unlock a known password',
      section: ToolSection.pdf,
      icon: Icons.lock_open_outlined,
      featureNumber: 12,
      builder: (BuildContext context) => const UnlockPdfScreen(),
    ),
    ToolEntry(
      id: 'redact-pdf',
      name: 'Redact PDF',
      section: ToolSection.pdf,
      icon: Icons.format_color_fill,
      featureNumber: 13,
      builder: (BuildContext context) => const RedactPdfScreen(),
    ),
    ToolEntry(
      id: 'page-numbers',
      name: 'Page numbers',
      section: ToolSection.pdf,
      icon: Icons.format_list_numbered,
      featureNumber: 14,
      builder: (BuildContext context) => const PageNumbersScreen(),
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
      id: LockableIds.vault,
      name: 'Private vault',
      section: ToolSection.security,
      icon: Icons.shield_outlined,
      featureNumber: 56,
      touches: const <DataTouch>{DataTouch.files, DataTouch.photos},
      builder: (BuildContext context) => const PrivateVaultScreen(),
    ),
    ToolEntry(
      id: 'encrypt-file',
      name: 'Encrypt any file',
      section: ToolSection.security,
      icon: Icons.enhanced_encryption_outlined,
      featureNumber: 58,
      builder: (BuildContext context) => const EncryptFileScreen(),
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
      id: 'print-to-pdf',
      name: 'Print to PDF',
      section: ToolSection.pdf,
      icon: Icons.print_outlined,
      featureNumber: 17,
      builder: (BuildContext context) => const PrintToPdfScreen(),
    ),
    ToolEntry(
      id: 'fill-forms',
      name: 'Fill forms',
      section: ToolSection.pdf,
      icon: Icons.edit_note_outlined,
      featureNumber: 9,
      builder: (BuildContext context) => const FillFormsScreen(),
    ),
    ToolEntry(
      id: 'sign-pdf',
      name: 'Sign PDF',
      section: ToolSection.pdf,
      icon: Icons.draw_outlined,
      featureNumber: 10,
      builder: (BuildContext context) => const SignPdfScreen(),
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
      id: 'compress-video',
      name: 'Compress video',
      section: ToolSection.compress,
      icon: Icons.video_settings_outlined,
      featureNumber: 36,
      builder: (BuildContext context) => const CompressVideoScreen(),
    ),
    ToolEntry(
      id: 'shrink-to-send',
      name: 'Shrink to send',
      section: ToolSection.compress,
      icon: Icons.send_outlined,
      featureNumber: 38,
      builder: (BuildContext context) => const ShrinkToSendScreen(),
    ),
    ToolEntry(
      id: 'exact-kb',
      name: 'Image to exact KB',
      section: ToolSection.compress,
      icon: Icons.straighten,
      featureNumber: 35,
      builder: (BuildContext context) => const ExactKbScreen(),
    ),
    ToolEntry(
      id: 'resize',
      name: 'Resize',
      section: ToolSection.image,
      icon: Icons.aspect_ratio,
      featureNumber: 40,
      builder: (BuildContext context) => const ResizeScreen(),
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
      id: 'passport-photo',
      name: 'Passport photo',
      section: ToolSection.image,
      icon: Icons.portrait_outlined,
      featureNumber: 43,
      builder: (BuildContext context) => const PassportPhotoScreen(),
    ),
    ToolEntry(
      id: 'id-card',
      name: 'ID card to A4',
      section: ToolSection.image,
      icon: Icons.badge_outlined,
      featureNumber: 44,
      touches: const <DataTouch>{DataTouch.camera, DataTouch.files},
      builder: (BuildContext context) => const IdCardScreen(),
    ),
    ToolEntry(
      id: 'id-scan',
      name: 'ID scan',
      section: ToolSection.scan,
      icon: Icons.contact_mail_outlined,
      featureNumber: 49,
      touches: const <DataTouch>{DataTouch.camera, DataTouch.files},
      builder: (BuildContext context) => const IdScanScreen(),
    ),
    ToolEntry(
      id: 'pdf-to-images',
      name: 'PDF to images',
      section: ToolSection.pdf,
      icon: Icons.collections_outlined,
      featureNumber: 22,
      builder: (BuildContext context) => const PdfToImagesScreen(),
    ),
    ToolEntry(
      id: 'webp',
      name: 'WebP to JPG or PNG',
      section: ToolSection.convert,
      icon: Icons.swap_horiz,
      featureNumber: 26,
      builder: (BuildContext context) => const WebpScreen(),
    ),
    ToolEntry(
      id: 'raster',
      name: 'Convert pictures',
      section: ToolSection.convert,
      icon: Icons.image_outlined,
      featureNumber: 27,
      builder: (BuildContext context) => const RasterScreen(),
    ),
    ToolEntry(
      id: 'exif',
      name: 'Photo details (EXIF)',
      section: ToolSection.image,
      icon: Icons.location_off_outlined,
      featureNumber: 46,
      builder: (BuildContext context) => const ExifScreen(),
    ),
    ToolEntry(
      id: 'qr-generator',
      name: 'QR generator',
      section: ToolSection.scan,
      icon: Icons.qr_code_2,
      featureNumber: 52,
      builder: (BuildContext context) => const QrGeneratorScreen(),
    ),
    ToolEntry(
      id: 'background-jobs',
      name: 'Background jobs',
      section: ToolSection.share,
      icon: Icons.pending_actions_outlined,
      featureNumber: 67,
      touches: const <DataTouch>{},
      builder: (BuildContext context) => const BackgroundJobsScreen(),
    ),
    ToolEntry(
      id: 'copy-result',
      name: 'Copy result',
      section: ToolSection.share,
      icon: Icons.copy_all_outlined,
      featureNumber: 66,
      touches: const <DataTouch>{DataTouch.clipboard, DataTouch.files},
      builder: (BuildContext context) => const CopyResultScreen(),
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
      id: 'nearby-share',
      name: 'Nearby share',
      section: ToolSection.share,
      icon: Icons.share_location_outlined,
      featureNumber: 61,
      touches: const <DataTouch>{DataTouch.files, DataTouch.lan},
      builder: (BuildContext context) => const NearbyShareScreen(),
    ),
    ToolEntry(
      id: 'images-to-pdf',
      name: 'Images to PDF',
      section: ToolSection.convert,
      icon: Icons.picture_as_pdf_outlined,
      featureNumber: 21,
      builder: (BuildContext context) => const ImagesToPdfScreen(),
    ),
    ToolEntry(
      id: 'text-to-pdf',
      name: 'Text to PDF',
      section: ToolSection.convert,
      icon: Icons.text_snippet_outlined,
      featureNumber: 24,
      builder: (BuildContext context) => const TextToPdfScreen(),
    ),
    ToolEntry(
      id: 'web-page-pdf',
      name: 'Web page to PDF',
      section: ToolSection.convert,
      icon: Icons.web_outlined,
      featureNumber: 23,
      needsNetwork: true,
      networkReason: 'Fetches the public page you paste. Nothing of yours is uploaded.',
      touches: const <DataTouch>{DataTouch.files, DataTouch.network},
      builder: (BuildContext context) => const WebPagePdfScreen(),
    ),
    ToolEntry(
      id: 'document-scanner',
      name: 'Document scanner',
      section: ToolSection.scan,
      icon: Icons.document_scanner_outlined,
      featureNumber: 47,
      touches: const <DataTouch>{DataTouch.camera, DataTouch.files},
      builder: (BuildContext context) => DocumentScannerScreen(autoNamer: ScanAutoNamer.instance, oneTap: OneTapScan.instance),
    ),
    ToolEntry(
      id: 'convert-anything',
      name: 'Convert anything',
      section: ToolSection.convert,
      icon: Icons.swap_horiz,
      featureNumber: 30,
      builder: (BuildContext context) => const ConvertAnythingScreen(),
    ),
    ToolEntry(
      id: 'heic',
      name: 'HEIC to JPG or PNG',
      section: ToolSection.convert,
      icon: Icons.photo_outlined,
      featureNumber: 25,
      builder: (BuildContext context) => const HeicScreen(),
    ),
    ToolEntry(
      id: 'avif',
      name: 'AVIF to JPG or PNG',
      section: ToolSection.convert,
      icon: Icons.image_outlined,
      featureNumber: 28,
      builder: (BuildContext context) => const AvifScreen(),
    ),
    ToolEntry(
      id: 'batch-convert',
      name: 'Batch convert',
      section: ToolSection.convert,
      icon: Icons.dynamic_feed_outlined,
      featureNumber: 31,
      builder: (BuildContext context) => const BatchConvertScreen(),
    ),
    ToolEntry(
      id: 'batch',
      name: 'Batch',
      section: ToolSection.convert,
      icon: Icons.library_add_check_outlined,
      featureNumber: 107,
      builder: (BuildContext context) => const BatchScreen(),
    ),
    ToolEntry(
      id: 'versions',
      name: 'Versions',
      section: ToolSection.platform,
      icon: Icons.history_toggle_off_outlined,
      featureNumber: 108,
      builder: (BuildContext context) => const VersionsScreen(),
    ),
    ToolEntry(
      id: 'word-pdf',
      name: 'Word to PDF and back',
      section: ToolSection.convert,
      icon: Icons.description_outlined,
      featureNumber: 18,
      builder: (BuildContext context) => const WordPdfScreen(),
    ),
    ToolEntry(
      id: 'excel-pdf',
      name: 'Excel to PDF and back',
      section: ToolSection.convert,
      icon: Icons.table_chart_outlined,
      featureNumber: 19,
      builder: (BuildContext context) => const ExcelPdfScreen(),
    ),
    ToolEntry(
      id: 'powerpoint-pdf',
      name: 'PowerPoint to PDF and back',
      section: ToolSection.convert,
      icon: Icons.slideshow_outlined,
      featureNumber: 20,
      builder: (BuildContext context) => const PowerPointPdfScreen(),
    ),
    ToolEntry(
      id: 'archives',
      name: 'Archives',
      section: ToolSection.convert,
      icon: Icons.folder_zip_outlined,
      featureNumber: 29,
      builder: (BuildContext context) => const ArchivesScreen(),
    ),
    ToolEntry(
      id: 'zip',
      name: 'Zip files',
      section: ToolSection.compress,
      icon: Icons.folder_zip,
      featureNumber: 37,
      builder: (BuildContext context) => const ZipScreen(),
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
      id: 'cloud',
      name: 'Cloud import and save',
      section: ToolSection.share,
      icon: Icons.cloud_outlined,
      featureNumber: 63,
      builder: (BuildContext context) => const CloudScreen(),
    ),
    ToolEntry(
      id: 'download-queue',
      name: 'Download queue',
      section: ToolSection.links,
      icon: Icons.download_outlined,
      featureNumber: 127,
      needsNetwork: true,
      networkReason: 'Fetches the links you add. Nothing of yours is uploaded.',
      touches: const <DataTouch>{DataTouch.files, DataTouch.network},
      builder: (BuildContext context) => const DownloadQueueScreen(),
    ),
    ToolEntry(
      id: 'video-link',
      name: 'Video from a link',
      section: ToolSection.links,
      icon: Icons.video_library_outlined,
      featureNumber: 123,
      needsNetwork: true,
      networkReason: 'Reads the public page of the link you paste and fetches its video. Nothing of yours is uploaded.',
      touches: const <DataTouch>{DataTouch.files, DataTouch.network},
      builder: (BuildContext context) => const VideoLinkScreen(),
    ),
    ToolEntry(
      id: 'audio-link',
      name: 'Audio from a link',
      section: ToolSection.links,
      icon: Icons.audiotrack_outlined,
      featureNumber: 124,
      needsNetwork: true,
      networkReason: 'Reads the public page of the link you paste and fetches its sound. Nothing of yours is uploaded.',
      touches: const <DataTouch>{DataTouch.files, DataTouch.network},
      builder: (BuildContext context) => const AudioLinkScreen(),
    ),
    ToolEntry(
      id: 'clipboard-watch',
      name: 'Clipboard link watch',
      section: ToolSection.links,
      icon: Icons.content_paste_go,
      featureNumber: 126,
      touches: const <DataTouch>{DataTouch.clipboard},
      builder: (BuildContext context) => ClipboardWatchScreen(
        onSave: (BuildContext c, Uri url) => unawaited(Navigator.of(c).push<void>(MaterialPageRoute<void>(
          builder: (BuildContext _) => VideoLinkScreen(initialText: url.toString()),
        ))),
      ),
    ),
    ToolEntry(
      id: 'status-saver',
      name: 'Status saver',
      section: ToolSection.links,
      icon: Icons.amp_stories_outlined,
      featureNumber: 125,
      builder: (BuildContext context) => const StatusSaverScreen(),
    ),
    ToolEntry(
      id: LockableIds.deletedMessages,
      name: 'Recover deleted messages',
      section: ToolSection.links,
      icon: Icons.restore_from_trash_outlined,
      featureNumber: 129,
      touches: const <DataTouch>{DataTouch.notifications, DataTouch.files},
      builder: (BuildContext context) => const DeletedMessagesScreen(),
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
      id: 'video-player',
      name: 'Video player',
      section: ToolSection.links,
      icon: Icons.play_circle_outline,
      featureNumber: 130,
      touches: const <DataTouch>{DataTouch.files},
      builder: (BuildContext context) => const VideoPlayerScreen(),
    ),
    ToolEntry(
      id: 'accessibility',
      name: 'Accessibility',
      section: ToolSection.platform,
      icon: Icons.accessibility_new,
      featureNumber: 109,
      touches: const <DataTouch>{},
      builder: (BuildContext context) => const AccessibilityScreen(),
    ),
    ToolEntry(
      id: guestModeToolId,
      name: 'Guest mode',
      section: ToolSection.platform,
      icon: Icons.child_care,
      featureNumber: 119,
      touches: const <DataTouch>{},
      builder: (BuildContext context) => const GuestModeScreen(),
    ),
    ToolEntry(
      id: 'custom-home',
      name: 'Arrange home',
      section: ToolSection.platform,
      icon: Icons.dashboard_customize_outlined,
      featureNumber: 116,
      touches: const <DataTouch>{},
      builder: (BuildContext context) => const CustomHomeScreen(),
    ),
    ToolEntry(
      id: 'language',
      name: 'Language',
      section: ToolSection.platform,
      icon: Icons.translate,
      featureNumber: 110,
      touches: const <DataTouch>{},
      builder: (BuildContext context) => const LanguageScreen(),
    ),
    ToolEntry(
      id: 'family-roles',
      name: 'Family roles',
      section: ToolSection.platform,
      icon: Icons.admin_panel_settings_outlined,
      featureNumber: 70,
      touches: const <DataTouch>{},
      builder: (BuildContext context) => const FamilyRolesScreen(),
    ),
    ToolEntry(
      id: 'backup',
      name: 'Backup and export',
      section: ToolSection.platform,
      icon: Icons.backup_outlined,
      featureNumber: 120,
      touches: const <DataTouch>{DataTouch.files},
      builder: (BuildContext context) => const BackupScreen(),
    ),
    ToolEntry(
      id: 'home-widget',
      name: 'Widgets and tile',
      section: ToolSection.platform,
      icon: Icons.widgets_outlined,
      featureNumber: 112,
      touches: const <DataTouch>{},
      builder: (BuildContext context) => const HomeWidgetScreen(),
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

/// 112: claims widget deep links before the Navigator sees them as routes.
class _WidgetLinkObserver with WidgetsBindingObserver {
  _WidgetLinkObserver(this.widgets);

  final HomeWidgets widgets;

  @override
  Future<bool> didPushRouteInformation(RouteInformation routeInformation) async =>
      widgets.handleRoute(routeInformation.uri.toString());
}
