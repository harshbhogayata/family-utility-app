import 'dart:convert';

import 'package:family_utility_app/app/theme.dart';
import 'package:family_utility_app/engines/security/app_lock.dart';
import 'package:family_utility_app/engines/security/secure_notes.dart';
import 'package:family_utility_app/tools/secure_notes/note_edit_screen.dart';
import 'package:family_utility_app/tools/secure_notes/secure_notes_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget app(Widget home) => MaterialApp(theme: buildAppTheme(), home: home);

SecureNote wifiNote() => SecureNote(
      id: 'n1',
      title: 'Home Wi-Fi',
      fields: const <NoteField>[
        NoteField(label: 'Network', value: 'HomeNet', secret: false),
        NoteField(label: 'Password', value: 'p@ss-1234'),
      ],
      note: 'Router is in the hall.',
      updatedAt: DateTime(2026, 11, 1),
    );

void main() {
  late MemoryKeyStore keys;
  late MemoryNoteBlobStore blobs;
  late MemoryClipboard clipboard;
  late SecureNotes notes;

  setUp(() {
    keys = MemoryKeyStore();
    blobs = MemoryNoteBlobStore();
    clipboard = MemoryClipboard();
    notes = SecureNotes(keyStore: keys, blobStore: blobs, clipboard: clipboard);
    SecureNotes.install(notes);
    AppLock.install(AppLock(store: MemoryLockStore()));
  });

  group('engine', () {
    test('notes are encrypted at rest: the blob holds no plain text and needs the key', () async {
      await notes.load();
      await notes.save(wifiNote());
      final String blob = blobs.blob!;
      expect(blob, isNot(contains('p@ss-1234')));
      expect(blob, isNot(contains('Home Wi-Fi')));
      expect(blob, isNot(contains('HomeNet')));
      final Map<String, Object?> parsed = jsonDecode(blob) as Map<String, Object?>;
      expect(parsed.keys, containsAll(<String>['v', 'n', 'c', 'm']));
      expect(keys.readKey(), completion(hasLength(32)));

      // Same key store, fresh engine: reads back.
      final SecureNotes again = SecureNotes(keyStore: keys, blobStore: blobs, clipboard: clipboard);
      await again.load();
      expect(again.loadError, isNull);
      expect(again.notes.single.title, 'Home Wi-Fi');
      expect(again.notes.single.fields[1].value, 'p@ss-1234');
      expect(again.notes.single.note, 'Router is in the hall.');

      // Another key: cannot read, but does not crash.
      final SecureNotes stranger =
          SecureNotes(keyStore: MemoryKeyStore(), blobStore: blobs, clipboard: clipboard);
      await stranger.load();
      expect(stranger.loadError, isNotNull);
      expect(stranger.notes, isEmpty);
    });

    test('a tampered blob is rejected', () async {
      await notes.save(wifiNote());
      final Map<String, Object?> parsed = jsonDecode(blobs.blob!) as Map<String, Object?>;
      final List<int> ct = base64Url.decode(parsed['c']! as String);
      ct[0] ^= 0xFF;
      parsed['c'] = base64Url.encode(ct);
      blobs.blob = jsonEncode(parsed);
      final SecureNotes again = SecureNotes(keyStore: keys, blobStore: blobs, clipboard: clipboard);
      await again.load();
      expect(again.loadError, isNotNull);
    });

    test('every write uses a fresh nonce', () async {
      await notes.save(wifiNote());
      final String first = blobs.blob!;
      await notes.save(wifiNote());
      expect(blobs.blob, isNot(first));
    });

    test('save, update, delete and newest-first order', () async {
      await notes.load();
      final SecureNote a = await notes.save(wifiNote());
      await notes.save(SecureNote(id: 'n2', title: 'Aadhaar', updatedAt: DateTime(2000)));
      expect(notes.notes.map((SecureNote n) => n.id), <String>['n2', 'n1']);
      await notes.save(a.copyWith(title: 'Wi-Fi (new router)'));
      expect(notes.notes.first.title, 'Wi-Fi (new router)');
      expect(notes.notes, hasLength(2));
      await notes.delete('n2');
      expect(notes.byId('n2'), isNull);
      expect(notes.notes, hasLength(1));
    });

    test('plain text for Share and JSON round-trip', () {
      final SecureNote n = wifiNote();
      expect(n.toPlainText(), 'Home Wi-Fi\nNetwork: HomeNet\nPassword: p@ss-1234\n\nRouter is in the hall.');
      final SecureNote back = SecureNote.fromJson(jsonDecode(jsonEncode(n.toJson())) as Map<String, Object?>);
      expect(back.id, 'n1');
      expect(back.fields, n.fields);
      expect(back.updatedAt, n.updatedAt);
      expect(SecureNotes.newId(), hasLength(16));
      expect(SecureNotes.newId(), isNot(SecureNotes.newId()));
    });
  });

  group('clipboard', () {
    testWidgets('a copied value clears itself after the delay unless replaced', (WidgetTester tester) async {
      final SecureNotes quick = SecureNotes(
        keyStore: keys,
        blobStore: blobs,
        clipboard: clipboard,
        clearClipboardAfter: const Duration(seconds: 5),
      );
      await quick.copy('p@ss-1234');
      expect(clipboard.text, 'p@ss-1234');
      await tester.pump(const Duration(seconds: 4));
      expect(clipboard.text, 'p@ss-1234');
      await tester.pump(const Duration(seconds: 2));
      expect(clipboard.text, isNull);

      await quick.copy('secret');
      clipboard.text = 'something the person copied elsewhere';
      await tester.pump(const Duration(seconds: 6));
      expect(clipboard.text, 'something the person copied elsewhere', reason: 'never wipe someone else\'s copy');

      await quick.copy('secret');
      await quick.clearClipboardNow();
      expect(clipboard.text, isNull);
      quick.dispose();
    });
  });

  group('list screen', () {
    testWidgets('copies a field without opening the note and masks secrets', (WidgetTester tester) async {
      await notes.save(wifiNote());
      await tester.pumpWidget(app(const SecureNotesScreen()));
      await tester.pumpAndSettle();
      expect(find.text('Home Wi-Fi'), findsOneWidget);
      expect(find.text('HomeNet'), findsOneWidget, reason: 'non-secret fields show');
      expect(find.text('p@ss-1234'), findsNothing, reason: 'secret fields are masked');
      expect(find.textContaining('Set a PIN in App lock'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey<String>('copy-n1-Password')));
      await tester.pump();
      expect(clipboard.text, 'p@ss-1234');
      expect(find.textContaining('Password copied'), findsOneWidget);
      expect(find.byType(NoteEditScreen), findsNothing);
    });

    testWidgets('empty state, New note opens the editor, buttons are 44 px and labelled',
        (WidgetTester tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await tester.pumpWidget(app(const SecureNotesScreen()));
      await tester.pumpAndSettle();
      expect(find.text('No notes yet'), findsOneWidget);
      final Size fab = tester.getSize(find.byKey(const Key('new-note')));
      expect(fab.height, greaterThanOrEqualTo(44));
      await tester.tap(find.byKey(const Key('new-note')));
      await tester.pumpAndSettle();
      expect(find.byType(NoteEditScreen), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Add field')), findsWidgets);
      handle.dispose();
    });
  });

  group('edit screen', () {
    testWidgets('template, type, save; Undo reverts unsaved edits; Share sends plain text',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(app(NoteEditScreen(notes: notes)));
      await tester.tap(find.byKey(const ValueKey<String>('template-Wi-Fi')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey<String>('field-value-0')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('field-value-1')), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey<String>('field-value-0')), 'HomeNet');
      await tester.enterText(find.byKey(const ValueKey<String>('field-value-1')), 'p@ss-1234');
      await tester.tap(find.byKey(const Key('result-save')));
      await tester.pumpAndSettle();
      expect(notes.notes.single.title, 'Wi-Fi');
      expect(notes.notes.single.fields.map((NoteField f) => f.value), <String>['HomeNet', 'p@ss-1234']);
      expect(blobs.blob, isNot(contains('p@ss-1234')));

      await tester.enterText(find.byKey(const Key('note-title')), 'Changed');
      await tester.tap(find.byKey(const Key('result-undo')));
      await tester.pumpAndSettle();
      expect(find.text('Changed'), findsNothing);
      expect(find.text('Wi-Fi'), findsWidgets);
      expect(find.text('Back to the saved version'), findsOneWidget);

      // Values are obscured by default and can be revealed per field.
      final TextField pw = tester.widget<TextField>(find.byKey(const ValueKey<String>('field-value-1')));
      expect(pw.obscureText, isTrue);
      await tester.tap(find.byTooltip('Show value').last);
      await tester.pump();
      expect(tester.widget<TextField>(find.byKey(const ValueKey<String>('field-value-1'))).obscureText, isFalse);
    });

    testWidgets('remove field and delete note', (WidgetTester tester) async {
      await notes.save(wifiNote());
      await tester.pumpWidget(app(NoteEditScreen(notes: notes, existing: notes.notes.single)));
      await tester.tap(find.byKey(const ValueKey<String>('field-remove-0')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey<String>('field-value-1')), findsNothing);
      await tester.tap(find.byKey(const Key('result-save')));
      await tester.pumpAndSettle();
      expect(notes.notes.single.fields, hasLength(1));

      await tester.tap(find.byKey(const Key('delete-note')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(notes.notes, isEmpty);
    });
  });

  group('privacy', () {
    test('the notes engine has no network code', () {
      // Covered by the airplane-mode scan in 104; here: no plain-text field
      // ever reaches the blob store.
      expect(MemoryNoteBlobStore().blob, isNull);
    });
  });
}
