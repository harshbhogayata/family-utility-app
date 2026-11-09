import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:family_utility_app/app/theme.dart';
import 'package:family_utility_app/engines/pdf/pdf_compressor.dart';
import 'package:family_utility_app/engines/pdf/pdf_protector.dart';
import 'package:family_utility_app/engines/pdf/pdf_unlocker.dart';
import 'package:family_utility_app/engines/share/share_engine.dart';
import 'package:family_utility_app/tools/unlock_pdf/unlock_pdf_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'qpdf_fixtures.dart';

Uint8List fixture(String name) => base64.decode(qpdfFixtures[name]!);

/// A classic PDF from object bodies, numbered from 1, with a real xref.
Uint8List classicPdf(List<String> bodies, {String extraTrailer = ''}) {
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
  b.write('trailer\n<< /Size ${bodies.length + 1} /Root 1 0 R$extraTrailer >>\nstartxref\n$xref\n%%EOF\n');
  return Uint8List.fromList(latin1.encode(b.toString()));
}

const String content = 'BT /F1 12 Tf 72 700 Td (Hello secret world) Tj ET';

Uint8List samplePdf() => classicPdf(<String>[
      '<< /Type /Catalog /Pages 2 0 R >>',
      '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
      '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R >>',
      '<< /Length ${content.length} >>\nstream\n$content\nendstream',
      '<< /Title (Private \\(family\\) notes) >>',
    ], extraTrailer: ' /Info 5 0 R');

/// The document title of an unencrypted PDF.
String titleOf(Uint8List pdf) {
  final PdfDocumentModel doc = PdfDocumentModel.parse(pdf);
  final Object? info = doc.resolve(doc.trailer['Info']);
  final Object? title = info is PdfDict ? info['Title'] : null;
  return title is PdfString ? latin1.decode(PdfProtector.stringBytes(title.raw)) : '';
}

class FakeFiles implements UnlockFiles {
  FakeFiles(this.input);
  final UnlockInput input;
  final Map<String, Uint8List> written = <String, Uint8List>{};

  @override
  Future<UnlockInput?> pick() async => input;

