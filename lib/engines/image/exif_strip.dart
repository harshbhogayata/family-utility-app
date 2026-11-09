import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../share/share_engine.dart';

/// Feature 046 — View and strip EXIF. Reads where, with what and when a
/// photo was taken, and removes it. JPEG and PNG, pure Dart, on the phone.
/// A JPEG keeps only its Orientation tag so it still shows the right way up.

class ExifError implements Exception {
  const ExifError(this.message);
  final String message;
  @override
  String toString() => message;
}

class PhotoMeta {
  const PhotoMeta({
    this.make,
    this.model,
    this.software,
    this.taken,
    this.latitude,
    this.longitude,
    this.orientation = 1,
    this.otherBlocks = 0,
  });

  final String? make;
  final String? model;
  final String? software;

  /// As written by the camera: "2024:05:01 10:20:30".
  final String? taken;
  final double? latitude;
  final double? longitude;
  final int orientation;

  /// XMP, IPTC, comments and text chunks that may hold more personal data.
  final int otherBlocks;

  bool get hasGps => latitude != null && longitude != null;

  String? get camera {
    final String joined = <String?>[make, model].whereType<String>().join(' ').trim();
    return joined.isEmpty ? null : joined;
  }

  bool get isClean => !hasGps && camera == null && software == null && taken == null && otherBlocks == 0;

  String get gpsLabel => hasGps ? '${latitude!.toStringAsFixed(5)}, ${longitude!.toStringAsFixed(5)}' : 'None';
}

/// Reads the IFDs of a TIFF block (the body of an EXIF segment).
class _Tiff {
  _Tiff(this.b) : little = b.length > 1 && b[0] == 0x49 {
    _d = ByteData.sublistView(b);
  }

  final Uint8List b;
  final bool little;
  late final ByteData _d;

  Endian get _e => little ? Endian.little : Endian.big;
  int u16(int at) => _d.getUint16(at, _e);
  int u32(int at) => _d.getUint32(at, _e);

  static const Map<int, int> _size = <int, int>{1: 1, 2: 1, 3: 2, 4: 4, 5: 8, 7: 1, 9: 4, 10: 8};

  /// tag → (type, count, data offset)
  Map<int, (int, int, int)> ifd(int at) {
    final Map<int, (int, int, int)> out = <int, (int, int, int)>{};
    if (at <= 0 || at + 2 > b.length) {
      return out;
    }
    final int n = u16(at);
    for (int i = 0; i < n; i++) {
      final int e = at + 2 + i * 12;
      if (e + 12 > b.length) {
        break;
      }
      final int type = u16(e + 2);
      final int count = u32(e + 4);
      final int bytes = (_size[type] ?? 1) * count;
      final int data = bytes <= 4 ? e + 8 : u32(e + 8);
      if (data + bytes <= b.length) {
        out[u16(e)] = (type, count, data);
      }
    }
    return out;
  }

  int firstIfd() => u32(4);

  String? text(Map<int, (int, int, int)> ifd, int tag) {
    final (int, int, int)? v = ifd[tag];
    if (v == null || v.$1 != 2) {
      return null;
    }
    final String s = latin1.decode(b.sublist(v.$3, v.$3 + v.$2)).replaceAll('\u0000', '').trim();
    return s.isEmpty ? null : s;
  }

  int? integer(Map<int, (int, int, int)> ifd, int tag) {
    final (int, int, int)? v = ifd[tag];
    if (v == null) {
      return null;
    }
    return v.$1 == 3 ? u16(v.$3) : (v.$1 == 4 ? u32(v.$3) : null);
  }

  double? degrees(Map<int, (int, int, int)> ifd, int tag) {
    final (int, int, int)? v = ifd[tag];
    if (v == null || v.$1 != 5 || v.$2 < 3) {
      return null;
    }
    double part(int i) {
      final int den = u32(v.$3 + i * 8 + 4);
      return den == 0 ? 0 : u32(v.$3 + i * 8) / den;
    }

    return part(0) + part(1) / 60 + part(2) / 3600;
  }
}

enum PhotoFormat { jpeg, png, other }

class ExifTool {
  ExifTool._();

  static const List<int> _pngSig = <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

  static PhotoFormat formatOf(Uint8List b) {
    if (b.length > 3 && b[0] == 0xFF && b[1] == 0xD8) {
      return PhotoFormat.jpeg;
    }
    if (b.length > 8) {
      for (int i = 0; i < 8; i++) {
        if (b[i] != _pngSig[i]) {
          return PhotoFormat.other;
        }
      }
      return PhotoFormat.png;
    }
    return PhotoFormat.other;
  }

