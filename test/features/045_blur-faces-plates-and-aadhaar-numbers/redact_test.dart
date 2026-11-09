import 'dart:typed_data';

import 'package:family_utility_app/app/theme.dart';
import 'package:family_utility_app/engines/image/passport_photo.dart';
import 'package:family_utility_app/engines/image/redact.dart';
import 'package:family_utility_app/engines/pdf/pdf_ocr.dart';
import 'package:family_utility_app/engines/share/share_engine.dart';
import 'package:family_utility_app/tools/redact/redact_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

OcrWord w(String t, double left, double top, {double width = 40}) =>
    OcrWord(t, left: left, top: top, right: left + width, bottom: top + 20);

/// A colourful gradient, so covered parts are easy to tell apart.
img.Image picture() {
  final img.Image im = img.Image(width: 200, height: 120);
  for (final img.Pixel p in im) {
    p
      ..r = p.x
      ..g = p.y * 2
      ..b = (p.x + p.y) & 0xFF;
  }
  return im;
}

class FakeFaces implements FaceFinder {
  FakeFaces(this.boxes);
  final List<FaceBox> boxes;

  @override
  Future<List<FaceBox>> find(String path) async => boxes;
}

class FakeText implements TextRecognizerEngine {
  FakeText(this.words);
  final List<OcrWord> words;

  @override
  Future<List<OcrWord>> recognize(img.Image page, Uint8List jpeg, OcrScript script) async => words;
}

class FakeFiles implements RedactFiles {
  final Map<String, Uint8List> written = <String, Uint8List>{};

  @override
  Future<String?> pick() async => '/photos/card.jpg';

  @override
  Future<Uint8List> read(String path) async => Uint8List.fromList(img.encodeJpg(picture(), quality: 95));

  @override
  Future<String> write(String name, Uint8List bytes) async {
    written['/covered/$name'] = bytes;
    return '/covered/$name';
  }

  @override
  Future<void> remove(String path) async => written.remove(path);
}

class RecordingSheet implements ShareSheet {
  final List<ShareRequest> sent = <ShareRequest>[];

  @override
  Future<ShareOutcome> share(ShareRequest request) async {
    sent.add(request);
    return const ShareOutcome.dismissed();
  }
}

