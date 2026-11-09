import 'dart:typed_data';

import 'package:family_utility_app/app/theme.dart';
import 'package:family_utility_app/engines/image/exact_kb.dart';
import 'package:family_utility_app/engines/image/passport_photo.dart';
import 'package:family_utility_app/tools/compress_images/compress_images_screen.dart';
import 'package:family_utility_app/tools/passport_photo/passport_photo_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// A grey picture with a dark "face" block at [face]; returns a busy JPG.
Uint8List portrait(int w, int h, FaceBox face) {
  final img.Image im = img.Image(width: w, height: h);
  int seed = 3;
  for (final img.Pixel p in im) {
    seed = (seed * 1103515245 + 12345) & 0x7fffffff;
    final bool inFace = p.x >= face.left && p.x < face.left + face.width && p.y >= face.top && p.y < face.bottom;
    final int base = inFace ? 40 : 170;
    p
      ..r = base + (seed & 31)
      ..g = base + ((seed >> 5) & 31)
      ..b = base + ((seed >> 10) & 31);
  }
  return img.encodeJpg(im, quality: 95);
}

class FakeFiles implements ImageFiles {
  FakeFiles(this.inputs);
  final Map<String, Uint8List> inputs;
  final Map<String, Uint8List> written = <String, Uint8List>{};

  @override
  Future<List<String>> pick() async => inputs.keys.toList();

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

class FakeFaces implements FaceFinder {
  FakeFaces(this.faces);
  final List<FaceBox> faces;
  final List<String> asked = <String>[];

