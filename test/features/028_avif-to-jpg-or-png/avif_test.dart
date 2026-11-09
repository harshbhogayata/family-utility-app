import 'dart:typed_data';

import 'package:family_utility_app/engines/convert/convert_registry.dart';
import 'package:family_utility_app/engines/convert/file_kind.dart';
import 'package:family_utility_app/engines/image/avif_convert.dart';
import 'package:family_utility_app/engines/image/heic_convert.dart' show ConvertedPicture, PictureResult;
import 'package:family_utility_app/engines/image/webp_convert.dart' show ImageTarget;
import 'package:family_utility_app/engines/platform/background_jobs.dart';
import 'package:family_utility_app/engines/share/share_engine.dart';
import 'package:family_utility_app/tools/avif/avif_screen.dart';
import 'package:family_utility_app/tools/compress_images/compress_images_screen.dart' show ImageFiles;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// Bytes the app recognises as AVIF; [tag] tells the fake codec which
/// picture it is.
Uint8List fakeAvif(int tag) => Uint8List.fromList(<int>[
      0, 0, 0, 28, ...'ftyp'.codeUnits, ...'avif'.codeUnits, 0, 0, 0, 0, //
      ...'avif'.codeUnits, ...'mif1'.codeUnits, ...'miaf'.codeUnits, tag,
    ]);

/// Stands in for the phone codec: a [tag]-wide, 2-high picture; tag 0 is
/// what an old phone does with AVIF.
class FakeCodec implements AvifCodec {
  final List<int> seen = <int>[];

  @override
  Future<Uint8List> convert(Uint8List avif, ImageTarget target, {int quality = 92}) async {
    final int tag = avif.last;
    seen.add(tag);
    if (tag == 0) {
      throw PlatformException(code: 'decode', message: 'cannot decode');
    }
    final img.Image im = img.Image(width: tag, height: 2);
    return target == ImageTarget.png ? img.encodePng(im) : img.encodeJpg(im);
  }
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

class FakeSheet implements ShareSheet {
  final List<ShareRequest> requests = <ShareRequest>[];

