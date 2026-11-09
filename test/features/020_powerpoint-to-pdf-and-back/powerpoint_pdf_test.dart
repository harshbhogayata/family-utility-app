import 'dart:convert';
import 'dart:typed_data';

import 'package:family_utility_app/app/theme.dart';
import 'package:family_utility_app/engines/archive/zip_codec.dart';
import 'package:family_utility_app/engines/convert/convert_registry.dart';
import 'package:family_utility_app/engines/convert/file_kind.dart';
import 'package:family_utility_app/engines/convert/pdf_to_word.dart';
import 'package:family_utility_app/engines/convert/slides.dart';
import 'package:family_utility_app/tools/convert_anything/convert_anything_screen.dart';
import 'package:family_utility_app/tools/powerpoint_pdf/powerpoint_pdf_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

class FakeChooser implements ConvertFileChooser {
  FakeChooser(this.input);
  ConvertInput input;

  @override
  Future<ConvertInput?> pick() async => input;
}

class FakeSink implements ConvertSink {
  final Map<String, ConvertOutput> files = <String, ConvertOutput>{};

  @override
  Future<String> write(ConvertOutput out) async {
    final String p = '/converted/${out.name}';
    files[p] = out;
    return p;
  }

  @override
  Future<void> remove(String path) async => files.remove(path);
}

/// Two A4 pages of positioned text, as PDFium would report them.
class FakeTextSource implements PdfTextSource {
  @override
  Future<List<List<PdfTextPiece>>> read(Uint8List pdf) async => <List<PdfTextPiece>>[
        <PdfTextPiece>[
          const PdfTextPiece('Trip plan', left: 72, bottom: 760, right: 200, top: 784),
          const PdfTextPiece('Leave at', left: 72, bottom: 700, right: 120, top: 712),
          const PdfTextPiece('6 am', left: 124, bottom: 700, right: 150, top: 712),
        ],
        <PdfTextPiece>[
          const PdfTextPiece('Packing', left: 72, bottom: 760, right: 160, top: 784),
        ],
      ];
}

const String _p = 'http://schemas.openxmlformats.org/presentationml/2006/main';
const String _a = 'http://schemas.openxmlformats.org/drawingml/2006/main';
const String _r = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
const String _rel = 'http://schemas.openxmlformats.org/package/2006/relationships';

List<int> u(String s) => utf8.encode(s);

