import 'dart:io';
import 'dart:typed_data';

/// Feature 124 — pulls the sound out of an MP4 or M4A file, on the phone.
///
/// Pure Dart, no re-encoding: the audio track's samples are copied as they
/// are into a fresh M4A (the same AAC sound, so no quality is lost). Plain
/// MP4s and fragmented ones (the kind streaming sites serve) both work.
/// An optional start and end trim the result to whole audio frames.

/// A file this reader cannot use.
class AudioExtractError implements Exception {
  const AudioExtractError(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Random access to the source file's bytes.
abstract class ByteSource {
  int get length;

  Uint8List read(int offset, int length);
}

class MemoryByteSource implements ByteSource {
  MemoryByteSource(this.bytes);

  final Uint8List bytes;

  @override
  int get length => bytes.length;

  @override
  Uint8List read(int offset, int length) {
    if (offset < 0 || length < 0 || offset + length > bytes.length) {
      throw const AudioExtractError('The file ends too early; it may be damaged or not fully downloaded.');
    }
    return Uint8List.sublistView(bytes, offset, offset + length);
  }
}

class FileByteSource implements ByteSource {
  FileByteSource(this.file) : length = file.lengthSync();

  final RandomAccessFile file;

  @override
  final int length;

  @override
  Uint8List read(int offset, int count) {
    if (offset < 0 || count < 0 || offset + count > length) {
      throw const AudioExtractError('The file ends too early; it may be damaged or not fully downloaded.');
    }
    file.setPositionSync(offset);
    return file.readSync(count);
  }
}

/// One box: where its payload starts and how long it is.
class Mp4Box {
  const Mp4Box(this.type, this.start, this.headerSize, this.size);

  final String type;

  /// Offset of the box header.
  final int start;
  final int headerSize;

  /// Whole box, header included.
  final int size;

  int get dataStart => start + headerSize;
  int get dataSize => size - headerSize;
  int get end => start + size;
}

int _u32(Uint8List b, int o) => (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];

int _u64(Uint8List b, int o) => _u32(b, o) * 4294967296 + _u32(b, o + 4);

int _s32(Uint8List b, int o) {
  final int v = _u32(b, o);
  return v >= 0x80000000 ? v - 0x100000000 : v;
}

/// The boxes laid end to end between [from] and [to].
List<Mp4Box> readBoxes(ByteSource src, int from, int to) {
  final List<Mp4Box> out = <Mp4Box>[];
  int at = from;
  while (at + 8 <= to) {
    final Uint8List h = src.read(at, 8);
    int size = _u32(h, 0);
    final String type = String.fromCharCodes(h.sublist(4, 8));
    int header = 8;
    if (size == 1) {
      if (at + 16 > to) {
        break;
      }
      size = _u64(src.read(at + 8, 8), 0);
      header = 16;
    } else if (size == 0) {
      size = to - at;
    }
    if (size < header || at + size > to) {
      // A truncated last box (an unfinished download): stop reading here.
      break;
    }
    out.add(Mp4Box(type, at, header, size));
    at += size;
  }
  return out;
}

Mp4Box? _child(List<Mp4Box> boxes, String type) {
  for (final Mp4Box b in boxes) {
    if (b.type == type) {
      return b;
    }
  }
  return null;
}

/// One audio frame in the source file.
class AudioSample {
  const AudioSample(this.offset, this.size, this.duration);

  final int offset;
  final int size;
  final int duration;
}

/// What [Mp4AudioReader.read] found.
class AudioTrack {
  AudioTrack({
    required this.timescale,
    required this.samples,
    required this.stsd,
    required this.mdhd,
    required this.hdlr,
    required this.smhd,
    required this.dinf,
    required this.mvhd,
    required this.tkhd,
    required this.codec,
  });

  /// Ticks per second of the sample durations.
  final int timescale;
  final List<AudioSample> samples;

  /// Raw boxes copied into the new file.
  final Uint8List stsd;
  final Uint8List mdhd;
  final Uint8List hdlr;
  final Uint8List? smhd;
  final Uint8List? dinf;
  final Uint8List mvhd;
  final Uint8List tkhd;

  /// The sample entry type, e.g. `mp4a`.
  final String codec;

  int get totalTicks {
    int t = 0;
    for (final AudioSample s in samples) {
      t += s.duration;
    }
    return t;
  }

  Duration get duration => Duration(microseconds: timescale == 0 ? 0 : totalTicks * 1000000 ~/ timescale);
}

/// Finds the sound track in an MP4/M4A and lists its frames.
class Mp4AudioReader {
  const Mp4AudioReader();

  AudioTrack read(ByteSource src) {
    final List<Mp4Box> top = readBoxes(src, 0, src.length);
    final Mp4Box? moov = _child(top, 'moov');
    if (moov == null) {
      throw const AudioExtractError('This is not an MP4 or M4A file the app can read.');
    }
    final List<Mp4Box> moovKids = readBoxes(src, moov.dataStart, moov.end);
    final Mp4Box? mvhd = _child(moovKids, 'mvhd');
    if (mvhd == null) {
      throw const AudioExtractError('This MP4 file is missing its header.');
    }
    for (final Mp4Box trak in moovKids.where((Mp4Box b) => b.type == 'trak')) {
      final List<Mp4Box> trakKids = readBoxes(src, trak.dataStart, trak.end);
      final Mp4Box? tkhd = _child(trakKids, 'tkhd');
      final Mp4Box? mdia = _child(trakKids, 'mdia');
      if (tkhd == null || mdia == null) {
        continue;
      }
      final List<Mp4Box> mdiaKids = readBoxes(src, mdia.dataStart, mdia.end);
      final Mp4Box? hdlr = _child(mdiaKids, 'hdlr');
      final Mp4Box? mdhd = _child(mdiaKids, 'mdhd');
      final Mp4Box? minf = _child(mdiaKids, 'minf');
      if (hdlr == null || mdhd == null || minf == null || hdlr.dataSize < 12) {
        continue;
      }
      final String handler = String.fromCharCodes(src.read(hdlr.dataStart + 8, 4));
      if (handler != 'soun') {
        continue;
      }
      final List<Mp4Box> minfKids = readBoxes(src, minf.dataStart, minf.end);
      final Mp4Box? stbl = _child(minfKids, 'stbl');
      if (stbl == null) {
        continue;
      }
      final List<Mp4Box> stblKids = readBoxes(src, stbl.dataStart, stbl.end);
      final Mp4Box? stsd = _child(stblKids, 'stsd');
      if (stsd == null) {
        continue;
      }
      final Uint8List mdhdBytes = src.read(mdhd.start, mdhd.size);
      final int mdhdVersion = mdhdBytes[mdhd.headerSize];
      final int timescale = _u32(mdhdBytes, mdhd.headerSize + 4 + (mdhdVersion == 1 ? 16 : 8));
      final Uint8List tkhdBytes = src.read(tkhd.start, tkhd.size);
      final int trackId = _u32(tkhdBytes, tkhd.headerSize + 4 + (tkhdBytes[tkhd.headerSize] == 1 ? 16 : 8));
      List<AudioSample> samples = _tableSamples(src, stblKids);
      if (samples.isEmpty) {
        samples = _fragmentSamples(src, top, moovKids, trackId);
      }
      if (samples.isEmpty) {
        throw const AudioExtractError('The sound track in this file is empty.');
      }
      final Uint8List stsdBytes = src.read(stsd.start, stsd.size);
      final String codec = stsdBytes.length >= 24 ? String.fromCharCodes(stsdBytes.sublist(stsd.headerSize + 12, stsd.headerSize + 16)) : '';
      final Mp4Box? smhd = _child(minfKids, 'smhd');
      final Mp4Box? dinf = _child(minfKids, 'dinf');
      return AudioTrack(
        timescale: timescale,
        samples: samples,
        stsd: stsdBytes,
        mdhd: mdhdBytes,
        hdlr: src.read(hdlr.start, hdlr.size),
        smhd: smhd == null ? null : src.read(smhd.start, smhd.size),
        dinf: dinf == null ? null : src.read(dinf.start, dinf.size),
        mvhd: src.read(mvhd.start, mvhd.size),
        tkhd: tkhdBytes,
        codec: codec,
      );
    }
    throw const AudioExtractError('This video has no sound track.');
  }

  /// Samples listed in the classic tables (stts, stsz, stsc, stco/co64).
  List<AudioSample> _tableSamples(ByteSource src, List<Mp4Box> stbl) {
    final Mp4Box? stts = _child(stbl, 'stts');
    final Mp4Box? stsz = _child(stbl, 'stsz');
    final Mp4Box? stsc = _child(stbl, 'stsc');
    final Mp4Box? stco = _child(stbl, 'stco') ?? _child(stbl, 'co64');
    if (stts == null || stsz == null || stsc == null || stco == null) {
      return <AudioSample>[];
    }
    final Uint8List sz = src.read(stsz.dataStart, stsz.dataSize);
    final int constSize = _u32(sz, 4);
    final int count = _u32(sz, 8);
    if (count == 0) {
      return <AudioSample>[];
    }
    final List<int> sizes = List<int>.generate(count, (int i) => constSize != 0 ? constSize : _u32(sz, 12 + i * 4));

    final Uint8List tt = src.read(stts.dataStart, stts.dataSize);
    final List<int> durations = <int>[];
    final int ttEntries = _u32(tt, 4);
    for (int e = 0; e < ttEntries && durations.length < count; e++) {
      final int n = _u32(tt, 8 + e * 8);
      final int d = _u32(tt, 12 + e * 8);
      for (int k = 0; k < n && durations.length < count; k++) {
        durations.add(d);
      }
    }
    while (durations.length < count) {
      durations.add(durations.isEmpty ? 1024 : durations.last);
    }

    final Uint8List co = src.read(stco.dataStart, stco.dataSize);
    final bool wide = stco.type == 'co64';
    final int chunks = _u32(co, 4);
    final List<int> chunkOffsets =
        List<int>.generate(chunks, (int i) => wide ? _u64(co, 8 + i * 8) : _u32(co, 8 + i * 4));

    final Uint8List sc = src.read(stsc.dataStart, stsc.dataSize);
    final int scEntries = _u32(sc, 4);
    final List<AudioSample> out = <AudioSample>[];
    int sample = 0;
    for (int e = 0; e < scEntries; e++) {
      final int firstChunk = _u32(sc, 8 + e * 12);
      final int perChunk = _u32(sc, 12 + e * 12);
      final int lastChunk = e + 1 < scEntries ? _u32(sc, 8 + (e + 1) * 12) - 1 : chunks;
      for (int c = firstChunk; c <= lastChunk && c <= chunks; c++) {
        int at = chunkOffsets[c - 1];
        for (int k = 0; k < perChunk && sample < count; k++) {
          out.add(AudioSample(at, sizes[sample], durations[sample]));
          at += sizes[sample];
          sample++;
        }
      }
    }
    return out;
  }

  /// Samples listed in movie fragments (moof / traf / trun).
  List<AudioSample> _fragmentSamples(ByteSource src, List<Mp4Box> top, List<Mp4Box> moovKids, int trackId) {
    int defDuration = 0;
    int defSize = 0;
    final Mp4Box? mvex = _child(moovKids, 'mvex');
    if (mvex != null) {
      for (final Mp4Box trex in readBoxes(src, mvex.dataStart, mvex.end).where((Mp4Box b) => b.type == 'trex')) {
        final Uint8List t = src.read(trex.dataStart, trex.dataSize);
        if (t.length >= 24 && _u32(t, 4) == trackId) {
          defDuration = _u32(t, 12);
          defSize = _u32(t, 16);
        }
      }
    }
    final List<AudioSample> out = <AudioSample>[];
    for (final Mp4Box moof in top.where((Mp4Box b) => b.type == 'moof')) {
      for (final Mp4Box traf in readBoxes(src, moof.dataStart, moof.end).where((Mp4Box b) => b.type == 'traf')) {
        final List<Mp4Box> kids = readBoxes(src, traf.dataStart, traf.end);
        final Mp4Box? tfhd = _child(kids, 'tfhd');
        if (tfhd == null) {
          continue;
        }
        final Uint8List h = src.read(tfhd.dataStart, tfhd.dataSize);
        final int flags = _u32(h, 0) & 0xffffff;
        if (_u32(h, 4) != trackId) {
          continue;
        }
        int p = 8;
        int base = moof.start;
        if (flags & 0x1 != 0) {
          base = _u64(h, p);
          p += 8;
        }
        if (flags & 0x2 != 0) {
          p += 4;
        }
        int tDuration = defDuration;
        int tSize = defSize;
        if (flags & 0x8 != 0) {
          tDuration = _u32(h, p);
          p += 4;
        }
        if (flags & 0x10 != 0) {
          tSize = _u32(h, p);
          p += 4;
        }
        int next = base;
        for (final Mp4Box trun in kids.where((Mp4Box b) => b.type == 'trun')) {
          final Uint8List r = src.read(trun.dataStart, trun.dataSize);
          final int rf = _u32(r, 0) & 0xffffff;
          final int n = _u32(r, 4);
          int q = 8;
          int at = next;
          if (rf & 0x1 != 0) {
            at = base + _s32(r, q);
            q += 4;
          }
          if (rf & 0x4 != 0) {
            q += 4;
          }
          for (int i = 0; i < n; i++) {
            int d = tDuration;
            int s = tSize;
            if (rf & 0x100 != 0) {
              d = _u32(r, q);
              q += 4;
            }
            if (rf & 0x200 != 0) {
              s = _u32(r, q);
              q += 4;
            }
            if (rf & 0x400 != 0) {
              q += 4;
            }
            if (rf & 0x800 != 0) {
              q += 4;
            }
            out.add(AudioSample(at, s, d));
            at += s;
          }
          next = at;
        }
      }
    }
    return out;
  }
}

class _Writer {
  final BytesBuilder b = BytesBuilder(copy: false);

  void u32(int v) => b.add(<int>[(v >> 24) & 0xff, (v >> 16) & 0xff, (v >> 8) & 0xff, v & 0xff]);

  void u64(int v) {
    u32(v ~/ 4294967296);
    u32(v % 4294967296);
  }

  void type(String t) => b.add(t.codeUnits);

  void bytes(List<int> v) => b.add(v);
}

Uint8List _box(String type, List<Uint8List> parts) {
  int size = 8;
  for (final Uint8List p in parts) {
    size += p.length;
  }
  final _Writer w = _Writer()
    ..u32(size)
    ..type(type);
  for (final Uint8List p in parts) {
    w.bytes(p);
  }
  return w.b.takeBytes();
}

Uint8List _fullBox(String type, void Function(_Writer w) body) {
  final _Writer w = _Writer()..u32(0);
  body(w);
  return _box(type, <Uint8List>[w.b.takeBytes()]);
}

/// Copy of a full box with its duration field set. [skip] is the bytes
/// between the version/flags word and the duration for version 0 and 1.
Uint8List _withDuration(Uint8List box, int skip0, int skip1, int duration) {
  final Uint8List out = Uint8List.fromList(box);
  final int header = _u32(out, 0) == 1 ? 16 : 8;
  final bool v1 = out[header] == 1;
  final int at = header + 4 + (v1 ? skip1 : skip0);
  final ByteData d = ByteData.sublistView(out);
  if (v1) {
    d.setUint32(at, duration ~/ 4294967296);
    d.setUint32(at + 4, duration % 4294967296);
  } else {
    d.setUint32(at, duration > 0xffffffff ? 0xffffffff : duration);
  }
  return out;
}

int _timescaleOf(Uint8List box, int skip0, int skip1) {
  final int header = _u32(box, 0) == 1 ? 16 : 8;
  final bool v1 = box[header] == 1;
  return _u32(box, header + 4 + (v1 ? skip1 : skip0));
}

/// Builds the M4A: ftyp, moov (one sound track, every frame in one chunk),
/// then mdat with the frames copied in order.
class M4aWriter {
  const M4aWriter();

  /// Samples of [track] whose start lies in [start, end).
  static List<AudioSample> window(AudioTrack track, Duration? start, Duration? end) {
    if (start == null && end == null) {
      return track.samples;
    }
    final int from = start == null ? 0 : start.inMicroseconds * track.timescale ~/ 1000000;
    final int to = end == null ? -1 : end.inMicroseconds * track.timescale ~/ 1000000;
    final List<AudioSample> out = <AudioSample>[];
    int t = 0;
    for (final AudioSample s in track.samples) {
      if (t >= from && (to < 0 || t < to)) {
        out.add(s);
      }
      t += s.duration;
    }
    return out;
  }

  /// The header part (everything before the frames) for [samples].
  Uint8List header(AudioTrack track, List<AudioSample> samples) {
    int ticks = 0;
    int dataSize = 0;
    for (final AudioSample s in samples) {
      ticks += s.duration;
      dataSize += s.size;
    }
    final int movieScale = _timescaleOf(track.mvhd, 8, 16);
    final int movieTicks = track.timescale == 0 ? 0 : ticks * movieScale ~/ track.timescale;

    final Uint8List ftyp = _box('ftyp', <Uint8List>[
      Uint8List.fromList(<int>[...'M4A '.codeUnits, 0, 0, 2, 0, ...'M4A '.codeUnits, ...'mp42'.codeUnits, ...'isom'.codeUnits]),
    ]);

    // Run-length durations.
    final List<List<int>> runs = <List<int>>[];
    for (final AudioSample s in samples) {
      if (runs.isNotEmpty && runs.last[1] == s.duration) {
        runs.last[0]++;
      } else {
        runs.add(<int>[1, s.duration]);
      }
    }
    final Uint8List stts = _fullBox('stts', (_Writer w) {
      w.u32(runs.length);
      for (final List<int> r in runs) {
        w
          ..u32(r[0])
          ..u32(r[1]);
      }
    });
    final Uint8List stsc = _fullBox('stsc', (_Writer w) {
      w
        ..u32(1)
        ..u32(1)
        ..u32(samples.length)
        ..u32(1);
    });
    final Uint8List stsz = _fullBox('stsz', (_Writer w) {
      w
        ..u32(0)
        ..u32(samples.length);
      for (final AudioSample s in samples) {
        w.u32(s.size);
      }
    });

    Uint8List build(int dataOffset) {
      final bool wide = dataOffset + dataSize > 0xffffffff;
      final Uint8List co = wide
          ? _fullBox('co64', (_Writer w) {
              w
                ..u32(1)
                ..u64(dataOffset);
            })
          : _fullBox('stco', (_Writer w) {
              w
                ..u32(1)
                ..u32(dataOffset);
            });
      final Uint8List stbl = _box('stbl', <Uint8List>[track.stsd, stts, stsc, stsz, co]);
      final Uint8List smhd = track.smhd ??
          _fullBox('smhd', (_Writer w) {
            w.u32(0);
          });
      final Uint8List dinf = track.dinf ??
          _box('dinf', <Uint8List>[
            _fullBox('dref', (_Writer w) {
              w
                ..u32(1)
                ..u32(12)
                ..type('url ')
                ..u32(1);
            }),
          ]);
      final Uint8List minf = _box('minf', <Uint8List>[smhd, dinf, stbl]);
      final Uint8List mdia = _box('mdia', <Uint8List>[_withDuration(track.mdhd, 12, 20, ticks), track.hdlr, minf]);
      final Uint8List trak = _box('trak', <Uint8List>[_withDuration(track.tkhd, 16, 24, movieTicks), mdia]);
      final Uint8List moov = _box('moov', <Uint8List>[_withDuration(track.mvhd, 12, 20, movieTicks), trak]);
      final _Writer w = _Writer()
        ..bytes(ftyp)
        ..bytes(moov);
      final bool bigData = dataSize + 8 > 0xffffffff;
      if (bigData) {
        w
          ..u32(1)
          ..type('mdat')
          ..u64(dataSize + 16);
      } else {
        w
          ..u32(dataSize + 8)
          ..type('mdat');
      }
      return w.b.takeBytes();
    }

    // The offset depends on the header's own length; two passes settle it.
    Uint8List h = build(0);
    h = build(h.length);
    final Uint8List again = build(h.length);
    return again.length == h.length ? h : build(again.length);
  }

  /// The whole M4A in memory (for small files and tests).
  Uint8List toBytes(ByteSource src, AudioTrack track, {Duration? start, Duration? end}) {
    final List<AudioSample> samples = window(track, start, end);
    if (samples.isEmpty) {
      throw const AudioExtractError('Nothing is left between that start and end.');
    }
    final BytesBuilder out = BytesBuilder(copy: false)..add(header(track, samples));
    for (final AudioSample s in samples) {
      out.add(src.read(s.offset, s.size));
    }
    return out.takeBytes();
  }

  /// Writes the M4A to [path], streaming the frames from [src].
  void toFile(ByteSource src, AudioTrack track, String path, {Duration? start, Duration? end}) {
    final List<AudioSample> samples = window(track, start, end);
    if (samples.isEmpty) {
      throw const AudioExtractError('Nothing is left between that start and end.');
    }
    final RandomAccessFile f = File(path).openSync(mode: FileMode.write);
    try {
      f.writeFromSync(header(track, samples));
      for (final AudioSample s in samples) {
        f.writeFromSync(src.read(s.offset, s.size));
      }
    } finally {
      f.closeSync();
    }
  }
}

/// Reads [input] (MP4 or M4A) and writes its sound as M4A to [output],
/// trimmed to [start]..[end] when given. Safe to run in an isolate.
void extractAudioFile(String input, String output, {Duration? start, Duration? end}) {
  final RandomAccessFile f = File(input).openSync();
  try {
    final FileByteSource src = FileByteSource(f);
    final AudioTrack track = const Mp4AudioReader().read(src);
    const M4aWriter().toFile(src, track, output, start: start, end: end);
  } finally {
    f.closeSync();
  }
}
