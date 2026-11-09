import 'package:family_utility_app/engines/records/autofill_profile.dart';
import 'package:family_utility_app/engines/security/secure_notes.dart';
import 'package:family_utility_app/records/profile/autofill_profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

AutofillProfile sample() => AutofillProfile(
      firstName: 'Asha',
      middleName: 'R',
      lastName: 'Mehta',
      dateOfBirth: DateTime(1990, 4, 7),
      phone: '+91 98200 12345',
      email: 'asha@example.com',
      addresses: const <SavedAddress>[
        SavedAddress(
          id: 'h',
          label: 'Home',
          line1: '12 MG Road',
          line2: 'Indiranagar',
          city: 'Bengaluru',
          state: 'Karnataka',
          pincode: '560038',
        ),
        SavedAddress(id: 'w', label: 'Work', line1: '4 Park St', city: 'Kolkata', state: 'West Bengal', pincode: '700016'),
      ],
      custom: const <CustomField>[CustomField(label: "Father's name", value: 'Ramesh Mehta')],
    );

void main() {
  group('form field matcher', () {
    test('maps common form names to profile keys', () {
      expect(FormFieldMatcher.keyFor('applicant_name'), ProfileKey.fullName);
      expect(FormFieldMatcher.keyFor('Full Name'), ProfileKey.fullName);
      expect(FormFieldMatcher.keyFor('FirstName'), ProfileKey.firstName);
      expect(FormFieldMatcher.keyFor('Surname'), ProfileKey.lastName);
      expect(FormFieldMatcher.keyFor('Date of Birth'), ProfileKey.dateOfBirth);
      expect(FormFieldMatcher.keyFor('DOB'), ProfileKey.dateOfBirth);
      expect(FormFieldMatcher.keyFor('Mobile No.'), ProfileKey.phone);
      expect(FormFieldMatcher.keyFor('E-mail ID'), ProfileKey.email);
      expect(FormFieldMatcher.keyFor('Pin Code'), ProfileKey.pincode);
      expect(FormFieldMatcher.keyFor('City'), ProfileKey.city);
      expect(FormFieldMatcher.keyFor('State'), ProfileKey.state);
      expect(FormFieldMatcher.keyFor('Address Line 2'), ProfileKey.addressLine2);
      expect(FormFieldMatcher.keyFor('Residential Address'), ProfileKey.address);
    });

    test('leaves other people and unknown fields alone', () {
      expect(FormFieldMatcher.keyFor("Father's Name"), isNull);
      expect(FormFieldMatcher.keyFor('Nominee name'), isNull);
      expect(FormFieldMatcher.keyFor('Signature'), isNull);
      expect(FormFieldMatcher.keyFor(''), isNull);
    });
  });

  group('profile book', () {
    late MemoryNoteBlobStore blobs;
    late MemoryKeyStore keys;
    late MemoryClipboard clip;
    late AutofillProfileBook book;

    setUp(() {
      blobs = MemoryNoteBlobStore();
      keys = MemoryKeyStore();
      clip = MemoryClipboard();
      book = AutofillProfileBook(keyStore: keys, blobStore: blobs, clipboard: clip);
    });

    test('stores the profile encrypted and reads it back', () async {
      await book.save(sample());
      final String blob = blobs.blob!;
      expect(blob.contains('Asha'), isFalse);
      expect(blob.contains('560038'), isFalse);

      final AutofillProfileBook again = AutofillProfileBook(keyStore: keys, blobStore: blobs, clipboard: clip);
      await again.load();
      expect(again.loadError, isNull);
      expect(again.profile, sample());
      expect(again.profile.fullName, 'Asha R Mehta');
      expect(again.profile.addresses.first.oneLine, '12 MG Road, Indiranagar, Bengaluru, Karnataka 560038, India');
    });

    test('a wrong key does not leak or crash', () async {
      await book.save(sample());
      final AutofillProfileBook other = AutofillProfileBook(keyStore: MemoryKeyStore(), blobStore: blobs, clipboard: clip);
      await other.load();
      expect(other.loadError, isNotNull);
      expect(other.profile.isEmpty, isTrue);
    });

    test('suggestions for PDF form fields (009)', () async {
      await book.save(sample());
      expect(book.valueFor('applicant_name'), 'Asha R Mehta');
      expect(book.valueFor('first_name'), 'Asha');
      expect(book.valueFor('DOB'), '07/04/1990');
      expect(book.suggestionsFor('Date of birth').map((AutofillSuggestion s) => s.value), <String>['07/04/1990', '1990-04-07']);
      expect(book.valueFor('Mobile'), '+91 98200 12345');
      expect(book.suggestionsFor('PIN').map((AutofillSuggestion s) => s.value), <String>['560038', '700016']);
      expect(book.suggestionsFor('City').map((AutofillSuggestion s) => s.label), <String>['Home', 'Work']);
      expect(book.valueFor("Father's name"), 'Ramesh Mehta');
      expect(book.valueFor('Signature'), isNull);
    });

    test('copy goes to the clipboard and is cleared later', () async {
      final AutofillProfileBook quick = AutofillProfileBook(
        keyStore: keys,
        blobStore: blobs,
        clipboard: clip,
        clearClipboardAfter: const Duration(milliseconds: 10),
      );
      await quick.copy('560038');
      expect(clip.text, '560038');
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(clip.text, isNull);
    });

    test('undo puts back the previous profile', () async {
      await book.save(sample());
      await book.save(book.profile.copyWith(phone: '000'));
      expect(book.profile.phone, '000');
      expect(await book.undo(), isTrue);
      expect(book.profile.phone, '+91 98200 12345');
      final SavedAddress a = await book.addAddress(label: 'Parents');
      expect(book.profile.addresses.length, 3);
      await book.removeAddress(a.id);
      expect(book.profile.addresses.length, 2);
      expect(await book.undo(), isTrue);
      expect(book.profile.addresses.length, 3);
    });
  });

  testWidgets('screen copies a value in one tap and has Share, Save, Undo', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final MemoryClipboard clip = MemoryClipboard();
    final AutofillProfileBook book = AutofillProfileBook(
      keyStore: MemoryKeyStore(),
      blobStore: MemoryNoteBlobStore(),
      clipboard: clip,
    );
    await book.load();
    await book.save(sample());
    String? shared;
    await tester.pumpWidget(MaterialApp(
      home: AutofillProfileScreen(book: book, share: (String t) async => shared = t, save: (String t) async => '/tmp/x.txt'),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Asha R Mehta'), findsOneWidget);
    expect(find.text('Encrypted on this phone. Never uploaded.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('copy-phone')));
    await tester.pump();
    expect(clip.text, '+91 98200 12345');
    expect(find.text('Phone copied'), findsOneWidget);

    await tester.tap(find.byKey(const Key('copy-address-h')));
    await tester.pump();
    expect(clip.text, '12 MG Road, Indiranagar, Bengaluru, Karnataka 560038, India');

    await tester.tap(find.byKey(const Key('result-share')));
    await tester.pump();
    expect(shared, contains('Date of birth: 07/04/1990'));
    expect(find.byKey(const Key('result-undo')), findsOneWidget);
    expect(find.byKey(const Key('result-save')), findsOneWidget);

    // Copy buttons meet the touch target and are labelled.
    final Size s = tester.getSize(find.byKey(const Key('copy-email')));
    expect(s.width, greaterThanOrEqualTo(44));
    expect(s.height, greaterThanOrEqualTo(44));
    expect(find.byTooltip('Copy Email'), findsOneWidget);

    // Undo after deleting an address brings it back.
    await tester.tap(find.byTooltip('Delete Work address'));
    await tester.pump();
    await tester.pump();
    expect(book.profile.addresses.length, 1);
    await tester.tap(find.byKey(const Key('result-undo')));
    await tester.pump();
    await tester.pump();
    expect(book.profile.addresses.length, 2);

    await tester.pumpWidget(const SizedBox());
    book.dispose();
    await tester.pump(const Duration(seconds: 5));
  });
}
