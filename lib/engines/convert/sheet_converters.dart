import 'dart:convert';
import 'dart:typed_data';

import 'package:xml/xml.dart';

import '../archive/zip_codec.dart';
import 'convert_registry.dart';
import 'file_kind.dart';
import 'pdf_to_word.dart';
import 'truetype_font.dart';
import 'word_document.dart';
import 'word_pdf_renderer.dart';

/// Feature 019 — Excel to PDF and back.
///
/// An Excel workbook (.xlsx) is read on the phone and laid out as tables on
/// landscape pages: long sheets run on to more pages, wide sheets are cut into
/// column blocks that each fit the page width. A PDF's tables (found from the
/// positioned text, as in feature 018) become sheets of a new workbook, one
/// cell per table cell. Nothing is uploaded.

/// One sheet: its name and rows of cell text.
class SheetData {
  const SheetData(this.name, this.rows);

  final String name;
  final List<List<String>> rows;

  int get columnCount => rows.fold<int>(0, (int m, List<String> r) => r.length > m ? r.length : m);
}

/// Columns per printed block; wider sheets continue in the next block.
const int sheetColumnsPerBlock = 8;

/// "A" for 0, "Z" for 25, "AA" for 26.
String columnLetters(int index) {
  final StringBuffer b = StringBuffer();
  int n = index + 1;
  final List<String> out = <String>[];
  while (n > 0) {
    final int r = (n - 1) % 26;
    out.insert(0, String.fromCharCode(65 + r));
    n = (n - 1) ~/ 26;
  }
  b.writeAll(out);
  return b.toString();
}

/// 0-based column of a cell reference such as "AB12".
int columnOf(String ref) {
  int n = 0;
  for (final int c in ref.toUpperCase().codeUnits) {
    if (c < 65 || c > 90) {
      break;
    }
    n = n * 26 + (c - 64);
  }
  return n - 1;
}

String? _attr(XmlElement e, String local) {
  for (final XmlAttribute a in e.attributes) {
    if (a.name.local == local) {
      return a.value;
    }
  }
  return null;
}

Iterable<XmlElement> _all(XmlNode n, String local) =>
    n.descendants.whereType<XmlElement>().where((XmlElement e) => e.name.local == local);

String _texts(XmlElement e) => _all(e, 't').map((XmlElement t) => t.innerText).join();

class XlsxReader {
  const XlsxReader();

  List<SheetData> read(Uint8List bytes) {
    final ZipReader zip;
    try {
      zip = ZipReader(bytes);
    } catch (_) {
      throw const ConvertException('This is not an Excel workbook (XLSX).');
    }
    Uint8List? part(String name) {
      for (final ZipEntry e in zip.entries) {
        if (e.name == name) {
          return zip.extract(e);
        }
      }
      return null;
    }

    XmlDocument? xml(String name) {
      final Uint8List? b = part(name);
      return b == null ? null : XmlDocument.parse(utf8.decode(b, allowMalformed: true));
    }

    final XmlDocument? workbook = xml('xl/workbook.xml');
    if (workbook == null) {
      throw const ConvertException('This is not an Excel workbook (XLSX).');
    }
    final Map<String, String> targets = <String, String>{};
    final XmlDocument? rels = xml('xl/_rels/workbook.xml.rels');
    if (rels != null) {
      for (final XmlElement r in _all(rels, 'Relationship')) {
        final String? id = _attr(r, 'Id');
        final String? target = _attr(r, 'Target');
        if (id != null && target != null) {
          final String t = target.startsWith('/') ? target.substring(1) : 'xl/$target';
          targets[id] = t;
        }
      }
    }
    final List<String> shared = <String>[];
    final XmlDocument? sst = xml('xl/sharedStrings.xml');
    if (sst != null) {
      for (final XmlElement si in _all(sst, 'si')) {
        shared.add(_texts(si));
      }
    }
    final List<SheetData> out = <SheetData>[];
    int n = 0;
    for (final XmlElement s in _all(workbook, 'sheet')) {
      n++;
      final String name = _attr(s, 'name') ?? 'Sheet$n';
      final String? rid = _attr(s, 'id');
      final String path = (rid != null ? targets[rid] : null) ?? 'xl/worksheets/sheet$n.xml';
      final XmlDocument? sheet = xml(path);
      if (sheet == null) {
        continue;
      }
      out.add(SheetData(name, _rows(sheet, shared)));
    }
    if (out.isEmpty) {
      throw const ConvertException('This workbook has no sheets.');
    }
    return out;
  }

