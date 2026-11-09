import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Feature 017 — Print to PDF.
///
/// Android: `PdfPrintService` (Kotlin) adds a printer called
/// [PrintToPdfNames.printerName] to every app's print dialog and writes each
/// job into the app's `printed` folder. iOS: the print preview's Share button
/// sends the PDF to this app (document types from feature 065), and
/// [PrintedPdfs.adoptInbox] files it here. This engine lists those PDFs, keeps a
/// copy, removes one and undoes the last step. Nothing leaves the phone.

abstract final class PrintToPdfNames {
  /// Folder under the app's documents directory the print service writes to.
  static const String folder = 'printed';

  /// A job still being written ends in this; it is never listed.
  static const String partSuffix = '.part';

  /// Shown in Android's print dialog (and in PdfPrintService.kt).
  static const String printerName = 'Save as PDF (Family)';

  /// Turns a print job's label into a safe file name. Same rule as Kotlin's
  /// `PdfPrintService.fileName`.
  static String fileName(String? label) {
    String base = (label ?? '').replaceAll(RegExp(r'[^A-Za-z0-9 ._-]'), ' ');
    base = base.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (base.toLowerCase().endsWith('.pdf')) {
      base = base.substring(0, base.length - 4).trim();
    }
    base = base.replaceFirst(RegExp(r'^[. ]+'), '');
    if (base.length > 60) {
      base = base.substring(0, 60).trim();
    }
    if (base.isEmpty) {
      base = 'Printed';
    }
    return '$base.pdf';
  }

  /// [name], or `name (2).pdf`, `name (3).pdf` … when taken.
  static String unique(String name, bool Function(String candidate) taken) {
    if (!taken(name)) {
      return name;
    }
    final String stem = name.substring(0, name.length - 4);
    int i = 2;
    while (taken('$stem ($i).pdf')) {
      i++;
    }
    return '$stem ($i).pdf';
  }
}

/// True when [bytes] start like a PDF (`%PDF-`).
bool looksLikePdf(List<int> bytes) {
  const List<int> magic = <int>[0x25, 0x50, 0x44, 0x46, 0x2D];
  if (bytes.length < magic.length) {
    return false;
  }
  for (int i = 0; i < magic.length; i++) {
    if (bytes[i] != magic[i]) {
      return false;
    }
  }
  return true;
}

/// One PDF a print or share produced.
@immutable
class PrintedPdf {
  const PrintedPdf({required this.path, required this.size, required this.received});

  final String path;
  final int size;
  final DateTime received;

  String get name => path.split('/').last;

  @override
  bool operator ==(Object other) => other is PrintedPdf && other.path == path;

  @override
  int get hashCode => path.hashCode;
}

class PrintToPdfError implements Exception {
  const PrintToPdfError(this.message);

  final String message;

  @override
  String toString() => message;
}

typedef FolderProvider = Future<Directory> Function();

/// The printed PDFs in the app's files, newest first.
class PrintedPdfs extends ChangeNotifier {
  PrintedPdfs({required this.folder, required this.savedFolder});

  /// Where the print service writes (`<documents>/printed`).
  final FolderProvider folder;

  /// Where Save keeps a copy (`<documents>/Saved`).
  final FolderProvider savedFolder;

  List<PrintedPdf> _items = const <PrintedPdf>[];
  final List<_Step> _undo = <_Step>[];

  List<PrintedPdf> get items => _items;

  bool get canUndo => _undo.isNotEmpty;

  Future<void> refresh() async {
    final Directory dir = await folder();
    final List<PrintedPdf> out = <PrintedPdf>[];
    if (dir.existsSync()) {
      await for (final FileSystemEntity e in dir.list(followLinks: false)) {
        if (e is! File) {
          continue;
        }
        final String lower = e.path.toLowerCase();
        if (lower.endsWith(PrintToPdfNames.partSuffix) || !lower.endsWith('.pdf')) {
          continue;
        }
        final FileStat s = await e.stat();
        out.add(PrintedPdf(path: e.path, size: s.size, received: s.modified));
      }
    }
    out.sort((PrintedPdf a, PrintedPdf b) {
      final int byTime = b.received.compareTo(a.received);
      return byTime != 0 ? byTime : a.name.compareTo(b.name);
    });
    _items = List<PrintedPdf>.unmodifiable(out);
    notifyListeners();
  }