  @override
  Future<String> write(String name, Uint8List bytes) async {
    written['/unlocked/$name'] = bytes;
    return '/unlocked/$name';
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
    test('RC4 and MD5 match their published test vectors', () {
      expect(PdfUnlocker.rc4(ascii.encode('Key'), ascii.encode('Plaintext')),
          <int>[0xBB, 0xF3, 0x16, 0xE8, 0xD9, 0x40, 0xAF, 0x0A, 0xD3]);
      final String md5 = PdfUnlocker.md5(ascii.encode('abc')).map((int b) => b.toRadixString(16).padLeft(2, '0')).join();
      expect(md5, '900150983cd24fb0d6963f7d28e17f72');
      expect(PdfUnlocker.padPassword(<int>[]), PdfUnlocker.pad);
      expect(PdfUnlocker.padPassword(ascii.encode('ab')).sublist(0, 4), <int>[0x61, 0x62, 0x28, 0xBF]);
    });

    const Map<String, String> methods = <String, String>{
      'r2': 'RC4 40-bit',
      'r3': 'RC4 128-bit',
      'r4': 'AES-128',
      'r4rc4': 'RC4 128-bit',
      'r6': 'AES-256',
    };

    for (final MapEntry<String, String> m in methods.entries) {
      test('the user password removes ${m.value} (${m.key}, made by qpdf)', () {
        final Uint8List locked = fixture(m.key);
        expect(PdfUnlocker.isProtected(locked), isTrue);
        final PdfUnlockResult r = PdfUnlocker.unlock(locked, 'SURE1990');
        expect(r.method, m.value);
        expect(r.pages, 1);
        final String s = latin1.decode(r.bytes);
        expect(s, isNot(contains('/Encrypt')));
        expect(PdfUnlocker.isProtected(r.bytes), isFalse);
        expect(s, contains('Hello Aadhaar 1990'));
        expect(titleOf(r.bytes), 'Family statement (private)');
      });

      test('the owner password opens ${m.key} too, a wrong one does not', () {
        final PdfUnlockResult r = PdfUnlocker.unlock(fixture(m.key), 'own-er');
        expect(latin1.decode(r.bytes), contains('Hello Aadhaar 1990'));
        expect(() => PdfUnlocker.unlock(fixture(m.key), 'sure1990'), throwsA(isA<PdfWrongPasswordError>()));
        expect(() => PdfUnlocker.unlock(fixture(m.key), ''), throwsA(isA<PdfWrongPasswordError>()));
      });
    }

    test('undoes the app\'s own AES-256 protection', () {
      final PdfProtectResult p =
          PdfProtector.protect(samplePdf(), const PdfProtectOptions(password: 'Tulip-House-27'), random: Random(7));
      expect(() => PdfUnlocker.unlock(p.bytes, 'tulip-house-27'), throwsA(isA<PdfWrongPasswordError>()));
      final PdfUnlockResult r = PdfUnlocker.unlock(p.bytes, 'Tulip-House-27');
      expect(r.method, 'AES-256');
      expect(latin1.decode(r.bytes), contains(content));
      expect(titleOf(r.bytes), 'Private (family) notes');
      // The copy can be protected again, so it is a normal PDF.
      expect(PdfProtector.protect(r.bytes, const PdfProtectOptions(password: 'x')).bytes, isNotEmpty);
    });

    test('a PDF without a password is refused with a clear message', () {
      expect(PdfUnlocker.isProtected(samplePdf()), isFalse);
      expect(
        () => PdfUnlocker.unlock(samplePdf(), 'anything'),
        throwsA(isA<PdfCompressError>().having((PdfCompressError e) => e.message, 'message', contains('no password'))),
      );
    });

    test('other tools still refuse a locked PDF', () {
      expect(() => PdfDocumentModel.parse(fixture('r4')), throwsA(isA<PdfCompressError>()));
    });

    test('Aadhaar format and hint text', () {
      expect(PdfUnlocker.aadhaarPassword('Suresh Kumar', 1990), 'SURE1990');
      expect(PdfUnlocker.aadhaarPassword('s. rao', 2001), 'SRAO2001');
      expect(PdfUnlocker.aadhaarPassword('Al', 1985), 'AL1985');
      final PdfPasswordHint aadhaar = PdfUnlocker.hints.first;
      expect(aadhaar.title, contains('Aadhaar'));
      expect(aadhaar.format, contains('First 4 letters'));
      expect(aadhaar.format, contains('birth year'));
    });
  });

  testWidgets('wrong password, Aadhaar helper, unlock, share and undo', (WidgetTester tester) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    final FakeFiles files = FakeFiles(UnlockInput('statement.pdf', fixture('r6')));
    final FakeSheet sheet = FakeSheet();
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: UnlockPdfScreen(
        files: files,
        runner: (UnlockJob j) async => PdfUnlocker.unlock(j.bytes, j.password),
        share: ShareEngine(sheet, MemoryShareTargetStore()),
      ),
    ));
    expect(find.textContaining('First 4 letters'), findsOneWidget);
    await tester.tap(find.byKey(const Key('unlock-pick')));
    await tester.pumpAndSettle();
    expect(find.text('statement.pdf'), findsOneWidget);
    expect(find.text('Type its password'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('unlock-password')), 'sure1990');
    await tester.pump();
    final Finder run = find.byKey(const Key('unlock-run'));
    expect(tester.getSize(run).height, greaterThanOrEqualTo(44));
    await tester.tap(run);
    await tester.pumpAndSettle();
    expect(find.text('Wrong password'), findsOneWidget);
    expect(files.written, isEmpty);

    final Finder name = find.byKey(const Key('unlock-aadhaar-name'));
    await tester.ensureVisible(name);
    await tester.enterText(name, 'Suresh Kumar');
    await tester.enterText(find.byKey(const Key('unlock-aadhaar-year')), '1990');
    await tester.pump();
    final Finder use = find.byKey(const Key('unlock-aadhaar-use'));
    await tester.ensureVisible(use);
    expect(find.text('Use SURE1990'), findsOneWidget);
    expect(tester.getSize(use).height, greaterThanOrEqualTo(44));
    await tester.tap(use);
    await tester.pump();
    expect(tester.widget<TextField>(find.byKey(const Key('unlock-password'))).controller!.text, 'SURE1990');

    await tester.ensureVisible(run);
    await tester.tap(run);
    await tester.pumpAndSettle();
    expect(files.written.keys.single, '/unlocked/statement unlocked.pdf');
    expect(PdfUnlocker.isProtected(files.written.values.single), isFalse);
    expect(find.textContaining('AES-256'), findsOneWidget);
    expect(tester.widget<TextField>(find.byKey(const Key('unlock-password'))).controller!.text, isEmpty);

    await tester.tap(find.byKey(const Key('result-share')));
    await tester.pumpAndSettle();
    expect(sheet.requests.single.files.single.path, '/unlocked/statement unlocked.pdf');

    await tester.tap(find.byKey(const Key('result-undo')));
    await tester.pumpAndSettle();
    expect(files.written, isEmpty);
    expect(find.textContaining('still has its password'), findsOneWidget);
    handle.dispose();
  });
}
