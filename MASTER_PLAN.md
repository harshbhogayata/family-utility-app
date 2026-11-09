# Family Utility App — Master Plan

One app for the family: file chores (PDF, convert, compress, scan, images), a shared live family layer, and personal records, all offline-first with no accounts and no third-party servers.

This file is the single source of truth. Every feature has its own spec in `features/`, linked below. A feature is done only when its spec's acceptance boxes are ticked and its status line says `done`.

## Goal
Ship all 130 features. Progress = features marked done ÷ 130. Keep `PROGRESS.md` updated after every feature.

## Rules that do not change
1. **Offline first.** Every tool runs on the device. Nothing the user gives the app is uploaded, ever, unless they explicitly share it.
2. **No accounts.** No sign-up, no login, no analytics, no ads.
3. **No cloud AI.** Nothing that needs a paid API key. On-device ML (ML Kit text recognition, barcode, face detection, segmentation) is fine.
4. **Family data stays in the family.** Sync is LAN first, own-cloud folder second, no vendor server.
5. **Do the chore, then get out of the way.** A result screen always offers Share, Save and Undo.

## Stack
- **Flutter 3.x / Dart**, one codebase for Android and iOS. Material 3 with the app's own theme (see `DESIGN.md`).
- **PDF:** `pdfx` or `pdfrx` for rendering; `syncfusion_flutter_pdf` or a pdfium binding via FFI for editing, merge, split, forms, signatures, encryption.
- **Images:** `image` package for decode and encode; platform channels for HEIC and AVIF where needed.
- **Video and audio:** `ffmpeg_kit_flutter` (LGPL build).
- **OCR, barcode, faces:** `google_mlkit_*` packages, on device.
- **Archives:** `archive` package plus a 7z and RAR channel.
- **Downloads:** a Dart port of extractors behind a plugin interface; `youtube_explode_dart` for YouTube; others per site, isolated so breakage is contained.
- **Storage:** `drift` (SQLite) for records; files on disk under the app directory; `flutter_secure_storage` for keys.
- **Sync:** CRDT per record (`crdt` package or a small custom LWW map with vector clocks); LAN transport over mDNS discovery (`multicast_dns`) and WebSockets; own-cloud transport writes encrypted change files to a user-chosen folder via the system document picker.
- **Encryption:** AES-256-GCM via `cryptography`; keys in Keystore or Keychain.
- **Location:** `geolocator` and `geofence_service`; map tiles from OpenStreetMap through `flutter_map` (no API key).
- **Background:** `workmanager` on Android, `background_fetch` on iOS, foreground service for long jobs.
- **Share and open-with:** `share_plus`, `receive_sharing_intent`, Android intent filters and iOS document types.

## Repository layout
```
lib/
  app/            theme, routing, profiles
  engines/        pure logic per domain: pdf, image, video, archive, ocr, download, sync, records
  tools/          one folder per tool screen (thin UI over an engine)
  family/         shared store, sync, feed, map
  records/        money, health, home, documents
  platform/       share sheet, open-with, widgets, background jobs
features/         one spec per feature (this plan links them)
test/features/    one test folder per feature
DESIGN.md         screens, theme tokens, component rules
PROGRESS.md       running tally, updated after every feature
```

## Build order
Work strictly in phases; inside a phase, highest score first, but never start a feature whose dependencies are not done.

- **Phase 1 — file chores and the platform core (86 features).** The app is useful on day one as an iLovePDF replacement: platform core (file manager, open-with, share, search, history), PDF basics, convert, compress, images, scan and QR, security, links.
- **Phase 2 — the family layer (20 features).** Shared store and sync, profiles and roles, calendar, lists, vault, live location, check-in, plus transfer and platform polish.
- **Phase 3 — personal records (24 features).** Money, health, home, templates and contacts, all built on the shared store with per-member privacy.

## Definition of done for the whole project
- All 130 feature specs marked `done` with commit hashes.
- `flutter test` and integration tests green on CI for Android and iOS.
- A release build installs on a Samsung mid-range phone and an iPhone and passes the airplane-mode walkthrough in `QA.md`.
- `PROGRESS.md` reads 130 / 130.

