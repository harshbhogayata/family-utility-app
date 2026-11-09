import 'dart:convert';
import 'dart:typed_data';

import 'package:family_utility_app/app/theme.dart';
import 'package:family_utility_app/engines/share/cloud_bridge.dart';
import 'package:family_utility_app/tools/cloud/cloud_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakePicker implements DocumentPicker {
  final List<(String, Uint8List)> savedAs = <(String, Uint8List)>[];

  @override
  Future<List<PickedDocument>> open({bool multiple = true}) async => <PickedDocument>[
        PickedDocument('rent.pdf', Uint8List.fromList(utf8.encode('%PDF-1.4'))),
        PickedDocument('photo.jpg', Uint8List.fromList(<int>[0xFF, 0xD8])),
      ];

  @override
  Future<String?> saveAs(String name, Uint8List bytes) async {
    savedAs.add((name, bytes));
    return 'Google Drive › Family/$name';
  }
}

class FakeSink implements ImportSink {
  final Map<String, Uint8List> files = <String, Uint8List>{};

  @override
  Future<String> write(String name, Uint8List bytes) async {
    files['/imported/$name'] = bytes;
    return '/imported/$name';
  }

  @override
  Future<void> remove(String path) async => files.remove(path);
}

void main() {
  test('imports copy into Files; the default and the last place are remembered', () async {
    final MemoryCloudPrefsStore store = MemoryCloudPrefsStore();
    final FakePicker picker = FakePicker();
    final CloudBridge b = CloudBridge(picker: picker, sink: FakeSink(), store: store);
    await b.load();
    expect(b.saveDefault, SaveDefault.ask);
    expect(await b.import(), <String>['/imported/rent.pdf', '/imported/photo.jpg']);
    await b.setDefault(SaveDefault.cloud);
    expect(await b.saveToCloud('rent.pdf', Uint8List(3)), 'Google Drive › Family/rent.pdf');

    final CloudBridge again = CloudBridge(picker: picker, sink: FakeSink(), store: store);
    await again.load();
    expect(again.saveDefault, SaveDefault.cloud);
    expect(again.lastSavedTo, 'Google Drive › Family/rent.pdf');

    store.value = 'not json';
    final CloudBridge damaged = CloudBridge(picker: picker, sink: FakeSink(), store: store);
    await damaged.load();
    expect(damaged.saveDefault, SaveDefault.ask);
  });

  testWidgets('import, save one back to the cloud, undo the import', (WidgetTester tester) async {
    final FakePicker picker = FakePicker();
    final FakeSink sink = FakeSink();
    final CloudBridge b = CloudBridge(picker: picker, sink: sink, store: MemoryCloudPrefsStore());
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: CloudScreen(bridge: b, readFile: (String p) async => sink.files[p]!),
    ));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byKey(const Key('cloud-import'))).height, greaterThanOrEqualTo(44));
    await tester.tap(find.byKey(const Key('cloud-import')));
    await tester.pumpAndSettle();
    expect(sink.files.length, 2);
    expect(find.textContaining('Copied 2 files'), findsOneWidget);

    await tester.tap(find.byKey(const Key('cloud-save-rent.pdf')));
    await tester.pumpAndSettle();
    expect(picker.savedAs.single.$1, 'rent.pdf');
    expect(find.text('Last saved to Google Drive › Family/rent.pdf'), findsOneWidget);

    await tester.tap(find.byKey(const Key('result-undo')));
    await tester.pumpAndSettle();
    expect(sink.files.keys, <String>['/imported/rent.pdf']);
  });
}
