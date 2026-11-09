import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';

import '../engines/image/heic_convert.dart';
import '../engines/image/webp_convert.dart' show ImageTarget;

/// Feature 025 — HEIC through the phone's own codec (Android 9+ and iOS
/// decode HEIF natively). `autoCorrectionAngle` applies the EXIF
/// orientation so the picture comes out upright; EXIF is not copied.
class PlatformHeicCodec implements HeicCodec {
  const PlatformHeicCodec();

  @override
  Future<Uint8List> convert(Uint8List heic, ImageTarget target, {int quality = 92}) async {
    final Uint8List out = await FlutterImageCompress.compressWithList(
      heic,
      minWidth: 100000,
      minHeight: 100000,
      quality: quality,
      format: target == ImageTarget.png ? CompressFormat.png : CompressFormat.jpeg,
      keepExif: false,
      autoCorrectionAngle: true,
    );
    if (out.isEmpty) {
      throw const HeicConvertError('This phone could not open this HEIC photo');
    }
    return out;
  }
}
