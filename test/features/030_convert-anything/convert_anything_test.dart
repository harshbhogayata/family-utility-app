import 'dart:convert';
import 'dart:typed_data';

import 'package:family_utility_app/app/theme.dart';
import 'package:family_utility_app/engines/archive/zip_codec.dart';
import 'package:family_utility_app/engines/convert/convert_registry.dart';
import 'package:family_utility_app/engines/convert/file_kind.dart';
import 'package:family_utility_app/tools/convert_anything/convert_anything_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

Uint8List smallPng() {
  final img.Image im = img.Image(width: 6, height: 4);
  img.fill(im, color: img.ColorRgb8(200, 30, 60));
  return img.encodePng(im);
}

class FakeChooser implements ConvertFileChooser {
  FakeChooser(this.input);
  final ConvertInput input;

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

/// A converter a later feature might add.
class ShoutConverter extends Converter {
  const ShoutConverter();
  @override
  String get id => 'shout';
  @override
  String get label => 'Shouted text';
  @override
  FileKind get target => FileKind.text;
  @override
  bool accepts(FileKind kind) => kind == FileKind.text;
  @override
  Future<ConvertOutput> convert(ConvertInput input, FileKind kind) async =>
      output(input, Uint8List.fromList(utf8.encode(utf8.decode(input.bytes).toUpperCase())));
}

Uint8List bytesOf(String s) => Uint8List.fromList(utf8.encode(s));

void main() {
  group('real type, not extension', () {
    test('sniffs common types from their bytes', () {
      expect(sniffFileKind(smallPng()), FileKind.png);
      expect(sniffFileKind(img.encodeJpg(img.Image(width: 2, height: 2))), FileKind.jpeg);
      expect(sniffFileKind(bytesOf('%PDF-1.7\n')), FileKind.pdf);
      expect(sniffFileKind(ZipWriter().build(<ZipInput>[ZipInput('a.txt', utf8.encode('a'))])), FileKind.zip);
      expect(sniffFileKind(bytesOf('[{"a":1}]')), FileKind.json);
      expect(sniffFileKind(bytesOf('name,age\nAsha,9\n"Ravi, Jr",12\n')), FileKind.csv);
      expect(sniffFileKind(bytesOf('Just a note to self.')), FileKind.text);
      expect(sniffFileKind(Uint8List.fromList(<int>[0, 1, 2, 3, 0xFE])), FileKind.unknown);
      final Uint8List heic = Uint8List.fromList(<int>[0, 0, 0, 24, ...ascii.encode('ftypheic'), 0, 0, 0, 0]);
      expect(sniffFileKind(heic), FileKind.heic);
    });

    test('a PNG named .jpg is offered JPG, never PNG', () {
      final List<String> ids = ConvertRegistry.builtIn().targetsForBytes(smallPng()).map((Converter c) => c.id).toList();
      expect(ids, containsAll(<String>['image-to-jpg', 'image-to-bmp', 'image-to-gif', 'image-to-tiff', 'to-zip']));
      expect(ids, isNot(contains('image-to-png')));
      expect(ids, isNot(contains('csv-to-json')));
    });

    test('CSV parsing handles quotes and commas', () {
      expect(parseCsv('a,b\n"x, y","he said ""hi"""\n'), <List<String>>[
        <String>['a', 'b'],
        <String>['x, y', 'he said "hi"'],
      ]);
      expect(writeCsv(<List<String>>[<String>['x, y', 'q"']]), '"x, y","q"""');
    });
  });

  group('one registry', () {
    test('converts PNG to JPG and the result really is a JPG', () async {
      final ConvertOutput out = await ConvertRegistry.builtIn()
          .convert(ConvertInput(name: 'photo.jpg', bytes: smallPng()), 'image-to-jpg');
      expect(sniffFileKind(out.bytes), FileKind.jpeg);
      expect(out.name, 'photo.jpg');
      expect(img.decodeImage(out.bytes)!.width, 6);
    });

    test('CSV to JSON and back keeps the table', () async {
      final ConvertRegistry r = ConvertRegistry.builtIn();
      final ConvertOutput json =
          await r.convert(ConvertInput(name: 'kids.csv', bytes: bytesOf('name,age\nAsha,9\n"Ravi, Jr",12')), 'csv-to-json');
      expect(jsonDecode(utf8.decode(json.bytes)), <Object>[
        <String, String>{'name': 'Asha', 'age': '9'},
        <String, String>{'name': 'Ravi, Jr', 'age': '12'},
      ]);
      final ConvertOutput csv = await r.convert(ConvertInput(name: 'kids.json', bytes: json.bytes), 'json-to-csv');
      expect(parseCsv(utf8.decode(csv.bytes)), <List<String>>[
        <String>['name', 'age'],
        <String>['Asha', '9'],
        <String>['Ravi, Jr', '12'],
      ]);
    });

    test('any file can go into a ZIP that opens again', () async {
      final ConvertOutput out = await ConvertRegistry.builtIn()
          .convert(ConvertInput(name: 'scan.pdf', bytes: bytesOf('%PDF-1.4 tiny')), 'to-zip');
      final ZipReader z = ZipReader(out.bytes);
      expect(out.name, 'scan.zip');
      expect(utf8.decode(z.extract(z.find('scan.pdf')!)), '%PDF-1.4 tiny');
    });

    test('a new converter appears automatically for its type', () {
      final ConvertRegistry r = ConvertRegistry.builtIn();
      expect(r.targetsFor(FileKind.text).map((Converter c) => c.id), isNot(contains('shout')));
      r.register(const ShoutConverter());
      expect(r.targetsFor(FileKind.text).map((Converter c) => c.id), contains('shout'));
    });

    test('asking for a conversion the type does not allow fails clearly', () async {
      await expectLater(
        ConvertRegistry.builtIn().convert(ConvertInput(name: 'a.txt', bytes: bytesOf('hello')), 'image-to-png'),
        throwsA(isA<ConvertException>()),
      );
    });
  });

  testWidgets('pick a mislabelled file, see its real formats, convert, undo', (WidgetTester tester) async {
    final FakeSink sink = FakeSink();
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: ConvertAnythingScreen(
        chooser: FakeChooser(ConvertInput(name: 'holiday.jpg', bytes: smallPng())),
        sink: sink,
        registry: ConvertRegistry.builtIn(),
      ),
    ));
    await tester.tap(find.byKey(const Key('convert-pick')));
    await tester.pumpAndSettle();
    expect(find.text('Real type: PNG'), findsOneWidget);
    expect(find.textContaining('really a PNG'), findsOneWidget);
    expect(find.byKey(const Key('convert-to-image-to-png')), findsNothing);
    expect(find.byKey(const Key('convert-to-image-to-jpg')), findsOneWidget);
    expect(tester.getSize(find.byKey(const Key('convert-to-image-to-jpg'))).height, greaterThanOrEqualTo(44));

    await tester.tap(find.byKey(const Key('convert-to-image-to-jpg')));
    await tester.pumpAndSettle();
    expect(sink.files.keys, <String>['/converted/holiday.jpg']);
    expect(sniffFileKind(sink.files.values.single.bytes), FileKind.jpeg);
    expect(find.textContaining('Made holiday.jpg'), findsOneWidget);
    expect(find.byKey(const Key('result-share')), findsOneWidget);
    expect(find.byKey(const Key('result-save')), findsOneWidget);

    await tester.tap(find.byKey(const Key('result-undo')));
    await tester.pumpAndSettle();
    expect(sink.files, isEmpty);
    expect(find.textContaining('Removed holiday.jpg'), findsOneWidget);
  });
}
