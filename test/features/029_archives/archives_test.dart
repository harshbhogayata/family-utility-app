import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:family_utility_app/app/theme.dart';
import 'package:family_utility_app/engines/archive/archive_engine.dart';
import 'package:family_utility_app/engines/archive/zip_codec.dart';
import 'package:family_utility_app/tools/archives/archives_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Made with Python's pyzipper: WinZip AES-256 (AE-2), deflated, password
/// "family123". Proves the reader opens ZIPs other tools lock.
const String pyzipperAes =
    'UEsDBBQAAQBjAOMaaV0AAAAAOAAAAKQBAAAPAAsAbm90ZXMvaGVsbG8udHh0AZkHAAIAQUUDCABS+KFe93ZiFvVmhrHRwxd48ou9IQY+JbucELYFK9lRIJe7ZmTB17RipXj2Vilxe9wsxpnqCEHvTFBLAwQUAAEAYwDjGmldAAAAACEBAAAAAQAABQALAGEuYmluAZkHAAIAQUUDCABizqB7RtgojFQupvqI7IH37k76PKroMH4S49en6KhZVC1K6Sw8GKeYBcyh8KsxKevlRXP6IjVppHzpGEc55G8dgec8LG1Sh+mRRCOOJwCuQeuFsJuPJvWhJ7hfSECMoqwIgDKdxP9p40iZ0JSEtk8hgrguPIECaQQm+EfVF31YcRqJpnoEZTorsxbz2Tj+dPRxjh2Dk+c96xXxKViay9ikosVBrEeUQb9FhOWAONFVtoDt68TxfuADt0VJ7Gc6tyQd+44TIKQgx4/o3X7RI7H+/Ff/ginlfnjYABSsBpvaCuLDhpAf+0PatGq8DhvQ0+Sm1ApRKj6NcooWf2Q4PKzLPeylO8bG7lIfXK66TGqseYWSlK4aNlh/NMVpUwz3+/k7UEsBAhQDFAABAGMA4xppXQAAAAA4AAAApAEAAA8ACwAAAAAAAAAAAIABAAAAAG5vdGVzL2hlbGxvLnR4dAGZBwACAEFFAwgAUEsBAhQDFAABAGMA4xppXQAAAAAhAQAAAAEAAAUACwAAAAAAAAAAAIABcAAAAGEuYmluAZkHAAIAQUUDCABQSwUGAAAAAAIAAgCGAAAAvwEAAAAA';

/// Made with Python's zipfile: a folder, a deflated file and a stored file.
const String pythonPlain =
    'UEsDBBQAAAAIAOMaaV0AAAAAAgAAAAAAAAAFAAAAZG9jcy8DAFBLAwQUAAAACADjGmldo1OEIxQAAACWAAAADwAAAGRvY3MvcmVhZG1lLnR4dCvISczMU6jKLFAoSa0oUSgYHFwAUEsDBBQAAAAAAOMaaV0L+UNWBgAAAAYAAAAHAAAAcmF3LnR4dHN0b3JlZFBLAQIUAxQAAAAIAOMaaV0AAAAAAgAAAAAAAAAFAAAAAAAAAAAAEAD9QQAAAABkb2NzL1BLAQIUAxQAAAAIAOMaaV2jU4QjFAAAAJYAAAAPAAAAAAAAAAAAAACAASUAAABkb2NzL3JlYWRtZS50eHRQSwECFAMUAAAAAADjGmldC/lDVgYAAAAGAAAABwAAAAAAAAAAAAAAgAFmAAAAcmF3LnR4dFBLBQYAAAAAAwADAKUAAACRAAAAAAA=';

class FakePlatform implements ArchivePlatform {
  FakePlatform({this.supported = true});
  final bool supported;
  List<String>? lastEntries;

  @override
  Future<List<ArchiveItem>?> list(String archivePath, {String? password}) async => supported
      ? const <ArchiveItem>[
          ArchiveItem(path: 'photos/a.jpg', size: 2048, isDirectory: false),
          ArchiveItem(path: 'photos/b.jpg', size: 4096, isDirectory: false),
        ]
      : null;

  @override
  Future<List<String>?> extract(String archivePath, List<String> entries, String destination,
      {String? password}) async {
    if (!supported) {
      return null;
    }
    lastEntries = entries;
    return <String>[for (final String e in entries) '$destination/$e'];
  }
}

class FakeChooser implements ArchiveFileChooser {
  @override
  Future<String?> pickArchive() async => '/cache/holiday.rar';

  @override
  Future<List<String>> pickFiles() async => <String>[];
}

/// Opens without touching the disk, so the widget test needs no real IO.
class FakeEngine extends ArchiveEngine {
  FakeEngine(this.fake) : super(platform: fake);
  final FakePlatform fake;

  @override
  Future<OpenedArchive> open(String path) async => OpenedArchive(
        path: path,
        format: ArchiveFormat.rar,
        items: (await fake.list(path))!,
      );

