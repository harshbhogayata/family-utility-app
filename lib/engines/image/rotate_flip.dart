import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Feature 042 — Rotate and flip.
///
/// A turn or flip is one of the eight EXIF orientations. For a JPG nothing is
/// re-encoded: the photo's existing EXIF orientation is read, the person's
/// turns and flips are added to it, and the new orientation is written back
/// (an EXIF block is added when the photo has none). Other images are drawn
/// upright from their own orientation, turned and saved as PNG.

enum RotateOp { left, right, flipHorizontal, flipVertical }

/// Display = turn clockwise by [turns] quarter turns after mirroring the
/// stored picture left-to-right when [mirror] is set.
class PhotoOrientation {
  const PhotoOrientation(this.turns, this.mirror);

  final int turns;
  final bool mirror;

  static const PhotoOrientation upright = PhotoOrientation(0, false);

  static const List<PhotoOrientation> _byExif = <PhotoOrientation>[
    PhotoOrientation(0, false), // 1
    PhotoOrientation(0, true), // 2 mirror horizontal
    PhotoOrientation(2, false), // 3 rotate 180
    PhotoOrientation(2, true), // 4 mirror vertical
    PhotoOrientation(3, true), // 5 mirror horizontal, rotate 270 clockwise
    PhotoOrientation(1, false), // 6 rotate 90 clockwise
    PhotoOrientation(1, true), // 7 mirror horizontal, rotate 90 clockwise
    PhotoOrientation(3, false), // 8 rotate 270 clockwise
  ];

  static PhotoOrientation fromExif(int value) => value >= 1 && value <= 8 ? _byExif[value - 1] : upright;

  int get exif {
    for (int i = 0; i < _byExif.length; i++) {
      if (_byExif[i] == this) {
        return i + 1;
      }
    }
    return 1;
  }

  /// This orientation followed by [op] on what is seen.
  PhotoOrientation then(RotateOp op) {
    switch (op) {
      case RotateOp.right:
        return PhotoOrientation((turns + 1) % 4, mirror);
      case RotateOp.left:
        return PhotoOrientation((turns + 3) % 4, mirror);
      case RotateOp.flipHorizontal:
        return PhotoOrientation((4 - turns) % 4, !mirror);
      case RotateOp.flipVertical:
        return PhotoOrientation((6 - turns) % 4, !mirror);
    }
  }

  PhotoOrientation thenAll(Iterable<RotateOp> ops) => ops.fold(this, (PhotoOrientation o, RotateOp op) => o.then(op));

  bool get swapsSides => turns.isOdd;

  @override
  bool operator ==(Object other) => other is PhotoOrientation && other.turns == turns && other.mirror == mirror;

  @override
  int get hashCode => turns * 2 + (mirror ? 1 : 0);
}

class RotateError implements Exception {
  const RotateError(this.message);
  final String message;
  @override
  String toString() => message;
}

class RotateResult {
  const RotateResult(this.bytes, this.extension, {required this.lossless, required this.orientation});

  final Uint8List bytes;
  final String extension;

  /// True when only the EXIF orientation changed (JPG).
  final bool lossless;

  /// The orientation now stored in the file (JPG) or 1 (redrawn).
  final int orientation;
}

bool isJpeg(Uint8List b) => b.length > 3 && b[0] == 0xFF && b[1] == 0xD8;

/// The EXIF orientation of a JPG, 1 when it has none.
int readJpegOrientation(Uint8List b) {
  final _Tag? t = _findOrientation(b);
  return t == null ? 1 : t.value;
}

class _Tag {
  const _Tag(this.offset, this.little, this.value);
  final int offset;
  final bool little;
  final int value;
}

