import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../convert/convert_registry.dart';
import '../convert/file_kind.dart';
import 'heic_convert.dart' show ConvertedPicture, PictureResult;
import 'webp_convert.dart' show ImageTarget;

/// Feature 028 — AVIF to JPG or PNG.
///
/// AVIF has no pure-Dart decoder, so the phone's own codec does the work
/// behind [AvifCodec]: Android 12+ and iOS 16+ decode AVIF natively. On
/// older phones the tool says so plainly instead of failing silently.
/// Other pictures picked alongside go through the pure-Dart path. Results
/// keep the order the pictures were picked in. Nothing leaves the phone.

class AvifConvertError implements Exception {
  const AvifConvertError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Shown when the phone's codec cannot open AVIF.
const String avifUnsupportedMessage =
    'This phone can\'t open AVIF pictures. AVIF needs Android 12 or iOS 16 or newer. Nothing was uploaded.';

/// The phone's AVIF decoder: AVIF bytes in, JPG or PNG out.
abstract class AvifCodec {
  Future<Uint8List> convert(Uint8List avif, ImageTarget target, {int quality = 92});
}

/// Whether this phone's system decodes AVIF.
enum AvifSupport { yes, no, unknown }

/// Works out [AvifSupport] from what Dart knows about the system.
///
/// iOS reports its version (`Version 16.4 (Build 20E247)`), so iOS 15 and
/// older are told up front. Android's version string does not carry the
/// API level, so Android is `unknown` and the decode itself decides.
AvifSupport avifSupportFor(String operatingSystem, String operatingSystemVersion) {
  if (operatingSystem == 'ios') {
    final RegExpMatch? m = RegExp(r'(\d+)(?:\.\d+)*').firstMatch(operatingSystemVersion);
    if (m == null) {
      return AvifSupport.unknown;
    }
    return int.parse(m.group(1)!) >= 16 ? AvifSupport.yes : AvifSupport.no;
  }
  if (operatingSystem == 'macos') {
    final RegExpMatch? m = RegExp(r'(\d+)(?:\.\d+)*').firstMatch(operatingSystemVersion);
    if (m == null) {
      return AvifSupport.unknown;
    }
    return int.parse(m.group(1)!) >= 13 ? AvifSupport.yes : AvifSupport.no;
  }
  if (operatingSystem == 'android') {
    return AvifSupport.unknown;
  }
  return AvifSupport.no;
}

String _outName(String name, ImageTarget target) {
  final int dot = name.lastIndexOf('.');
  return '${dot > 0 ? name.substring(0, dot) : name}.${target.extension}';
}

class AvifConverter {
  const AvifConverter(this.codec, {this.support = AvifSupport.unknown, this.quality = 92});

  final AvifCodec codec;
  final AvifSupport support;
  final int quality;

  Future<Uint8List> _platform(Uint8List bytes, ImageTarget target) async {
    if (support == AvifSupport.no) {
      throw const AvifConvertError(avifUnsupportedMessage);
    }
    final Uint8List result;
    try {
      result = await codec.convert(bytes, target, quality: quality);
    } on AvifConvertError {
      rethrow;
    } catch (_) {
      throw const AvifConvertError(avifUnsupportedMessage);
    }
    final FileKind want = target == ImageTarget.png ? FileKind.png : FileKind.jpeg;
    if (result.isEmpty || sniffFileKind(result) != want) {
      throw const AvifConvertError(avifUnsupportedMessage);
    }
    return result;
  }

  /// Turns one picture (AVIF or anything the app reads) into [target].
  Future<ConvertedPicture> convert(Uint8List bytes, String name, ImageTarget target) async {
    if (target == ImageTarget.webp) {
      throw const AvifConvertError('Pick JPG or PNG');
    }
    final String out = _outName(name, target);
    final FileKind kind = sniffFileKind(bytes);
    if (kind == FileKind.avif) {
      return ConvertedPicture(out, await _platform(bytes, target));
    }
    img.Image? decoded;
    try {
      decoded = img.decodeImage(bytes);
    } catch (_) {
      decoded = null;
    }
    if (decoded == null) {
      throw const AvifConvertError('This file is not a picture the app can read');
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
      } on AvifConvertError catch (e) {
        out.add(PictureResult(source: p, error: e.message));
      } catch (e) {
        out.add(PictureResult(source: p, error: '$e'));
      }
      progress?.call(i + 1, paths.length);
    }
    return out;
  }
}

/// AVIF in the 030 registry, so Convert anything and Batch convert take
/// AVIF pictures too.
class AvifImageConverter extends Converter {
  const AvifImageConverter(this.codec, this.target, {this.support = AvifSupport.unknown});

  final AvifCodec codec;
  final AvifSupport support;

  @override
  final FileKind target;

  @override
  String get id => 'avif-to-${target.extension}';

  @override
  String get label => '${target.label} image';

  @override
  bool accepts(FileKind kind) => kind == FileKind.avif;

  @override
  Future<ConvertOutput> convert(ConvertInput input, FileKind kind) async {
    try {
      final ConvertedPicture p = await AvifConverter(codec, support: support)
          .convert(input.bytes, input.name, target == FileKind.png ? ImageTarget.png : ImageTarget.jpg);
      return output(input, p.bytes);
    } on AvifConvertError catch (e) {
      throw ConvertException(e.message);
    }
  }
}

/// Adds AVIF → JPG and AVIF → PNG to [registry].
void registerAvifConverters(ConvertRegistry registry, AvifCodec codec, {AvifSupport support = AvifSupport.unknown}) {
  registry
    ..register(AvifImageConverter(codec, FileKind.jpeg, support: support))
    ..register(AvifImageConverter(codec, FileKind.png, support: support));
}
