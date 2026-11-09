import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';

import 'zip_codec.dart';

/// Feature 029 — Archives. Browse, extract and create archives on the phone.
///
/// ZIP is read and written in pure Dart ([ZipReader], [ZipWriter]). RAR and
/// 7Z go through [ArchivePlatform], a platform channel; when the phone has no
/// native handler the tool says so plainly instead of uploading anything.

enum ArchiveFormat { zip, rar, sevenZip, unknown }

extension ArchiveFormatLabel on ArchiveFormat {
  String get label {
    switch (this) {
      case ArchiveFormat.zip:
        return 'ZIP';
      case ArchiveFormat.rar:
        return 'RAR';
      case ArchiveFormat.sevenZip:
        return '7Z';
      case ArchiveFormat.unknown:
        return 'Unknown';
    }
  }
}

/// Recognises an archive by its first bytes, not by its name.
ArchiveFormat detectArchiveFormat(List<int> head) {
  bool starts(List<int> sig) {
    if (head.length < sig.length) {
      return false;
    }
    for (int i = 0; i < sig.length; i++) {
      if (head[i] != sig[i]) {
        return false;
      }
    }
    return true;
  }

  if (starts(const <int>[0x50, 0x4B, 0x03, 0x04]) || starts(const <int>[0x50, 0x4B, 0x05, 0x06])) {
    return ArchiveFormat.zip;
  }
  if (starts(const <int>[0x52, 0x61, 0x72, 0x21, 0x1A, 0x07])) {
    return ArchiveFormat.rar;
  }
  if (starts(const <int>[0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C])) {
    return ArchiveFormat.sevenZip;
  }
  return ArchiveFormat.unknown;
}

/// One row of an archive listing, whatever the format.
class ArchiveItem {
  const ArchiveItem({
    required this.path,
    required this.size,
    required this.isDirectory,
    this.encrypted = false,
    this.packedSize = 0,
  });

  final String path;
  final int size;
  final bool isDirectory;
  final bool encrypted;
  final int packedSize;

  String get name {
    final String trimmed = path.endsWith('/') ? path.substring(0, path.length - 1) : path;
    final int slash = trimmed.lastIndexOf('/');
    return slash < 0 ? trimmed : trimmed.substring(slash + 1);
  }
}

/// Native RAR and 7Z support. Paths are local files; nothing is uploaded.
abstract class ArchivePlatform {
  /// Null when this phone cannot read the format.
  Future<List<ArchiveItem>?> list(String archivePath, {String? password});

  /// Writes the chosen entries under [destination]; returns the written paths,
  /// or null when this phone cannot read the format.
  Future<List<String>?> extract(String archivePath, List<String> entries, String destination,
      {String? password});
}

class ChannelArchivePlatform implements ArchivePlatform {
  const ChannelArchivePlatform();

  static const MethodChannel _channel = MethodChannel('app.family/archives');

  @override
  Future<List<ArchiveItem>?> list(String archivePath, {String? password}) async {
    try {
      final List<Object?>? rows = await _channel.invokeListMethod<Object?>(
        'list',
        <String, Object?>{'path': archivePath, 'password': password},
      );
      if (rows == null) {
        return null;
      }
      return <ArchiveItem>[
        for (final Object? r in rows)
          if (r is Map)
            ArchiveItem(
              path: '${r['path']}',
              size: (r['size'] as int?) ?? 0,
              isDirectory: r['dir'] == true,
              encrypted: r['encrypted'] == true,
            ),
      ];
    } on MissingPluginException {
      return null;
    }
  }

  @override
  Future<List<String>?> extract(String archivePath, List<String> entries, String destination,
      {String? password}) async {
    try {
      final List<String>? out = await _channel.invokeListMethod<String>(
        'extract',
        <String, Object?>{
          'path': archivePath,
          'entries': entries,
          'destination': destination,
          'password': password,
        },
      );
      return out;
    } on MissingPluginException {
      return null;
    }
  }
}

/// An opened archive.
class OpenedArchive {
  OpenedArchive({
    required this.path,
    required this.format,
    required this.items,
    ZipReader? zip,
  }) : _zip = zip;

  final String path;
  final ArchiveFormat format;
  final List<ArchiveItem> items;
  final ZipReader? _zip;

  bool get anyEncrypted => items.any((ArchiveItem i) => i.encrypted);
  List<ArchiveItem> get files => items.where((ArchiveItem i) => !i.isDirectory).toList();
}