  static List<List<String>> _rows(XmlDocument sheet, List<String> shared) {
    final Map<int, Map<int, String>> cells = <int, Map<int, String>>{};
    int nextRow = 0;
    for (final XmlElement row in _all(sheet, 'row')) {
      final int r = (int.tryParse(_attr(row, 'r') ?? '') ?? nextRow + 1) - 1;
      nextRow = r + 1;
      int nextCol = 0;
      for (final XmlElement c in row.childElements.where((XmlElement e) => e.name.local == 'c')) {
        final String? ref = _attr(c, 'r');
        final int col = ref == null ? nextCol : columnOf(ref);
        nextCol = col + 1;
        final String type = _attr(c, 't') ?? 'n';
        final XmlElement? v = c.childElements.where((XmlElement e) => e.name.local == 'v').firstOrNull;
        final String text;
        switch (type) {
          case 's':
            final int? i = int.tryParse(v?.innerText.trim() ?? '');
            text = i != null && i >= 0 && i < shared.length ? shared[i] : '';
          case 'inlineStr':
            text = _texts(c);
          case 'b':
            text = v?.innerText.trim() == '1' ? 'TRUE' : 'FALSE';
          default:
            text = _number(v?.innerText.trim() ?? '');
        }
        if (text.isNotEmpty && col >= 0) {
          (cells[r] ??= <int, String>{})[col] = text;
        }
      }
    }
    if (cells.isEmpty) {
      return <List<String>>[];
    }
    final int lastRow = cells.keys.reduce((int a, int b) => a > b ? a : b);
    final int lastCol = cells.values
        .expand((Map<int, String> m) => m.keys)
        .reduce((int a, int b) => a > b ? a : b);
    return <List<String>>[
      for (int r = 0; r <= lastRow; r++)
        <String>[for (int c = 0; c <= lastCol; c++) cells[r]?[c] ?? ''],
    ];
  }

  /// "3.0000000000000004" reads as "3"; whole numbers lose ".0".
  static String _number(String raw) {
    final double? d = double.tryParse(raw);
    if (d == null) {
      return raw;
    }
    if (d == d.roundToDouble() && d.abs() < 1e15) {
      return d.toInt().toString();
    }
    final String p = d.toStringAsPrecision(12);
    return p.contains('e') ? raw : p.replaceFirst(RegExp(r'\.?0+$'), '');
  }
}

class XlsxWriter {
  const XlsxWriter();

