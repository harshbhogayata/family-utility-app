import 'dart:typed_data';

import 'package:family_utility_app/engines/convert/convert_registry.dart';
import 'package:family_utility_app/engines/convert/file_kind.dart';
import 'package:family_utility_app/engines/image/heic_convert.dart';
import 'package:family_utility_app/engines/image/webp_convert.dart' show ImageTarget;
import 'package:family_utility_app/engines/platform/background_jobs.dart';
import 'package:family_utility_app/engines/share/shared_files.dart';
import 'package:family_utility_app/tools/compress_images/compress_images_screen.dart' show ImageFiles;
import 'package:family_utility_app/tools/heic/heic_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// Bytes the app recognises as HEIC; [tag] tells the fake codec which
/// picture it is.
Uint8List fakeHeic(int tag) => Uint8List.fromList(<int>[
      0, 0, 0, 24, ...'ftyp'.codeUnits, ...'heic'.codeUnits, 0, 0, 0, 0, ...'mif1'.codeUnits, ...'heic'.codeUnits, tag,
    ]);

/// Stands in for the phone codec: a [tag]-wide, 2-high upright picture.
class FakeCodec implements HeicCodec {
  final List<int> seen = <int>[];

  @override
  Future<Uint8List> convert(Uint8List heic, ImageTarget target, {int quality = 92}) async {
    final int tag = heic.last;
    seen.add(tag);
    if (tag == 0) {
      throw PlatformException(code: 'decode', message: 'cannot decode');
    }
    final img.Image im = img.Image(width: tag, height: 2);
    return target == ImageTarget.png ? img.encodePng(im) : img.encodeJpg(im);
  }
}

/// A JPG stored sideways with EXIF orientation 6 (rotate 90° to view).
Uint8List sidewaysJpg() {
  final img.Image im = img.Image(width: 8, height: 4);
  im.exif.imageIfd.orientation = 6;
  return img.encodeJpg(im);
}

class MemFiles implements ImageFiles {
  MemFiles(this.inputs);

  final Map<String, Uint8List> inputs;
  final Map<String, Uint8List> written = <String, Uint8List>{};
  final List<String> order = <String>[];

  @override
  Future<List<String>> pick() async => inputs.keys.toList();

  @override
  Future<Uint8List> read(String path) async => inputs[path]!;

  @override
  Future<String> write(String name, Uint8List bytes) async {
    final String p = '/converted/$name';
    written[p] = bytes;
    order.add(p);
    return p;
  }

  @override
  Future<void> remove(String path) async => written.remove(path);
}

