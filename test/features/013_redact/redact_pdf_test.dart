import 'dart:convert';
import 'dart:io' show ZLibCodec;
import 'dart:typed_data';

import 'package:family_utility_app/app/theme.dart';
import 'package:family_utility_app/engines/convert/pdf_to_word.dart';
import 'package:family_utility_app/engines/pdf/pdf_compressor.dart';
import 'package:family_utility_app/engines/pdf/pdf_redactor.dart';
import 'package:family_utility_app/engines/share/share_engine.dart';
import 'package:family_utility_app/tools/redact_pdf/redact_pdf_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A classic PDF from object bodies, numbered from 1, with a real xref.
Uint8List classicPdf(List<String> bodies) {
  final StringBuffer b = StringBuffer('%PDF-1.4\n');
  final List<int> offsets = <int>[];
  for (int i = 0; i < bodies.length; i++) {
    offsets.add(b.length);
    b.write('${i + 1} 0 obj\n${bodies[i]}\nendobj\n');
  }
  final int xref = b.length;
  b.write('xref\n0 ${bodies.length + 1}\n0000000000 65535 f \n');
  for (final int o in offsets) {
    b.write('${o.toString().padLeft(10, '0')} 00000 n \n');
  }
  b.write('trailer\n<< /Size ${bodies.length + 1} /Root 1 0 R >>\nstartxref\n$xref\n%%EOF\n');
  return Uint8List.fromList(latin1.encode(b.toString()));
}

String stream(String dict, String data) => '<< $dict /Length ${data.length} >>\nstream\n$data\nendstream';

/// Courier-like: every glyph 600 units wide.
final String courier =
    '<< /Type /Font /Subtype /Type1 /BaseFont /Courier /FirstChar 32 /LastChar 126 /Widths [${List<String>.filled(95, '600').join(' ')}] >>';

/// One page: "Hello secret world" at (72, 700) in 12 pt, glyphs 7.2 pt wide,
/// plus [extra] content and resources.
Uint8List textPdf({
  String text = '(Hello secret world) Tj',
  String extraContent = '',
  String extraResources = '',
  String extraPage = '',
  List<String> extraObjects = const <String>[],
}) {
  final String content = 'BT /F1 12 Tf 72 700 Td $text ET\n$extraContent';
  return classicPdf(<String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R '
        '/Resources << /Font << /F1 5 0 R >> $extraResources >> $extraPage >>',
    stream('', content),
    courier,
    ...extraObjects,
  ]);
}

const RedactPageBox letter = RedactPageBox(0, 0, 612, 792);

/// The box over "secret": x 115.2–158.4, baseline 700.
RedactBox secretBox() => letter.boxFor(0, 115.2, 699, 158.4, 708, pad: 0.5);

/// Every stream in the file, inflated where it is Flate.
List<String> allStreams(Uint8List pdf) {
  final PdfDocumentModel doc = PdfDocumentModel.parse(pdf);
  return <String>[
    for (final PdfObject o in doc.objects.values)
      if (o.stream != null && o.value is PdfDict) latin1.decode(PdfRedactor.decode(o.value as PdfDict, o.stream!) ?? o.stream!),
  ];
}

List<PdfObject> images(Uint8List pdf) {
  final PdfDocumentModel doc = PdfDocumentModel.parse(pdf);
  return doc.objects.values
      .where((PdfObject o) => o.value is PdfDict && (o.value as PdfDict).name('Subtype') == 'Image')
      .toList();
}

class FakeFiles implements RedactPdfFiles {
  FakeFiles(this.input);
  final RedactInput input;
  final Map<String, Uint8List> written = <String, Uint8List>{};

  @override
  Future<RedactInput?> pick() async => input;

  @override
  Future<String> write(String name, Uint8List bytes) async {
    written['/redacted/$name'] = bytes;
    return '/redacted/$name';
  }

  @override
  Future<void> remove(String path) async => written.remove(path);
}

class FakeText implements PdfTextSource {
  int reads = 0;

