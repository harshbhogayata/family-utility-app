import 'dart:convert';
import 'dart:typed_data';

import 'package:family_utility_app/app/theme.dart';
import 'package:family_utility_app/engines/convert/word_document.dart';
import 'package:family_utility_app/engines/convert/word_pdf_renderer.dart';
import 'package:family_utility_app/engines/pdf/pdf_compressor.dart';
import 'package:family_utility_app/engines/pdf/pdf_merger.dart';
import 'package:family_utility_app/tools/merge_pdf/merge_pdf_screen.dart';
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

/// Two pages that inherit a landscape MediaBox from the page tree, with
/// two bookmarks.
Uint8List withBookmarks() {
  const String content = 'BT /F1 12 Tf 72 500 Td (Bookmarked) Tj ET';
  return classicPdf(<String>[
    '<< /Type /Catalog /Pages 2 0 R /Outlines 6 0 R >>',
    '<< /Type /Pages /Kids [3 0 R 4 0 R] /Count 2 /MediaBox [0 0 842 595] '
        '/Resources << /Font << /F1 9 0 R >> >> >>',
    '<< /Type /Page /Parent 2 0 R /Contents 5 0 R >>',
    '<< /Type /Page /Parent 2 0 R /Contents 5 0 R /Rotate 90 >>',
    '<< /Length ${content.length} >>\nstream\n$content\nendstream',
    '<< /Type /Outlines /First 7 0 R /Last 8 0 R /Count 2 >>',
    '<< /Title (Chapter one) /Parent 6 0 R /Next 8 0 R /Dest [3 0 R /Fit] >>',
    '<< /Title (Chapter two) /Parent 6 0 R /Prev 7 0 R /Dest [4 0 R /Fit] >>',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
  ]);
}

Future<Uint8List> letterDoc(String text) => WordPdfRenderer().render(
      WordDocument(<DocBlock>[DocParagraph(<DocRun>[DocRun(text)])]),
      options: const WordPdfOptions(pageWidth: 612, pageHeight: 792),
    );

List<PdfDict> pagesOf(PdfDocumentModel d) {
  final PdfDict root = d.resolve(d.trailer['Root'])! as PdfDict;
  final PdfDict pages = d.resolve(root['Pages'])! as PdfDict;
  return <PdfDict>[for (final Object k in (pages['Kids']! as PdfArray).items) d.resolve(k)! as PdfDict];
}

String box(PdfDocumentModel d, PdfDict page) =>
    (d.resolve(page['MediaBox'])! as PdfArray).items.map((Object o) => (o as PdfNum).value.round()).join(' ');

String title(PdfDocumentModel d, PdfDict item) => latin1.decode((d.resolve(item['Title'])! as PdfString).raw);

class FakeFiles implements MergeFiles {
  FakeFiles(this.inputs);
  final List<MergeInput> inputs;
  final Map<String, Uint8List> written = <String, Uint8List>{};

  @override
  Future<List<MergeInput>> pick() async => inputs;

  @override
  Future<String> write(String name, Uint8List bytes) async {
    written['/merged/$name'] = bytes;
    return '/merged/$name';
  }

  @override
  Future<void> remove(String path) async => written.remove(path);
}

Future<PdfMergeResult> direct(List<MergeInput> inputs) async => PdfMerger.merge(inputs);