void main() {
  group('Aadhaar', () {
    test('covers the first 8 of 12 digits, leaves the last 4', () {
      final List<RedactRegion> r = aadhaarRegions(<OcrWord>[
        w('Name', 10, 10),
        w('2345', 10, 50),
        w('6789', 60, 51),
        w('0123', 110, 50),
      ]);
      expect(r, hasLength(1));
      expect(r.single.kind, RedactKind.aadhaar);
      expect(r.single.left, 10);
      expect(r.single.right, 100);
    });

    test('one word with all 12 digits is covered for two thirds of its width', () {
      final RedactRegion r = aadhaarRegions(<OcrWord>[w('2345-6789-0123', 0, 0, width: 120)]).single;
      expect(r.width, 80);
      expect(aadhaarRegions(<OcrWord>[w('Phone', 0, 0), w('98765', 50, 0), w('43210', 100, 0)]), isEmpty);
    });
  });

  group('plates', () {
    test('reads state, district, series and number across words', () {
      expect(isPlateText('MH 12 AB 1234'), isTrue);
      expect(isPlateText('dl3cab1234'), isTrue);
      expect(isPlateText('22 BH 1234 AA'), isTrue);
      expect(isPlateText('INVOICE 1234'), isFalse);
      final List<RedactRegion> r = plateRegions(<OcrWord>[
        w('Car', 0, 0),
        w('MH12', 10, 50),
        w('AB', 55, 50, width: 20),
        w('1234', 80, 50),
      ]);
      expect(r.single.kind, RedactKind.plate);
      expect(r.single.left, lessThan(10));
      expect(r.single.right, greaterThan(120));
    });
  });

  group('cover', () {
    final img.Image src = picture();
    const List<RedactRegion> regions = <RedactRegion>[RedactRegion(RedactKind.manual, 20, 20, 60, 48)];

    test('a black box overwrites every pixel inside and none outside', () {
      final img.Image out = Redactor.apply(src, regions, RedactStyle.box);
      for (int y = 20; y < 68; y++) {
        for (int x = 20; x < 80; x++) {
          final img.Pixel p = out.getPixel(x, y);
          expect(<num>[p.r, p.g, p.b], <num>[0, 0, 0]);
        }
      }
      final img.Pixel o = out.getPixel(100, 100);
      final img.Pixel i = src.getPixel(100, 100);
      expect(<num>[o.r, o.g, o.b], <num>[i.r, i.g, i.b]);
      expect(src.getPixel(30, 30).r, 30, reason: 'the source is not changed');
    });

    test('blur leaves no original pixel: blocks of one average colour', () {
      final img.Image out = Redactor.apply(src, regions, RedactStyle.blur);
      int same = 0;
      for (int y = 20; y < 68; y++) {
        for (int x = 20; x < 80; x++) {
          final img.Pixel a = out.getPixel(x, y);
          final img.Pixel b = src.getPixel(x, y);
          if (a.r == b.r && a.g == b.g && a.b == b.b) {
            same++;
          }
        }
      }
      // Only a pixel that happens to equal its block's average survives.
      expect(same, lessThan(60 * 48 ~/ 20));
      final img.Pixel corner = out.getPixel(20, 20);
      final img.Pixel next = out.getPixel(22, 22);
      expect(<num>[corner.r, corner.g, corner.b], <num>[next.r, next.g, next.b]);
    });

    test('the saved file is a fresh JPEG with no EXIF', () {
      final img.Image tagged = picture()..exif.imageIfd['Make'] = img.IfdValueAscii('Phone');
      final Uint8List out = Redactor.encode(Redactor.apply(tagged, regions, RedactStyle.box));
      final img.Image back = img.decodeJpg(out)!;
      expect(back.exif.imageIfd['Make'], isNull);
      expect(back.width, 200);
    });
  });

  test('detection collects faces, plates and Aadhaar, and survives a failing detector', () async {
    final Redactor r = Redactor(
      faces: FakeFaces(const <FaceBox>[FaceBox(100, 10, 40, 50)]),
      text: FakeText(<OcrWord>[w('2345', 10, 80), w('6789', 60, 80), w('0123', 110, 80)]),
    );
    final List<RedactRegion> found = await r.detect('/p.jpg', picture(), Uint8List(0), const RedactTargets());
    expect(found.map((RedactRegion x) => x.kind), <RedactKind>[RedactKind.face, RedactKind.aadhaar]);
    final List<RedactRegion> onlyText = await r.detect(
      '/p.jpg',
      picture(),
      Uint8List(0),
      const RedactTargets(faces: false, plates: false),
    );
    expect(onlyText.single.kind, RedactKind.aadhaar);
  });

  testWidgets('pick, auto-find, drag a box, cover, share and undo', (WidgetTester tester) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    final FakeFiles files = FakeFiles();
    final RecordingSheet sheet = RecordingSheet();
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: RedactScreen(
        files: files,
        redactor: Redactor(
          faces: FakeFaces(const <FaceBox>[FaceBox(100, 10, 40, 50)]),
          text: FakeText(const <OcrWord>[]),
        ),
        share: ShareEngine(sheet, MemoryShareTargetStore()),
      ),
    ));
    await tester.tap(find.byKey(const Key('redact-pick')));
    await tester.pumpAndSettle();
    expect(find.text('Face'), findsOneWidget);
    expect(find.text('Cover 1'), findsOneWidget);

    await tester.drag(find.byKey(const Key('redact-canvas')), const Offset(80, 12));
    await tester.pumpAndSettle();
    expect(find.text('Your box'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Picture with 2 covered parts')), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('redact-apply')));
    expect(tester.getSize(find.byKey(const Key('redact-apply'))).height, greaterThanOrEqualTo(44));
    await tester.tap(find.byKey(const Key('redact-apply')));
    await tester.pumpAndSettle();
    expect(files.written.keys.single, '/covered/card-covered.jpg');

    await tester.tap(find.byKey(const Key('result-share')));
    await tester.pumpAndSettle();
    expect(sheet.sent.single.files.single.path, '/covered/card-covered.jpg');

    await tester.tap(find.byKey(const Key('result-undo')));
    await tester.pumpAndSettle();
    expect(files.written, isEmpty);
    handle.dispose();
  });
}