  @override
  Future<List<FaceBox>> find(String path) async {
    asked.add(path);
    return faces;
  }
}

/// Bounding box of dark pixels (the fake face) in [im].
(int, int, int, int) darkBox(img.Image im) {
  int x0 = im.width;
  int y0 = im.height;
  int x1 = -1;
  int y1 = -1;
  for (final img.Pixel p in im) {
    if (p.r < 110 && p.g < 110 && p.b < 110) {
      x0 = p.x < x0 ? p.x : x0;
      y0 = p.y < y0 ? p.y : y0;
      x1 = p.x > x1 ? p.x : x1;
      y1 = p.y > y1 ? p.y : y1;
    }
  }
  return (x0, y0, x1, y1);
}

void main() {
  // Face off to the right and high up in a wide shot.
  const FaceBox face = FaceBox(500, 120, 120, 150);
  final Uint8List photo = portrait(900, 700, face);

  test('presets: India, US, UK, Schengen at 300 dpi; custom mm', () {
    final Map<String, PassportSpec> by = <String, PassportSpec>{for (final PassportSpec p in passportPresets) p.id: p};
    expect(by.keys, containsAll(<String>['in', 'us', 'uk', 'schengen']));
    expect((by['in']!.widthPx, by['in']!.heightPx), (413, 531));
    expect((by['us']!.widthPx, by['us']!.heightPx), (600, 600));
    expect((by['uk']!.widthMm, by['uk']!.heightMm), (35, 45));
    expect((by['schengen']!.widthMm, by['schengen']!.heightMm), (35, 45));
    final PassportSpec c = PassportSpec.custom(40, 50);
    expect((c.widthPx, c.heightPx), (472, 591));
  });

  test('the face is centred and the head sized to the spec', () {
    for (final PassportSpec spec in passportPresets) {
      final img.Image out = PassportPhoto.render(photo, spec, face);
      expect((out.width, out.height), (spec.widthPx, spec.heightPx), reason: spec.id);
      final (int x0, int y0, int x1, int y1) = darkBox(out);
      final double centre = (x0 + x1) / 2;
      expect((centre - out.width / 2).abs(), lessThan(out.width * 0.03), reason: '${spec.id} centred');
      // The detector box is brow to chin; the whole head is headPerFaceBox times it.
      final double head = (y1 - y0 + 1) * headPerFaceBox / out.height;
      expect(head, inInclusiveRange(spec.headMin - 0.02, spec.headMax + 0.02), reason: '${spec.id} head share');
      expect(y1, lessThan(out.height), reason: 'chin inside the frame');
    }
  });

  test('no face: a plain centre crop at the right size', () {
    final PassportCrop c = PassportPhoto.crop(900, 700, passportPresets.first, null);
    expect(c.centred, isFalse);
    expect(c.height, 700);
    expect(c.left, closeTo((900 - 700 * 35 / 45) / 2, 0.01));
    final img.Image out = PassportPhoto.render(photo, passportPresets.first, null);
    expect((out.width, out.height), (413, 531));
  });

  test('space past the edges is filled with the plain background', () {
    // Face at the very top-left: the crop runs past the picture.
    const FaceBox corner = FaceBox(0, 0, 200, 260);
    final Uint8List p = portrait(400, 400, corner);
    final img.Image out = PassportPhoto.render(p, passportPresets.first, corner, background: 0xDCE9F5);
    final img.Pixel tl = out.getPixel(0, 0);
    expect((tl.r, tl.g, tl.b), (0xDC, 0xE9, 0xF5));
  });

  test('single copy at exact KB and pixel size', () {
    final img.Image out = PassportPhoto.render(photo, passportPresets.first, face);
    final ExactKbResult r = PassportPhoto.single(out, 50);
    expect(r.bytes.length, lessThanOrEqualTo(50 * 1024));
    expect((r.width, r.height), (413, 531));
    final img.Image? back = img.decodeJpg(r.bytes);
    expect((back!.width, back.height), (413, 531));
  });

  test('print sheets: 8 or 6 on 4x6 and A4; US 2x2 fits 6 on 4x6', () {
    final img.Image india = PassportPhoto.render(photo, passportPresets.first, face);
    final PassportSheet s8 = PassportPhoto.sheet(india, SheetPaper.r4x6, 8);
    expect(s8.count, 8);
    expect({s8.image.width, s8.image.height}, <int>{1200, 1800});
    final PassportSheet s6 = PassportPhoto.sheet(india, SheetPaper.r4x6, 6);
    expect(s6.count, 6);
    final PassportSheet a4 = PassportPhoto.sheet(india, SheetPaper.a4, 8);
    expect(a4.count, 8);
    expect({a4.image.width, a4.image.height}, <int>{2480, 3508});

    final img.Image us = PassportPhoto.render(photo, passportPresets[1], face);
    expect(PassportPhoto.sheet(us, SheetPaper.r4x6, 6).count, 6);
    final PassportSheet us8 = PassportPhoto.sheet(us, SheetPaper.r4x6, 8);
    expect(us8.count, 6, reason: 'only six 2 in squares fit on 4 × 6 in');
  });

  testWidgets('pick, face found, save the photo and a sheet, undo', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final FakeFiles files = FakeFiles(<String, Uint8List>{'/a/me.jpg': photo});
    final FakeFaces faces = FakeFaces(<FaceBox>[face, const FaceBox(10, 10, 20, 25)]);
    await tester.pumpWidget(
      MaterialApp(theme: buildAppTheme(), home: PassportPhotoScreen(files: files, faces: faces)),
    );
    await tester.tap(find.byKey(const Key('pp-pick')));
    await tester.pumpAndSettle();
    expect(faces.asked, <String>['/a/me.jpg']);
    expect(find.byKey(const Key('pp-preview')), findsOneWidget);
    expect(
      find.byWidgetPredicate((Widget w) => w is Semantics && w.properties.label == 'Passport photo preview'),
      findsOneWidget,
    );
    expect(find.textContaining('framed the largest'), findsOneWidget);

    final Finder single = find.byKey(const Key('pp-single'));
    await tester.ensureVisible(single);
    expect(tester.getSize(single).height, greaterThanOrEqualTo(44));
    expect(tester.getSize(find.byKey(const Key('pp-preset-us'))).height, greaterThanOrEqualTo(44));
    await tester.tap(single);
    await tester.pumpAndSettle();
    expect(files.written.keys, <String>['/out/me-passport-in-100kb.jpg']);
    expect(files.written.values.single.length, lessThanOrEqualTo(100 * 1024));

    await tester.ensureVisible(find.byKey(const Key('pp-sheet')));
    await tester.tap(find.byKey(const Key('pp-sheet')));
    await tester.pumpAndSettle();
    expect(files.written.keys, contains('/out/me-passport-in-sheet-4x6.jpg'));
    expect(find.textContaining('8 copies on 4 × 6 in'), findsOneWidget);

    await tester.tap(find.byKey(const Key('result-undo')));
    await tester.pumpAndSettle();
    expect(files.written.keys, <String>['/out/me-passport-in-100kb.jpg']);
  });

  testWidgets('custom mm and no face still give a photo', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final FakeFiles files = FakeFiles(<String, Uint8List>{'/a/me.jpg': photo});
    await tester.pumpWidget(
      MaterialApp(theme: buildAppTheme(), home: PassportPhotoScreen(files: files, faces: FakeFaces(<FaceBox>[]))),
    );
    await tester.tap(find.byKey(const Key('pp-pick')));
    await tester.pumpAndSettle();
    expect(find.textContaining('No face found'), findsOneWidget);
    await tester.tap(find.byKey(const Key('pp-preset-custom')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('pp-custom-w')), '40');
    await tester.enterText(find.byKey(const Key('pp-custom-h')), '50');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pp-single')));
    await tester.pumpAndSettle();
    final Uint8List out = files.written.values.single;
    final img.Image? back = img.decodeJpg(out);
    expect((back!.width, back.height), (472, 591));
  });
}
