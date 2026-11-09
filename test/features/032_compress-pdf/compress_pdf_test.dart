import 'dart:convert';
import 'dart:io' show ZLibCodec;
import 'dart:typed_data';

import 'package:family_utility_app/app/theme.dart';
import 'package:family_utility_app/engines/pdf/pdf_compressor.dart';
import 'package:family_utility_app/engines/share/share_engine.dart';
import 'package:family_utility_app/tools/compress_pdf/compress_pdf_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

const String content = 'BT /F1 24 Tf 72 700 Td (Hello family) Tj ET\n'
    'q 400 0 0 280 72 300 cm /Im1 Do Q\n';

/// Builds a PDF from object bodies (object n is bodies[n - 1]).
Uint8List buildPdf(List<List<int>> bodies, {String trailerExtra = ''}) {
  final BytesBuilder b = BytesBuilder();
  b.add(latin1.encode('%PDF-1.4\n'));
  final List<int> offsets = <int>[];
  for (int i = 0; i < bodies.length; i++) {
    offsets.add(b.length);
    b.add(latin1.encode('${i + 1} 0 obj\n'));
    b.add(bodies[i]);
    b.add(latin1.encode('\nendobj\n'));
  }
  final int xref = b.length;
  b.add(latin1.encode('xref\n0 ${bodies.length + 1}\n0000000000 65535 f \n'));
  for (final int o in offsets) {
    b.add(latin1.encode('${o.toString().padLeft(10, '0')} 00000 n \n'));
  }
  b.add(latin1.encode('trailer\n<< /Size ${bodies.length + 1} /Root 1 0 R $trailerExtra>>\nstartxref\n$xref\n%%EOF\n'));
  return b.toBytes();
}

List<int> streamObj(String dict, List<int> data) =>
    <int>[...latin1.encode('<< $dict /Length ${data.length} >>\nstream\n'), ...data, ...latin1.encode('\nendstream')];

Uint8List photo(int w, int h) {
  final img.Image im = img.Image(width: w, height: h);
  int seed = 7;
  for (int y = 0; y < h; y += 2) {
    for (int x = 0; x < w; x += 2) {
      seed = (seed * 1103515245 + 12345) & 0x7fffffff;
      final int n = seed % 60;
      final img.Color c = img.ColorRgb8((x * 255 ~/ w + n) % 256, (y * 255 ~/ h + n) % 256, (n * 4) % 256);
      for (int dy = 0; dy < 2 && y + dy < h; dy++) {
        for (int dx = 0; dx < 2 && x + dx < w; dx++) {
          im.setPixel(x + dx, y + dy, c);
        }
      }
    }
  }
  return img.encodeJpg(im, quality: 95);
}

Uint8List samplePdf() {
  final Uint8List jpg = photo(2000, 1400);
  return buildPdf(<List<int>>[
    latin1.encode('<< /Type /Catalog /Pages 2 0 R >>'),
    latin1.encode('<< /Type /Pages /Kids [3 0 R] /Count 1 >>'),
    latin1.encode('<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R '
        '/Resources << /Font << /F1 5 0 R >> /XObject << /Im1 6 0 R >> >> >>'),
    streamObj('', latin1.encode(content * 20)),
    latin1.encode('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>'),
    streamObj('/Type /XObject /Subtype /Image /Width 2000 /Height 1400 /ColorSpace /DeviceRGB '
        '/BitsPerComponent 8 /Filter /DCTDecode', jpg),
    latin1.encode('(an orphan nobody uses)'),
  ]);
}

/// Checks every xref offset points at its object header.
void expectValidXref(Uint8List pdf) {
  final String t = latin1.decode(pdf);
  final int start = int.parse(RegExp(r'startxref\s+(\d+)').firstMatch(t)!.group(1)!);
  expect(t.substring(start, start + 4), 'xref');
  final Match head = RegExp(r'xref\s+0 (\d+)\s+').matchAsPrefix(t, start)!;
  final int size = int.parse(head.group(1)!);
  int at = head.end;
  for (int n = 0; n < size; n++) {
    final String row = t.substring(at, at + 20);
    at += 20;
    if (row.contains(' n ')) {
      final int off = int.parse(row.substring(0, 10));
      expect(t.substring(off).startsWith('$n 0 obj'), isTrue, reason: 'object $n');
    }
  }
}