  /// Files [bytes] as a printed PDF named after [label]. Written to a `.part`
  /// file first, so a half-written job is never listed.
  Future<PrintedPdf> add(String? label, Uint8List bytes) async {
    if (!looksLikePdf(bytes)) {
      throw const PrintToPdfError('That is not a PDF, so it was not saved.');
    }
    final Directory dir = await folder();
    await dir.create(recursive: true);
    final String name = PrintToPdfNames.unique(
      PrintToPdfNames.fileName(label),
      (String n) => File('${dir.path}/$n').existsSync(),
    );
    final File part = File('${dir.path}/$name${PrintToPdfNames.partSuffix}');
    await part.writeAsBytes(bytes, flush: true);
    final File done = await part.rename('${dir.path}/$name');
    _undo.add(_Step.added(done.path));
    await refresh();
    return _items.firstWhere((PrintedPdf p) => p.path == done.path);
  }

  /// iOS: PDFs the print preview shared into the app land in
  /// `Documents/Inbox` (feature 065 opens them too, so they are copied, not
  /// moved). Each inbox file is copied here once; a hidden list in this
  /// folder remembers which. Returns the PDFs added.
  Future<List<PrintedPdf>> adoptInbox(String inboxDir) async {
    final Directory inbox = Directory(inboxDir);
    if (!inbox.existsSync()) {
      return const <PrintedPdf>[];
    }
    final Directory dir = await folder();
    await dir.create(recursive: true);
    final File marker = File('${dir.path}/$adoptedListName');
    final Set<String> done = marker.existsSync()
        ? (await marker.readAsLines()).where((String l) => l.isNotEmpty).toSet()
        : <String>{};
    final List<File> files = inbox.listSync().whereType<File>().toList()
      ..sort((File a, File b) => a.statSync().modified.compareTo(b.statSync().modified));
    final List<PrintedPdf> added = <PrintedPdf>[];
    for (final File f in files) {
      final String key = f.path.split('/').last;
      if (done.contains(key) || !key.toLowerCase().endsWith('.pdf')) {
        continue;
      }
      final Uint8List bytes = await f.readAsBytes();
      done.add(key);
      if (!looksLikePdf(bytes)) {
        continue;
      }
      added.add(await add(key, bytes));
    }
    await marker.writeAsString(done.join('\n'), flush: true);
    return added;
  }

  /// Hidden file in [folder] listing inbox names already copied.
  static const String adoptedListName = '.adopted';

  /// Copies [pdf] into the Saved folder; returns the copy's path.
  Future<String> keep(PrintedPdf pdf) async {
    final Directory dir = await savedFolder();
    await dir.create(recursive: true);
    final String name = PrintToPdfNames.unique(pdf.name, (String n) => File('${dir.path}/$n').existsSync());
    final File copy = await File(pdf.path).copy('${dir.path}/$name');
    _undo.add(_Step.added(copy.path));
    notifyListeners();
    return copy.path;
  }

  /// Deletes [pdf]; Undo puts it back.
  Future<void> remove(PrintedPdf pdf) async {
    final File f = File(pdf.path);
    if (!f.existsSync()) {
      await refresh();
      return;
    }
    final Uint8List bytes = await f.readAsBytes();
    await f.delete();
    _undo.add(_Step.removed(pdf.path, bytes));
    await refresh();
  }

  /// Reverses the last add, keep or remove. Returns what was undone, or null.
  Future<String?> undo() async {
    if (_undo.isEmpty) {
      return null;
    }
    final _Step step = _undo.removeLast();
    final File f = File(step.path);
    final String name = step.path.split('/').last;
    if (step.bytes == null) {
      if (f.existsSync()) {
        await f.delete();
      }
      await refresh();
      return 'Removed $name';
    }
    await f.parent.create(recursive: true);
    await f.writeAsBytes(step.bytes!, flush: true);
    await refresh();
    return 'Restored $name';
  }
}

class _Step {
  _Step.added(this.path) : bytes = null;

  _Step.removed(this.path, Uint8List this.bytes);

  final String path;

  /// Null for a file this engine wrote (undo deletes it); the old contents for
  /// a removed file (undo writes them back).
  final Uint8List? bytes;
}

/// The bits only the phone can do: open the system's print settings.
abstract class PrintToPdfPlatform {
  /// Android: Settings > Printing, where the service is switched on.
  Future<bool> openPrintSettings();
}

class ChannelPrintToPdfPlatform implements PrintToPdfPlatform {
  const ChannelPrintToPdfPlatform();

  static const MethodChannel channel = MethodChannel('app.family/print_to_pdf');

  @override
  Future<bool> openPrintSettings() async {
    try {
      return await channel.invokeMethod<bool>('openPrintSettings') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}