/// A deck laid out the way PowerPoint saves one: 16:9 (960 x 540 pt), a
/// title placeholder placed by the layout, a positioned text box, a picture
/// and speaker notes on slide 1; slide 2 listed second but stored as slide9.
Uint8List sampleDeck() {
  final img.Image pic = img.Image(width: 4, height: 3);
  img.fill(pic, color: img.ColorRgb8(200, 30, 30));
  final Uint8List png = img.encodePng(pic);
  return ZipWriter().build(<ZipInput>[
    ZipInput('[Content_Types].xml', u('<Types/>')),
    ZipInput('ppt/presentation.xml', u('<p:presentation xmlns:p="$_p" xmlns:r="$_r">'
        '<p:sldIdLst><p:sldId id="256" r:id="rId7"/><p:sldId id="257" r:id="rId8"/></p:sldIdLst>'
        '<p:sldSz cx="12192000" cy="6858000"/></p:presentation>')),
    ZipInput('ppt/_rels/presentation.xml.rels', u('<Relationships xmlns="$_rel">'
        '<Relationship Id="rId8" Type="$_r/slide" Target="slides/slide9.xml"/>'
        '<Relationship Id="rId7" Type="$_r/slide" Target="slides/slide1.xml"/></Relationships>')),
    ZipInput('ppt/slides/slide1.xml', u('<p:sld xmlns:p="$_p" xmlns:a="$_a" xmlns:r="$_r"><p:cSld><p:spTree>'
        '<p:sp><p:nvSpPr><p:cNvPr id="2" name="Title"/><p:cNvSpPr/><p:nvPr><p:ph type="title"/></p:nvPr></p:nvSpPr>'
        '<p:spPr/><p:txBody><a:bodyPr/><a:p><a:pPr algn="ctr"/><a:r><a:rPr sz="4000" b="1"/><a:t>Family (trip)</a:t></a:r></a:p></p:txBody></p:sp>'
        '<p:sp><p:nvSpPr><p:cNvPr id="3" name="Box"/><p:cNvSpPr txBox="1"/><p:nvPr/></p:nvSpPr>'
        '<p:spPr><a:xfrm><a:off x="1270000" y="2540000"/><a:ext cx="3810000" cy="1270000"/></a:xfrm>'
        '<a:solidFill><a:srgbClr val="FFEEAA"/></a:solidFill></p:spPr>'
        '<p:txBody><a:bodyPr/><a:p><a:r><a:rPr sz="2000"><a:solidFill><a:srgbClr val="FF0000"/></a:solidFill></a:rPr>'
        '<a:t>Leave at 6 am</a:t></a:r></a:p></p:txBody></p:sp>'
        '<p:pic><p:nvPicPr><p:cNvPr id="4" name="Pic"/><p:cNvPicPr/><p:nvPr/></p:nvPicPr>'
        '<p:blipFill><a:blip r:embed="rId3"/></p:blipFill>'
        '<p:spPr><a:xfrm><a:off x="6350000" y="2540000"/><a:ext cx="2540000" cy="1905000"/></a:xfrm></p:spPr></p:pic>'
        '</p:spTree></p:cSld></p:sld>')),
    ZipInput('ppt/slides/_rels/slide1.xml.rels', u('<Relationships xmlns="$_rel">'
        '<Relationship Id="rId3" Type="$_r/image" Target="../media/image1.png"/>'
        '<Relationship Id="rId4" Type="$_r/notesSlide" Target="../notesSlides/notesSlide1.xml"/></Relationships>')),
    ZipInput('ppt/media/image1.png', png),
    ZipInput('ppt/notesSlides/notesSlide1.xml', u('<p:notes xmlns:p="$_p" xmlns:a="$_a"><p:cSld><p:spTree>'
        '<p:sp><p:nvSpPr><p:cNvPr id="2" name="Img"/><p:cNvSpPr/><p:nvPr><p:ph type="sldImg"/></p:nvPr></p:nvSpPr></p:sp>'
        '<p:sp><p:nvSpPr><p:cNvPr id="3" name="Notes"/><p:cNvSpPr/><p:nvPr><p:ph type="body" idx="1"/></p:nvPr></p:nvSpPr>'
        '<p:txBody><a:bodyPr/><a:p><a:r><a:t>Remind everyone about tickets</a:t></a:r></a:p></p:txBody></p:sp>'
        '</p:spTree></p:cSld></p:notes>')),
    ZipInput('ppt/slides/slide9.xml', u('<p:sld xmlns:p="$_p" xmlns:a="$_a"><p:cSld><p:spTree>'
        '<p:sp><p:nvSpPr><p:cNvPr id="2" name="Body"/><p:cNvSpPr/><p:nvPr><p:ph idx="1"/></p:nvPr></p:nvSpPr>'
        '<p:spPr/><p:txBody><a:bodyPr/><a:p><a:r><a:t>Second slide</a:t></a:r></a:p></p:txBody></p:sp>'
        '</p:spTree></p:cSld></p:sld>')),
  ]);
}

int pageCount(Uint8List pdf) => RegExp(r'/Type /Page ').allMatches(latin1.decode(pdf)).length;