## How a build session works
1. `git pull`, read `PROGRESS.md`, pick the next feature per the build order above.
2. Open its spec, implement engine first, then UI, then the test.
3. Tick the acceptance boxes in the spec, set its status to `done <short hash>`, update `PROGRESS.md`, commit with message `feat(NNN): <name>`.
4. Repeat. Never leave a feature half-ticked at the end of a session; mark it `in progress` with a note of what remains.

## Feature tracker

### Phase 1

| # | Feature | Section | Score | Status |
| --- | --- | --- | --- | --- |
| 001 | [PDF viewer](features/001-pdf-viewer.md) | 1. PDF basics | 125 | done 1555094 |
| 021 | [Images to PDF](features/021-images-to-pdf.md) | 2. Convert | 125 | done 1995985 |
| 034 | [Compress images](features/034-compress-images.md) | 3. Compress | 125 | done 494703f |
| 047 | [Document scanner](features/047-document-scanner.md) | 5. Scan and QR | 125 | done d7ded95 |
| 051 | [QR scanner](features/051-qr-scanner.md) | 5. Scan and QR | 125 | done 012db23 |
| 059 | [On-device mode](features/059-on-device-mode.md) | 6. Security | 125 | done 5fbcce5 |
| 060 | [Share to any app](features/060-share-to-any-app.md) | 7. Share and transfer | 125 | done 9fcace7 |
| 065 | [Open-with for all file types](features/065-open-with-for-all-file-types.md) | 7. Share and transfer | 125 | done 0a5a347 |
| 104 | [Offline first](features/104-offline-first.md) | 10. Platform | 125 | done 12c34d3 |
| 114 | [One search](features/114-one-search.md) | 10. Platform | 125 | done 02b6068 |
| 117 | [File manager](features/117-file-manager.md) | 10. Platform | 125 | done 213b1d0 |
| 032 | [Compress PDF](features/032-compress-pdf.md) | 3. Compress | 100 | done d697bdf |
| 033 | [PDF to target size](features/033-pdf-to-target-size.md) | 3. Compress | 100 | done dc2c45a |
| 035 | [Image to exact KB](features/035-image-to-exact-kb.md) | 3. Compress | 100 | done 678b67d |
| 041 | [Crop with ratios](features/041-crop-with-ratios.md) | 4. Image basics | 100 | done 63f712a |
| 048 | [Scan filters](features/048-scan-filters.md) | 5. Scan and QR | 100 | done cb126a8 |
| 055 | [App lock](features/055-app-lock.md) | 6. Security | 100 | done d092d46 |
| 057 | [Secure notes](features/057-secure-notes.md) | 6. Security | 100 | done e9c143f |
| 064 | [Save anywhere](features/064-save-anywhere.md) | 7. Share and transfer | 100 | done a9a7f75 |
| 106 | [Smart suggestions](features/106-smart-suggestions.md) | 10. Platform | 100 | done 196df57 |
| 111 | [No login](features/111-no-login.md) | 10. Platform | 100 | done 8507290 |
| 115 | [Recents and favourites](features/115-recents-and-favourites.md) | 10. Platform | 100 | done 93c0972 |
| 123 | [Download video from a link](features/123-download-video-from-a-link.md) | 11. Links and WhatsApp essentials | 100 | done 14d74f8 |
| 130 | [Universal video player](features/130-universal-video-player.md) | 11. Links and WhatsApp essentials | 100 | done 7b12cb8 |
| 010 | [Sign PDF](features/010-sign-pdf.md) | 1. PDF basics | 80 | done 2fbb457 |
| 018 | [Word to PDF and back](features/018-word-to-pdf-and-back.md) | 2. Convert | 80 | done 6a5f2ee |
| 025 | [HEIC to JPG or PNG](features/025-heic-to-jpg-or-png.md) | 2. Convert | 80 | done 8a74947 |
| 029 | [Archives](features/029-archives.md) | 2. Convert | 80 | done f5d36ba |
| 030 | [Convert anything](features/030-convert-anything.md) | 2. Convert | 80 | done 068831f |
| 036 | [Compress video](features/036-compress-video.md) | 3. Compress | 80 | done ad80377 |
| 038 | [Shrink-to-send presets](features/038-shrink-to-send-presets.md) | 3. Compress | 80 | done 6558d5c |
| 040 | [Resize](features/040-resize.md) | 4. Image basics | 80 | done 4369d50 |
| 062 | [Phone to laptop](features/062-phone-to-laptop.md) | 7. Share and transfer | 80 | done ddae934 |
| 127 | [Download queue](features/127-download-queue.md) | 11. Links and WhatsApp essentials | 80 | done 7311ffc |
| 128 | [Send at original quality](features/128-send-at-original-quality.md) | 11. Links and WhatsApp essentials | 80 | done e65f4c8 |
| 049 | [ID scan](features/049-id-scan.md) | 5. Scan and QR | 75 | done cedf8ab |
| 118 | [Action history and trash](features/118-action-history-and-trash.md) | 10. Platform | 75 | done bfeeaf5 |
| 125 | [WhatsApp status saver](features/125-whatsapp-status-saver.md) | 11. Links and WhatsApp essentials | 75 | done d1b57d3 |
| 126 | [Clipboard link watch](features/126-clipboard-link-watch.md) | 11. Links and WhatsApp essentials | 75 | done 44ef7df |
| 002 | [Merge PDF](features/002-merge-pdf.md) | 1. PDF basics | 64 | done a590af7 |
| 017 | [Print to PDF](features/017-print-to-pdf.md) | 1. PDF basics | 64 | done b3d4547 |
| 054 | [One-tap searchable scan](features/054-one-tap-searchable-scan.md) | 5. Scan and QR | 64 | done 6232042 |
| 063 | [Cloud import and save](features/063-cloud-import-and-save.md) | 7. Share and transfer | 64 | done 1cf27d4 |
| 105 | [Paste anything](features/105-paste-anything.md) | 10. Platform | 64 | done 1516ef8 |
| 009 | [Fill forms](features/009-fill-forms.md) | 1. PDF basics | 60 | not started |
| 056 | [Private vault](features/056-private-vault.md) | 6. Security | 60 | done 3aa5d75 |
| 061 | [Nearby share](features/061-nearby-share.md) | 7. Share and transfer | 60 | done 049dd84 |
| 124 | [Download audio from a link](features/124-download-audio-from-a-link.md) | 11. Links and WhatsApp essentials | 60 | done 2be5196 |
| 043 | [Passport photo maker](features/043-passport-photo-maker.md) | 4. Image basics | 50 | done d567b9f |
| 044 | [ID card to A4](features/044-id-card-to-a4.md) | 4. Image basics | 50 | done ce3fade |
| 022 | [PDF to images](features/022-pdf-to-images.md) | 2. Convert | 48 | done 07812c7 |
| 026 | [WebP to JPG or PNG and back](features/026-webp-to-jpg-or-png-and-back.md) | 2. Convert | 48 | done 012d5cd |
| 027 | [Raster any to any](features/027-raster-any-to-any.md) | 2. Convert | 48 | done bbf5ab1 |
| 031 | [Batch convert](features/031-batch-convert.md) | 2. Convert | 48 | done 72d3259 |
| 037 | [Zip with optional password](features/037-zip-with-optional-password.md) | 3. Compress | 48 | done e559ab8 |
| 039 | [Before and after preview](features/039-before-and-after-preview.md) | 3. Compress | 48 | done f5ee72f |
| 046 | [View and strip EXIF](features/046-view-and-strip-exif.md) | 4. Image basics | 48 | done 3717803 |
| 052 | [QR generator](features/052-qr-generator.md) | 5. Scan and QR | 48 | done e0c8180 |
| 053 | [Auto-name scans](features/053-auto-name-scans.md) | 5. Scan and QR | 48 | done 32adde0 |
| 066 | [Copy result](features/066-copy-result.md) | 7. Share and transfer | 48 | done 39196a8 |
| 067 | [Background jobs](features/067-background-jobs.md) | 7. Share and transfer | 48 | done 5302aae |
| 107 | [Batch everywhere](features/107-batch-everywhere.md) | 10. Platform | 48 | done e56c777 |
| 108 | [Versions](features/108-versions.md) | 10. Platform | 48 | done d46302d |
| 113 | [Job notifications](features/113-job-notifications.md) | 10. Platform | 48 | done 28fc557 |
| 045 | [Blur faces, plates and Aadhaar numbers](features/045-blur-faces-plates-and-aadhaar-numbers.md) | 4. Image basics | 40 | done 11ef7d0 |
| 003 | [Split PDF](features/003-split-pdf.md) | 1. PDF basics | 36 | done 75b311c |
| 008 | [OCR a scan](features/008-ocr-a-scan.md) | 1. PDF basics | 36 | done 2e732c5 |
| 011 | [Protect with password](features/011-protect-with-password.md) | 1. PDF basics | 36 | done 75b311c |
| 015 | [Remove blank pages and straighten](features/015-remove-blank-pages-and-straighten.md) | 1. PDF basics | 36 | done fe57ee1 |
| 016 | [Search inside PDFs](features/016-search-inside-pdfs.md) | 1. PDF basics | 36 | done 3e2b2f4 |
| 019 | [Excel to PDF and back](features/019-excel-to-pdf-and-back.md) | 2. Convert | 36 | done 28e7f65 |
| 042 | [Rotate and flip](features/042-rotate-and-flip.md) | 4. Image basics | 36 | done 47fa235 |
| 050 | [Receipt scan into the receipt vault](features/050-receipt-scan-into-the-receipt-vault.md) | 5. Scan and QR | 36 | not started |
| 129 | [Recover deleted messages](features/129-recover-deleted-messages.md) | 11. Links and WhatsApp essentials | 36 | done 639e04b |
| 004 | [Extract pages](features/004-extract-pages.md) | 1. PDF basics | 27 | done 2814a57 |
| 005 | [Remove pages](features/005-remove-pages.md) | 1. PDF basics | 27 | done 5f495f0 |
| 006 | [Reorder pages](features/006-reorder-pages.md) | 1. PDF basics | 27 | done 3633a4f |
| 007 | [Rotate pages](features/007-rotate-pages.md) | 1. PDF basics | 27 | done 7a0efef |
| 024 | [Text to PDF](features/024-text-to-pdf.md) | 2. Convert | 27 | done 1c5ba86 |
| 012 | [Unlock a known password](features/012-unlock-a-known-password.md) | 1. PDF basics | 24 | done 2a524de |
| 013 | [Redact](features/013-redact.md) | 1. PDF basics | 24 | done 6b65c18 |
| 058 | [Encrypt any file](features/058-encrypt-any-file.md) | 6. Security | 24 | done d74c332 |
| 023 | [Web page to PDF](features/023-web-page-to-pdf.md) | 2. Convert | 18 | done f802eac |
| 028 | [AVIF to JPG or PNG](features/028-avif-to-jpg-or-png.md) | 2. Convert | 18 | done 8db1c9d |
| 020 | [PowerPoint to PDF and back](features/020-powerpoint-to-pdf-and-back.md) | 2. Convert | 16 | done cca7309 |
| 014 | [Page numbers](features/014-page-numbers.md) | 1. PDF basics | 8 | done e91dafa |

