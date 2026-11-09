import 'dart:convert';
import 'dart:io' show ZLibCodec;
import 'dart:typed_data';

import 'package:family_utility_app/app/theme.dart';
import 'package:family_utility_app/engines/convert/convert_registry.dart';
import 'package:family_utility_app/engines/convert/file_kind.dart';
import 'package:family_utility_app/engines/pdf/images_to_pdf.dart' show PdfPageSize;
import 'package:family_utility_app/engines/pdf/pdf_compressor.dart';
import 'package:family_utility_app/engines/pdf/text_to_pdf.dart';
import 'package:family_utility_app/engines/share/share_engine.dart';
import 'package:family_utility_app/tools/text_to_pdf/text_to_pdf_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Hindi and Tamil with conjuncts and pre-base vowel signs.
const String indic = 'नमस्ते, क्षत्रिय और कृष्ण की किताब।\nவணக்கம், தமிழ் கொண்டு எழுதுங்கள்.';

List<PdfDict> pageDicts(Uint8List pdf) {
  final PdfDocumentModel d = PdfDocumentModel.parse(pdf);
  final PdfDict root = d.resolve(d.trailer['Root'])! as PdfDict;
  final PdfDict pages = d.resolve(root['Pages'])! as PdfDict;
  return <PdfDict>[for (final Object k in (pages['Kids']! as PdfArray).items) d.resolve(k)! as PdfDict];
}

/// Records what it was asked to draw; one small page per 10 lines.
class FakeRenderer implements TextPageRenderer {
  final List<(String, TextPdfOptions)> calls = <(String, TextPdfOptions)>[];

  @override
  Future<List<GreyPage>> render(String text, TextPdfOptions o) async {
    calls.add((text, o));
    final int n = (text.split('\n').length + 9) ~/ 10;
    return <GreyPage>[
      for (int i = 0; i < n; i++)
        GreyPage(width: 4, height: 4, pixels: Uint8List(16)..fillRange(0, 16, 255), widthPt: o.page.$1, heightPt: o.page.$2),
    ];
  }
}

class FakeFiles implements TextPdfFiles {
  FakeFiles([this.clip]);
  final String? clip;
  final Map<String, Uint8List> written = <String, Uint8List>{};

  @override
  Future<String?> paste() async => clip;

  @override
  Future<String> write(String name, Uint8List bytes) async {
    written['/converted/$name'] = bytes;
    return '/converted/$name';
  }

  @override
  Future<void> remove(String path) async => written.remove(path);
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
  group('engine', () {
    test('lines never split across pages; a tall line gets its own page', () {
      final List<LineSpan> lines = <LineSpan>[for (int i = 0; i < 10; i++) LineSpan(i * 20.0, i * 20.0 + 18)];
      expect(TextToPdf.paginate(lines, 70), const <PageSlice>[
        PageSlice(0, 60),
        PageSlice(60, 120),
        PageSlice(120, 180),
        PageSlice(180, 250),
      ]);
      expect(TextToPdf.paginate(<LineSpan>[const LineSpan(0, 10), const LineSpan(10, 200)], 50).length, 2);
      expect(TextToPdf.paginate(<LineSpan>[], 50), const <PageSlice>[PageSlice(0, 50)]);
    });

    test('names come from the first line', () {
      expect(TextToPdf.nameFor('  Shopping list\nmilk'), 'Shopping list.pdf');
      expect(TextToPdf.nameFor('a/b: c?'), 'a b c.pdf');
      expect(TextToPdf.nameFor('नमस्ते दुनिया'), 'नमस्ते दुनिया.pdf');
      expect(TextToPdf.nameFor('\n\n'), 'Text.pdf');
    });

    test('pages are lossless grey images on A4 or Letter', () {
      final Uint8List px = Uint8List.fromList(List<int>.generate(12, (int i) => i * 20));
      final Uint8List pdf = TextToPdf.writePdf(<GreyPage>[
        GreyPage(width: 4, height: 3, pixels: px, widthPt: 595.28, heightPt: 841.89),
        GreyPage(width: 4, height: 3, pixels: px, widthPt: 612, heightPt: 792),
      ]);
      final PdfDocumentModel d = PdfDocumentModel.parse(pdf);
      final List<PdfDict> pages = pageDicts(pdf);
      expect(pages, hasLength(2));
      expect(<String>[for (final Object n in (pages[1]['MediaBox']! as PdfArray).items) (n as PdfNum).raw],
          <String>['0', '0', '612.00', '792.00']);
      final PdfDict xo = d.resolve((d.resolve(pages[0]['Resources'])! as PdfDict)['XObject'])! as PdfDict;
      final PdfObject im = d.objects[(xo['Im0']! as PdfRef).num]!;
      final PdfDict id = im.value as PdfDict;
      expect(id.name('ColorSpace'), 'DeviceGray');
      expect(id.name('Filter'), 'FlateDecode');
      expect(ZLibCodec().decode(im.stream!), px);
      expect(() => TextToPdf.writePdf(<GreyPage>[]), throwsA(isA<TextPdfError>()));
    });

    test('the maker passes font, size and page; empty text is refused', () async {
      final FakeRenderer r = FakeRenderer();
      final TextPdfMaker m = TextPdfMaker(renderer: r);
      final TextPdfResult res = await m.make('$indic\r\n\tend\n\n',
          const TextPdfOptions(font: TextPdfFont.serif, fontSize: 18, pageSize: PdfPageSize.letter));
      expect(res.pages, 1);
      expect(res.name, 'नमस्ते, क्षत्रिय और कृष्ण की किताब।.pdf');
      expect(r.calls.single.$1, '$indic\n    end');
      expect(r.calls.single.$2.font.family, 'serif');
      expect(r.calls.single.$2.fontSize, 18);
      expect(pageDicts(res.bytes), hasLength(1));
      await expectLater(m.make('  \n ', const TextPdfOptions()), throwsA(isA<TextPdfError>()));
    });

    test('Convert anything turns a .txt file into a PDF', () async {
      final ConvertRegistry reg = ConvertRegistry.builtIn()..register(TextToPdfConverter(maker: TextPdfMaker(renderer: FakeRenderer())));
      expect(reg.targetsFor(FileKind.text).map((Converter c) => c.id), contains('text-to-pdf'));
      final ConvertOutput out = await reg.convert(
          ConvertInput(name: 'notes.txt', bytes: Uint8List.fromList(utf8.encode('hello\nनमस्ते'))), 'text-to-pdf');
      expect(out.name, 'notes.pdf');
      expect(pageDicts(out.bytes), hasLength(1));
    });

    testWidgets('the phone text engine draws Indian scripts onto pages', (WidgetTester tester) async {
      final List<GreyPage> pages = (await tester.runAsync(() => const FlutterTextPageRenderer()
          .render(List<String>.filled(60, 'Hello world $indic').join('\n'), const TextPdfOptions(fontSize: 14, dpi: 36))))!;
      expect(pages.length, greaterThan(1));
      final GreyPage p = pages.first;
      expect(p.width, (595.28 * 36 / 72).round());
      expect(p.pixels.length, p.width * p.height);
      // Ink inside the margins, white margins.
      expect(p.pixels.any((int v) => v < 128), isTrue);
      expect(p.pixels.sublist(0, p.width * 5).every((int v) => v > 250), isTrue);
    });
  });