void main() {
  test('merges in order, keeping each page size, rotation and the bookmarks', () async {
    final Uint8List a = await letterDoc('First file');
    final Uint8List b = withBookmarks();
    final PdfMergeResult r = PdfMerger.merge(<MergeInput>[
      MergeInput('letter.pdf', a),
      MergeInput('report.pdf', b),
      MergeInput('again.pdf', a),
    ]);
    expect(r.pageCount, 4);
    final PdfDocumentModel m = PdfDocumentModel.parse(r.bytes);
    expect(m.pageCount(), 4);
    final List<PdfDict> pages = pagesOf(m);
    expect(pages.map((PdfDict p) => box(m, p)), <String>['0 0 612 792', '0 0 842 595', '0 0 842 595', '0 0 612 792']);
    expect(pages[2].integer('Rotate'), 90);
    expect(pages[1]['Resources'], isNotNull, reason: 'inherited resources are copied onto the page');

    final PdfDict root = m.resolve(m.trailer['Root'])! as PdfDict;
    final PdfDict outlines = m.resolve(root['Outlines'])! as PdfDict;
    final PdfDict f1 = m.resolve(outlines['First'])! as PdfDict;
    final PdfDict f2 = m.resolve(f1['Next'])! as PdfDict;
    final PdfDict f3 = m.resolve(f2['Next'])! as PdfDict;
    expect(<String>[title(m, f1), title(m, f2), title(m, f3)], <String>['(letter.pdf)', '(report.pdf)', '(again.pdf)']);
    final PdfDict ch1 = m.resolve(f2['First'])! as PdfDict;
    final PdfDict ch2 = m.resolve(ch1['Next'])! as PdfDict;
    expect(title(m, ch1), '(Chapter one)');
    expect(title(m, ch2), '(Chapter two)');
    // The bookmark still lands on the right page.
    final PdfRef dest = (m.resolve(ch2['Dest'])! as PdfArray).items.first as PdfRef;
    expect(identical(m.resolve(dest), pages[2]), isTrue);
    expect(latin1.decode(r.bytes), contains('(First file) Tj'));
    expect(latin1.decode(r.bytes), contains('(Bookmarked) Tj'));
  });

  test('50 MB of input merges in one pass', () {
    // Each file: one page whose picture stream is 25 MB.
    Uint8List big(int seed) {
      const int n = 25 * 1024 * 1024;
      final Uint8List data = Uint8List(n);
      for (int i = 0; i < n; i += 4096) {
        data[i] = (i ~/ 4096 + seed) & 255;
      }
      final Uint8List head = Uint8List.fromList(latin1.encode('%PDF-1.4\n'
          '1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n'
          '2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n'
          '3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << /XObject << /Im0 4 0 R >> >> >>\nendobj\n'
          '4 0 obj\n<< /Type /XObject /Subtype /Image /Width 4096 /Height 6400 /ColorSpace /DeviceGray '
          '/BitsPerComponent 8 /Length $n >>\nstream\n'));
      final Uint8List tail = Uint8List.fromList(latin1.encode('\nendstream\nendobj\ntrailer\n<< /Root 1 0 R >>\n%%EOF\n'));
      return (BytesBuilder(copy: false)
            ..add(head)
            ..add(data)
            ..add(tail))
          .takeBytes();
    }

    final PdfMergeResult r = PdfMerger.merge(<MergeInput>[MergeInput('a.pdf', big(1)), MergeInput('b.pdf', big(2))]);
    expect(r.pageCount, 2);
    expect(r.bytes.length, greaterThan(50 * 1024 * 1024));
    expect(PdfDocumentModel.parse(r.bytes).pageCount(), 2);
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('one file, or a broken file, is refused plainly', () {
    expect(() => PdfMerger.merge(<MergeInput>[MergeInput('a.pdf', withBookmarks())]), throwsA(isA<PdfCompressError>()));
    expect(
      () => PdfMerger.merge(<MergeInput>[MergeInput('a.pdf', withBookmarks()), MergeInput('b.pdf', Uint8List(10))]),
      throwsA(predicate((Object e) => e is PdfCompressError && e.message.startsWith('b.pdf'))),
    );
    expect(latin1.decode(PdfMerger.textString('Café').raw), '<FEFF00430061006600e9>');
  });

  testWidgets('pick, reorder, merge, open in the viewer, undo', (WidgetTester tester) async {
    final FakeFiles files = FakeFiles(<MergeInput>[
      MergeInput('one.pdf', withBookmarks()),
      MergeInput('two.pdf', withBookmarks()),
    ]);
    String? opened;
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: MergePdfScreen(files: files, runner: direct, openViewer: (BuildContext c, String p) => opened = p),
    ));
    await tester.tap(find.byKey(const Key('merge-add')));
    await tester.pumpAndSettle();
    expect(find.text('Merge 2 PDFs'), findsOneWidget);
    await tester.tap(find.byKey(const Key('merge-down-0')));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.byKey(const Key('merge-name-0'))).data, 'two.pdf');
    expect(tester.getSize(find.byKey(const Key('merge-down-1'))).height, greaterThanOrEqualTo(44));

    await tester.tap(find.byKey(const Key('merge-run')));
    await tester.pumpAndSettle();
    expect(files.written.keys, <String>['/merged/two merged.pdf']);
    expect(find.text('Merged 2 files into 4 pages'), findsOneWidget);
    await tester.tap(find.byKey(const Key('merge-open')));
    expect(opened, '/merged/two merged.pdf');

    await tester.tap(find.byKey(const Key('result-undo')));
    await tester.pumpAndSettle();
    expect(files.written, isEmpty);
  });
}