void main() {
  group('engine', () {
    test('HEIC goes through the phone codec; output is the asked format', () async {
      final FakeCodec codec = FakeCodec();
      final PictureConverter c = PictureConverter(codec);
      final ConvertedPicture jpg = await c.convert(fakeHeic(5), 'IMG_0001.HEIC', ImageTarget.jpg);
      expect(jpg.name, 'IMG_0001.jpg');
      expect(sniffFileKind(jpg.bytes), FileKind.jpeg);
      final ConvertedPicture png = await c.convert(fakeHeic(3), 'IMG_0002.heic', ImageTarget.png);
      expect(png.name, 'IMG_0002.png');
      expect(sniffFileKind(png.bytes), FileKind.png);
      expect(codec.seen, <int>[5, 3]);
    });

    test('a photo the codec cannot open is a clear error', () async {
      final PictureConverter c = PictureConverter(FakeCodec());
      await expectLater(c.convert(fakeHeic(0), 'bad.heic', ImageTarget.jpg),
          throwsA(isA<HeicConvertError>().having((HeicConvertError e) => e.message, 'm', contains('HEIC'))));
      await expectLater(c.convert(Uint8List.fromList(<int>[1, 2, 3]), 'x.txt', ImageTarget.jpg),
          throwsA(isA<HeicConvertError>()));
    });

    test('other pictures in the batch come out upright (EXIF orientation applied)', () async {
      final ConvertedPicture r = await PictureConverter(FakeCodec()).convert(sidewaysJpg(), 'side.jpg', ImageTarget.jpg);
      final img.Image out = img.decodeJpg(r.bytes)!;
      expect(out.width, 4);
      expect(out.height, 8);
    });

    test('a batch keeps its order and reports failures without stopping', () async {
      final MemFiles files = MemFiles(<String, Uint8List>{
        '/in/c.heic': fakeHeic(7),
        '/in/a.heic': fakeHeic(0),
        '/in/b.heic': fakeHeic(2),
        '/in/side.jpg': sidewaysJpg(),
      });
      final List<int> ticks = <int>[];
      final List<PictureResult> r = await PictureConverter(FakeCodec()).convertAll(
        files.inputs.keys.toList(),
        ImageTarget.jpg,
        read: files.read,
        write: files.write,
        progress: (int done, int total) => ticks.add(done),
      );
      expect(r.map((PictureResult x) => x.source).toList(), <String>['/in/c.heic', '/in/a.heic', '/in/b.heic', '/in/side.jpg']);
      expect(r.map((PictureResult x) => x.ok).toList(), <bool>[true, false, true, true]);
      expect(files.order, <String>['/converted/c.jpg', '/converted/b.jpg', '/converted/side.jpg']);
      expect(img.decodeJpg(files.written['/converted/c.jpg']!)!.width, 7);
      expect(ticks, <int>[1, 2, 3, 4]);
    });

    test('Convert anything and Batch convert take HEIC once registered', () async {
      final ConvertRegistry reg = ConvertRegistry.builtIn();
      expect(reg.targetsFor(FileKind.heic).where((Converter c) => c.target == FileKind.jpeg), isEmpty);
      registerHeicConverters(reg, FakeCodec());
      final List<FileKind> targets = reg.targetsFor(FileKind.heic).map((Converter c) => c.target).toList();
      expect(targets, containsAll(<FileKind>[FileKind.jpeg, FileKind.png]));
      final ConvertOutput out = await reg.convert(ConvertInput(name: 'IMG_9.HEIC', bytes: fakeHeic(4)), 'heic-to-jpg');
      expect(out.name, 'IMG_9.jpg');
      expect(out.kind, FileKind.jpeg);
      await expectLater(
          reg.convert(ConvertInput(name: 'bad.heic', bytes: fakeHeic(0)), 'heic-to-png'), throwsA(isA<ConvertException>()));
    });
  });

  group('sharing from Photos', () {
    test('the inbox hands shared paths over once, in order', () async {
      final SharedFilesInbox inbox = SharedFilesInbox();
      final List<List<String>> seen = <List<String>>[];
      inbox.onFiles = seen.add;
      await inbox.handle(const MethodCall('files', <Object?>['/c/0/IMG_3.HEIC', '/c/1/IMG_1.HEIC']));
      expect(seen.single, <String>['/c/0/IMG_3.HEIC', '/c/1/IMG_1.HEIC']);
      expect(inbox.take(), <String>['/c/0/IMG_3.HEIC', '/c/1/IMG_1.HEIC']);
      expect(inbox.take(), isNull);
      await inbox.handle(const MethodCall('files', <Object?>[]));
      expect(seen.length, 1);
    });

    testWidgets('shared photos convert straight away; share keeps the order; undo removes them',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final MemFiles files = MemFiles(<String, Uint8List>{
        '/c/0/IMG_3.HEIC': fakeHeic(3),
        '/c/1/IMG_1.HEIC': fakeHeic(1),
        '/c/2/IMG_2.HEIC': fakeHeic(2),
      });
      final NoopJobHost host = NoopJobHost();
      await tester.pumpWidget(MaterialApp(
        home: HeicScreen(
          files: files,
          codec: FakeCodec(),
          jobs: BackgroundJobs(host),
          initialPaths: const <String>['/c/0/IMG_3.HEIC', '/c/1/IMG_1.HEIC', '/c/2/IMG_2.HEIC'],
        ),
      ));
      await tester.pumpAndSettle();
      expect(files.order, <String>['/converted/IMG_3.jpg', '/converted/IMG_1.jpg', '/converted/IMG_2.jpg']);
      expect(find.textContaining('3 photos saved as JPG'), findsOneWidget);
      expect(find.text('IMG_3.jpg'), findsOneWidget);
      expect(host.log, contains('finished 1 done'));

      for (final String k in <String>['heic-pick', 'heic-run', 'heic-to-jpg', 'heic-to-png']) {
        expect(tester.getSize(find.byKey(Key(k))).height, greaterThanOrEqualTo(44), reason: k);
      }
      expect(find.byWidgetPredicate((Widget w) => w is Icon && w.semanticLabel == 'Converted'), findsNWidgets(3));

      await tester.tap(find.byKey(const Key('result-undo')));
      await tester.pumpAndSettle();
      expect(files.written, isEmpty);
      expect(find.text('Removed the converted copies'), findsOneWidget);
    });

    testWidgets('pick, choose PNG, convert', (WidgetTester tester) async {
      final MemFiles files = MemFiles(<String, Uint8List>{'/p/IMG_5.heic': fakeHeic(5)});
      await tester.pumpWidget(MaterialApp(
        home: HeicScreen(files: files, codec: FakeCodec(), jobs: BackgroundJobs(NoopJobHost())),
      ));
      await tester.tap(find.byKey(const Key('heic-pick')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('heic-to-png')));
      await tester.pumpAndSettle();
      expect(find.text('Convert to PNG'), findsOneWidget);
      await tester.tap(find.byKey(const Key('heic-run')));
      await tester.pumpAndSettle();
      expect(files.order, <String>['/converted/IMG_5.png']);
      expect(sniffFileKind(files.written['/converted/IMG_5.png']!), FileKind.png);
    });
  });
}
