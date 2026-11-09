import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:family_utility_app/app/theme.dart';
import 'package:family_utility_app/engines/pdf/pdf_compressor.dart';
import 'package:family_utility_app/engines/pdf/pdf_protector.dart';
import 'package:family_utility_app/engines/share/share_engine.dart';
import 'package:family_utility_app/tools/protect_pdf/protect_pdf_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/export.dart';

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
      '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R '
          '/Resources << /Font << /F1 5 0 R >> >> >>',
      '<< /Length ${content.length} >>\nstream\n$content\nendstream',
      '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
      '<< /Title (Private \\(family\\) notes) >>',
    ], extraTrailer: ' /Info 6 0 R');

/// Every stream body in [pdf], as written by the app's writer.
List<Uint8List> streams(Uint8List pdf) {
  final String s = latin1.decode(pdf);
  return RegExp(r'\nstream\n([\s\S]*?)\nendstream')
      .allMatches(s)
      .map((RegExpMatch m) => Uint8List.fromList(latin1.encode(m.group(1)!)))
      .toList();
}

Uint8List hexOf(Uint8List pdf, String key) {
  final RegExpMatch m = RegExp('/$key <([0-9a-f]+)>').firstMatch(latin1.decode(pdf))!;
  return PdfProtector.stringBytes(Uint8List.fromList(latin1.encode('<${m.group(1)}>')));
}

class FakeFiles implements ProtectFiles {
  FakeFiles(this.input);
  final ProtectInput input;
  final Map<String, Uint8List> written = <String, Uint8List>{};

  @override
  Future<ProtectInput?> pick() async => input;

