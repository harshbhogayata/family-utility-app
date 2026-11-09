import 'dart:convert';
import 'dart:typed_data';

import 'package:family_utility_app/app/theme.dart';
import 'package:family_utility_app/engines/pdf/pdf_compressor.dart';
import 'package:family_utility_app/engines/share/share_engine.dart';
import 'package:family_utility_app/tools/compress_pdf/compress_pdf_screen.dart';
import 'package:family_utility_app/tools/pdf_target_size/pdf_target_size_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

Uint8List buildPdf(List<List<int>> bodies) {
  final BytesBuilder b = BytesBuilder();
  b.add(latin1.encode('%PDF-1.4\n'));
  for (int i = 0; i < bodies.length; i++) {
    b.add(latin1.encode('${i + 1} 0 obj\n'));
    b.add(bodies[i]);
    b.add(latin1.encode('\nendobj\n'));
  }
  b.add(latin1.encode('trailer\n<< /Size ${bodies.length + 1} /Root 1 0 R >>\n%%EOF\n'));
  return b.toBytes();
}

List<int> streamObj(String dict, List<int> data) =>
    <int>[...latin1.encode('<< $dict /Length ${data.length} >>\nstream\n'), ...data, ...latin1.encode('\nendstream')];

Uint8List photoPdf() {
  const int w = 1000;
  const int h = 800;
  final img.Image im = img.Image(width: w, height: h);
  int seed = 3;
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      seed = (seed * 1103515245 + 12345) & 0x7fffffff;
      final int n = seed % 50;
      im.setPixelRgb(x, y, (x * 255 ~/ w + n) % 256, (y * 255 ~/ h + n) % 256, (n * 5) % 256);
    }
  }
  final Uint8List jpg = img.encodeJpg(im, quality: 95);
  return buildPdf(<List<int>>[
    latin1.encode('<< /Type /Catalog /Pages 2 0 R >>'),
    latin1.encode('<< /Type /Pages /Kids [3 0 R] /Count 1 >>'),
    latin1.encode('<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R '
        '/Resources << /XObject << /Im1 5 0 R >> >> >>'),
    streamObj('', latin1.encode('BT (Form) Tj ET q 500 0 0 375 50 300 cm /Im1 Do Q')),
    streamObj('/Type /XObject /Subtype /Image /Width $w /Height $h /ColorSpace /DeviceRGB '
        '/BitsPerComponent 8 /Filter /DCTDecode', jpg),
  ]);
}

void main() {
  test('parses typed limits in KB and MB', () {
    expect(parseTarget('500', megabytes: false), 500 * 1024);
    expect(parseTarget('1,5', megabytes: true), 1572864);
    expect(parseTarget('abc', megabytes: false), isNull);
    expect(parseTarget('0', megabytes: true), isNull);
    expect(targetPresets.map(presetLabel), <String>['100 KB', '200 KB', '500 KB', '1 MB', '2 MB']);
  });

  test('walks quality down until the file fits, keeping the mildest that fits', () {
    final Uint8List input = photoPdf();
    final int target = (input.length * 0.25).round();
    final PdfTargetResult r = PdfCompressor.toTarget(input, target);
    expect(r.reached, isTrue);
    expect(r.result.after, lessThanOrEqualTo(target));
    expect(r.message, contains('under the'));
    // The mildest step does not fit, so the search had to go lower.
    expect(PdfCompressor.compressWith(input, PdfSettings.ladder.first).after, greaterThan(target));
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('says clearly when the target is impossible, and when nothing is needed', () {
    final Uint8List input = photoPdf();
    final PdfTargetResult r = PdfCompressor.toTarget(input, 2000);
    expect(r.reached, isFalse);
    expect(r.message, startsWith('Cannot get this PDF under'));
    final PdfTargetResult easy = PdfCompressor.toTarget(input, input.length + 1);
    expect(easy.reached, isTrue);
    expect(easy.result.smaller, isFalse);
    expect(easy.message, contains('Already under'));
  }, timeout: const Timeout(Duration(minutes: 3)));

  testWidgets('preset chips, the run, the message, then save, share and undo', (WidgetTester tester) async {
    final _Files files = _Files();
    final _Sheet sheet = _Sheet();
    int? asked;
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: PdfTargetSizeScreen(
        files: files,
        share: ShareEngine(sheet, MemoryShareTargetStore()),
        runner: (Uint8List input, int target) async {
          asked = target;
          return PdfTargetResult(
            target: target,
            result: PdfCompressResult(bytes: Uint8List(900), before: input.length, imagesChanged: 1, streamsChanged: 0),
            reached: true,
            message: '900 B, under the 1 MB limit.',
          );
        },
      ),
    ));
    await tester.tap(find.byKey(const Key('target-pick')));
    await tester.pumpAndSettle();
    expect(find.textContaining('form.pdf'), findsOneWidget);
    for (final String k in <String>['100KB', '200KB', '500KB', '1MB', '2MB']) {
      expect(find.byKey(Key('target-$k')), findsOneWidget);
      expect(tester.getSize(find.byKey(Key('target-$k'))).height, greaterThanOrEqualTo(44));
    }
    await tester.tap(find.byKey(const Key('target-1MB')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('target-run')));
    await tester.pumpAndSettle();
    expect(asked, 1024 * 1024);
    expect(find.text('900 B, under the 1 MB limit.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('result-save')));
    await tester.pumpAndSettle();
    expect(files.written, <String>['form-1mb.pdf']);
    await tester.tap(find.byKey(const Key('result-share')));
    await tester.pumpAndSettle();
    expect(sheet.sent.single.files.single.path, '/out/form-1mb.pdf');
    await tester.tap(find.byKey(const Key('result-undo')));
    await tester.pumpAndSettle();
    expect(files.removed, <String>['/out/form-1mb.pdf']);

    await tester.enterText(find.byKey(const Key('target-amount')), 'lots');
    await tester.tap(find.byKey(const Key('target-run')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('target-error')), findsOneWidget);
  });
}

class _Files implements PdfFiles {
  final List<String> written = <String>[];
  final List<String> removed = <String>[];

  @override
  Future<String?> pick() async => '/docs/form.pdf';

  @override
  Future<Uint8List> read(String path) async => Uint8List(3000000);

  @override
  Future<String> write(String name, Uint8List bytes) async {
    written.add(name);
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
