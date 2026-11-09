import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:family_utility_app/app/theme.dart';
import 'package:family_utility_app/engines/pdf/print_to_pdf.dart';
import 'package:family_utility_app/engines/share/share_engine.dart';
import 'package:family_utility_app/tools/print_to_pdf/print_to_pdf_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List pdfBytes(String body) => Uint8List.fromList(utf8.encode('%PDF-1.4\n% $body\n%%EOF\n'));

class _Sheet implements ShareSheet {
  final List<ShareRequest> sent = <ShareRequest>[];

  @override
  Future<ShareOutcome> share(ShareRequest request) async {
    sent.add(request);
    return const ShareOutcome.dismissed();
  }
}

class _Platform implements PrintToPdfPlatform {
  int opened = 0;

  @override
  Future<bool> openPrintSettings() async {
    opened++;
    return true;
  }
}

void main() {
  late Directory root;
  late PrintedPdfs pdfs;

  setUp(() {
    root = Directory.systemTemp.createTempSync('print_to_pdf_');
    pdfs = PrintedPdfs(
      folder: () async => Directory('${root.path}/printed'),
      savedFolder: () async => Directory('${root.path}/Saved'),
    );
  });

  tearDown(() {
    if (root.existsSync()) {
      root.deleteSync(recursive: true);
    }
  });

  group('names', () {
    test('job labels become safe PDF names', () {
      expect(PrintToPdfNames.fileName('Boarding pass: DEL→BOM'), 'Boarding pass DEL BOM.pdf');
      expect(PrintToPdfNames.fileName('Invoice.pdf'), 'Invoice.pdf');
      expect(PrintToPdfNames.fileName('../../etc/passwd'), 'etc passwd.pdf');
      expect(PrintToPdfNames.fileName(''), 'Printed.pdf');
      expect(PrintToPdfNames.fileName(null), 'Printed.pdf');
      expect(PrintToPdfNames.fileName('x' * 100), '${'x' * 60}.pdf');
    });

    test('taken names get a number', () {
      final Set<String> taken = <String>{'a.pdf', 'a (2).pdf'};
      expect(PrintToPdfNames.unique('a.pdf', taken.contains), 'a (3).pdf');
      expect(PrintToPdfNames.unique('b.pdf', taken.contains), 'b.pdf');
    });

    test('only real PDFs pass the header check', () {
      expect(looksLikePdf(pdfBytes('ok')), isTrue);
      expect(looksLikePdf(utf8.encode('hello')), isFalse);
      expect(looksLikePdf(<int>[0x25]), isFalse);
    });
  });

  group('engine', () {
    test('lists printed PDFs newest first and skips half-written jobs', () async {
      final Directory dir = Directory('${root.path}/printed')..createSync(recursive: true);
      File('${dir.path}/old.pdf')
        ..writeAsBytesSync(pdfBytes('old'))
        ..setLastModifiedSync(DateTime(2024));
      File('${dir.path}/new.pdf').writeAsBytesSync(pdfBytes('new'));
      File('${dir.path}/busy.pdf.part').writeAsBytesSync(pdfBytes('busy'));
      File('${dir.path}/note.txt').writeAsStringSync('not a pdf');
      await pdfs.refresh();
      expect(pdfs.items.map((PrintedPdf p) => p.name), <String>['new.pdf', 'old.pdf']);
    });

    test('a missing folder is an empty list', () async {
      await pdfs.refresh();
      expect(pdfs.items, isEmpty);
    });

    test('add files a job under its label, never twice the same name', () async {
      final PrintedPdf a = await pdfs.add('Ticket', pdfBytes('1'));
      final PrintedPdf b = await pdfs.add('Ticket', pdfBytes('2'));
      expect(a.name, 'Ticket.pdf');
      expect(b.name, 'Ticket (2).pdf');
      expect(File(b.path).readAsBytesSync(), pdfBytes('2'));
      expect(Directory('${root.path}/printed').listSync().where((FileSystemEntity e) => e.path.endsWith('.part')), isEmpty);
      await expectLater(pdfs.add('junk', Uint8List.fromList(<int>[1, 2, 3])), throwsA(isA<PrintToPdfError>()));
    });

    test('keep copies into Saved; undo removes the copy', () async {
      final PrintedPdf a = await pdfs.add('Form', pdfBytes('f'));
      final String copy = await pdfs.keep(a);
      expect(copy, '${root.path}/Saved/Form.pdf');
      expect(File(copy).readAsBytesSync(), pdfBytes('f'));
      expect(await pdfs.undo(), 'Removed Form.pdf');
      expect(File(copy).existsSync(), isFalse);
      expect(File(a.path).existsSync(), isTrue);
    });

    test('remove deletes; undo puts the same bytes back', () async {
      final PrintedPdf a = await pdfs.add('Bill', pdfBytes('b'));
      await pdfs.remove(a);
      expect(File(a.path).existsSync(), isFalse);
      expect(pdfs.items, isEmpty);
      expect(await pdfs.undo(), 'Restored Bill.pdf');
      expect(File(a.path).readAsBytesSync(), pdfBytes('b'));
      expect(pdfs.items.single.name, 'Bill.pdf');
    });

    test('iOS: PDFs shared into the inbox are copied once and left in place', () async {
      final Directory inbox = Directory('${root.path}/Inbox')..createSync();
      File('${inbox.path}/Receipt.pdf').writeAsBytesSync(pdfBytes('r'));
      File('${inbox.path}/photo.jpg').writeAsBytesSync(<int>[0xFF, 0xD8]);
      File('${inbox.path}/fake.pdf').writeAsStringSync('nope');
      final List<PrintedPdf> first = await pdfs.adoptInbox(inbox.path);
      expect(first.map((PrintedPdf p) => p.name), <String>['Receipt.pdf']);
      expect(File('${inbox.path}/Receipt.pdf').existsSync(), isTrue);
      expect(await pdfs.adoptInbox(inbox.path), isEmpty);
      expect(pdfs.items.single.name, 'Receipt.pdf');
      expect(await pdfs.adoptInbox('${root.path}/nowhere'), isEmpty);
    });
  });

  group('platform registration', () {
    test('Android: a print service bound to the system print framework', () {
      final String manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
      final int at = manifest.indexOf('android:name=".PdfPrintService"');
      expect(at, greaterThan(0));
      final String block = manifest.substring(at, manifest.indexOf('</service>', at));
      expect(block, contains('android:permission="android.permission.BIND_PRINT_SERVICE"'));
      expect(block, contains('android.printservice.PrintService'));
      expect(block, contains('android:exported="true"'));
    });

    test('Android: the service writes into the folder Dart lists, with the same names', () {
      final String kt =
          File('android/app/src/main/kotlin/app/family/family_utility_app/PdfPrintService.kt').readAsStringSync();
      expect(kt, contains('getDir("flutter", Context.MODE_PRIVATE)'));
      expect(kt, contains('const val FOLDER = "${PrintToPdfNames.folder}"'));
      expect(kt, contains('const val PART = "${PrintToPdfNames.partSuffix}"'));
      expect(kt, contains('const val PRINTER_NAME = "${PrintToPdfNames.printerName}"'));
      expect(kt, contains('printJob.complete()'));
      expect(kt, isNot(contains('java.net')));
      final String main =
          File('android/app/src/main/kotlin/app/family/family_utility_app/MainActivity.kt').readAsStringSync();
      expect(main, contains('"app.family/print_to_pdf"'));
      expect(main, contains('Settings.ACTION_PRINT_SETTINGS'));
    });

    test('iOS: PDFs are a registered document type, so Share > this app works', () {
      final String plist = File('ios/Runner/Info.plist').readAsStringSync();
      expect(plist, contains('CFBundleDocumentTypes'));
      expect(plist, contains('com.adobe.pdf'));
    });

    test('the engine and screen never reach the network', () {
      for (final String path in <String>[
        'lib/engines/pdf/print_to_pdf.dart',
        'lib/tools/print_to_pdf/print_to_pdf_screen.dart',
      ]) {
        final String src = File(path).readAsStringSync();
        expect(src, isNot(contains('HttpClient')), reason: path);
        expect(src, isNot(contains('package:http')), reason: path);
      }
    });
  });

  group('screen', () {
    Future<void> settle(WidgetTester tester) async {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pump();
    }

    Widget app(Widget child) => MaterialApp(theme: buildAppTheme(), home: child);

    testWidgets('Android: how-to, settings button, list and Share / Save / Undo', (WidgetTester tester) async {
      await tester.runAsync(() => pdfs.add('Ticket', pdfBytes('t')));
      final _Sheet sheet = _Sheet();
      final _Platform platform = _Platform();
      await tester.pumpWidget(app(PrintToPdfScreen(
        pdfs: pdfs,
        platform: platform,
        inboxDir: () async => null,
        share: ShareEngine(sheet, MemoryShareTargetStore()),
        isIos: false,
      )));
      await settle(tester);

      expect(find.textContaining(PrintToPdfNames.printerName), findsWidgets);
      expect(find.byKey(const Key('printed-Ticket.pdf')), findsOneWidget);
      expect(find.byKey(const Key('result-share')), findsOneWidget);
      expect(find.byKey(const Key('result-save')), findsOneWidget);
      expect(find.byKey(const Key('result-undo')), findsOneWidget);

      await tester.tap(find.byKey(const Key('print-settings')));
      await settle(tester);
      expect(platform.opened, 1);

      await tester.tap(find.byKey(const Key('result-share')));
      await settle(tester);
      expect(sheet.sent.single.files.single.name, 'Ticket.pdf');

      await tester.tap(find.byKey(const Key('result-save')));
      await settle(tester);
      expect(File('${root.path}/Saved/Ticket.pdf').existsSync(), isTrue);

      await tester.tap(find.byKey(const Key('result-undo')));
      await settle(tester);
      expect(File('${root.path}/Saved/Ticket.pdf').existsSync(), isFalse);

      await tester.tap(find.byKey(const Key('printed-remove-Ticket.pdf')));
      await settle(tester);
      expect(find.byKey(const Key('print-empty')), findsOneWidget);

      await tester.tap(find.byKey(const Key('result-undo')));
      await settle(tester);
      expect(find.byKey(const Key('printed-Ticket.pdf')), findsOneWidget);
    });

    testWidgets('iOS: share-sheet how-to and the inbox PDF shows up', (WidgetTester tester) async {
      final Directory inbox = Directory('${root.path}/Inbox')..createSync();
      File('${inbox.path}/Receipt.pdf').writeAsBytesSync(pdfBytes('r'));
      await tester.pumpWidget(app(PrintToPdfScreen(
        pdfs: pdfs,
        platform: _Platform(),
        inboxDir: () async => inbox.path,
        isIos: true,
      )));
      await settle(tester);
      expect(find.byKey(const Key('print-settings')), findsNothing);
      expect(find.textContaining('Share in the print preview'), findsOneWidget);
      expect(find.byKey(const Key('printed-Receipt.pdf')), findsOneWidget);
    });

    testWidgets('touch targets are at least 44 px and labelled', (WidgetTester tester) async {
      await tester.runAsync(() => pdfs.add('Ticket', pdfBytes('t')));
      final SemanticsHandle handle = tester.ensureSemantics();
      await tester.pumpWidget(app(PrintToPdfScreen(
        pdfs: pdfs,
        platform: _Platform(),
        inboxDir: () async => null,
        isIos: false,
      )));
      await settle(tester);
      for (final Key k in <Key>[
        const Key('print-settings'),
        const Key('printed-remove-Ticket.pdf'),
        const Key('result-share'),
        const Key('result-save'),
        const Key('result-undo'),
      ]) {
        final Size s = tester.getSize(find.byKey(k));
        expect(s.height, greaterThanOrEqualTo(44), reason: '$k');
      }
      expect(find.bySemanticsLabel(RegExp('Remove Ticket')), findsWidgets);
      handle.dispose();
    });
  });

  test('the method channel is the one MainActivity answers', () {
    expect(ChannelPrintToPdfPlatform.channel.name, 'app.family/print_to_pdf');
    expect(ChannelPrintToPdfPlatform.channel, isA<MethodChannel>());
  });
}