  static bool isPhotoName(String path) {
    final String p = path.toLowerCase();
    return p.endsWith('.jpg') || p.endsWith('.jpeg') || p.endsWith('.png');
  }

  static PhotoMeta _fromTiff(Uint8List tiff, int otherBlocks) {
    if (tiff.length < 8) {
      return PhotoMeta(otherBlocks: otherBlocks);
    }
    final _Tiff t = _Tiff(tiff);
    final Map<int, (int, int, int)> ifd0 = t.ifd(t.firstIfd());
    final int? exifAt = t.integer(ifd0, 0x8769);
    final int? gpsAt = t.integer(ifd0, 0x8825);
    final Map<int, (int, int, int)> exif = exifAt == null ? <int, (int, int, int)>{} : t.ifd(exifAt);
    final Map<int, (int, int, int)> gps = gpsAt == null ? <int, (int, int, int)>{} : t.ifd(gpsAt);
    double? lat = t.degrees(gps, 2);
    double? lon = t.degrees(gps, 4);
    if (lat != null && t.text(gps, 1) == 'S') {
      lat = -lat;
    }
    if (lon != null && t.text(gps, 3) == 'W') {
      lon = -lon;
    }
    return PhotoMeta(
      make: t.text(ifd0, 0x010F),
      model: t.text(ifd0, 0x0110),
      software: t.text(ifd0, 0x0131),
      taken: t.text(exif, 0x9003) ?? t.text(ifd0, 0x0132),
      latitude: lat,
      longitude: lon,
      orientation: t.integer(ifd0, 0x0112) ?? 1,
      otherBlocks: otherBlocks,
    );
  }

  static bool _isExif(Uint8List b, int at) =>
      at + 6 <= b.length && b[at] == 0x45 && b[at + 1] == 0x78 && b[at + 2] == 0x69 && b[at + 3] == 0x66 && b[at + 4] == 0;

  /// JPEG segments before the image data: (marker, start, end).
  static List<(int, int, int)> _jpegSegments(Uint8List b) {
    final List<(int, int, int)> out = <(int, int, int)>[];
    int i = 2;
    while (i + 4 <= b.length && b[i] == 0xFF) {
      final int marker = b[i + 1];
      if (marker == 0xDA || marker == 0xD9) {
        break;
      }
      final int len = (b[i + 2] << 8) | b[i + 3];
      if (len < 2 || i + 2 + len > b.length) {
        throw const ExifError('This photo looks damaged');
      }
      out.add((marker, i, i + 2 + len));
      i += 2 + len;
    }
    return out;
  }

  /// APP1 (EXIF, XMP), APP13 (IPTC) and comments hold personal data.
  static bool _personal(int marker) => marker == 0xE1 || marker == 0xED || marker == 0xFE;

  static const Set<String> _pngPersonal = <String>{'eXIf', 'tEXt', 'iTXt', 'zTXt', 'tIME'};

  /// PNG chunks: (type, start, end, data start, data length).
  static List<(String, int, int, int, int)> _pngChunks(Uint8List b) {
    final ByteData d = ByteData.sublistView(b);
    final List<(String, int, int, int, int)> out = <(String, int, int, int, int)>[];
    int i = 8;
    while (i + 12 <= b.length) {
      final int len = d.getUint32(i);
      final String type = latin1.decode(b.sublist(i + 4, i + 8));
      final int end = i + 12 + len;
      if (end > b.length) {
        throw const ExifError('This picture looks damaged');
      }
      out.add((type, i, end, i + 8, len));
      i = end;
      if (type == 'IEND') {
        break;
      }
    }
    return out;
  }

  static PhotoMeta read(Uint8List b) {
    switch (formatOf(b)) {
      case PhotoFormat.jpeg:
        Uint8List? tiff;
        int other = 0;
        for (final (int, int, int) s in _jpegSegments(b)) {
          if (!_personal(s.$1)) {
            continue;
          }
          if (s.$1 == 0xE1 && tiff == null && _isExif(b, s.$2 + 4)) {
            tiff = Uint8List.sublistView(b, s.$2 + 10, s.$3);
          } else {
            other++;
          }
        }
        return tiff == null ? PhotoMeta(otherBlocks: other) : _fromTiff(tiff, other);
      case PhotoFormat.png:
        Uint8List? tiff;
        int other = 0;
        for (final (String, int, int, int, int) c in _pngChunks(b)) {
          if (c.$1 == 'eXIf' && tiff == null) {
            tiff = Uint8List.sublistView(b, c.$4, c.$4 + c.$5);
          } else if (_pngPersonal.contains(c.$1)) {
            other++;
          }
        }
        return tiff == null ? PhotoMeta(otherBlocks: other) : _fromTiff(tiff, other);
      case PhotoFormat.other:
        throw const ExifError('Only JPG and PNG photos can be checked here');
    }
  }

