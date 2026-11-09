import 'dart:io';
import 'dart:typed_data';

import 'package:family_utility_app/app/theme.dart';
import 'package:family_utility_app/engines/share/status_saver.dart';
import 'package:family_utility_app/tools/status_saver/status_saver_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

final Uint8List photo = img.encodeJpg(img.Image(width: 4, height: 4));

class FakeSource implements StatusSource {
  FakeSource(this.state);
  StatusAccess state;
  int asked = 0;

  final List<StatusItem> items = <StatusItem>[
    StatusItem(id: 'a', name: 'IMG-1.jpg', modified: DateTime(2026, 11, 9, 8), size: 10),
    StatusItem(id: 'b', name: 'VID-2.mp4', modified: DateTime(2026, 11, 9, 9, 5, 7), size: 20),
    StatusItem(id: 'c', name: '.nomedia', modified: DateTime(2026, 11, 9), size: 0),
    StatusItem(id: 'd', name: 'IMG-1.jpg', modified: DateTime(2026, 11, 9, 8), size: 10),
    StatusItem(id: 'e', name: 'notes.txt', modified: DateTime(2026, 11, 9), size: 4),
  ];

  @override
  Future<StatusAccess> access() async => state;

  @override
  Future<StatusAccess> requestAccess() async {
    asked++;
    state = StatusAccess.granted;
    return state;
  }

  @override
  Future<List<StatusItem>> entries() async => items;

  @override
  Future<Uint8List> read(StatusItem item) async {
    if (item.id == 'b') {
      return Uint8List.fromList(<int>[0, 0, 0, 24, 0x66, 0x74, 0x79, 0x70]);
    }
    return photo;
  }
}

class FakeSink implements StatusSink {
  final Map<String, Uint8List> files = <String, Uint8List>{};

  @override
  Future<String> write(String name, Uint8List bytes) async {
    files['/statuses/$name'] = bytes;
    return '/statuses/$name';
  }

  @override
  Future<void> remove(String path) async => files.remove(path);
}

void main() {
  test('lists photos and videos only, newest first, without duplicates', () async {
    final StatusSaver saver = StatusSaver(FakeSource(StatusAccess.granted), FakeSink());
    final List<StatusItem> list = await saver.list();
    expect(list.map((StatusItem s) => s.name), <String>['VID-2.mp4', 'IMG-1.jpg']);
    expect(list.first.isVideo, isTrue);
    expect(StatusSaver.savedName(list.first), 'Status 2026-11-09 09.05.07.mp4');
  });

  test('on a desktop test run there is no WhatsApp folder to read', () async {
    final StatusAccess a = await const PhoneStatusSource().access();
    expect(a, Platform.isAndroid ? isNotNull : StatusAccess.unsupported);
  });

  testWidgets('ask for the folder, pick two statuses, keep them, undo', (WidgetTester tester) async {
    final FakeSource source = FakeSource(StatusAccess.needsGrant);
    final FakeSink sink = FakeSink();
    await tester.pumpWidget(MaterialApp(theme: buildAppTheme(), home: StatusSaverScreen(source: source, sink: sink)));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('status-allow')), findsOneWidget);
    expect(tester.getSize(find.byKey(const Key('status-allow'))).height, greaterThanOrEqualTo(44));

    await tester.tap(find.byKey(const Key('status-allow')));
    await tester.pumpAndSettle();
    expect(source.asked, 1);
    expect(find.byKey(const Key('status-IMG-1.jpg')), findsOneWidget);
    expect(find.byKey(const Key('status-VID-2.mp4')), findsOneWidget);
    expect(tester.getSize(find.byKey(const Key('status-IMG-1.jpg'))).width, greaterThanOrEqualTo(44));

    await tester.tap(find.byKey(const Key('status-IMG-1.jpg')));
    await tester.tap(find.byKey(const Key('status-VID-2.mp4')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('result-save')));
    await tester.pumpAndSettle();
    expect(sink.files.keys.toSet(), <String>{
      '/statuses/Status 2026-11-09 08.00.00.jpg',
      '/statuses/Status 2026-11-09 09.05.07.mp4',
    });
    expect(find.text('Kept 2 statuses in Files › statuses'), findsOneWidget);

    await tester.tap(find.byKey(const Key('result-undo')));
    await tester.pumpAndSettle();
    expect(sink.files, isEmpty);
  });

  testWidgets('unsupported phones get a plain explanation', (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: StatusSaverScreen(source: FakeSource(StatusAccess.unsupported), sink: FakeSink()),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('does not let other apps read statuses'), findsOneWidget);
  });
}
