import 'dart:convert';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../archive/zip_codec.dart';
import 'file_kind.dart';

/// Feature 030 — Convert anything.
///
/// One registry of converters. A tool asks "what can this file become?" and
/// gets every registered converter that accepts the file's real type, so a
/// converter added later shows up everywhere without touching the UI.

/// Why a conversion failed, in words a person can act on.
class ConvertException implements Exception {
  const ConvertException(this.message);
  final String message;

  @override
  String toString() => 'ConvertException: $message';
}

/// A file in memory, with the name it came with.
class ConvertInput {
  const ConvertInput({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;

  String get stem {
    final int dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }
}

class ConvertOutput {
  const ConvertOutput({required this.name, required this.bytes, required this.kind});

  final String name;
  final Uint8List bytes;
  final FileKind kind;
}

/// One way to turn a file into another format.
abstract class Converter {
  const Converter();

  /// Stable id, e.g. `image-to-png`.
  String get id;

  /// What the person sees, e.g. "PNG image".
  String get label;

  /// The type it produces.
  FileKind get target;

  /// True when this converter can take a file of [kind].
  bool accepts(FileKind kind);

  Future<ConvertOutput> convert(ConvertInput input, FileKind kind);

  ConvertOutput output(ConvertInput input, Uint8List bytes) =>
      ConvertOutput(name: '${input.stem}.${target.extension}', bytes: bytes, kind: target);
}

/// Re-encodes any image the `image` package can decode into [target].
class ImageConverter extends Converter {
  const ImageConverter(this.target, {this.jpegQuality = 92});

  @override
  final FileKind target;
  final int jpegQuality;

  static const Set<FileKind> _decodable = <FileKind>{
    FileKind.jpeg,
    FileKind.png,
    FileKind.gif,
    FileKind.webp,
    FileKind.bmp,
    FileKind.tiff,
  };

  @override
  String get id => 'image-to-${target.extension}';

  @override
  String get label => '${target.label} image';

  @override
  bool accepts(FileKind kind) => _decodable.contains(kind) && kind != target;

  @override
  Future<ConvertOutput> convert(ConvertInput input, FileKind kind) async {
    final img.Image? decoded = img.decodeImage(input.bytes);
    if (decoded == null) {
      throw const ConvertException('This image could not be read. It may be damaged.');
    }
    final img.Image im = img.bakeOrientation(decoded);
    final Uint8List bytes;
    switch (target) {
      case FileKind.png:
        bytes = img.encodePng(im, level: 6);
      case FileKind.jpeg:
        bytes = img.encodeJpg(_opaque(im), quality: jpegQuality);
      case FileKind.bmp:
        bytes = img.encodeBmp(im);
      case FileKind.gif:
        bytes = img.encodeGif(im);
      case FileKind.tiff:
        bytes = img.encodeTiff(im);
      default:
        throw ConvertException('Cannot write ${target.label} images yet.');
    }
    return output(input, bytes);
  }

  static img.Image _opaque(img.Image src) {
    if (!src.hasAlpha) {
      return src;
    }
    final img.Image bg = img.Image(width: src.width, height: src.height);
    img.fill(bg, color: img.ColorRgb8(255, 255, 255));
    return img.compositeImage(bg, src);
  }
}

/// A JSON array of objects becomes a CSV table (columns in first-seen order).
class JsonToCsvConverter extends Converter {
  const JsonToCsvConverter();

  @override
  String get id => 'json-to-csv';
  @override
  String get label => 'CSV table';
  @override
  FileKind get target => FileKind.csv;
  @override
  bool accepts(FileKind kind) => kind == FileKind.json;

  @override
  Future<ConvertOutput> convert(ConvertInput input, FileKind kind) async {
    final Object? data = jsonDecode(utf8.decode(input.bytes));
    final List<Object?> list = data is List ? data : <Object?>[data];
    final List<String> columns = <String>[];
    for (final Object? row in list) {
      if (row is! Map) {
        throw const ConvertException('Only a list of objects can become a table.');
      }
      for (final Object? k in row.keys) {
        if (!columns.contains('$k')) {
          columns.add('$k');
        }
      }
    }
    String cell(Object? v) => v == null ? '' : (v is String ? v : jsonEncode(v));
    final List<List<String>> rows = <List<String>>[
      columns,
      for (final Object? row in list) <String>[for (final String c in columns) cell((row! as Map)[c])],
    ];
    return output(input, Uint8List.fromList(utf8.encode(writeCsv(rows))));
  }
}

/// A CSV with a header row becomes a JSON list of objects.
class CsvToJsonConverter extends Converter {
  const CsvToJsonConverter();

  @override
  String get id => 'csv-to-json';
  @override
  String get label => 'JSON list';
  @override
  FileKind get target => FileKind.json;
  @override
  bool accepts(FileKind kind) => kind == FileKind.csv;

  @override
  Future<ConvertOutput> convert(ConvertInput input, FileKind kind) async {
    final List<List<String>> rows = parseCsv(utf8.decode(input.bytes, allowMalformed: true));
    if (rows.isEmpty) {
      throw const ConvertException('This CSV is empty.');
    }
    final List<String> header = rows.first;
    final List<Map<String, String>> out = <Map<String, String>>[
      for (final List<String> r in rows.skip(1))
        <String, String>{
          for (int i = 0; i < header.length; i++) header[i]: i < r.length ? r[i] : '',
        },
    ];
    const JsonEncoder pretty = JsonEncoder.withIndent('  ');
    return output(input, Uint8List.fromList(utf8.encode(pretty.convert(out))));
  }
}

/// Any text (JSON and CSV included) as plain text.
class ToTextConverter extends Converter {
  const ToTextConverter();

  @override
  String get id => 'to-text';
  @override
  String get label => 'Plain text';
  @override
  FileKind get target => FileKind.text;
  @override
  bool accepts(FileKind kind) => kind == FileKind.json || kind == FileKind.csv;

  @override
  Future<ConvertOutput> convert(ConvertInput input, FileKind kind) async {
    String s = utf8.decode(input.bytes, allowMalformed: true);
    if (kind == FileKind.json) {
      s = const JsonEncoder.withIndent('  ').convert(jsonDecode(s));
    }
    return output(input, Uint8List.fromList(utf8.encode(s)));
  }
}

/// Any file can go into a ZIP.
class ToZipConverter extends Converter {
  const ToZipConverter();

  @override
  String get id => 'to-zip';
  @override
  String get label => 'ZIP archive';
  @override
  FileKind get target => FileKind.zip;
  @override
  bool accepts(FileKind kind) => kind != FileKind.zip;

  @override
  Future<ConvertOutput> convert(ConvertInput input, FileKind kind) async {
    final Uint8List zip = ZipWriter().build(<ZipInput>[ZipInput(input.name, input.bytes)]);
    return output(input, zip);
  }
}

class ConvertRegistry {
  ConvertRegistry([Iterable<Converter> converters = const <Converter>[]]) {
    converters.forEach(register);
  }

  /// The built-in converters; features add theirs with [register].
  factory ConvertRegistry.builtIn() => ConvertRegistry(const <Converter>[
        ImageConverter(FileKind.jpeg),
        ImageConverter(FileKind.png),
        ImageConverter(FileKind.bmp),
        ImageConverter(FileKind.gif),
        ImageConverter(FileKind.tiff),
        CsvToJsonConverter(),
        JsonToCsvConverter(),
        ToTextConverter(),
        ToZipConverter(),
      ]);

  static ConvertRegistry instance = ConvertRegistry.builtIn();

  final List<Converter> _converters = <Converter>[];

  List<Converter> get all => List<Converter>.unmodifiable(_converters);

  /// Adds a converter; one with the same id is replaced.
  void register(Converter c) {
    _converters
      ..removeWhere((Converter e) => e.id == c.id)
      ..add(c);
  }

  /// Every format a file of [kind] can become, never its own format.
  List<Converter> targetsFor(FileKind kind) =>
      _converters.where((Converter c) => c.accepts(kind) && c.target != kind).toList();

  /// Reads the file's real type, then lists what it can become.
  List<Converter> targetsForBytes(Uint8List bytes) => targetsFor(sniffFileKind(bytes));

  Future<ConvertOutput> convert(ConvertInput input, String converterId) async {
    final FileKind kind = sniffFileKind(input.bytes);
    for (final Converter c in targetsFor(kind)) {
      if (c.id == converterId) {
        return c.convert(input, kind);
      }
    }
    throw ConvertException('${kind.label} files cannot be turned into that.');
  }
}