  @override
  Future<List<String>> extract(OpenedArchive archive, Directory destination,
      {Iterable<String> selected = const <String>[], String? password}) async {
    return (await fake.extract(archive.path, selected.toList(), destination.path))!;
  }
}

void main() {
  group('format detection', () {
    test('by magic bytes, not by name', () {
      expect(detectArchiveFormat(const <int>[0x50, 0x4B, 0x03, 0x04, 0]), ArchiveFormat.zip);
      expect(detectArchiveFormat(const <int>[0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0]), ArchiveFormat.rar);
      expect(detectArchiveFormat(const <int>[0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C]), ArchiveFormat.sevenZip);
      expect(detectArchiveFormat(const <int>[0x25, 0x50, 0x44, 0x46]), ArchiveFormat.unknown);
    });

    test('CRC-32 matches the standard check value', () {
      expect(Crc32.of(ascii.encode('123456789')), 0xCBF43926);
    });
  });

  group('ZipReader', () {
    test('browses a plain ZIP and extracts single entries', () {
      final ZipReader r = ZipReader(base64.decode(pythonPlain));
      expect(r.entries.map((ZipEntry e) => e.name), <String>['docs/', 'docs/readme.txt', 'raw.txt']);
      expect(r.entries.first.isDirectory, isTrue);
      expect(r.anyEncrypted, isFalse);
      expect(utf8.decode(r.extract(r.find('raw.txt')!)), 'stored');
      expect(utf8.decode(r.extract(r.find('docs/readme.txt')!)), 'plain zip text ' * 10);
    });

    test('lists an AES ZIP without the password, extracts with it', () {
      final ZipReader r = ZipReader(base64.decode(pyzipperAes));
      expect(r.entries.length, 2);
      expect(r.anyEncrypted, isTrue);
      final ZipEntry hello = r.find('notes/hello.txt')!;
      expect(hello.isAes, isTrue);
      expect(hello.aesStrength, 3);
      expect(hello.size, ('Hello from pyzipper! ' * 20).length);
      expect(utf8.decode(r.extract(hello, password: 'family123')), 'Hello from pyzipper! ' * 20);
      expect(r.extract(r.find('a.bin')!, password: 'family123'), List<int>.generate(256, (int i) => i));
    });

    test('a missing or wrong password is reported, not crashed on', () {
      final ZipReader r = ZipReader(base64.decode(pyzipperAes));
      final ZipEntry hello = r.find('notes/hello.txt')!;
      expect(
        () => r.extract(hello),
        throwsA(isA<ArchiveException>().having((ArchiveException e) => e.needsPassword, 'needsPassword', isTrue)),
      );
      expect(
        () => r.extract(hello, password: 'nope'),
        throwsA(isA<ArchiveException>().having((ArchiveException e) => e.wrongPassword, 'wrongPassword', isTrue)),
      );
    });

    test('rejects a file that is not a ZIP', () {
      expect(() => ZipReader(Uint8List.fromList(utf8.encode('just text'))), throwsA(isA<ArchiveException>()));
    });
  });

  group('ZipWriter', () {
    final List<ZipInput> files = <ZipInput>[
      ZipInput('letters/one.txt', utf8.encode('Dear family, ' * 50)),
      ZipInput('two.bin', List<int>.generate(1000, (int i) => (i * 37) % 251)),
      const ZipInput('empty.txt', <int>[]),
    ];

    test('round-trips without a password', () {
      final ZipReader r = ZipReader(ZipWriter().build(files));
      expect(r.anyEncrypted, isFalse);
      expect(r.entries.length, 3);
      expect(r.find('letters/one.txt')!.method, 8, reason: 'repetitive text is deflated');
      expect(utf8.decode(r.extract(r.find('letters/one.txt')!)), 'Dear family, ' * 50);
      expect(r.extract(r.find('two.bin')!), files[1].bytes);
      expect(r.extract(r.find('empty.txt')!), isEmpty);
    });

    test('with a password every file is AES-256 and needs it back', () {
      final Uint8List zip = ZipWriter().build(files, password: 'S3cret!');
      final ZipReader r = ZipReader(zip);
      expect(r.entries.every((ZipEntry e) => e.encrypted && e.isAes && e.aesStrength == 3), isTrue);
      expect(utf8.decode(r.extract(r.find('letters/one.txt')!, password: 'S3cret!')), 'Dear family, ' * 50);
      expect(r.extract(r.find('two.bin')!, password: 'S3cret!'), files[1].bytes);
      expect(() => r.extract(r.find('two.bin')!, password: 'wrong'), throwsA(isA<ArchiveException>()));
      // The plain text must not appear in the locked archive.
      expect(latin1.decode(zip).contains('Dear family'), isFalse);
    });

    test('a tampered AES entry is caught by its HMAC', () {
      final Uint8List zip = ZipWriter().build(
          <ZipInput>[ZipInput('a.txt', utf8.encode('hello world, hello world'))],
          password: 'pw');
      // Local header (30) + name (5) + extra (11) + salt (16) + verifier (2): first cipher byte.
      zip[30 + 5 + 11 + 16 + 2] ^= 0xFF;
      final ZipReader r = ZipReader(zip);
      expect(() => r.extract(r.entries.single, password: 'pw'), throwsA(isA<ArchiveException>()));
    });
  });

  group('ArchiveEngine', () {
    late Directory tmp;
    setUp(() async => tmp = await Directory.systemTemp.createTemp('archives_test'));
    tearDown(() async => tmp.delete(recursive: true));

    test('creates a locked ZIP from files and extracts only the selected one', () async {
      final File a = await File('${tmp.path}/a.txt').writeAsString('first file');
      final File b = await File('${tmp.path}/b.txt').writeAsString('second file');
      final ArchiveEngine engine = ArchiveEngine(platform: FakePlatform());
      final File zip = await engine.createZip(<String>[a.path, b.path], File('${tmp.path}/out/x.zip'),
          password: 'pw');
      final OpenedArchive opened = await engine.open(zip.path);
      expect(opened.format, ArchiveFormat.zip);
      expect(opened.files.map((ArchiveItem i) => i.path), <String>['a.txt', 'b.txt']);
      expect(opened.anyEncrypted, isTrue);

      final Directory dest = Directory('${tmp.path}/dest');
      await expectLater(
        engine.extract(opened, dest, selected: <String>['b.txt'], password: 'bad'),
        throwsA(isA<ArchiveException>()),
      );
      expect(dest.listSync(), isEmpty, reason: 'a wrong password writes nothing');
      final List<String> written =
          await engine.extract(opened, dest, selected: <String>['b.txt'], password: 'pw');
      expect(written, <String>['${dest.path}/b.txt']);
      expect(await File(written.single).readAsString(), 'second file');
      expect(File('${dest.path}/a.txt').existsSync(), isFalse);
    });

    test('entries that try to escape the folder are skipped', () async {
      expect(safeRelativePath('../../etc/passwd'), isNull);
      expect(safeRelativePath('/abs/ok.txt'), 'abs/ok.txt');
      expect(safeRelativePath('C:\\win.ini'), isNull);
      final Uint8List zip = ZipWriter().build(<ZipInput>[
        ZipInput('../evil.txt', utf8.encode('x')),
        ZipInput('good.txt', utf8.encode('y')),
      ]);
      final File f = await File('${tmp.path}/slip.zip').writeAsBytes(zip);
      final ArchiveEngine engine = ArchiveEngine(platform: FakePlatform());
      final List<String> out = await engine.extract(await engine.open(f.path), Directory('${tmp.path}/d'));
      expect(out, <String>['${tmp.path}/d/good.txt']);
      expect(File('${tmp.path}/evil.txt').existsSync(), isFalse);
    });

    test('RAR and 7Z go to the platform, and say so when it cannot', () async {
      final File rar = await File('${tmp.path}/x.rar')
          .writeAsBytes(<int>[0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x01, 0x00]);
      final OpenedArchive opened = await ArchiveEngine(platform: FakePlatform()).open(rar.path);
      expect(opened.format, ArchiveFormat.rar);
      expect(opened.files.length, 2);
      await expectLater(
        ArchiveEngine(platform: FakePlatform(supported: false)).open(rar.path),
        throwsA(isA<ArchiveException>()),
      );
    });
  });

  testWidgets('browse an archive, untick a file, extract the rest, undo', (WidgetTester tester) async {
    final FakePlatform platform = FakePlatform();
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: ArchivesScreen(
        chooser: FakeChooser(),
        engine: FakeEngine(platform),
        outputFolder: () async => Directory('/nonexistent/archives'),
      ),
    ));
    await tester.tap(find.byKey(const Key('archive-open')));
    await tester.pumpAndSettle();
    expect(find.text('a.jpg'), findsOneWidget);
    expect(find.text('b.jpg'), findsOneWidget);
    expect(find.textContaining('RAR · 2 files inside'), findsOneWidget);

    await tester.tap(find.byKey(const Key('archive-item-photos/a.jpg')));
    await tester.pump();
    expect(find.text('Extract 1 selected'), findsOneWidget);

    final Size extract = tester.getSize(find.byKey(const Key('archive-extract')));
    expect(extract.height, greaterThanOrEqualTo(44));

    await tester.ensureVisible(find.byKey(const Key('archive-extract')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('archive-extract')));
    await tester.pumpAndSettle();
    expect(platform.lastEntries, <String>['photos/b.jpg']);
    expect(find.textContaining('Extracted 1 file'), findsOneWidget);

    expect(find.byKey(const Key('result-share')), findsOneWidget);
    expect(find.byKey(const Key('result-save')), findsOneWidget);
    await tester.tap(find.byKey(const Key('result-undo')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Removed 1 file'), findsOneWidget);
  });
}