/// Turns an entry name into a safe relative path, or null if it tries to
/// escape the destination folder ("zip slip").
String? safeRelativePath(String entryName) {
  final List<String> parts = <String>[];
  for (final String part in entryName.replaceAll('\\', '/').split('/')) {
    if (part.isEmpty || part == '.') {
      continue;
    }
    if (part == '..' || part.contains(':')) {
      return null;
    }
    parts.add(part);
  }
  return parts.isEmpty ? null : parts.join('/');
}

class ArchiveEngine {
  ArchiveEngine({ArchivePlatform? platform, ZipWriter? writer})
      : platform = platform ?? const ChannelArchivePlatform(),
        _writer = writer ?? ZipWriter();

  final ArchivePlatform platform;
  final ZipWriter _writer;

  /// Reads the archive's table of contents. Nothing is extracted.
  Future<OpenedArchive> open(String path) async {
    final File f = File(path);
    final RandomAccessFile raf = await f.open();
    final Uint8List head;
    try {
      head = await raf.read(8);
    } finally {
      await raf.close();
    }
    final ArchiveFormat format = detectArchiveFormat(head);
    switch (format) {
      case ArchiveFormat.zip:
        final ZipReader zip = ZipReader(await f.readAsBytes());
        return OpenedArchive(
          path: path,
          format: format,
          zip: zip,
          items: <ArchiveItem>[
            for (final ZipEntry e in zip.entries)
              ArchiveItem(
                path: e.name,
                size: e.size,
                isDirectory: e.isDirectory,
                encrypted: e.encrypted,
                packedSize: e.compressedSize,
              ),
          ],
        );
      case ArchiveFormat.rar:
      case ArchiveFormat.sevenZip:
        final List<ArchiveItem>? items = await platform.list(path);
        if (items == null) {
          throw ArchiveException(
              '${format.label} files cannot be opened on this phone yet. Nothing was uploaded.');
        }
        return OpenedArchive(path: path, format: format, items: items);
      case ArchiveFormat.unknown:
        throw const ArchiveException('This file is not a ZIP, RAR or 7Z archive.');
    }
  }

  /// Extracts the chosen entries (all files when [selected] is empty) into
  /// [destination]. Returns the paths written.
  Future<List<String>> extract(
    OpenedArchive archive,
    Directory destination, {
    Iterable<String> selected = const <String>[],
    String? password,
  }) async {
    final Set<String> wanted = selected.toSet();
    final List<ArchiveItem> chosen = archive.files
        .where((ArchiveItem i) => wanted.isEmpty || wanted.contains(i.path))
        .toList();
    await destination.create(recursive: true);
    if (archive.format != ArchiveFormat.zip) {
      final List<String>? out = await platform.extract(
        archive.path,
        chosen.map((ArchiveItem i) => i.path).toList(),
        destination.path,
        password: password,
      );
      if (out == null) {
        throw ArchiveException('${archive.format.label} files cannot be extracted on this phone yet.');
      }
      return out;
    }
    final ZipReader zip = archive._zip!;
    // Decrypt and check everything first, so a wrong password writes nothing.
    final Map<String, Uint8List> data = <String, Uint8List>{};
    for (final ArchiveItem item in chosen) {
      final String? rel = safeRelativePath(item.path);
      if (rel == null) {
        continue;
      }
      data[rel] = zip.extract(zip.find(item.path)!, password: password);
    }
    final List<String> written = <String>[];
    for (final MapEntry<String, Uint8List> e in data.entries) {
      final File out = File('${destination.path}/${e.key}');
      await out.parent.create(recursive: true);
      await out.writeAsBytes(e.value, flush: true);
      written.add(out.path);
    }
    return written;
  }

  /// Builds a ZIP from files on the phone. [password] turns on AES-256.
  Future<File> createZip(List<String> sources, File output, {String? password}) async {
    final List<ZipInput> inputs = <ZipInput>[];
    final Set<String> names = <String>{};
    for (final String src in sources) {
      final File f = File(src);
      String name = src.substring(src.lastIndexOf('/') + 1);
      if (!names.add(name)) {
        final int dot = name.lastIndexOf('.');
        int n = 2;
        String candidate;
        do {
          candidate = dot > 0 ? '${name.substring(0, dot)} ($n)${name.substring(dot)}' : '$name ($n)';
          n++;
        } while (!names.add(candidate));
        name = candidate;
      }
      inputs.add(ZipInput(name, await f.readAsBytes(), modified: await f.lastModified()));
    }
    await output.parent.create(recursive: true);
    return output.writeAsBytes(_writer.build(inputs, password: password), flush: true);
  }
}