  static String _esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '');

  static final RegExp _numeric = RegExp(r'^-?\d+(\.\d+)?$');

  Uint8List write(List<SheetData> sheets, {DateTime? now}) {
    final List<ZipInput> files = <ZipInput>[];
    final StringBuffer wbSheets = StringBuffer();
    final StringBuffer wbRels = StringBuffer();
    final StringBuffer types = StringBuffer()
      ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
      ..write('<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">')
      ..write('<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>')
      ..write('<Default Extension="xml" ContentType="application/xml"/>')
      ..write('<Override PartName="/xl/workbook.xml" '
          'ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>');
    final Set<String> used = <String>{};
    for (int i = 0; i < sheets.length; i++) {
      final SheetData s = sheets[i];
      String name = s.name.replaceAll(RegExp(r'[\\/?*\[\]:]'), ' ').trim();
      if (name.isEmpty) {
        name = 'Sheet${i + 1}';
      }
      if (name.length > 31) {
        name = name.substring(0, 31);
      }
      while (used.contains(name.toLowerCase())) {
        name = '${name.length > 27 ? name.substring(0, 27) : name} (${i + 1})';
      }
      used.add(name.toLowerCase());
      wbSheets.write('<sheet name="${_esc(name)}" sheetId="${i + 1}" r:id="rId${i + 1}"/>');
      wbRels.write('<Relationship Id="rId${i + 1}" '
          'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" '
          'Target="worksheets/sheet${i + 1}.xml"/>');
      types.write('<Override PartName="/xl/worksheets/sheet${i + 1}.xml" '
          'ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>');
      final StringBuffer data = StringBuffer();
      for (int r = 0; r < s.rows.length; r++) {
        data.write('<row r="${r + 1}">');
        for (int c = 0; c < s.rows[r].length; c++) {
          final String v = s.rows[r][c];
          if (v.isEmpty) {
            continue;
          }
          final String ref = '${columnLetters(c)}${r + 1}';
          if (_numeric.hasMatch(v) && v.length < 16) {
            data.write('<c r="$ref"><v>$v</v></c>');
          } else {
            data.write('<c r="$ref" t="inlineStr"><is><t xml:space="preserve">${_esc(v)}</t></is></c>');
          }
        }
        data.write('</row>');
      }
      files.add(ZipInput(
        'xl/worksheets/sheet${i + 1}.xml',
        utf8.encode('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
            '<sheetData>$data</sheetData></worksheet>'),
        modified: now,
      ));
    }
    types.write('</Types>');
    return ZipWriter().build(<ZipInput>[
      ZipInput('[Content_Types].xml', utf8.encode(types.toString()), modified: now),
      ZipInput(
        '_rels/.rels',
        utf8.encode('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
            '<Relationship Id="rId1" '
            'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" '
            'Target="xl/workbook.xml"/></Relationships>'),
        modified: now,
      ),
      ZipInput(
        'xl/workbook.xml',
        utf8.encode('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
            'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
            '<sheets>$wbSheets</sheets></workbook>'),
        modified: now,
      ),
      ZipInput(
        'xl/_rels/workbook.xml.rels',
        utf8.encode('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">$wbRels</Relationships>'),
        modified: now,
      ),
      ...files,
    ], now: now);
  }
}

/// Lays sheets out as a document: a heading per sheet (and per column block
/// of a wide sheet) and a table that runs on over as many pages as it needs.
WordDocument sheetsToDocument(List<SheetData> sheets, {int columnsPerBlock = sheetColumnsPerBlock}) {
  final List<DocBlock> blocks = <DocBlock>[];
  for (final SheetData s in sheets) {
    final int cols = s.columnCount;
    if (cols == 0) {
      blocks.add(DocParagraph(<DocRun>[DocRun(s.name, bold: true)], headingLevel: 2));
      blocks.add(const DocParagraph(<DocRun>[DocRun('(empty sheet)')]));
      continue;
    }
    for (int start = 0; start < cols; start += columnsPerBlock) {
      final int end = start + columnsPerBlock < cols ? start + columnsPerBlock : cols;
      final String title = cols <= columnsPerBlock
          ? s.name
          : '${s.name}, columns ${columnLetters(start)}–${columnLetters(end - 1)}';
      blocks.add(DocParagraph(<DocRun>[DocRun(title, bold: true)], headingLevel: 2));
      blocks.add(DocTable(<List<List<DocParagraph>>>[
        for (final List<String> row in s.rows)
          <List<DocParagraph>>[
            for (int c = start; c < end; c++)
              <DocParagraph>[DocParagraph(<DocRun>[DocRun(c < row.length ? row[c] : '')])],
          ],
      ]));
    }
  }
  return WordDocument(blocks);
}

/// Landscape A4 with narrow margins and small type, as spreadsheets print.
const WordPdfOptions sheetPdfOptions = WordPdfOptions(pageWidth: 841.89, pageHeight: 595.28, margin: 36, bodySize: 9);