### Phase 2

| # | Feature | Section | Score | Status |
| --- | --- | --- | --- | --- |
| 068 | [Family space](features/068-family-space.md) | 8. Family — shared live data | 125 | done b41233b |
| 069 | [Profile per member](features/069-profile-per-member.md) | 8. Family — shared live data | 125 | done 5ea2376 |
| 071 | [Shared calendar](features/071-shared-calendar.md) | 8. Family — shared live data | 125 | done 1354986 |
| 072 | [Shared shopping list](features/072-shared-shopping-list.md) | 8. Family — shared live data | 125 | done d94d2bc |
| 079 | [Sync through your own Drive or home Wi-Fi](features/079-sync-through-your-own-drive-or-home-wi-fi.md) | 8. Family — shared live data | 125 | done 83d0f04 |
| 073 | [Shared to-do and notice board](features/073-shared-to-do-and-notice-board.md) | 8. Family — shared live data | 100 | done 4cd4908 |
| 074 | [Shared document vault with expiry](features/074-shared-document-vault-with-expiry.md) | 8. Family — shared live data | 100 | done d47e0c6 |
| 121 | [Quick-add](features/121-quick-add.md) | 10. Platform | 100 | not started |
| 076 | [Live family location](features/076-live-family-location.md) | 8. Family — shared live data | 80 | done 7ed778a |
| 077 | [Auto check-in](features/077-auto-check-in.md) | 8. Family — shared live data | 80 | done 14439cb |
| 109 | [Accessibility](features/109-accessibility.md) | 10. Platform | 80 | done 8173048 |
| 110 | [Indian languages per profile](features/110-indian-languages-per-profile.md) | 10. Platform | 80 | done e643735 |
| 112 | [Widgets and quick-settings tile](features/112-widgets-and-quick-settings-tile.md) | 10. Platform | 80 | done f9d3c08 |
| 075 | [Shared contacts](features/075-shared-contacts.md) | 8. Family — shared live data | 75 | done a6a4f49 |
| 120 | [Backup and export](features/120-backup-and-export.md) | 10. Platform | 75 | done 42ee688 |
| 122 | [Cross-links](features/122-cross-links.md) | 10. Platform | 64 | not started |
| 070 | [Family roles](features/070-family-roles.md) | 8. Family — shared live data | 60 | not started |
| 116 | [Custom home](features/116-custom-home.md) | 10. Platform | 45 | not started |
| 078 | [Change log](features/078-change-log.md) | 8. Family — shared live data | 36 | not started |
| 119 | [Guest mode](features/119-guest-mode.md) | 10. Platform | 24 | not started |