  /// A tiny EXIF block holding only the Orientation tag.
  static Uint8List orientationOnly(int orientation) {
    final ByteData d = ByteData(6 + 8 + 2 + 12 + 4);
    const List<int> head = <int>[0x45, 0x78, 0x69, 0x66, 0, 0, 0x4D, 0x4D, 0, 0x2A, 0, 0, 0, 8];
    for (int i = 0; i < head.length; i++) {
      d.setUint8(i, head[i]);
    }
    d.setUint16(14, 1);
    d.setUint16(16, 0x0112);
    d.setUint16(18, 3);
    d.setUint32(20, 1);
    d.setUint16(24, orientation);
    d.setUint32(28, 0);
    return d.buffer.asUint8List();
  }

  /// The same picture with location, camera, dates and text removed. The
  /// image data itself is copied untouched, so quality does not change.
  static Uint8List strip(Uint8List b) {
    switch (formatOf(b)) {
      case PhotoFormat.jpeg:
        final int orientation = read(b).orientation;
        final List<(int, int, int)> segs = _jpegSegments(b);
        final BytesBuilder out = BytesBuilder(copy: false)..add(<int>[0xFF, 0xD8]);
        void orient() {
          if (orientation != 1) {
            final Uint8List body = orientationOnly(orientation);
            final int len = body.length + 2;
            out
              ..add(<int>[0xFF, 0xE1, len >> 8, len & 0xFF])
              ..add(body);
          }
        }

        // The Orientation block goes right after JFIF's APP0 when there is one.
        final bool jfif = segs.isNotEmpty && segs.first.$1 == 0xE0;
        if (!jfif) {
          orient();
        }
        int rest = 2;
        for (int i = 0; i < segs.length; i++) {
          final (int, int, int) s = segs[i];
          if (!_personal(s.$1)) {
            out.add(Uint8List.sublistView(b, s.$2, s.$3));
          }
          if (i == 0 && jfif) {
            orient();
          }
          rest = s.$3;
        }
        out.add(Uint8List.sublistView(b, rest));
        return out.toBytes();
      case PhotoFormat.png:
        final BytesBuilder out = BytesBuilder(copy: false)..add(Uint8List.sublistView(b, 0, 8));
        for (final (String, int, int, int, int) c in _pngChunks(b)) {
          if (!_pngPersonal.contains(c.$1)) {
            out.add(Uint8List.sublistView(b, c.$2, c.$3));
          }
        }
        return out.toBytes();
      case PhotoFormat.other:
        throw const ExifError('Only JPG and PNG photos can be cleaned here');
    }
  }

  /// "IMG_1.jpg" → "IMG_1-clean.jpg".
  static String cleanName(String path) {
    final String name = path.substring(path.lastIndexOf('/') + 1);
    final int dot = name.lastIndexOf('.');
    return dot > 0 ? '${name.substring(0, dot)}-clean${name.substring(dot)}' : '$name-clean';
  }
}

/// Remembers "always strip on share".
abstract class StripOnShareStore {
  Future<bool> read();
  Future<void> write(bool on);
}

class MemoryStripOnShareStore implements StripOnShareStore {
  MemoryStripOnShareStore([this.value = false]);
  bool value;

  @override
  Future<bool> read() async => value;

  @override
  Future<void> write(bool on) async {
    value = on;
  }
}

/// Installed on [ShareEngine.prepare]: when the setting is on, photos are
/// swapped for cleaned copies in [tempFolder] before the share sheet opens.
class StripOnShare {
  StripOnShare(this.store, this.tempFolder);
  final StripOnShareStore store;
  final Future<Directory> Function() tempFolder;

  Future<ShareRequest> prepare(ShareRequest request) async {
    if (!request.hasFiles || !await store.read()) {
      return request;
    }
    final List<ShareFile> files = <ShareFile>[];
    Directory? dir;
    for (final ShareFile f in request.files) {
      if (!ExifTool.isPhotoName(f.path)) {
        files.add(f);
        continue;
      }
      try {
        final Uint8List clean = ExifTool.strip(await File(f.path).readAsBytes());
        dir ??= await tempFolder();
        await dir.create(recursive: true);
        final File out = File('${dir.path}/${f.path.substring(f.path.lastIndexOf('/') + 1)}');
        await out.writeAsBytes(clean, flush: true);
        files.add(ShareFile(out.path, mimeType: f.mimeType, name: f.name));
      } on Object {
        files.add(f); // unreadable: share as it is rather than not at all
      }
    }
    return ShareRequest(files: files, text: request.text, subject: request.subject);
  }
}
