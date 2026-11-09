import 'dart:convert';
import 'dart:typed_data';

import 'package:family_utility_app/app/theme.dart';
import 'package:family_utility_app/engines/security/file_crypt.dart';
import 'package:family_utility_app/engines/share/share_engine.dart';
import 'package:family_utility_app/tools/encrypt_file/encrypt_file_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Made with Python's `cryptography` (PBKDF2-HMAC-SHA256, 1000 rounds,
/// AES-256-GCM): the format is standard, so any implementation can read it.
const String pythonVector =
    'RlVBRU5DAQEAAAPoAAECAwQFBgcICQoLDA0OD2RlZmdoaWprbG1ub2aE8kNOmGnawCcGpP4o01ACHV5t3zU5Kp5YhQSux9hAw4PbDyXP';

Uint8List bytesOf(String s) => Uint8List.fromList(utf8.encode(s));

class FakeFiles implements CryptFiles {
  FakeFiles(this.input);
  CryptInput input;
  final Map<String, Uint8List> written = <String, Uint8List>{};

  @override
  Future<CryptInput?> pick() async => input;

  @override
  Future<String> write(String folder, String name, Uint8List bytes) async {
    written['/$folder/$name'] = bytes;
    return '/$folder/$name';
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

Future<DecryptedFile> fastRunner(CryptJob j) async {
  if (j.lock) {
    return DecryptedFile(FileCrypt.lockedName(j.name), await FileCrypt.encrypt(j.bytes, j.name, j.password, iterations: 1000));
  }
  return FileCrypt.decrypt(j.bytes, j.password);
}

void main() {
  group('FileCrypt', () {
    test('locks and opens any bytes, keeping the name', () async {
      final Uint8List data = Uint8List.fromList(List<int>.generate(5000, (int i) => i % 256));
      final Uint8List locked = await FileCrypt.encrypt(data, 'scan 1.jpg', 'family123', iterations: 1000);
      expect(FileCrypt.isEncrypted(locked), isTrue);
      expect(FileCrypt.isEncrypted(data), isFalse);
      expect(locked.length, FileCrypt.headerLength + 2 + 'scan 1.jpg'.length + data.length + FileCrypt.tagLength);
      expect(latin1.decode(locked.sublist(0, 6)), 'FUAENC');
      final DecryptedFile out = await FileCrypt.decrypt(locked, 'family123');
      expect(out.name, 'scan 1.jpg');
      expect(out.bytes, data);
    });

    test('a fresh salt and nonce every time', () async {
      final Uint8List a = await FileCrypt.encrypt(bytesOf('same'), 'a.txt', 'family123', iterations: 1000);
      final Uint8List b = await FileCrypt.encrypt(bytesOf('same'), 'a.txt', 'family123', iterations: 1000);
      expect(a, isNot(b));
    });

    test('reads a file made by another AES-256-GCM implementation', () async {
      final DecryptedFile out = await FileCrypt.decrypt(base64.decode(pythonVector), 'family123');
      expect(out.name, 'note.txt');
      expect(utf8.decode(out.bytes), 'hello family');
      // And writes the very same bytes with the same salt and nonce.
      final Uint8List again = await FileCrypt.encrypt(bytesOf('hello family'), 'note.txt', 'family123',
          iterations: 1000, salt: List<int>.generate(16, (int i) => i), nonce: List<int>.generate(12, (int i) => 100 + i));
      expect(base64.encode(again), pythonVector);
    });

    test('wrong password, changed header, changed contents', () async {
      final Uint8List locked = await FileCrypt.encrypt(bytesOf('secret'), 'x.txt', 'family123', iterations: 1000);
      await expectLater(FileCrypt.decrypt(locked, 'family124'), throwsA(isA<FileCryptWrongPassword>()));
      final Uint8List header = Uint8List.fromList(locked)..[20] ^= 1;
      await expectLater(FileCrypt.decrypt(header, 'family123'), throwsA(isA<FileCryptWrongPassword>()));
      final Uint8List body = Uint8List.fromList(locked)..[FileCrypt.headerLength + 1] ^= 1;
      await expectLater(FileCrypt.decrypt(body, 'family123'), throwsA(isA<FileCryptWrongPassword>()));
      await expectLater(FileCrypt.decrypt(bytesOf('plain text file, not locked at all'), 'family123'),
          throwsA(isA<FileCryptError>()));
      final Uint8List future = Uint8List.fromList(locked)..[6] = 9;
      await expectLater(FileCrypt.decrypt(future, 'family123'), throwsA(isA<FileCryptError>()));
    });

    test('passwords and names', () async {
      expect(FileCrypt.passwordProblem('abc', 'abc'), contains('at least'));
      expect(FileCrypt.passwordProblem('family123', 'family12'), 'The two passwords differ');
      expect(FileCrypt.passwordProblem('family123', 'family123'), isNull);
      expect(FileCrypt.lockedName('a.pdf'), 'a.pdf.fuaenc');
      await expectLater(FileCrypt.encrypt(bytesOf('x'), 'x', 'abc'), throwsA(isA<FileCryptError>()));
      // A name with folders in it comes back as a plain name.
      final Uint8List locked = await FileCrypt.encrypt(bytesOf('x'), '../../etc/passwd', 'family123', iterations: 1000);
      expect((await FileCrypt.decrypt(locked, 'family123')).name, 'passwd');
    });
  });

  testWidgets('lock a file, share, then open the locked copy', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final SemanticsHandle handle = tester.ensureSemantics();
    final FakeFiles files = FakeFiles(CryptInput('will.pdf', bytesOf('%PDF-1.4 my will')));
    final FakeSheet sheet = FakeSheet();
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: EncryptFileScreen(files: files, runner: fastRunner, share: ShareEngine(sheet, MemoryShareTargetStore())),
    ));
    expect(find.text('Choose a file first'), findsOneWidget);
    await tester.tap(find.byKey(const Key('crypt-pick')));
    await tester.pumpAndSettle();
    expect(find.text('will.pdf'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('crypt-password')), 'abc');
    await tester.pump();
    expect(find.text('Use at least 6 characters'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('crypt-password')), 'family123');
    await tester.enterText(find.byKey(const Key('crypt-again')), 'family124');
    await tester.pump();
    expect(find.text('The two passwords differ'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('crypt-again')), 'family123');
    await tester.pump();
    final Finder run = find.byKey(const Key('crypt-run'));
    expect(tester.getSize(run).height, greaterThanOrEqualTo(44));
    expect(find.text('Lock the file'), findsOneWidget);
    await tester.tap(run);
    await tester.pumpAndSettle();
    expect(find.textContaining('Locked as will.pdf.fuaenc'), findsOneWidget);
    final Uint8List locked = files.written['/locked/will.pdf.fuaenc']!;
    expect(FileCrypt.isEncrypted(locked), isTrue);

    await tester.tap(find.byKey(const Key('result-share')));
    await tester.pumpAndSettle();
    expect(sheet.requests, hasLength(1));

    // Open the locked copy: one password field, wrong then right.
    files.input = CryptInput('will.pdf.fuaenc', locked);
    await tester.tap(find.byKey(const Key('crypt-pick')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('crypt-again')), findsNothing);
    await tester.enterText(find.byKey(const Key('crypt-password')), 'family999');
    await tester.pump();
    await tester.tap(run);
    await tester.pumpAndSettle();
    expect(find.textContaining('Wrong password'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('crypt-password')), 'family123');
    await tester.pump();
    expect(find.text('Open the file'), findsOneWidget);
    await tester.tap(run);
    await tester.pumpAndSettle();
    expect(find.textContaining('Opened will.pdf'), findsOneWidget);
    expect(utf8.decode(files.written['/unlocked/will.pdf']!), '%PDF-1.4 my will');

    await tester.tap(find.byKey(const Key('result-undo')));
    await tester.pumpAndSettle();
    expect(files.written.containsKey('/unlocked/will.pdf'), isFalse);
    handle.dispose();
  });
}
