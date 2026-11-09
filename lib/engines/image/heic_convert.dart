import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../convert/convert_registry.dart';
import '../convert/file_kind.dart';
import 'webp_convert.dart' show ImageTarget;

/// Feature 025 — HEIC to JPG or PNG.
///
/// iPhone photos (HEIC/HEIF) are decoded by the phone's own codec behind
/// [HeicCodec] (HEVC has no pure-Dart decoder) and come out upright, with
/// the EXIF orientation applied. Other pictures in the same batch go
/// through the pure-Dart path. Results keep the order the pictures were
/// shared or picked in. Nothing leaves the phone.

class HeicConvertError implements Exception {
  const HeicConvertError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// The phone's HEIC decoder: HEIC bytes in, upright JPG or PNG out.
abstract class HeicCodec {
  Future<Uint8List> convert(Uint8List heic, ImageTarget target, {int quality = 92});
}

/// One picture turned into JPG or PNG.
class ConvertedPicture {
  const ConvertedPicture(this.name, this.bytes);
  final String name;
  final Uint8List bytes;
}

/// What happened to one picture of a batch, in input order.
class PictureResult {
  const PictureResult({required this.source, this.outputPath, this.error});

  final String source;
  final String? outputPath;
  final String? error;

  bool get ok => outputPath != null;
}

String _outName(String name, ImageTarget target) {
  final int dot = name.lastIndexOf('.');
  return '${dot > 0 ? name.substring(0, dot) : name}.${target.extension}';
}

class PictureConverter {
  const PictureConverter(this.codec, {this.quality = 92});

  final HeicCodec codec;
  final int quality;

  Future<Uint8List> _platform(Uint8List bytes, ImageTarget target) async {
    try {
      return await codec.convert(bytes, target, quality: quality);
    } on HeicConvertError {
      rethrow;
    } catch (_) {
      throw const HeicConvertError('This phone could not open this HEIC photo');
    }
  }

  /// Turns one picture (HEIC or anything the app reads) into [target].
  Future<ConvertedPicture> convert(Uint8List bytes, String name, ImageTarget target) async {
    if (target == ImageTarget.webp) {
      throw const HeicConvertError('Pick JPG or PNG');
    }
    final String out = _outName(name, target);
    final FileKind kind = sniffFileKind(bytes);
    if (kind == FileKind.heic) {
      final Uint8List result = await _platform(bytes, target);
      final FileKind got = sniffFileKind(result);
      final FileKind want = target == ImageTarget.png ? FileKind.png : FileKind.jpeg;
      if (result.isEmpty || got != want) {
        throw const HeicConvertError('This phone could not open this HEIC photo');
      }
      return ConvertedPicture(out, result);
    }
    img.Image? decoded;
    try {
      decoded = img.decodeImage(bytes);
    } catch (_) {
      decoded = null;
    }
    if (decoded == null) {
      throw const HeicConvertError('This file is not a picture the app can read');
    }
    final img.Image up = img.bakeOrientation(decoded);
    if (target == ImageTarget.png) {
      return ConvertedPicture(out, img.encodePng(up, level: 6));
    }
    img.Image flat = up;
    if (up.hasAlpha) {
      flat = img.Image(width: up.width, height: up.height);
      img.fill(flat, color: img.ColorRgb8(255, 255, 255));
      img.compositeImage(flat, up);
    }
    return ConvertedPicture(out, img.encodeJpg(flat, quality: quality));
  }

  /// Converts every path in order. A picture that fails is reported and the
  /// rest still run. [progress] is told after each picture.
  Future<List<PictureResult>> convertAll(
    List<String> paths,
    ImageTarget target, {
    required Future<Uint8List> Function(String path) read,
    required Future<String> Function(String name, Uint8List bytes) write,
    void Function(int done, int total)? progress,
    bool Function()? cancelled,
  }) async {
    final List<PictureResult> out = <PictureResult>[];
    for (int i = 0; i < paths.length; i++) {
      if (cancelled?.call() ?? false) {
        break;
      }
      final String p = paths[i];
      final String name = p.split('/').last;
      try {
        final ConvertedPicture c = await convert(await read(p), name, target);
        out.add(PictureResult(source: p, outputPath: await write(c.name, c.bytes)));
      } on HeicConvertError catch (e) {
        out.add(PictureResult(source: p, error: e.message));
      } catch (e) {
        out.add(PictureResult(source: p, error: '$e'));
      }
      progress?.call(i + 1, paths.length);
    }
    return out;
  }
}

/// HEIC in the 030 registry, so Convert anything and Batch convert take
/// iPhone photos too.
class HeicImageConverter extends Converter {
  const HeicImageConverter(this.codec, this.target);

  final HeicCodec codec;

  @override
  final FileKind target;

  @override
  String get id => 'heic-to-${target.extension}';

  @override
  String get label => '${target.label} image';

  @override
  bool accepts(FileKind kind) => kind == FileKind.heic;

  @override
  Future<ConvertOutput> convert(ConvertInput input, FileKind kind) async {
    try {
      final ConvertedPicture p = await PictureConverter(codec)
          .convert(input.bytes, input.name, target == FileKind.png ? ImageTarget.png : ImageTarget.jpg);
      return output(input, p.bytes);
    } on HeicConvertError catch (e) {
      throw ConvertException(e.message);
    }
  }
}

/// Adds HEIC → JPG and HEIC → PNG to [registry].
void registerHeicConverters(ConvertRegistry registry, HeicCodec codec) {
  registry
    ..register(HeicImageConverter(codec, FileKind.jpeg))
    ..register(HeicImageConverter(codec, FileKind.png));
}
