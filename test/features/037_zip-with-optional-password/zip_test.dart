import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:family_utility_app/app/theme.dart';
import 'package:family_utility_app/engines/archive/zip_bundle.dart';
import 'package:family_utility_app/engines/archive/zip_codec.dart';
import 'package:family_utility_app/tools/zip/zip_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeFiles implements ZipFiles {
  FakeFiles(this.inputs);
  final Map<String, Uint8List> inputs;
  final Map<String, Uint8List> written = <String, Uint8List>{};

  @override
  Future<List<String>> pick() async => <String>['/phone/notes.txt', '/phone/b/notes.txt'];

  @override
  Future<Uint8List> read(String path) async => inputs[path]!;

  @override
  Future<String> write(String name, Uint8List bytes) async {
    final String p = '/out/$name';
    written[p] = bytes;
    return p;
  }

  @override
  Future<void> remove(String path) async => written.remove(path);
}

class FakeResults implements ResultLibrary {
  @override
  Future<List<String>> list() async => <String>['/app/compressed/photo.jpg'];
}

Uint8List bytesOf(String s) => Uint8List.fromList(utf8.encode(s));

final Map<String, Uint8List> inputs = <String, Uint8List>{
  '/phone/notes.txt': bytesOf('first notes'),
  '/phone/b/notes.txt': bytesOf('second notes'),
  '/app/compressed/photo.jpg': bytesOf('jpeg bytes'),
};

void main() {
  Future<Uint8List> read(String p) async => inputs[p]!;
  final List<BundleItem> items = <BundleItem>[
    const BundleItem('/phone/notes.txt'),
    const BundleItem('/phone/b/notes.txt'),
    const BundleItem('/app/compressed/photo.jpg', fromResults: true),
  ];

  test('bundles several files; same names get (2)', () async {
    final Uint8List zip = await ZipBundler().build(items, read);
    final ZipReader r = ZipReader(zip);
    expect(r.entries.map((ZipEntry e) => e.name), <String>['notes.txt', 'notes (2).txt', 'photo.jpg']);
    expect(r.anyEncrypted, isFalse);
    expect(utf8.decode(r.extract(r.find('notes (2).txt')!)), 'second notes');
  });

  test('a password locks every entry with AES', () async {
    final Uint8List zip = await ZipBundler().build(items, read, password: 'garden42');
    final ZipReader r = ZipReader(zip);
    expect(r.entries.every((ZipEntry e) => e.encrypted), isTrue);
    expect(utf8.decode(r.extract(r.find('photo.jpg')!, password: 'garden42')), 'jpeg bytes');
    expect(() => r.extract(r.find('photo.jpg')!, password: 'wrong'), throwsA(isA<ArchiveException>()));
  });

  test('password, name and empty checks', () async {
    expect(ZipBundler.checkPassword('abc', 'abc'), isNotNull);
    expect(ZipBundler.checkPassword('abcd', 'abce'), isNotNull);
    expect(ZipBundler.checkPassword('abcd', 'abcd'), isNull);
    expect(ZipBundler.archiveName('', items), 'Files.zip');
    expect(ZipBundler.archiveName('', items.sublist(2)), 'photo.zip');
    expect(ZipBundler.archiveName('Tax/2026.zip', items), 'Tax_2026.zip');
    expect(() => ZipBundler().build(<BundleItem>[], read), throwsA(isA<ZipBundleError>()));
  });

  test('result library lists app results but not signatures', () async {
    final Directory tmp = await Directory.systemTemp.createTemp('zip037');
    await File('${tmp.path}/compressed/a.jpg').create(recursive: true);
    await File('${tmp.path}/signatures/me.png').create(recursive: true);
    await File('${tmp.path}/files.json').create(recursive: true);
    final List<String> got = await DirectoryResultLibrary(() async => tmp).list();
    expect(got.map((String p) => p.substring(p.lastIndexOf('/') + 1)), <String>['a.jpg']);
    await tmp.delete(recursive: true);
  });

  testWidgets('pick from phone and results, lock, make, undo', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final FakeFiles files = FakeFiles(inputs);
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: ZipScreen(files: files, results: FakeResults()),
    ));
    await tester.tap(find.byKey(const Key('zip-pick')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('zip-results')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('zip-result-/app/compressed/photo.jpg')));
    await tester.pumpAndSettle();
    expect(find.text('3 chosen'), findsOneWidget);
    expect(tester.getSize(find.byKey(const Key('zip-run'))).height, greaterThanOrEqualTo(44));

    await tester.tap(find.byKey(const Key('zip-lock')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('zip-password')), 'garden42');
    await tester.enterText(find.byKey(const Key('zip-confirm')), 'garden4');
    await tester.tap(find.byKey(const Key('zip-run')));
    await tester.pumpAndSettle();
    expect(find.text('The two passwords do not match'), findsOneWidget);
    expect(files.written, isEmpty);

    await tester.enterText(find.byKey(const Key('zip-confirm')), 'garden42');
    await tester.enterText(find.byKey(const Key('zip-name')), 'Bundle');
    await tester.tap(find.byKey(const Key('zip-run')));
    await tester.pumpAndSettle();
    expect(files.written.keys, <String>['/out/Bundle.zip']);
    expect(find.text('Made Bundle.zip with 3 files, locked with AES-256'), findsOneWidget);
    expect(ZipReader(files.written['/out/Bundle.zip']!).anyEncrypted, isTrue);

    await tester.tap(find.byKey(const Key('result-undo')));
    await tester.pumpAndSettle();
    expect(files.written, isEmpty);
  });
}