/// The tables in a PDF's text, one sheet each; a PDF with text but no table
/// gives one sheet with a line of text per row.
List<SheetData> pdfToSheets(List<List<PdfTextPiece>> pages) {
  final WordDocument doc = const PdfToWord().build(pages);
  final List<SheetData> tables = <SheetData>[];
  final List<List<String>> lines = <List<String>>[];
  for (final DocBlock b in doc.blocks) {
    switch (b) {
      case final DocTable t:
        tables.add(SheetData('Table ${tables.length + 1}', <List<String>>[
          for (final List<List<DocParagraph>> row in t.rows)
            <String>[
              for (final List<DocParagraph> cell in row)
                cell.map((DocParagraph p) => p.runs.map((DocRun r) => r.text).join()).join('\n'),
            ],
        ]));
      case final DocParagraph p:
        final String text = p.runs.map((DocRun r) => r.text).join();
        if (text.trim().isNotEmpty) {
          lines.add(<String>[text]);
        }
      default:
        break;
    }
  }
  if (tables.isNotEmpty) {
    return tables;
  }
  if (lines.isNotEmpty) {
    return <SheetData>[SheetData('Text', lines)];
  }
  throw const ConvertException('This PDF has no text to put in cells; it may be a scan. Try OCR a scan first.');
}

class XlsxToPdfConverter extends Converter {
  XlsxToPdfConverter({this.loadUnicodeFont});

  final Future<Uint8List> Function()? loadUnicodeFont;
  TrueTypeFont? _font;

  Future<TrueTypeFont?> _unicode() async {
    final Future<Uint8List> Function()? load = loadUnicodeFont;
    if (_font == null && load != null) {
      try {
        _font = TrueTypeFont.parse(await load());
      } catch (_) {
        _font = null;
      }
    }
    return _font;
  }

  @override
  String get id => 'xlsx-to-pdf';
  @override
  String get label => 'PDF';
  @override
  FileKind get target => FileKind.pdf;
  @override
  bool accepts(FileKind kind) => kind == FileKind.xlsx;

  @override
  Future<ConvertOutput> convert(ConvertInput input, FileKind kind) async {
    final List<SheetData> sheets = const XlsxReader().read(input.bytes);
    final WordDocument doc = sheetsToDocument(sheets);
    return output(input, await WordPdfRenderer(unicodeFont: await _unicode()).render(doc, options: sheetPdfOptions));
  }
}

class PdfToXlsxConverter extends Converter {
  const PdfToXlsxConverter(this.source);

  final PdfTextSource source;

  @override
  String get id => 'pdf-to-xlsx';
  @override
  String get label => 'Excel workbook';
  @override
  FileKind get target => FileKind.xlsx;
  @override
  bool accepts(FileKind kind) => kind == FileKind.pdf;

  @override
  Future<ConvertOutput> convert(ConvertInput input, FileKind kind) async {
    final List<SheetData> sheets = pdfToSheets(await source.read(input.bytes));
    return output(input, const XlsxWriter().write(sheets));
  }
}

/// Old binary .xls files: said plainly rather than converted badly.
class LegacyXlsConverter extends Converter {
  const LegacyXlsConverter();

  @override
  String get id => 'xls-to-pdf';
  @override
  String get label => 'PDF';
  @override
  FileKind get target => FileKind.pdf;
  @override
  bool accepts(FileKind kind) => kind == FileKind.xls;

  @override
  Future<ConvertOutput> convert(ConvertInput input, FileKind kind) async {
    throw const ConvertException(
        'Old Excel 97-2003 (.xls) files cannot be read on this phone. Save it as .xlsx in Excel or Sheets, then convert it here.');
  }
}

/// Adds the Excel converters to [registry].
void registerSheetConverters(ConvertRegistry registry, PdfTextSource source,
    {Future<Uint8List> Function()? loadUnicodeFont}) {
  registry
    ..register(XlsxToPdfConverter(loadUnicodeFont: loadUnicodeFont))
    ..register(PdfToXlsxConverter(source))
    ..register(const LegacyXlsConverter());
}