_Tag? _findOrientation(Uint8List b) {
  if (!isJpeg(b)) {
    return null;
  }
  int i = 2;
  while (i + 4 <= b.length && b[i] == 0xFF) {
    final int marker = b[i + 1];
    if (marker == 0xDA || marker == 0xD9) {
      break;
    }
    final int len = (b[i + 2] << 8) | b[i + 3];
    final int start = i + 4;
    if (marker == 0xE1 &&
        start + 14 <= b.length &&
        b[start] == 0x45 && // E
        b[start + 1] == 0x78 && // x
        b[start + 2] == 0x69 && // i
        b[start + 3] == 0x66) {
      final int tiff = start + 6;
      final bool little = b[tiff] == 0x49;
      int u16(int at) => little ? b[at] | (b[at + 1] << 8) : (b[at] << 8) | b[at + 1];
      int u32(int at) => little
          ? b[at] | (b[at + 1] << 8) | (b[at + 2] << 16) | (b[at + 3] << 24)
          : (b[at] << 24) | (b[at + 1] << 16) | (b[at + 2] << 8) | b[at + 3];
      final int ifd = tiff + u32(tiff + 4);
      if (ifd + 2 > b.length) {
        return null;
      }
      final int n = u16(ifd);
      for (int e = 0; e < n; e++) {
        final int at = ifd + 2 + e * 12;
        if (at + 12 > b.length) {
          break;
        }
        if (u16(at) == 0x0112) {
          return _Tag(at + 8, little, u16(at + 8));
        }
      }
      return null;
    }
    i = start + len - 2;
  }
  return null;
}

/// A minimal EXIF block holding only the orientation.
Uint8List _exifSegment(int orientation) => Uint8List.fromList(<int>[
      0xFF, 0xE1, 0x00, 34, // APP1, length 34
      0x45, 0x78, 0x69, 0x66, 0x00, 0x00, // Exif\0\0
      0x49, 0x49, 0x2A, 0x00, 0x08, 0x00, 0x00, 0x00, // TIFF, little endian, IFD0 at 8
      0x01, 0x00, // one entry
      0x12, 0x01, 0x03, 0x00, 0x01, 0x00, 0x00, 0x00, orientation, 0x00, 0x00, 0x00, // PhotoOrientation SHORT
      0x00, 0x00, 0x00, 0x00, // no next IFD
    ]);

/// A copy of [jpeg] with its EXIF orientation set to [orientation]; the
/// picture data is untouched.
Uint8List writeJpegOrientation(Uint8List jpeg, int orientation) {
  final _Tag? t = _findOrientation(jpeg);
  final Uint8List out;
  if (t != null) {
    out = Uint8List.fromList(jpeg);
    if (t.little) {
      out[t.offset] = orientation;
      out[t.offset + 1] = 0;
    } else {
      out[t.offset] = 0;
      out[t.offset + 1] = orientation;
    }
    return out;
  }
  // After SOI and a JFIF APP0 if there is one.
  int at = 2;
  if (jpeg.length > 6 && jpeg[2] == 0xFF && jpeg[3] == 0xE0) {
    at = 4 + ((jpeg[4] << 8) | jpeg[5]);
  }
  final BytesBuilder b = BytesBuilder(copy: false)
    ..add(jpeg.sublist(0, at))
    ..add(_exifSegment(orientation))
    ..add(jpeg.sublist(at));
  return b.toBytes();
}

abstract final class RotateFlip {
  static RotateResult apply(Uint8List input, List<RotateOp> ops) {
    if (isJpeg(input)) {
      final PhotoOrientation now = PhotoOrientation.fromExif(readJpegOrientation(input)).thenAll(ops);
      return RotateResult(writeJpegOrientation(input, now.exif), 'jpg', lossless: true, orientation: now.exif);
    }
    final img.Image? decoded = img.decodeImage(input);
    if (decoded == null) {
      throw const RotateError('This file is not a picture this phone can open');
    }
    final PhotoOrientation o = PhotoOrientation.upright.thenAll(ops);
    img.Image im = img.bakeOrientation(decoded);
    if (o.mirror) {
      im = img.flipHorizontal(im);
    }
    if (o.turns != 0) {
      im = img.copyRotate(im, angle: 90 * o.turns);
    }
    return RotateResult(Uint8List.fromList(img.encodePng(im)), 'png', lossless: false, orientation: 1);
  }

  /// "IMG_1.jpeg" becomes "IMG_1-rotated.jpg".
  static String outputName(String original, String extension) {
    final String name = original.split('/').last;
    final int dot = name.lastIndexOf('.');
    final String stem = dot > 0 ? name.substring(0, dot) : name;
    return '$stem-rotated.$extension';
  }
}