void main() {
  group('reading a deck', () {
    test('sniffs PPTX and old PPT', () {
      expect(sniffFileKind(sampleDeck()), FileKind.pptx);
      final Uint8List ppt = Uint8List.fromList(<int>[
        0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1, //
        for (final int c in ascii.encode('PowerPoint Document')) ...<int>[c, 0],
      ]);
      expect(sniffFileKind(ppt), FileKind.ppt);
    });

    test('slides in deck order with sizes, positions, pictures and notes', () {
      final SlideDeck deck = const PptxReader().read(sampleDeck());
      expect(deck.width, 960);
      expect(deck.height, 540);
      expect(deck.slides, hasLength(2));
      final Slide one = deck.slides.first;
      expect(one.notes, 'Remind everyone about tickets');
      expect(one.shapes, hasLength(3));
      expect(one.shapes[0].paragraphs.single.text, 'Family (trip)');
      expect(one.shapes[0].paragraphs.single.align, SlideAlign.center);
      expect(one.shapes[0].paragraphs.single.runs.single.bold, isTrue);
      expect(one.shapes[0].y, lessThan(540 * 0.2));
      final SlideShape box = one.shapes[1];
      expect((box.x, box.y, box.width, box.height), (100.0, 200.0, 300.0, 100.0));
      expect(box.fill, 'FFEEAA');
      expect(box.paragraphs.single.runs.single.size, 20);
      expect(box.paragraphs.single.runs.single.color, 'FF0000');
      expect(one.shapes[2].image, isNotNull);
      expect((one.shapes[2].x, one.shapes[2].width), (500.0, 200.0));
      expect(deck.slides[1].shapes.single.paragraphs.single.text, 'Second slide');
      expect(deck.slides[1].notes, '');
    });

    test('not a deck says so', () {
      expect(() => const PptxReader().read(Uint8List.fromList(<int>[1, 2, 3])), throwsA(isA<ConvertException>()));
    });
  });

  group('deck to PDF', () {
    test('one page per slide at the slide size; text and picture where they were', () async {
      final ConvertRegistry reg = ConvertRegistry.builtIn();
      registerSlideConverters(reg, FakeTextSource());
      final ConvertOutput out = await reg.convert(ConvertInput(name: 'trip.pptx', bytes: sampleDeck()), 'pptx-to-pdf');
      expect(out.name, 'trip.pdf');
      expect(sniffFileKind(out.bytes), FileKind.pdf);
      final String s = latin1.decode(out.bytes);
      expect(pageCount(out.bytes), 2);
      expect(s, contains('/MediaBox [0 0 960.00 540.00]'));
      expect(s, contains(r'(Family \(trip\)) Tj'));
      // The box's first line sits inside the box: x = 100 + inset, under its top (540 - 200).
      final RegExpMatch m = RegExp(r'/FR 20\.00 Tf ([\d.]+) ([\d.]+) Td \(Leave at 6 am\) Tj').firstMatch(s)!;
      expect(double.parse(m.group(1)!), closeTo(107.2, 0.01));
      expect(double.parse(m.group(2)!), lessThan(340));
      expect(double.parse(m.group(2)!), greaterThan(240));
      expect(s, contains('1.000 0.000 0.000 rg /FR 20.00 Tf'));
      expect(s, contains('200.00 0 0 150.00 500.00 190.00 cm /Im0 Do'));
      expect(s, contains('/Filter /DCTDecode'));
      expect(s, isNot(contains('Remind everyone')));
    });

    test('speaker notes are optional: a notes page follows the slide that has them', () async {
      final ConvertRegistry reg = ConvertRegistry.builtIn();
      registerSlideConverters(reg, FakeTextSource());
      final ConvertOutput out =
          await reg.convert(ConvertInput(name: 'trip.pptx', bytes: sampleDeck()), 'pptx-to-pdf-notes');
      expect(pageCount(out.bytes), 3);
      expect(latin1.decode(out.bytes), contains('(Remind everyone about tickets) Tj'));
    });

    test('long text wraps inside its box', () {
      final List<String> lines = wrapSlideText('one two three four five six seven eight nine ten', 80, 12);
      expect(lines.length, greaterThan(1));
      expect(lines.join(' '), 'one two three four five six seven eight nine ten');
    });

    test('old .ppt is refused plainly', () async {
      final ConvertRegistry reg = ConvertRegistry.builtIn();
      registerSlideConverters(reg, FakeTextSource());
      await expectLater(
        reg.convert(
            ConvertInput(name: 'old.ppt', bytes: Uint8List.fromList(<int>[
              0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1, //
              for (final int c in ascii.encode('PowerPoint Document')) ...<int>[c, 0],
            ])),
            'ppt-to-pdf'),
        throwsA(isA<ConvertException>().having((ConvertException e) => e.message, 'm', contains('.pptx'))),
      );
    });
  });

  group('PDF to deck', () {
    test('one slide per page, each line a text box in place; PowerPoint layout parts present', () async {
      final ConvertRegistry reg = ConvertRegistry.builtIn();
      registerSlideConverters(reg, FakeTextSource());
      final ConvertOutput out = await reg.convert(ConvertInput(name: 'plan.pdf', bytes: Uint8List.fromList(ascii.encode('%PDF-1.4\n%%EOF'))), 'pdf-to-pptx');
      expect(out.name, 'plan.pptx');
      expect(sniffFileKind(out.bytes), FileKind.pptx);
      final List<String> names = ZipReader(out.bytes).entries.map((ZipEntry e) => e.name).toList();
      expect(
          names,
          containsAll(<String>[
            '[Content_Types].xml',
            '_rels/.rels',
            'ppt/slideMasters/slideMaster1.xml',
            'ppt/slideLayouts/slideLayout1.xml',
            'ppt/theme/theme1.xml',
          ]));
      final SlideDeck deck = const PptxReader().read(out.bytes);
      expect(deck.slides, hasLength(2));
      final List<String> texts = deck.slides.first.shapes.map((SlideShape s) => s.paragraphs.single.text).toList();
      expect(texts, <String>['Trip plan', 'Leave at 6 am']);
      expect(deck.slides.first.shapes[0].y, lessThan(deck.slides.first.shapes[1].y));
      expect(deck.slides.first.shapes[0].paragraphs.single.size,
          greaterThan(deck.slides.first.shapes[1].paragraphs.single.size));
      expect(deck.slides[1].shapes.single.paragraphs.single.text, 'Packing');
    });

    test('a deck written here reads back the same', () {
      const SlideDeck deck = SlideDeck(width: 720, height: 540, slides: <Slide>[
        Slide(<SlideShape>[
          SlideShape(x: 36, y: 40, width: 600, height: 60, fill: '112233', paragraphs: <SlideParagraph>[
            SlideParagraph(<SlideRun>[SlideRun('A & B <ok>', size: 32, bold: true, color: '00FF00')],
                align: SlideAlign.right),
          ]),
        ]),
      ]);
      final SlideDeck back = const PptxReader().read(const PptxWriter().write(deck));
      expect((back.width, back.height), (720.0, 540.0));
      final SlideShape s = back.slides.single.shapes.single;
      expect((s.x, s.y, s.width, s.height), (36.0, 40.0, 600.0, 60.0));
      expect(s.fill, '112233');
      final SlideParagraph p = s.paragraphs.single;
      expect(p.text, 'A & B <ok>');
      expect(p.align, SlideAlign.right);
      expect((p.runs.single.size, p.runs.single.bold, p.runs.single.color), (32.0, true, '00FF00'));
    });
  });

  testWidgets('pick a deck, get a PDF; notes switch; .ppt refused; undo removes it', (WidgetTester tester) async {
    final ConvertRegistry r = ConvertRegistry.builtIn();
    registerSlideConverters(r, FakeTextSource());
    final FakeSink sink = FakeSink();
    final FakeChooser chooser = FakeChooser(ConvertInput(name: 'trip.pptx', bytes: sampleDeck()));
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: PowerPointPdfScreen(chooser: chooser, sink: sink, registry: r),
    ));
    expect(tester.getSize(find.byKey(const Key('ppt-pdf-pick'))).height, greaterThanOrEqualTo(44));
    expect(tester.getSize(find.byKey(const Key('ppt-pdf-notes'))).height, greaterThanOrEqualTo(44));
    await tester.tap(find.byKey(const Key('ppt-pdf-notes')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ppt-pdf-pick')));
    await tester.pumpAndSettle();
    expect(sink.files.keys, <String>['/converted/trip.pdf']);
    expect(pageCount(sink.files['/converted/trip.pdf']!.bytes), 3);
    expect(find.textContaining('Made trip.pdf'), findsOneWidget);
    expect(find.byKey(const Key('result-share')), findsOneWidget);
    expect(find.byKey(const Key('result-save')), findsOneWidget);

    await tester.tap(find.byKey(const Key('result-undo')));
    await tester.pumpAndSettle();
    expect(sink.files, isEmpty);

    chooser.input = ConvertInput(
      name: 'old.ppt',
      bytes: Uint8List.fromList(<int>[
        0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1, //
        for (final int c in ascii.encode('PowerPoint Document')) ...<int>[c, 0],
      ]),
    );
    await tester.tap(find.byKey(const Key('ppt-pdf-pick')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Save it as .pptx'), findsOneWidget);
    expect(sink.files, isEmpty);
  });
}