  @override
  Future<List<List<PdfTextPiece>>> read(Uint8List pdf) async {
    reads++;
    return <List<PdfTextPiece>>[
      <PdfTextPiece>[const PdfTextPiece('Hello secret world', left: 72, bottom: 697, right: 201.6, top: 709)],
    ];
  }
}

class FakeSheet implements ShareSheet {
  final List<ShareRequest> requests = <ShareRequest>[];

  @override
  Future<ShareOutcome> share(ShareRequest request) async {
    requests.add(request);
    return const ShareOutcome(completed: true);
  }
}

void main() {
  group('text', () {
    test('the letters under the box leave the content stream; the rest stay in place', () {
      final Uint8List input = textPdf();
      expect(PdfRedactor.pageText(input, 0), contains('secret'));
      final PdfRedactResult r = PdfRedactor.redact(input, <RedactBox>[secretBox()]);
      expect(r.glyphsRemoved, 6);
      expect(r.pages, 1);
      final String text = PdfRedactor.pageText(r.bytes, 0);
      expect(text, isNot(contains('secret')));
      expect(text, contains('Hello'));
      expect(text, contains('world'));
      // Not in any stream of the new file, compressed or not.
      for (final String s in allStreams(r.bytes)) {
        expect(s, isNot(contains('secret')));
        expect(s, isNot(contains('736563726574'))); // "secret" as hex
      }
      expect(latin1.decode(r.bytes), isNot(contains('secret')));
      // The gap keeps "world" where it was: six 600-unit moves.
      final String page = allStreams(r.bytes).firstWhere((String s) => s.contains('TJ'));
      expect('-600'.allMatches(page).length, 6);
      // A black box is drawn on top.
      expect(page, contains('0 0 0 rg'));
      expect(page, contains(' re f'));
    });

    test('verification: searched words are gone and nothing is left under the box', () {
      final Uint8List input = textPdf();
      final RedactCheck before = PdfRedactor.verify(input, <RedactBox>[secretBox()], words: <String>['secret']);
      expect(before.passed, isFalse);
      expect(before.glyphsLeft, 6);
      expect(before.wordsFound, <String>['secret']);

      final PdfRedactResult r = PdfRedactor.redact(input, <RedactBox>[secretBox()]);
      final RedactCheck after = PdfRedactor.verify(r.bytes, <RedactBox>[secretBox()], words: <String>['secret', 'SECRET']);
      expect(after.glyphsLeft, 0);
      expect(after.wordsFound, isEmpty);
      expect(after.passed, isTrue);
      // A word outside the box is still found.
      expect(PdfRedactor.verify(r.bytes, <RedactBox>[secretBox()], words: <String>['world']).wordsFound, <String>['world']);
    });

    test('TJ arrays with kerning, hex strings and the quote operator', () {
      final Uint8List input = textPdf(text: '[(Hello ) -0 <736563> (ret world)] TJ (Hello secret again) \'');
      final PdfRedactResult r = PdfRedactor.redact(input, <RedactBox>[secretBox()]);
      final String text = PdfRedactor.pageText(r.bytes, 0);
      expect(text, contains('Hello'));
      expect(text, contains('world'));
      // The second line (TL is 0, so it starts at the same place) is cut too.
      expect(text, isNot(contains('secret')));
      expect(text, contains('again'));
      expect('Hello'.allMatches(text).length, 2);
      expect(r.glyphsRemoved, 12);
    });

    test('text inside a form XObject is cut out of a copy of the form', () {
      const String form = 'BT /F1 12 Tf 72 700 Td (Hidden secret form) Tj ET';
      final Uint8List input = textPdf(
        text: '',
        extraContent: 'q 1 0 0 1 0 -100 cm /Fm1 Do Q',
        extraResources: '/XObject << /Fm1 6 0 R >>',
        extraObjects: <String>[
          stream('/Type /XObject /Subtype /Form /BBox [0 0 612 792] /Resources << /Font << /F1 5 0 R >> >>', form),
        ],
      );
      // The form is drawn 100 pt lower: "secret" sits at x 122.4–165.6, y 600.
      final RedactBox box = letter.boxFor(0, 122.4, 599, 165.6, 608, pad: 0.5);
      final PdfRedactResult r = PdfRedactor.redact(input, <RedactBox>[box]);
      expect(r.glyphsRemoved, 6);
      for (final String s in allStreams(r.bytes)) {
        expect(s, isNot(contains('secret')));
      }
      expect(PdfRedactor.pageText(r.bytes, 0), contains('Hidden'));
      expect(PdfRedactor.verify(r.bytes, <RedactBox>[box], words: <String>['secret']).passed, isTrue);
    });
  });

  group('pictures and notes', () {
    test('pixels under the box turn black; the old picture is not kept', () {
      final String white = String.fromCharCodes(List<int>.filled(4 * 4 * 3, 255));
      final Uint8List input = textPdf(
        extraContent: 'q 100 0 0 100 0 0 cm /Im1 Do Q',
        extraResources: '/XObject << /Im1 6 0 R >>',
        extraObjects: <String>[
          stream('/Type /XObject /Subtype /Image /Width 4 /Height 4 /ColorSpace /DeviceRGB /BitsPerComponent 8', white),
        ],
      );
      final PdfRedactResult r = PdfRedactor.redact(input, <RedactBox>[letter.boxFor(0, 0, 0, 48, 100, pad: 0)]);
      expect(r.imagesChanged, 1);
      final List<PdfObject> left = images(r.bytes);
      expect(left, hasLength(1));
      final PdfDict d = left.single.value as PdfDict;
      expect(d.name('Filter'), 'FlateDecode');
      final List<int> px = ZLibCodec().decode(left.single.stream!);
      for (int y = 0; y < 4; y++) {
        for (int x = 0; x < 4; x++) {
          final int v = px[(y * 4 + x) * 3];
          expect(v, x < 2 ? 0 : 255, reason: 'pixel $x,$y');
        }
      }
    });

    test('a picture in a format the app cannot rewrite is dropped, not covered', () {
      final Uint8List input = textPdf(
        extraContent: 'q 100 0 0 100 0 0 cm /Im1 Do Q',
        extraResources: '/XObject << /Im1 6 0 R >>',
        extraObjects: <String>[
          stream('/Type /XObject /Subtype /Image /Width 4 /Height 4 /ColorSpace /DeviceRGB /BitsPerComponent 8 '
              '/Filter /RunLengthDecode', 'xx'),
        ],
      );
      final PdfRedactResult r = PdfRedactor.redact(input, <RedactBox>[letter.boxFor(0, 0, 0, 50, 50, pad: 0)]);
      expect(r.imagesChanged, 1);
      expect(images(r.bytes), isEmpty);
    });

    test('notes over the box are deleted, others kept', () {
      final Uint8List input = textPdf(
        extraPage: '/Annots [6 0 R 7 0 R]',
        extraObjects: <String>[
          '<< /Type /Annot /Subtype /FreeText /Rect [110 690 170 715] /Contents (secret note) >>',
          '<< /Type /Annot /Subtype /Text /Rect [400 100 420 120] /Contents (keep me) >>',
        ],
      );
      final PdfRedactResult r = PdfRedactor.redact(input, <RedactBox>[secretBox()]);
      expect(r.annotationsRemoved, 1);
      final String all = latin1.decode(r.bytes);
      expect(all, isNot(contains('secret note')));
      expect(all, contains('keep me'));
    });
  });

  group('input', () {
    test('page boxes, empty marks and missing pages', () {
      final Uint8List input = textPdf();
      expect(PdfRedactor.pageBoxes(input).single.height, 792);
      expect(() => PdfRedactor.redact(input, const <RedactBox>[]), throwsA(isA<RedactError>()));
      expect(
        () => PdfRedactor.redact(input, const <RedactBox>[RedactBox(page: 3, left: 0, top: 0, width: 0.5, height: 0.5)]),
        throwsA(isA<RedactError>()),
      );
      expect(() => PdfRedactor.pageBoxes(Uint8List.fromList(utf8.encode('not a pdf'))), throwsA(isA<RedactError>()));
    });

    test('found words become boxes over just their letters', () {
      final List<RedactBox> boxes = boxesForQuery(
        <List<PdfTextPiece>>[
          <PdfTextPiece>[const PdfTextPiece('Hello secret world', left: 72, bottom: 697, right: 201.6, top: 709)],
        ],
        <RedactPageBox>[letter],
        'SECRET',
      );
      expect(boxes, hasLength(1));
      final RedactBox b = boxes.single;
      expect(b.left * 612, closeTo(114.2, 0.01));
      expect((b.left + b.width) * 612, closeTo(159.4, 0.01));
      expect(boxesForQuery(const <List<PdfTextPiece>>[], <RedactPageBox>[letter], ' '), isEmpty);
      // Applied to the file, it removes exactly the word.
      final PdfRedactResult r = PdfRedactor.redact(textPdf(), boxes);
      expect(r.glyphsRemoved, 6);
    });
  });

  testWidgets('find a word, black it out, verify, share and undo', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final SemanticsHandle handle = tester.ensureSemantics();
    final FakeFiles files = FakeFiles(RedactInput('bank.pdf', '/in/bank.pdf', textPdf()));
    final FakeSheet sheet = FakeSheet();
    final FakeText text = FakeText();
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: RedactPdfScreen(
        files: files,
        textSource: text,
        pageView: (BuildContext c, String path, int page) => const SizedBox.expand(),
        runner: (RedactJob j) async {
          final PdfRedactResult r = PdfRedactor.redact(j.bytes, j.boxes);
          return RedactOutcome(r, PdfRedactor.verify(r.bytes, j.boxes, words: j.words));
        },
        share: ShareEngine(sheet, MemoryShareTargetStore()),
      ),
    ));
    await tester.tap(find.byKey(const Key('redact-pdf-pick')));
    await tester.pumpAndSettle();
    expect(find.text('bank.pdf'), findsOneWidget);
    expect(find.text('Mark something first'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('redact-pdf-query')), 'secret');
    await tester.tap(find.byKey(const Key('redact-pdf-find')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Marked "secret" 1 time on 1 page'), findsOneWidget);
    expect(text.reads, 1);

    final Finder run = find.byKey(const Key('redact-pdf-run'));
    expect(tester.getSize(run).height, greaterThanOrEqualTo(44));
    expect(find.text('Black out 1 for good'), findsOneWidget);
    await tester.tap(run);
    await tester.pumpAndSettle();
    expect(find.textContaining('Checked: no text is left under the boxes.'), findsOneWidget);
    expect(find.textContaining('Searching for "secret" finds nothing.'), findsOneWidget);
    expect(files.written.keys.single, '/redacted/bank redacted.pdf');
    final Uint8List out = files.written.values.single;
    expect(PdfRedactor.pageText(out, 0), isNot(contains('secret')));

    await tester.tap(find.byKey(const Key('result-share')));
    await tester.pumpAndSettle();
    expect(sheet.requests, hasLength(1));

    await tester.tap(find.byKey(const Key('result-undo')));
    await tester.pumpAndSettle();
    expect(files.written, isEmpty);
    expect(find.textContaining('Removed the redacted copy'), findsOneWidget);

    // A hand-drawn box on the page.
    final Finder canvas = find.byKey(const Key('redact-pdf-canvas'));
    final Offset tl = tester.getTopLeft(canvas);
    final TestGesture g = await tester.startGesture(tl + const Offset(10, 10));
    await g.moveBy(const Offset(60, 40));
    await g.up();
    await tester.pumpAndSettle();
    expect(find.text('Black out 2 for good'), findsOneWidget);
    handle.dispose();
  });
}