void main() {
  test('downsamples the photo, deflates text streams, keeps the text, drops orphans', () {
    final Uint8List input = samplePdf();
    final PdfCompressResult r = PdfCompressor.compress(input, PdfPreset.medium);
    expect(r.smaller, isTrue);
    expect(r.after, lessThan(input.length * 0.8));
    expect(r.imagesChanged, 1);
    expect(r.streamsChanged, greaterThanOrEqualTo(1));
    expectValidXref(r.bytes);

    final PdfDocumentModel doc = PdfDocumentModel.parse(r.bytes);
    expect(doc.pageCount(), 1);
    expect(doc.objects.containsKey(7), isFalse);
    final PdfObject image = doc.objects[6]!;
    final PdfDict d = image.value as PdfDict;
    expect(d.integer('Width'), 1800);
    expect(d.integer('Height'), 1260);
    expect(img.decodeJpg(image.stream!)!.width, 1800);
    final PdfObject contents = doc.objects[4]!;
    expect((contents.value as PdfDict).name('Filter'), 'FlateDecode');
    final String text = latin1.decode(ZLibCodec().decode(contents.stream!));
    expect(text, content * 20);
    expect(PdfDocumentModel.parse(r.bytes).write().length, r.after);
  });

  test('estimate is shown before the run and orders the presets', () {
    final Uint8List input = samplePdf();
    final PdfAnalysis a = PdfCompressor.analyze(input);
    expect(a.pages, 1);
    expect(a.images, hasLength(1));
    expect(a.plainStreamBytes, greaterThan(0));
    final int low = a.estimate(PdfPreset.low);
    final int med = a.estimate(PdfPreset.medium);
    final int high = a.estimate(PdfPreset.high);
    expect(low, lessThan(med));
    expect(med, lessThanOrEqualTo(high));
    expect(high, lessThanOrEqualTo(input.length));
  });

  test('reads object streams and cross-reference streams', () {
    final ZLibCodec z = ZLibCodec();
    const String inner = '<< /Type /Catalog /Pages 2 0 R >> << /Type /Pages /Kids [3 0 R] /Count 1 >>';
    const String header = '1 0 2 34 ';
    final List<int> objStm = z.encode(latin1.encode('$header$inner'));
    final List<int> pdf = buildPdf(<List<int>>[
      latin1.encode('null'),
      latin1.encode('null'),
      latin1.encode('<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R >>'),
      streamObj('', latin1.encode(content * 10)),
      streamObj('/Type /ObjStm /N 2 /First ${header.length} /Filter /FlateDecode', objStm),
      streamObj('/Type /XRef /Root 1 0 R /Size 6 /W [1 2 1]', <int>[0, 0, 0, 0]),
    ]).toList();
    // The direct "null" placeholders stand in for compressed objects: drop them.
    final String t = latin1.decode(pdf).replaceAll('1 0 obj\nnull\nendobj\n', '').replaceAll('2 0 obj\nnull\nendobj\n', '');
    final PdfCompressResult r = PdfCompressor.compress(Uint8List.fromList(latin1.encode(t)), PdfPreset.low);
    final PdfDocumentModel doc = PdfDocumentModel.parse(r.bytes);
    expect(doc.pageCount(), 1);
    expect((doc.objects[1]!.value as PdfDict).name('Type'), 'Catalog');
    expect(doc.objects.values.where((PdfObject o) => o.value is PdfDict && (o.value as PdfDict).name('Type') == 'ObjStm'),
        isEmpty);
    expectValidXref(r.bytes);
  });

  test('refuses protected files and non-PDFs with a plain message', () {
    final Uint8List locked = buildPdf(<List<int>>[
      latin1.encode('<< /Type /Catalog /Pages 2 0 R >>'),
      latin1.encode('<< /Type /Pages /Kids [] /Count 0 >>'),
      latin1.encode('<< /Filter /Standard /V 2 >>'),
    ], trailerExtra: '/Encrypt 3 0 R ');
    expect(() => PdfCompressor.compress(locked, PdfPreset.low),
        throwsA(isA<PdfCompressError>().having((PdfCompressError e) => e.message, 'message', contains('password'))));
    expect(() => PdfCompressor.analyze(Uint8List.fromList(<int>[1, 2, 3, 4, 5, 6, 7, 8, 9])),
        throwsA(isA<PdfCompressError>()));
  });

  test('PNG predictors are undone', () {
    // Two rows, 2 px, 1 channel: Sub then Up.
    final Uint8List data = Uint8List.fromList(<int>[1, 10, 5, 2, 1, 1]);
    expect(PdfCompressor.unpredictPng(data, 2, 1), <int>[10, 15, 11, 16]);
  });

  testWidgets('pick, see the estimate, compress, then save, share and undo', (WidgetTester tester) async {
    final _FakeFiles files = _FakeFiles();
    final _Sheet sheet = _Sheet();
    const PdfAnalysis analysis = PdfAnalysis(size: 2000000, pages: 3, images: <(int, int)>[(1500000, 3000)], plainStreamBytes: 100000);
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: CompressPdfScreen(
        files: files,
        analyzer: (Uint8List _) async => analysis,
        runner: (Uint8List input, PdfPreset p) async => PdfCompressResult(
          bytes: Uint8List(p == PdfPreset.low ? 400000 : 700000),
          before: 2000000,
          imagesChanged: 1,
          streamsChanged: 2,
        ),
        share: ShareEngine(sheet, MemoryShareTargetStore()),
      ),
    ));
    await tester.tap(find.byKey(const Key('pdf-pick')));
    await tester.pumpAndSettle();
    expect(find.text('scan.pdf'), findsOneWidget);
    expect(find.textContaining('3 pages'), findsOneWidget);
    final String medium = tester.widget<Text>(find.byKey(const Key('pdf-estimate'))).data!;
    expect(medium, startsWith('Estimated: about'));
    await tester.tap(find.byKey(const Key('preset-low')));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.byKey(const Key('pdf-estimate'))).data, isNot(medium));

    await tester.tap(find.byKey(const Key('pdf-run')));
    await tester.pumpAndSettle();
    expect(find.text('1.9 MB → 391 KB'), findsOneWidget);
    expect(find.textContaining('text still selectable'), findsOneWidget);

    await tester.tap(find.byKey(const Key('result-save')));
    await tester.pumpAndSettle();
    expect(files.written.keys.single, 'scan-compressed.pdf');
    await tester.tap(find.byKey(const Key('result-share')));
    await tester.pumpAndSettle();
    expect(sheet.sent.single.files.single.path, '/out/scan-compressed.pdf');
    await tester.tap(find.byKey(const Key('result-undo')));
    await tester.pumpAndSettle();
    expect(files.removed, <String>['/out/scan-compressed.pdf']);

    expect(tester.getSize(find.byKey(const Key('pdf-run'))).height, greaterThanOrEqualTo(44));
    expect(tester.getSize(find.byKey(const Key('pdf-pick'))).height, greaterThanOrEqualTo(44));
  });
}

class _FakeFiles implements PdfFiles {
  final Map<String, Uint8List> written = <String, Uint8List>{};
  final List<String> removed = <String>[];

  @override
  Future<String?> pick() async => '/docs/scan.pdf';

  @override
  Future<Uint8List> read(String path) async => Uint8List(10);

  @override
  Future<String> write(String name, Uint8List bytes) async {
    written[name] = bytes;
    return '/out/$name';
  }

  @override
  Future<void> remove(String path) async => removed.add(path);
}

class _Sheet implements ShareSheet {
  final List<ShareRequest> sent = <ShareRequest>[];

  @override
  Future<ShareOutcome> share(ShareRequest request) async {
    sent.add(request);
    return const ShareOutcome.dismissed();
  }
}
