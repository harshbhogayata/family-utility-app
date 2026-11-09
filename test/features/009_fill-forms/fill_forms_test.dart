import 'dart:convert';
import 'dart:typed_data';

import 'package:family_utility_app/engines/pdf/pdf_compressor.dart';
import 'package:family_utility_app/engines/pdf/pdf_form_filler.dart';
import 'package:family_utility_app/engines/records/autofill_profile.dart';
import 'package:family_utility_app/engines/security/secure_notes.dart';
import 'package:family_utility_app/tools/fill_forms/fill_forms_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

String _stream(String dict, String body) => '<< $dict /Length ${body.length} >>\nstream\n$body\nendstream';

Uint8List formPdf() {
  final List<String> objs = <String>[
    '1 0 obj\n<< /Type /Catalog /Pages 2 0 R /AcroForm << /Fields [5 0 R 6 0 R 7 0 R 8 0 R 9 0 R] /DA (/Helv 0 Tf 0 g) >> >>\nendobj',
    '2 0 obj\n<< /Type /Pages /Kids [3 0 R 4 0 R] /Count 2 /MediaBox [0 0 595 842] >>\nendobj',
    '3 0 obj\n<< /Type /Page /Parent 2 0 R /Resources << >> /Contents 10 0 R /Annots [5 0 R 6 0 R 7 0 R 81 0 R 82 0 R 9 0 R] >>\nendobj',
    '4 0 obj\n<< /Type /Page /Parent 2 0 R /Contents 11 0 R >>\nendobj',
    '5 0 obj\n<< /Type /Annot /Subtype /Widget /FT /Tx /T (applicant_name) /TU (Full name) /Rect [100 700 300 720] /P 3 0 R /DA (/Helv 10 Tf 0 g) >>\nendobj',
    '6 0 obj\n<< /Type /Annot /Subtype /Widget /FT /Tx /T <FEFF0064006F0062> /Rect [100 660 200 680] /MaxLen 10 >>\nendobj',
    '7 0 obj\n<< /Type /Annot /Subtype /Widget /FT /Btn /T (agree) /Rect [100 620 115 635] /V /Off /AS /Off /AP << /N << /Yes 12 0 R /Off 13 0 R >> >> >>\nendobj',
    '8 0 obj\n<< /FT /Btn /Ff 49152 /T (gender) /V /Off /Kids [81 0 R 82 0 R] >>\nendobj',
    '81 0 obj\n<< /Type /Annot /Subtype /Widget /Parent 8 0 R /Rect [100 580 112 592] /AS /Off /AP << /N << /M 12 0 R /Off 13 0 R >> >> >>\nendobj',
    '82 0 obj\n<< /Type /Annot /Subtype /Widget /Parent 8 0 R /Rect [130 580 142 592] /AS /Off /AP << /N << /F 12 0 R /Off 13 0 R >> >> >>\nendobj',
    '9 0 obj\n<< /Type /Annot /Subtype /Widget /FT /Ch /Ff 131072 /T (state) /Opt [(Karnataka) (Kerala)] /V (Karnataka) /Rect [100 540 250 556] >>\nendobj',
    '10 0 obj\n${_stream('', 'BT ET')}\nendobj',
    '11 0 obj\n${_stream('', 'BT ET')}\nendobj',
    '12 0 obj\n${_stream('/Type /XObject /Subtype /Form /BBox [0 0 15 15]', '0 0 m')}\nendobj',
    '13 0 obj\n${_stream('/Type /XObject /Subtype /Form /BBox [0 0 15 15]', '0 0 m')}\nendobj',
  ];
  return Uint8List.fromList(latin1.encode('%PDF-1.4\n${objs.join('\n')}\ntrailer\n<< /Root 1 0 R /Size 83 >>\n%%EOF\n'));
}