### Phase 3

| # | Feature | Section | Score | Status |
| --- | --- | --- | --- | --- |
| 083 | [Bill reminders](features/083-bill-reminders.md) | 9. Personal records | 125 | not started |
| 088 | [Medicine reminders with pill stock](features/088-medicine-reminders-with-pill-stock.md) | 9. Personal records | 125 | not started |
| 080 | [Expense tracker](features/080-expense-tracker.md) | 9. Personal records | 100 | not started |
| 096 | [Saved addresses and autofill profile](features/096-saved-addresses-and-autofill-profile.md) | 9. Personal records | 100 | not started |
| 081 | [Shared expenses and settle-up](features/081-shared-expenses-and-settle-up.md) | 9. Personal records | 80 | not started |
| 087 | [Loan tracker](features/087-loan-tracker.md) | 9. Personal records | 80 | not started |
| 089 | [BP and sugar logs](features/089-bp-and-sugar-logs.md) | 9. Personal records | 80 | not started |
| 093 | [Elderly care log](features/093-elderly-care-log.md) | 9. Personal records | 80 | not started |
| 095 | [Birthdays and anniversaries](features/095-birthdays-and-anniversaries.md) | 9. Personal records | 80 | not started |
| 102 | [WhatsApp direct](features/102-whatsapp-direct.md) | 9. Personal records | 80 | not started |
| 086 | [Warranty tracker](features/086-warranty-tracker.md) | 9. Personal records | 75 | not started |
| 090 | [Doctor visits and prescriptions](features/090-doctor-visits-and-prescriptions.md) | 9. Personal records | 75 | not started |
| 091 | [Reports vault](features/091-reports-vault.md) | 9. Personal records | 75 | not started |
| 084 | [Subscription tracker](features/084-subscription-tracker.md) | 9. Personal records | 64 | not started |
| 085 | [Receipt vault](features/085-receipt-vault.md) | 9. Personal records | 64 | not started |
| 100 | [Loyalty cards](features/100-loyalty-cards.md) | 9. Personal records | 64 | not started |
| 099 | [Where-is-it notes](features/099-where-is-it-notes.md) | 9. Personal records | 60 | not started |
| 092 | [Vaccination record](features/092-vaccination-record.md) | 9. Personal records | 50 | not started |
| 094 | [Health summary PDF](features/094-health-summary-pdf.md) | 9. Personal records | 50 | not started |
| 103 | [Contacts backup](features/103-contacts-backup.md) | 9. Personal records | 50 | not started |
| 082 | [Lending ledger](features/082-lending-ledger.md) | 9. Personal records | 48 | not started |
| 098 | [Maintenance log](features/098-maintenance-log.md) | 9. Personal records | 48 | not started |
| 101 | [Templates](features/101-templates.md) | 9. Personal records | 48 | not started |
| 097 | [Wi-Fi and devices](features/097-wi-fi-and-devices.md) | 9. Personal records | 40 | not started |