  group('screen', () {
    Future<FakeFiles> pump(WidgetTester tester, {String? clip, ShareEngine? share, FakeRenderer? renderer}) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final FakeFiles files = FakeFiles(clip);
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: TextToPdfScreen(files: files, maker: TextPdfMaker(renderer: renderer ?? FakeRenderer()), share: share),
      ));
      return files;
    }

    testWidgets('paste, pick font and size, make, share and undo', (WidgetTester tester) async {
      final FakeSheet sheet = FakeSheet();
      final FakeRenderer renderer = FakeRenderer();
      final FakeFiles files =
          await pump(tester, clip: indic, share: ShareEngine(sheet, MemoryShareTargetStore()), renderer: renderer);
      expect(tester.getSize(find.byKey(const Key('text-pdf-paste'))).height, greaterThanOrEqualTo(44));
      expect(tester.getSize(find.byKey(const Key('text-pdf-make'))).height, greaterThanOrEqualTo(44));
      expect(tester.getSize(find.byKey(const Key('text-pdf-font-mono'))).height, greaterThanOrEqualTo(44));

      await tester.tap(find.byKey(const Key('text-pdf-paste')));
      await tester.pumpAndSettle();
      expect(find.text(indic), findsOneWidget);

      await tester.tap(find.byKey(const Key('text-pdf-font-mono')));
      await tester.pumpAndSettle();
      await tester.drag(find.byKey(const Key('text-pdf-size')), const Offset(400, 0));
      await tester.pumpAndSettle();
      expect(find.text('Size: 32 pt'), findsOneWidget);

      await tester.tap(find.byKey(const Key('text-pdf-make')));
      await tester.pumpAndSettle();
      final String name = '/converted/${TextToPdf.nameFor(indic)}';
      expect(files.written.keys, <String>[name]);
      expect(renderer.calls.single.$2.font, TextPdfFont.mono);
      expect(renderer.calls.single.$2.fontSize, 32);
      expect(find.byKey(const Key('text-pdf-result')), findsOneWidget);

      await tester.tap(find.byKey(const Key('result-share')));
      await tester.pumpAndSettle();
      expect(sheet.requests.single.files.single.path, name);

      await tester.tap(find.byKey(const Key('result-undo')));
      await tester.pumpAndSettle();
      expect(files.written, isEmpty);
      expect(find.text(indic), findsOneWidget);
    });

    testWidgets('empty text makes nothing; controls are labelled', (WidgetTester tester) async {
      final SemanticsHandle h = tester.ensureSemantics();
      final FakeFiles files = await pump(tester);
      await tester.tap(find.byKey(const Key('result-save')));
      await tester.pumpAndSettle();
      expect(files.written, isEmpty);
      expect(find.text('Paste or type some text first'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Text')), findsWidgets);
      expect(find.bySemanticsLabel('Phone font'), findsOneWidget);
      h.dispose();
    });
  });
}