Uint8List plainPdf() {
  final List<String> objs = <String>[
    '1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj',
    '2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj',
    '3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 600 800] /Contents 4 0 R >>\nendobj',
    '4 0 obj\n${_stream('', 'BT ET')}\nendobj',
  ];
  return Uint8List.fromList(latin1.encode('%PDF-1.4\n${objs.join('\n')}\ntrailer\n<< /Root 1 0 R /Size 5 >>\n%%EOF\n'));
}

String text(Uint8List b) => latin1.decode(b);

FormFieldInfo field(FormInfo i, String name) => i.fields.firstWhere((FormFieldInfo f) => f.name == name);

class FakeFiles implements FillFiles {
  FakeFiles(this.pdf);
  final Uint8List pdf;
  final Map<String, Uint8List> written = <String, Uint8List>{};

  @override
  Future<String?> pickPdf() async => '/docs/application.pdf';

  @override
  Future<Uint8List> read(String path) async => pdf;

  @override
  Future<String> write(String name, Uint8List bytes) async {
    written['/filled/$name'] = bytes;
    return '/filled/$name';
  }

  @override
  Future<void> remove(String path) async {
    written.remove(path);
  }
}

void main() {
  group('detect', () {
    test('finds text, check box, radio and choice fields', () {
      final FormInfo info = PdfFormFiller.detect(formPdf());
      expect(info.hasForm, isTrue);
      expect(info.pages.length, 2);
      expect(info.fields.map((FormFieldInfo f) => f.name), <String>['applicant_name', 'dob', 'agree', 'gender', 'state']);

      final FormFieldInfo name = field(info, 'applicant_name');
      expect(name.kind, FormFieldKind.text);
      expect(name.label, 'Full name');
      expect(name.page, 0);
      expect(name.rect!.width, 200);

      final FormFieldInfo dob = field(info, 'dob');
      expect(dob.maxLength, 10);
      expect(dob.page, 0);

      expect(field(info, 'agree').kind, FormFieldKind.checkbox);
      expect(field(info, 'agree').options, <String>['Yes']);
      expect(field(info, 'agree').checked, isFalse);
      expect(field(info, 'gender').kind, FormFieldKind.radio);
      expect(field(info, 'gender').options, <String>['M', 'F']);
      expect(field(info, 'state').kind, FormFieldKind.choice);
      expect(field(info, 'state').options, <String>['Karnataka', 'Kerala']);
      expect(field(info, 'state').value, 'Karnataka');
    });

    test('a PDF without a form has no fields', () {
      final FormInfo info = PdfFormFiller.detect(plainPdf());
      expect(info.hasForm, isFalse);
      expect(info.pages.single.width, 600);
    });

    test('decodes literal, escaped and UTF-16 strings', () {
      PdfString s(String raw) => PdfString(Uint8List.fromList(latin1.encode(raw)));
      expect(PdfFormFiller.decodeText(s(r'(a\(b\)\\c\101)')), r'a(b)\cA');
      expect(PdfFormFiller.decodeText(s('<FEFF0928092E>')), 'नम');
      expect(PdfFormFiller.pdfLiteral('a(b)'), r'a\(b\)');
    });
  });

  group('fill', () {
    final Map<String, String> values = <String, String>{
      'applicant_name': 'Asha Mehta',
      'dob': '07/04/1990-extra',
      'agree': 'true',
      'gender': 'F',
      'state': 'Kerala',
    };

    test('writes values with appearances and keeps the form editable', () {
      final Uint8List out = PdfFormFiller.fill(formPdf(), values: values);
      final FormInfo info = PdfFormFiller.detect(out);
      expect(field(info, 'applicant_name').value, 'Asha Mehta');
      expect(field(info, 'dob').value, '07/04/1990', reason: 'MaxLen is respected');
      expect(field(info, 'agree').checked, isTrue);
      expect(field(info, 'gender').value, 'F');
      expect(field(info, 'state').value, 'Kerala');
      final String s = text(out);
      expect(s, contains('(Asha Mehta) Tj'));
      expect(s, contains('/NeedAppearances true'));
      expect(s, contains('/AS /F'));
    });

    test('flatten draws the fields into the page and removes the form', () {
      final Uint8List out = PdfFormFiller.fill(formPdf(), values: values, flatten: true);
      final FormInfo info = PdfFormFiller.detect(out);
      expect(info.hasForm, isFalse);
      final String s = text(out);
      expect(s, contains('(Asha Mehta) Tj'));
      expect(s, contains('/FuaFlat0 Do'));
      expect(s.contains('/AcroForm'), isFalse);
      expect(s.contains('/Annots'), isFalse);
    });

    test('text boxes go anywhere on a PDF without a form', () {
      final Uint8List out = PdfFormFiller.fill(
        plainPdf(),
        texts: const <PlacedText>[PlacedText(page: 0, left: 0.5, top: 0.25, text: 'Hello (there)\nLine 2', fontSize: 10)],
      );
      final String s = text(out);
      expect(s, contains(r'(Hello \(there\)) Tj T* (Line 2) Tj'));
      expect(s, contains('300.00 590.00 Td'));
      expect(PdfFormFiller.detect(out).pages.length, 1);
    });

    test('a damaged file gives a plain error', () {
      expect(() => PdfFormFiller.detect(Uint8List.fromList(latin1.encode('not a pdf'))), throwsA(isA<FormFillError>()));
    });
  });

  testWidgets('screen offers profile values in fields and saves with Share, Save, Undo', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final AutofillProfileBook book = AutofillProfileBook(
      keyStore: MemoryKeyStore(),
      blobStore: MemoryNoteBlobStore(),
      clipboard: MemoryClipboard(),
    );
    await book.load();
    await book.save(AutofillProfile(firstName: 'Asha', lastName: 'Mehta', dateOfBirth: DateTime(1990, 4, 7)));

    final FakeFiles files = FakeFiles(formPdf());
    Map<String, String>? sent;
    bool? flat;
    await tester.pumpWidget(MaterialApp(
      home: FillFormsScreen(
        files: files,
        profile: book,
        pageView: (BuildContext context, String path, int page) => const SizedBox.expand(),
        runner: (Uint8List pdf, Map<String, String> v, List<PlacedText> t, bool f) async {
          sent = v;
          flat = f;
          return PdfFormFiller.fill(pdf, values: v, texts: t, flatten: f);
        },
      ),
    ));
    await tester.tap(find.byKey(const Key('fill-pick')));
    await tester.pumpAndSettle();

    expect(find.text('Full name'), findsWidgets);
    final Finder chip = find.byKey(const Key('fill-suggest-applicant_name-Asha Mehta'));
    expect(chip, findsOneWidget);
    expect(find.byKey(const Key('fill-suggest-dob-07/04/1990')), findsOneWidget);
    expect(tester.getSize(chip).height, greaterThanOrEqualTo(32));
    await tester.tap(chip);
    await tester.pump();
    expect(find.widgetWithText(TextField, 'Asha Mehta'), findsOneWidget);

    await tester.tap(find.byKey(const Key('fill-flatten')));
    await tester.pump();

    // Tap the page to place a text box.
    await tester.tap(find.byKey(const Key('fill-page')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('fill-box-text')), 'Bengaluru');
    await tester.tap(find.byKey(const Key('fill-box-ok')));
    await tester.pumpAndSettle();
    expect(find.text('Bengaluru'), findsOneWidget);

    await tester.tap(find.byKey(const Key('result-save')));
    await tester.pumpAndSettle();
    expect(sent, <String, String>{'applicant_name': 'Asha Mehta'});
    expect(flat, isTrue);
    expect(files.written.keys, <String>['/filled/application-filled.pdf']);
    expect(text(files.written.values.first), contains('(Bengaluru) Tj'));

    await tester.tap(find.byKey(const Key('result-undo')));
    await tester.pumpAndSettle();
    expect(files.written, isEmpty);
    await tester.tap(find.byKey(const Key('result-undo')));
    await tester.pumpAndSettle();
    expect(find.text('Bengaluru'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });
}