  @override
  Future<String> write(String name, Uint8List bytes) async {
    written['/protected/$name'] = bytes;
    return '/protected/$name';
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
    test('writes an AES-256 (V5 R6 AESV3) handler and hides the content', () {
      final PdfProtectResult r =
          PdfProtector.protect(samplePdf(), const PdfProtectOptions(password: 'Tulip-House-27'), random: Random(1));
      final String s = latin1.decode(r.bytes);
      expect(s, contains('/Filter /Standard'));
      expect(s, contains('/V 5'));
      expect(s, contains('/R 6'));
      expect(s, contains('/CFM /AESV3'));
      expect(s, contains('/Encrypt '));
      expect(s, isNot(contains('Hello secret world')));
      expect(s, isNot(contains('family')));
      expect(s, isNot(contains('Tulip')));
      expect(hexOf(r.bytes, 'U'), hasLength(48));
      expect(hexOf(r.bytes, 'O'), hasLength(48));
      expect(hexOf(r.bytes, 'UE'), hasLength(32));
      expect(hexOf(r.bytes, 'OE'), hasLength(32));
    });

    test('the password opens it, a wrong one does not, and the content decrypts', () {
      final PdfProtectResult r =
          PdfProtector.protect(samplePdf(), const PdfProtectOptions(password: 'Tulip-House-27'), random: Random(2));
      expect(PdfProtector.unlock(r.bytes, 'tulip-house-27'), isNull);
      final Uint8List key = PdfProtector.unlock(r.bytes, 'Tulip-House-27')!;
      expect(key, hasLength(32));
      final List<String> plain = <String>[
        for (final Uint8List st in streams(r.bytes)) latin1.decode(PdfProtector.decryptAes(key, st) ?? Uint8List(0)),
      ];
      expect(plain, contains(content));
    });

    test('Perms carries P and the adb marker under the file key', () {
      final PdfProtectResult r = PdfProtector.protect(
          samplePdf(), const PdfProtectOptions(password: 'pw', allowPrint: false), random: Random(3));
      final Uint8List key = PdfProtector.unlock(r.bytes, 'pw')!;
      final Uint8List perms = hexOf(r.bytes, 'Perms');
      final AESEngine ecb = AESEngine()..init(false, KeyParameter(key));
      final Uint8List out = Uint8List(16);
      ecb.processBlock(perms, 0, out, 0);
      expect(ascii.decode(out.sublist(9, 12)), 'adb');
      expect(out[8], 0x54); // 'T': metadata is encrypted too
      final int p = (out[0] | out[1] << 8 | out[2] << 16 | out[3] << 24).toSigned(32);
      expect(p, r.permissions);
      expect(latin1.decode(r.bytes), contains('/P ${r.permissions}'));
    });

    test('print and copy restrictions clear the right bits, accessibility stays', () {
      final int all = PdfProtector.permissions(allowPrint: true, allowCopy: true);
      final int noPrint = PdfProtector.permissions(allowPrint: false, allowCopy: true);
      final int noCopy = PdfProtector.permissions(allowPrint: true, allowCopy: false);
      bool bit(int p, int n) => p & (1 << (n - 1)) != 0;
      expect(all, isNegative);
      expect(bit(all, 3) && bit(all, 12) && bit(all, 5), isTrue);
      expect(bit(noPrint, 3) || bit(noPrint, 12), isFalse);
      expect(bit(noCopy, 5), isFalse);
      for (final int p in <int>[all, noPrint, noCopy]) {
        expect(bit(p, 1) || bit(p, 2), isFalse);
        expect(bit(p, 7) && bit(p, 8) && bit(p, 10) && bit(p, 32), isTrue);
      }
    });

    test('an already protected PDF and an empty password are refused', () {
      final PdfProtectResult r = PdfProtector.protect(samplePdf(), const PdfProtectOptions(password: 'x'), random: Random(4));
      expect(() => PdfProtector.protect(r.bytes, const PdfProtectOptions(password: 'y')), throwsA(isA<PdfCompressError>()));
      expect(() => PdfProtector.protect(samplePdf(), const PdfProtectOptions(password: '')), throwsA(isA<PdfCompressError>()));
    });

    test('AES round trip and literal string escapes', () {
      final Uint8List key = Uint8List.fromList(List<int>.generate(32, (int i) => i));
      final Uint8List iv = Uint8List(16);
      for (final int n in <int>[0, 1, 15, 16, 17, 100]) {
        final Uint8List data = Uint8List.fromList(List<int>.generate(n, (int i) => i * 7 & 0xFF));
        final Uint8List enc = PdfProtector.encryptAes(key, data, iv);
        expect(enc.length % 16, 0);
        expect(PdfProtector.decryptAes(key, enc), data);
      }
      expect(latin1.decode(PdfProtector.stringBytes(Uint8List.fromList(latin1.encode(r'(a\(b\)\n\101 (x))')))), 'a(b)\nA (x)');
      expect(PdfProtector.stringBytes(Uint8List.fromList(latin1.encode('<48 6>'))), <int>[0x48, 0x60]);
    });

    test('the R6 hash is 32 bytes and repeatable', () {
      final Uint8List pw = Uint8List.fromList(utf8.encode('pässword'));
      final Uint8List salt = Uint8List.fromList(<int>[1, 2, 3, 4, 5, 6, 7, 8]);
      final Uint8List a = PdfProtector.hash(pw, salt, Uint8List(0));
      expect(a, hasLength(32));
      expect(PdfProtector.hash(pw, salt, Uint8List(0)), a);
      expect(PdfProtector.hash(pw, salt, Uint8List(48)), isNot(a));
    });
  });

  test('strength meter', () {
    expect(PasswordStrength.of(''), PasswordStrength.empty);
    expect(PasswordStrength.of('abc'), PasswordStrength.weak);
    expect(PasswordStrength.of('password'), PasswordStrength.weak);
    expect(PasswordStrength.of('aaaaaaaaaaaa'), PasswordStrength.weak);
    expect(PasswordStrength.of('sunflower72'), PasswordStrength.fair);
    expect(PasswordStrength.of('Sunflower7'), PasswordStrength.good);
    expect(PasswordStrength.of('Sunflower-Garden-42'), PasswordStrength.strong);
  });

  testWidgets('protects, clears the password, shares, and undo removes the copy', (WidgetTester tester) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    final FakeFiles files = FakeFiles(ProtectInput('notes.pdf', samplePdf()));
    final FakeSheet sheet = FakeSheet();
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: ProtectPdfScreen(
        files: files,
        runner: (ProtectJob j) async => PdfProtector.protect(j.bytes, j.options, random: Random(5)),
        share: ShareEngine(sheet, MemoryShareTargetStore()),
      ),
    ));
    await tester.tap(find.byKey(const Key('protect-pick')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('protect-password')), 'abc');
    await tester.pump();
    expect(find.bySemanticsLabel('Password strength: Weak'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('protect-password')), 'Sunflower-Garden-42');
    await tester.enterText(find.byKey(const Key('protect-confirm')), 'Sunflower-Garden-4');
    await tester.pump();
    expect(find.text('Strong'), findsOneWidget);
    expect(find.text('The two passwords do not match'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(const Key('protect-run'))).onPressed, isNull);

    await tester.enterText(find.byKey(const Key('protect-confirm')), 'Sunflower-Garden-42');
    await tester.tap(find.byKey(const Key('protect-copy')));
    await tester.pump();
    final Finder run = find.byKey(const Key('protect-run'));
    expect(tester.getSize(run).height, greaterThanOrEqualTo(44));
    await tester.ensureVisible(run);
    await tester.tap(run);
    await tester.pumpAndSettle();

    expect(files.written.keys.single, '/protected/notes protected.pdf');
    expect(PdfProtector.unlock(files.written.values.single, 'Sunflower-Garden-42'), isNotNull);
    expect(find.textContaining('no copying'), findsOneWidget);
    expect(tester.widget<TextField>(find.byKey(const Key('protect-password'))).controller!.text, isEmpty);

    await tester.tap(find.byKey(const Key('result-share')));
    await tester.pumpAndSettle();
    expect(sheet.requests.single.files.single.path, '/protected/notes protected.pdf');

    await tester.tap(find.byKey(const Key('result-undo')));
    await tester.pumpAndSettle();
    expect(files.written, isEmpty);
    handle.dispose();
  });
}
