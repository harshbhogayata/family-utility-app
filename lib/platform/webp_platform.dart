import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';

import '../engines/image/webp_convert.dart';

/// Feature 026 — WebP through the phone's own image codec.
class PlatformWebpEncoder implements WebpEncoder {
  const PlatformWebpEncoder();

  @override
  Future<Uint8List> encode(Uint8List png, {int quality = 90}) async {
    final Uint8List out = await FlutterImageCompress.compressWithList(
      png,
      quality: quality,
      format: CompressFormat.webp,
      keepExif: false,
      autoCorrectionAngle: false,
    );
    if (out.isEmpty) {
      throw const WebpConvertError('This phone could not write WebP');
    }
    return out;
  }
}
