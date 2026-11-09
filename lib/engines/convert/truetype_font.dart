import 'dart:typed_data';

/// Just enough of a TrueType font to embed it in a PDF: units per em,
/// advance widths and the Unicode → glyph map. Used by the Word to PDF
/// renderer for text the PDF base fonts cannot draw.
class TrueTypeFont {
  TrueTypeFont._(this.bytes, this.unitsPerEm, this._advances, this._cmap);

  final Uint8List bytes;
  final int unitsPerEm;
  final List<int> _advances;
  final Map<int, int> _cmap;

  /// Parses [bytes]; throws [FormatException] when it is not a TrueType font.
  factory TrueTypeFont.parse(Uint8List bytes) {
    final ByteData d = ByteData.sublistView(bytes);
    if (bytes.length < 12) {
      throw const FormatException('Not a font');
    }
    final int count = d.getUint16(4);
    final Map<String, int> tables = <String, int>{};
    for (int i = 0; i < count; i++) {
      final int rec = 12 + i * 16;
      final String tag = String.fromCharCodes(bytes.sublist(rec, rec + 4));
      tables[tag] = d.getUint32(rec + 8);
    }
    final int? head = tables['head'];
    final int? hhea = tables['hhea'];
    final int? hmtx = tables['hmtx'];
    final int? cmap = tables['cmap'];
    if (head == null || hhea == null || hmtx == null || cmap == null) {
      throw const FormatException('Not a TrueType font');
    }
    final int upem = d.getUint16(head + 18);
    final int metrics = d.getUint16(hhea + 34);
    final List<int> advances = <int>[for (int i = 0; i < metrics; i++) d.getUint16(hmtx + i * 4)];

    final Map<int, int> map = <int, int>{};
    final int subtables = d.getUint16(cmap + 2);
    int? best;
    int bestRank = -1;
    for (int i = 0; i < subtables; i++) {
      final int platform = d.getUint16(cmap + 4 + i * 8);
      final int encoding = d.getUint16(cmap + 6 + i * 8);
      final int offset = cmap + d.getUint32(cmap + 8 + i * 8);
      final int format = d.getUint16(offset);
      int rank = -1;
      if (format == 12 && (platform == 3 && encoding == 10 || platform == 0)) {
        rank = 2;
      } else if (format == 4 && (platform == 3 && encoding == 1 || platform == 0)) {
        rank = 1;
      }
      if (rank > bestRank) {
        bestRank = rank;
        best = offset;
      }
    }
    if (best == null || bestRank < 0) {
      throw const FormatException('The font has no Unicode map');
    }
    if (d.getUint16(best) == 12) {
      final int groups = d.getUint32(best + 12);
      for (int g = 0; g < groups; g++) {
        final int at = best + 16 + g * 12;
        final int start = d.getUint32(at);
        final int end = d.getUint32(at + 4);
        final int glyph = d.getUint32(at + 8);
        for (int c = start; c <= end && c <= 0x10FFFF; c++) {
          map[c] = glyph + (c - start);
        }
      }
    } else {
      final int segX2 = d.getUint16(best + 6);
      final int ends = best + 14;
      final int starts = ends + segX2 + 2;
      final int deltas = starts + segX2;
      final int ranges = deltas + segX2;
      for (int s = 0; s < segX2 ~/ 2; s++) {
        final int end = d.getUint16(ends + s * 2);
        final int start = d.getUint16(starts + s * 2);
        final int delta = d.getInt16(deltas + s * 2);
        final int rangeOffset = d.getUint16(ranges + s * 2);
        for (int c = start; c <= end && c != 0xFFFF; c++) {
          int glyph;
          if (rangeOffset == 0) {
            glyph = (c + delta) & 0xFFFF;
          } else {
            final int at = ranges + s * 2 + rangeOffset + (c - start) * 2;
            glyph = at + 1 < bytes.length ? d.getUint16(at) : 0;
            if (glyph != 0) {
              glyph = (glyph + delta) & 0xFFFF;
            }
          }
          if (glyph != 0) {
            map[c] = glyph;
          }
        }
      }
    }
    return TrueTypeFont._(bytes, upem, advances, map);
  }

  /// The glyph for a Unicode code point, or 0 (the missing-glyph box).
  int glyphFor(int codePoint) => _cmap[codePoint] ?? 0;

  bool covers(int codePoint) => _cmap.containsKey(codePoint);

  /// Advance width of a glyph in 1/1000 em, as PDF wants it.
  int advance1000(int glyph) {
    final int a = glyph < _advances.length ? _advances[glyph] : (_advances.isEmpty ? 0 : _advances.last);
    return (a * 1000 / unitsPerEm).round();
  }

  double textWidth(String text, double size) {
    double units = 0;
    for (final int c in text.runes) {
      units += advance1000(glyphFor(c));
    }
    return units * size / 1000;
  }
}
