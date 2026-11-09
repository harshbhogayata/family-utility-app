import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';

import '../engines/image/avif_convert.dart';
import '../engines/image/webp_convert.dart' show ImageTarget;

/// Feature 028 — AVIF through the phone's own codec (Android 12+ and
/// iOS 16+ decode AVIF natively). EXIF is not copied; no downscaling.
class PlatformAvifCodec implements AvifCodec {
  const PlatformAvifCodec();

  @override
  Future<Uint8List> convert(Uint8List avif, ImageTarget target, {int quality = 92}) async {
    final Uint8List out = await FlutterImageCompress.compressWithList(
      avif,
      minWidth: 100000,
      minHeight: 100000,
      quality: quality,
      format: target == ImageTarget.png ? CompressFormat.png : CompressFormat.jpeg,
      keepExif: false,
      autoCorrectionAngle: true,
    );
    if (out.isEmpty) {
      throw const AvifConvertError(avifUnsupportedMessage);
    }
    return out;
  }
}

/// What this phone's system says about AVIF, read once.
AvifSupport platformAvifSupport() {
  try {
    return avifSupportFor(Platform.operatingSystem, Platform.operatingSystemVersion);
  } catch (_) {
    return AvifSupport.unknown;
  }
}