  @override
  Future<ShareOutcome> share(ShareRequest request) async {
    requests.add(request);
    return const ShareOutcome(completed: true);
  }
}

void main() {
  group('sniffing', () {
    test('AVIF is told apart from HEIC and MP4', () {
      expect(sniffFileKind(fakeAvif(1)), FileKind.avif);
      // Generic HEIF major brand with avif among the compatible brands.
      final Uint8List mif1 = Uint8List.fromList(<int>[
        0, 0, 0, 24, ...'ftyp'.codeUnits, ...'mif1'.codeUnits, 0, 0, 0, 0, ...'mif1'.codeUnits, ...'avif'.codeUnits,
      ]);
      expect(sniffFileKind(mif1), FileKind.avif);
      final Uint8List heic = Uint8List.fromList(<int>[
        0, 0, 0, 24, ...'ftyp'.codeUnits, ...'mif1'.codeUnits, 0, 0, 0, 0, ...'mif1'.codeUnits, ...'heic'.codeUnits,
      ]);
      expect(sniffFileKind(heic), FileKind.heic);
      final Uint8List mp4 = Uint8List.fromList(<int>[
        0, 0, 0, 20, ...'ftyp'.codeUnits, ...'isom'.codeUnits, 0, 0, 2, 0, ...'isom'.codeUnits,
      ]);
      expect(sniffFileKind(mp4), FileKind.mp4);
      expect(FileKind.avif.isImage, isTrue);
      expect(MimeTypes.fromPath('/x/a.avif'), 'image/avif');
    });
  });

  group('support', () {
    test('iOS 16+ decodes, iOS 15 is told up front, Android lets the decode decide', () {
      expect(avifSupportFor('ios', 'Version 16.4 (Build 20E247)'), AvifSupport.yes);
      expect(avifSupportFor('ios', 'Version 17.0 (Build 21A329)'), AvifSupport.yes);
      expect(avifSupportFor('ios', 'Version 15.7 (Build 19H12)'), AvifSupport.no);
      expect(avifSupportFor('ios', ''), AvifSupport.unknown);
      expect(avifSupportFor('android', 'Linux 5.10.43 #1 SMP PREEMPT'), AvifSupport.unknown);
      expect(avifSupportFor('linux', 'anything'), AvifSupport.no);
    });
  });

  group('engine', () {
    test('AVIF goes through the phone codec; output is the asked format', () async {
      final FakeCodec codec = FakeCodec();
      final AvifConverter c = AvifConverter(codec);
      final ConvertedPicture jpg = await c.convert(fakeAvif(5), 'hero.avif', ImageTarget.jpg);
      expect(jpg.name, 'hero.jpg');
      expect(sniffFileKind(jpg.bytes), FileKind.jpeg);
      final ConvertedPicture png = await c.convert(fakeAvif(3), 'logo.AVIF', ImageTarget.png);
      expect(png.name, 'logo.png');
      expect(sniffFileKind(png.bytes), FileKind.png);
      expect(codec.seen, <int>[5, 3]);
    });

    test('an older phone gets the plain message, not a crash', () async {
      await expectLater(AvifConverter(FakeCodec()).convert(fakeAvif(0), 'a.avif', ImageTarget.jpg),
          throwsA(isA<AvifConvertError>().having((AvifConvertError e) => e.message, 'm', avifUnsupportedMessage)));
      final FakeCodec codec = FakeCodec();
      await expectLater(
          AvifConverter(codec, support: AvifSupport.no).convert(fakeAvif(4), 'a.avif', ImageTarget.jpg),
          throwsA(isA<AvifConvertError>()));
      expect(codec.seen, isEmpty, reason: 'known-unsupported phones do not try');
      expect(avifUnsupportedMessage, contains('Android 12'));
      expect(avifUnsupportedMessage, contains('iOS 16'));
      await expectLater(AvifConverter(FakeCodec()).convert(Uint8List.fromList(<int>[1, 2, 3]), 'x.txt', ImageTarget.jpg),
          throwsA(isA<AvifConvertError>()));
    });

    test('a batch keeps its order and reports failures without stopping', () async {
      final MemFiles files = MemFiles(<String, Uint8List>{
        '/in/c.avif': fakeAvif(7),
        '/in/a.avif': fakeAvif(0),
        '/in/b.avif': fakeAvif(2),
      });
      final List<PictureResult> r = await AvifConverter(FakeCodec()).convertAll(
        files.inputs.keys.toList(),
        ImageTarget.jpg,
        read: files.read,
        write: files.write,
      );
      expect(r.map((PictureResult x) => x.ok).toList(), <bool>[true, false, true]);
      expect(files.order, <String>['/converted/c.jpg', '/converted/b.jpg']);
      expect(img.decodeJpg(files.written['/converted/c.jpg']!)!.width, 7);
    });

    test('Convert anything and Batch convert take AVIF once registered', () async {
      final ConvertRegistry reg = ConvertRegistry.builtIn();
      expect(reg.targetsFor(FileKind.avif), isEmpty);
      registerAvifConverters(reg, FakeCodec());
      final List<FileKind> targets = reg.targetsFor(FileKind.avif).map((Converter c) => c.target).toList();
      expect(targets, containsAll(<FileKind>[FileKind.jpeg, FileKind.png]));
      final ConvertOutput out = await reg.convert(ConvertInput(name: 'pic.avif', bytes: fakeAvif(4)), 'avif-to-jpg');
      expect(out.name, 'pic.jpg');
      expect(out.kind, FileKind.jpeg);
      await expectLater(
          reg.convert(ConvertInput(name: 'bad.avif', bytes: fakeAvif(0)), 'avif-to-png'), throwsA(isA<ConvertException>()));
    });
  });

  group('screen', () {
    testWidgets('pick, choose PNG, convert, share, undo', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final MemFiles files = MemFiles(<String, Uint8List>{'/p/a.avif': fakeAvif(5), '/p/b.avif': fakeAvif(3)});
      final FakeSheet sheet = FakeSheet();
      await tester.pumpWidget(MaterialApp(
        home: AvifScreen(
          files: files,
          codec: FakeCodec(),
          support: AvifSupport.yes,
          jobs: BackgroundJobs(NoopJobHost()),
          share: ShareEngine(sheet, MemoryShareTargetStore()),
        ),
      ));
      expect(find.byKey(const Key('avif-unsupported')), findsNothing);
      for (final String k in <String>['avif-pick', 'avif-run', 'avif-to-jpg', 'avif-to-png']) {
        expect(tester.getSize(find.byKey(Key(k))).height, greaterThanOrEqualTo(44), reason: k);
      }
      await tester.tap(find.byKey(const Key('avif-pick')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('avif-to-png')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('avif-run')));
      await tester.pumpAndSettle();
      expect(files.order, <String>['/converted/a.png', '/converted/b.png']);
      expect(find.textContaining('2 pictures saved as PNG'), findsOneWidget);
      expect(find.byWidgetPredicate((Widget w) => w is Icon && w.semanticLabel == 'Converted'), findsNWidgets(2));

      await tester.tap(find.byKey(const Key('result-share')));
      await tester.pumpAndSettle();
      expect(sheet.requests.single.files.map((ShareFile f) => f.path), <String>['/converted/a.png', '/converted/b.png']);

      await tester.tap(find.byKey(const Key('result-undo')));
      await tester.pumpAndSettle();
      expect(files.written, isEmpty);
      expect(find.text('Removed the converted copies'), findsOneWidget);
    });

    testWidgets('an older phone sees the message up front and per picture', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final MemFiles files = MemFiles(<String, Uint8List>{'/p/a.avif': fakeAvif(5)});
      await tester.pumpWidget(MaterialApp(
        home: AvifScreen(
          files: files,
          codec: FakeCodec(),
          support: AvifSupport.no,
          jobs: BackgroundJobs(NoopJobHost()),
        ),
      ));
      expect(find.byKey(const Key('avif-unsupported')), findsOneWidget);
      await tester.tap(find.byKey(const Key('avif-pick')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('avif-run')));
      await tester.pumpAndSettle();
      expect(files.written, isEmpty);
      expect(find.textContaining('1 could not be converted'), findsOneWidget);
      expect(find.byWidgetPredicate((Widget w) => w is Icon && w.semanticLabel == 'Failed'), findsOneWidget);
    });
  });
}
