import 'dart:convert';
import 'dart:typed_data';

/// Feature 030 — the real type of a file, read from its bytes.
///
/// The extension is never trusted: a PNG renamed to `.jpg` is a PNG, and the
/// list of formats it can become follows from that.
enum FileKind {
  jpeg('JPG', 'jpg', 'image/jpeg'),
  png('PNG', 'png', 'image/png'),
  gif('GIF', 'gif', 'image/gif'),
  webp('WebP', 'webp', 'image/webp'),
  bmp('BMP', 'bmp', 'image/bmp'),
  tiff('TIFF', 'tiff', 'image/tiff'),
  heic('HEIC', 'heic', 'image/heic'),
  avif('AVIF', 'avif', 'image/avif'),
  pdf('PDF', 'pdf', 'application/pdf'),
  docx('Word document', 'docx', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'),
  doc('Word 97-2003 document', 'doc', 'application/msword'),
  xlsx('Excel workbook', 'xlsx', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'),
  xls('Excel 97-2003 workbook', 'xls', 'application/vnd.ms-excel'),
  pptx('PowerPoint deck', 'pptx', 'application/vnd.openxmlformats-officedocument.presentationml.presentation'),
  ppt('PowerPoint 97-2003 deck', 'ppt', 'application/vnd.ms-powerpoint'),
  zip('ZIP', 'zip', 'application/zip'),
  rar('RAR', 'rar', 'application/vnd.rar'),
  sevenZip('7Z', '7z', 'application/x-7z-compressed'),
  gzip('GZip', 'gz', 'application/gzip'),
  mp4('MP4 video', 'mp4', 'video/mp4'),
  mp3('MP3 audio', 'mp3', 'audio/mpeg'),
  json('JSON', 'json', 'application/json'),
  csv('CSV', 'csv', 'text/csv'),
  text('Text', 'txt', 'text/plain'),
  unknown('File', 'bin', 'application/octet-stream');

  const FileKind(this.label, this.extension, this.mimeType);

  final String label;
  final String extension;
  final String mimeType;

  bool get isImage => const <FileKind>{
        FileKind.jpeg,
        FileKind.png,
        FileKind.gif,
        FileKind.webp,
        FileKind.bmp,
        FileKind.tiff,
        FileKind.heic,
        FileKind.avif,
      }.contains(this);

  bool get isText => this == FileKind.json || this == FileKind.csv || this == FileKind.text;
}

bool _at(Uint8List b, int offset, List<int> sig) {
  if (b.length < offset + sig.length) {
    return false;
  }
  for (int i = 0; i < sig.length; i++) {
    if (b[offset + i] != sig[i]) {
      return false;
    }
  }
  return true;
}

bool _contains(Uint8List b, List<int> needle) {
  final int last = b.length - needle.length;
  for (int i = 0; i <= last; i++) {
    if (b[i] == needle[0] && _at(b, i, needle)) {
      return true;
    }
  }
  return false;
}

/// AVIF: major brand `avif`/`avis`, or a generic HEIF major brand
/// (`mif1`/`msf1`) whose compatible brands list `avif`/`avis`.
bool _isAvif(Uint8List b, String major) {
  const Set<String> avif = <String>{'avif', 'avis'};
  if (avif.contains(major)) {
    return true;
  }
  if (major != 'mif1' && major != 'msf1') {
    return false;
  }
  final int boxSize = (b[0] << 24) | (b[1] << 16) | (b[2] << 8) | b[3];
  final int end = boxSize < b.length ? boxSize : b.length;
  for (int i = 16; i + 4 <= end; i += 4) {
    if (avif.contains(latin1.decode(b.sublist(i, i + 4)))) {
      return true;
    }
  }
  return false;
}

/// Reads the type from the first bytes (and, for text, the content).
FileKind sniffFileKind(Uint8List b) {
  if (_at(b, 0, const <int>[0xFF, 0xD8, 0xFF])) {
    return FileKind.jpeg;
  }
  if (_at(b, 0, const <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])) {
    return FileKind.png;
  }
  if (_at(b, 0, ascii.encode('GIF87a')) || _at(b, 0, ascii.encode('GIF89a'))) {
    return FileKind.gif;
  }
  if (_at(b, 0, ascii.encode('RIFF')) && _at(b, 8, ascii.encode('WEBP'))) {
    return FileKind.webp;
  }
  if (_at(b, 0, ascii.encode('BM')) && b.length > 26) {
    return FileKind.bmp;
  }
  if (_at(b, 0, const <int>[0x49, 0x49, 0x2A, 0x00]) || _at(b, 0, const <int>[0x4D, 0x4D, 0x00, 0x2A])) {
    return FileKind.tiff;
  }
  if (_at(b, 4, ascii.encode('ftyp'))) {
    final String brand = b.length >= 12 ? latin1.decode(b.sublist(8, 12)) : '';
    if (_isAvif(b, brand)) {
      return FileKind.avif;
    }
    if (const <String>{'heic', 'heix', 'hevc', 'mif1', 'msf1', 'heim', 'heis'}.contains(brand)) {
      return FileKind.heic;
    }
    return FileKind.mp4;
  }
  if (_at(b, 0, ascii.encode('%PDF-'))) {
    return FileKind.pdf;
  }
  if (_at(b, 0, const <int>[0x50, 0x4B, 0x03, 0x04]) || _at(b, 0, const <int>[0x50, 0x4B, 0x05, 0x06])) {
    if (_contains(b, ascii.encode('word/document.xml'))) {
      return FileKind.docx;
    }
    if (_contains(b, ascii.encode('ppt/presentation.xml'))) {
      return FileKind.pptx;
    }
    return _contains(b, ascii.encode('xl/workbook.xml')) ? FileKind.xlsx : FileKind.zip;
  }
  if (_at(b, 0, const <int>[0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1]) &&
      _contains(b, <int>[for (final int c in ascii.encode('WordDocument')) ...<int>[c, 0]])) {
    return FileKind.doc;
  }
  if (_at(b, 0, const <int>[0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1]) &&
      _contains(b, <int>[for (final int c in ascii.encode('PowerPoint Document')) ...<int>[c, 0]])) {
    return FileKind.ppt;
  }
  if (_at(b, 0, const <int>[0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1]) &&
      (_contains(b, <int>[for (final int c in ascii.encode('Workbook')) ...<int>[c, 0]]) ||
          _contains(b, <int>[for (final int c in ascii.encode('Book')) ...<int>[c, 0]]))) {
    return FileKind.xls;
  }
  if (_at(b, 0, const <int>[0x52, 0x61, 0x72, 0x21, 0x1A, 0x07])) {
    return FileKind.rar;
  }
  if (_at(b, 0, const <int>[0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C])) {
    return FileKind.sevenZip;
  }
  if (_at(b, 0, const <int>[0x1F, 0x8B])) {
    return FileKind.gzip;
  }
  if (_at(b, 0, ascii.encode('ID3')) || (b.length > 1 && b[0] == 0xFF && (b[1] & 0xE0) == 0xE0)) {
    return FileKind.mp3;
  }
  return _sniffText(b);
}

FileKind _sniffText(Uint8List b) {
  if (b.isEmpty || b.contains(0)) {
    return b.isEmpty ? FileKind.text : FileKind.unknown;
  }
  final String s;
  try {
    s = utf8.decode(b);
  } on FormatException {
    return FileKind.unknown;
  }
  final String t = s.trimLeft();
  if (t.startsWith('{') || t.startsWith('[')) {
    try {
      jsonDecode(s);
      return FileKind.json;
    } on FormatException {
      // Not JSON; fall through.
    }
  }
  if (looksLikeCsv(s)) {
    return FileKind.csv;
  }
  return FileKind.text;
}

/// At least two lines, every non-empty line with the same number (≥ 2) of
/// comma-separated cells.
bool looksLikeCsv(String s) {
  final List<String> lines =
      const LineSplitter().convert(s).where((String l) => l.trim().isNotEmpty).toList();
  if (lines.length < 2) {
    return false;
  }
  final int cols = parseCsv(lines.first).first.length;
  if (cols < 2) {
    return false;
  }
  return parseCsv(s).every((List<String> row) => row.length == cols);
}

/// RFC 4180 CSV: quotes, doubled quotes and newlines inside quotes.
List<List<String>> parseCsv(String s) {
  final List<List<String>> rows = <List<String>>[];
  List<String> row = <String>[];
  final StringBuffer cell = StringBuffer();
  bool quoted = false;
  bool any = false;
  for (int i = 0; i < s.length; i++) {
    final String c = s[i];
    if (quoted) {
      if (c == '"') {
        if (i + 1 < s.length && s[i + 1] == '"') {
          cell.write('"');
          i++;
        } else {
          quoted = false;
        }
      } else {
        cell.write(c);
      }
      continue;
    }
    if (c == '"') {
      quoted = true;
      any = true;
    } else if (c == ',') {
      row.add(cell.toString());
      cell.clear();
      any = true;
    } else if (c == '\n' || c == '\r') {
      if (c == '\r' && i + 1 < s.length && s[i + 1] == '\n') {
        i++;
      }
      if (any || cell.isNotEmpty) {
        row.add(cell.toString());
        rows.add(row);
      }
      row = <String>[];
      cell.clear();
      any = false;
    } else {
      cell.write(c);
      any = true;
    }
  }
  if (any || cell.isNotEmpty) {
    row.add(cell.toString());
    rows.add(row);
  }
  return rows;
}

/// Writes rows as RFC 4180 CSV.
String writeCsv(List<List<String>> rows) {
  String esc(String v) =>
      v.contains(',') || v.contains('"') || v.contains('\n') || v.contains('\r')
          ? '"${v.replaceAll('"', '""')}"'
          : v;
  return rows.map((List<String> r) => r.map(esc).join(',')).join('\r\n');
}
