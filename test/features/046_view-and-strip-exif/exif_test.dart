import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:family_utility_app/app/theme.dart';
import 'package:family_utility_app/engines/image/exif_strip.dart';
import 'package:family_utility_app/engines/share/share_engine.dart';
import 'package:family_utility_app/tools/compress_images/compress_images_screen.dart';
import 'package:family_utility_app/tools/exif/exif_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// 8 × 8 JPEG with Make "Pixelphone", Model "P9", Orientation 6, Software,
/// DateTime, GPS 12°58'30"N 77°35'24"W and a comment.
final Uint8List jpeg = base64Decode('/9j/4AAQSkZJRgABAQAAAQABAAD/4QDuRXhpZgAATU0AKgAAAAgABgEPAAIAAAALAAAAVgEQAAIAAAADUDkAAAESAAMAAAABAAYAAAExAAIAAAAJAAAAYgEyAAIAAAAUAAAAbIglAAQAAAABAAAAgAAAAABQaXhlbHBob25lAABTbmFwIDEuMAAAMjAyNDowNTowMSAxMDoyMDozMAAABAABAAIAAAACTgAAAAACAAUAAAADAAAAtgADAAIAAAACVwAAAAAEAAUAAAADAAAAzgAAAAAAAAAMAAAAAQAAADoAAAABAAAAHgAAAAEAAABNAAAAAQAAACMAAAABAAAAGAAAAAH//gAEaGn/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/2wBDAQkJCQwLDBgNDRgyIRwhMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjL/wAARCAAIAAgDASIAAhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9oADAMBAAIRAxEAPwDnqKKK8k/Qz//Z');

/// A PNG with a tEXt chunk added after IHDR (CRC left zero: only the
/// stripped copy is decoded).
Uint8List pngWithText() {
  final Uint8List plain = img.encodePng(img.Image(width: 4, height: 4));
  final List<int> data = latin1.encode('Author\u0000Someone');
  final ByteData len = ByteData(4)..setUint32(0, data.length);
  const int ihdrEnd = 8 + 12 + 13;
  return Uint8List.fromList(<int>[
    ...plain.sublist(0, ihdrEnd),
    ...len.buffer.asUint8List(),
    ...latin1.encode('tEXt'),
    ...data,
    0, 0, 0, 0,
    ...plain.sublist(ihdrEnd),
  ]);
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

class RecordingSheet implements ShareSheet {
  final List<ShareRequest> requests = <ShareRequest>[];

  @override
  Future<ShareOutcome> share(ShareRequest request) async {
    requests.add(request);
    return const ShareOutcome.dismissed();
  }
}

void main() {
  test('reads GPS, camera and time', () {
    final PhotoMeta m = ExifTool.read(jpeg);
    expect(m.camera, 'Pixelphone P9');
    expect(m.software, 'Snap 1.0');
    expect(m.taken, '2024:05:01 10:20:30');
    expect(m.latitude, closeTo(12.975, 1e-6));
    expect(m.longitude, closeTo(-77.59, 1e-6));
    expect(m.orientation, 6);
    expect(m.otherBlocks, 1, reason: 'the JPEG comment');
    expect(m.isClean, isFalse);
  });

  test('strip removes everything but orientation; picture unchanged', () {
    final Uint8List clean = ExifTool.strip(jpeg);
    final PhotoMeta m = ExifTool.read(clean);
    expect(m.hasGps, isFalse);
    expect(m.camera, isNull);
    expect(m.taken, isNull);
    expect(m.otherBlocks, 0);
    expect(m.orientation, 6);
    expect(m.isClean, isTrue);
    expect(clean.length, lessThan(jpeg.length));
    final img.Image a = img.decodeJpg(jpeg)!;
    final img.Image b = img.decodeJpg(clean)!;
    expect((b.width, b.height), (a.width, a.height));
    expect(b.getPixel(3, 3).r, a.getPixel(3, 3).r);
    expect(ExifTool.cleanName('/x/IMG_1.jpg'), 'IMG_1-clean.jpg');
  });

  test('PNG text chunks are found and removed', () {
    final Uint8List png = pngWithText();
    expect(ExifTool.read(png).otherBlocks, greaterThan(0));
    final Uint8List clean = ExifTool.strip(png);
    expect(ExifTool.read(clean).isClean, isTrue);
    expect(img.decodePng(clean)!.width, 4);
    expect(() => ExifTool.read(Uint8List.fromList(<int>[1, 2, 3, 4, 5])), throwsA(isA<ExifError>()));
  });

  test('always strip on share swaps photos for clean copies', () async {
    final Directory tmp = await Directory.systemTemp.createTemp('exif046');
    final File photo = File('${tmp.path}/trip.jpg')..writeAsBytesSync(jpeg);
    final File doc = File('${tmp.path}/notes.txt')..writeAsStringSync('hi');
    final MemoryStripOnShareStore store = MemoryStripOnShareStore();
    final RecordingSheet sheet = RecordingSheet();
    final ShareEngine share = ShareEngine(sheet, MemoryShareTargetStore())
      ..prepare = StripOnShare(store, () async => Directory('${tmp.path}/clean')).prepare;

    await share.shareFiles(<String>[photo.path, doc.path]);
    expect(sheet.requests.last.files.first.path, photo.path, reason: 'off by default');

    await store.write(true);
    await share.shareFiles(<String>[photo.path, doc.path]);
    final List<ShareFile> sent = sheet.requests.last.files;
    expect(sent.first.path, '${tmp.path}/clean/trip.jpg');
    expect(sent.first.name, 'trip.jpg');
    expect(sent.last.path, doc.path);
    expect(ExifTool.read(File(sent.first.path).readAsBytesSync()).hasGps, isFalse);
    expect(ExifTool.read(photo.readAsBytesSync()).hasGps, isTrue, reason: 'original untouched');
    await tmp.delete(recursive: true);
  });

  testWidgets('batch view, strip all, toggle, undo', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final FakeFiles files = FakeFiles(<String, Uint8List>{'/p/trip.jpg': jpeg, '/p/logo.png': pngWithText()});
    final MemoryStripOnShareStore store = MemoryStripOnShareStore();
    await tester.pumpWidget(MaterialApp(theme: buildAppTheme(), home: ExifScreen(files: files, setting: store)));
    await tester.tap(find.byKey(const Key('exif-pick')));
    await tester.pumpAndSettle();
    expect(find.text('12.97500, -77.59000'), findsOneWidget);
    expect(find.text('Pixelphone P9'), findsOneWidget);
    expect(find.text('2024:05:01 10:20:30'), findsOneWidget);
    expect(find.text('Strip all 2'), findsOneWidget);
    expect(tester.getSize(find.byKey(const Key('exif-strip'))).height, greaterThanOrEqualTo(44));

    await tester.tap(find.byKey(const Key('exif-strip')));
    await tester.pumpAndSettle();
    expect(files.written.keys, <String>['/out/trip-clean.jpg', '/out/logo-clean.png']);
    expect(ExifTool.read(files.written['/out/trip-clean.jpg']!).isClean, isTrue);

    await tester.tap(find.byKey(const Key('exif-always')));
    await tester.pumpAndSettle();
    expect(store.value, isTrue);

    await tester.tap(find.byKey(const Key('result-undo')));
    await tester.pumpAndSettle();
    expect(files.written, isEmpty);
  });
}
