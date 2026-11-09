import 'dart:convert';
import 'dart:typed_data';

import 'package:xml/xml.dart';

import '../archive/zip_codec.dart';
import 'convert_registry.dart';

/// Feature 018 — Word to PDF and back: the document model and DOCX I/O.
///
/// A DOCX is a ZIP of XML. [DocxReader] turns `word/document.xml` (with its
/// styles and pictures) into a small model of headings, paragraphs, runs,
/// tables and images; [DocxWriter] writes the model back as a DOCX Word
/// opens for editing. Pure Dart, on the phone.

/// A stretch of text with one look.
class DocRun {
  const DocRun(
    this.text, {
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.sizePt,
    this.color,
    this.font,
  });

  final String text;
  final bool bold;
  final bool italic;
  final bool underline;

  /// Null means the paragraph's default size.
  final double? sizePt;

  /// RRGGBB, or null for automatic.
  final String? color;

  /// The font name the document asked for, if any.
  final String? font;
}

enum DocAlign { left, center, right, justify }

/// One block of the document, in reading order.
sealed class DocBlock {
  const DocBlock();
}

class DocParagraph extends DocBlock {
  const DocParagraph(this.runs, {this.headingLevel = 0, this.align = DocAlign.left});

  final List<DocRun> runs;

  /// 1–6 for headings (0 = body text; the Title style counts as 1).
  final int headingLevel;
  final DocAlign align;

  String get text => runs.map((DocRun r) => r.text).join();
}

class DocTable extends DocBlock {
  const DocTable(this.rows);

  /// Rows of cells; each cell holds its own paragraphs.
  final List<List<List<DocParagraph>>> rows;

  int get columns => rows.fold<int>(0, (int m, List<List<DocParagraph>> r) => r.length > m ? r.length : m);
}

class DocImage extends DocBlock {
  const DocImage(this.bytes, {required this.widthPt, required this.heightPt, this.extension = 'png'});

  final Uint8List bytes;
  final double widthPt;
  final double heightPt;
  final String extension;
}

class WordDocument {
  const WordDocument(this.blocks);

  final List<DocBlock> blocks;

  /// Plain text, one block per line (tables as tab-separated rows).
  String get plainText {
    final List<String> out = <String>[];
    for (final DocBlock b in blocks) {
      switch (b) {
        case final DocParagraph p:
          out.add(p.text);
        case final DocTable t:
          for (final List<List<DocParagraph>> row in t.rows) {
            out.add(row.map((List<DocParagraph> c) => c.map((DocParagraph p) => p.text).join(' ')).join('\t'));
          }
        case DocImage():
          out.add('[image]');
      }
    }
    return out.join('\n');
  }
}

const String _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
const double _emuPerPt = 12700;

Iterable<XmlElement> _kids(XmlElement e, String local) =>
    e.childElements.where((XmlElement c) => c.name.local == local);

XmlElement? _kid(XmlElement e, String local) {
  for (final XmlElement c in e.childElements) {
    if (c.name.local == local) {
      return c;
    }
  }
  return null;
}

String? _val(XmlElement? e) {
  if (e == null) {
    return null;
  }
  for (final XmlAttribute a in e.attributes) {
    if (a.name.local == 'val') {
      return a.value;
    }
  }
  return null;
}

String? _attr(XmlElement e, String local) {
  for (final XmlAttribute a in e.attributes) {
    if (a.name.local == local) {
      return a.value;
    }
  }
  return null;
}

/// A toggle like <w:b/> or <w:b w:val="false"/>.
bool _on(XmlElement? e) {
  if (e == null) {
    return false;
  }
  final String? v = _val(e);
  return v == null || !(v == '0' || v == 'false' || v == 'off');
}

class DocxReader {
  const DocxReader();

  WordDocument read(Uint8List bytes) {
    final ZipReader zip;
    try {
      zip = ZipReader(bytes);
    } catch (_) {
      throw const ConvertException('This is not a Word document (DOCX).');
    }
    Uint8List? part(String name) {
      for (final ZipEntry e in zip.entries) {
        if (e.name == name) {
          return zip.extract(e);
        }
      }
      return null;
    }

    final Uint8List? main = part('word/document.xml');
    if (main == null) {
      throw const ConvertException('This is not a Word document (DOCX).');
    }
    final Map<String, int> headingStyles = _headingStyles(part('word/styles.xml'));
    final Map<String, String> rels = _relationships(part('word/_rels/document.xml.rels'));

    final XmlDocument doc = XmlDocument.parse(utf8.decode(main, allowMalformed: true));
    final XmlElement? body = _kid(doc.rootElement, 'body');
    if (body == null) {
      return const WordDocument(<DocBlock>[]);
    }
    final List<DocBlock> blocks = <DocBlock>[];
    for (final XmlElement e in body.childElements) {
      if (e.name.local == 'p') {
        final DocParagraph p = _paragraph(e, headingStyles);
        // Pictures inside the paragraph come out as their own blocks.
        for (final XmlElement drawing in e.findAllElements('drawing', namespace: '*')) {
          final DocImage? im = _image(drawing, rels, part);
          if (im != null) {
            blocks.add(im);
          }
        }
        if (p.runs.isNotEmpty || e.findAllElements('drawing', namespace: '*').isEmpty) {
          blocks.add(p);
        }
      } else if (e.name.local == 'tbl') {
        blocks.add(_table(e, headingStyles));
      }
    }
    return WordDocument(blocks);
  }

  static Map<String, int> _headingStyles(Uint8List? styles) {
    final Map<String, int> out = <String, int>{'Title': 1};
    for (int i = 1; i <= 6; i++) {
      out['Heading$i'] = i;
    }
    if (styles == null) {
      return out;
    }
    final XmlDocument d = XmlDocument.parse(utf8.decode(styles, allowMalformed: true));
    for (final XmlElement s in d.findAllElements('style', namespace: '*')) {
      final String? id = _attr(s, 'styleId');
      final String name = (_val(_kid(s, 'name')) ?? '').toLowerCase();
      final RegExpMatch? m = RegExp(r'^heading (\d)$').firstMatch(name);
      if (id != null && m != null) {
        out[id] = int.parse(m.group(1)!);
      } else if (id != null && name == 'title') {
        out[id] = 1;
      }
    }
    return out;
  }

  static Map<String, String> _relationships(Uint8List? rels) {
    final Map<String, String> out = <String, String>{};
    if (rels == null) {
      return out;
    }
    final XmlDocument d = XmlDocument.parse(utf8.decode(rels, allowMalformed: true));
    for (final XmlElement r in d.findAllElements('Relationship', namespace: '*')) {
      final String? id = _attr(r, 'Id');
      final String? target = _attr(r, 'Target');
      if (id != null && target != null) {
        out[id] = target.startsWith('/') ? target.substring(1) : 'word/$target';
      }
    }
    return out;
  }

  static DocParagraph _paragraph(XmlElement p, Map<String, int> headings) {
    final XmlElement? ppr = _kid(p, 'pPr');
    final int level = headings[_val(ppr == null ? null : _kid(ppr, 'pStyle')) ?? ''] ?? 0;
    final DocAlign align = switch (_val(ppr == null ? null : _kid(ppr, 'jc'))) {
      'center' => DocAlign.center,
      'right' || 'end' => DocAlign.right,
      'both' || 'distribute' => DocAlign.justify,
      _ => DocAlign.left,
    };
    final List<DocRun> runs = <DocRun>[];
    void addRun(XmlElement r) {
      final XmlElement? rpr = _kid(r, 'rPr');
      final StringBuffer text = StringBuffer();
      for (final XmlElement c in r.childElements) {
        switch (c.name.local) {
          case 't':
            text.write(c.innerText);
          case 'tab':
            text.write('\t');
          case 'br' || 'cr':
            text.write('\n');
        }
      }
      if (text.isEmpty) {
        return;
      }
      final String? half = _val(rpr == null ? null : _kid(rpr, 'sz'));
      final XmlElement? fonts = rpr == null ? null : _kid(rpr, 'rFonts');
      final String? color = _val(rpr == null ? null : _kid(rpr, 'color'));
      final String? u = _val(rpr == null ? null : _kid(rpr, 'u'));
      runs.add(DocRun(
        text.toString(),
        bold: _on(rpr == null ? null : _kid(rpr, 'b')),
        italic: _on(rpr == null ? null : _kid(rpr, 'i')),
        underline: rpr != null && _kid(rpr, 'u') != null && u != 'none',
        sizePt: half == null ? null : (double.tryParse(half) ?? 0) / 2,
        color: color == null || color == 'auto' ? null : color.toUpperCase(),
        font: fonts == null ? null : (_attr(fonts, 'ascii') ?? _attr(fonts, 'hAnsi')),
      ));
    }

    for (final XmlElement c in p.childElements) {
      if (c.name.local == 'r') {
        addRun(c);
      } else if (c.name.local == 'hyperlink' || c.name.local == 'ins' || c.name.local == 'smartTag') {
        _kids(c, 'r').forEach(addRun);
      }
    }
    return DocParagraph(runs, headingLevel: level, align: align);
  }

  static DocTable _table(XmlElement t, Map<String, int> headings) {
    final List<List<List<DocParagraph>>> rows = <List<List<DocParagraph>>>[];
    for (final XmlElement tr in _kids(t, 'tr')) {
      final List<List<DocParagraph>> cells = <List<DocParagraph>>[];
      for (final XmlElement tc in _kids(tr, 'tc')) {
        cells.add(<DocParagraph>[for (final XmlElement p in _kids(tc, 'p')) _paragraph(p, headings)]);
      }
      rows.add(cells);
    }
    return DocTable(rows);
  }

  static DocImage? _image(XmlElement drawing, Map<String, String> rels, Uint8List? Function(String) part) {
    final XmlElement? extent = drawing.findAllElements('extent', namespace: '*').firstOrNull;
    final XmlElement? blip = drawing.findAllElements('blip', namespace: '*').firstOrNull;
    final String? rid = blip == null ? null : _attr(blip, 'embed');
    final String? target = rid == null ? null : rels[rid];
    final Uint8List? bytes = target == null ? null : part(target);
    if (bytes == null) {
      return null;
    }
    final double cx = double.tryParse(extent == null ? '' : _attr(extent, 'cx') ?? '') ?? 0;
    final double cy = double.tryParse(extent == null ? '' : _attr(extent, 'cy') ?? '') ?? 0;
    final int dot = target!.lastIndexOf('.');
    return DocImage(
      bytes,
      widthPt: cx / _emuPerPt,
      heightPt: cy / _emuPerPt,
      extension: dot < 0 ? 'png' : target.substring(dot + 1).toLowerCase(),
    );
  }
}

String _esc(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

/// Writes the model as a DOCX that Word, Pages and Google Docs edit.
class DocxWriter {
  const DocxWriter();

  Uint8List write(WordDocument d, {DateTime? now}) {
    final List<ZipInput> media = <ZipInput>[];
    final StringBuffer rels = StringBuffer()
      ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
      ..write('<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">')
      ..write('<Relationship Id="rIdStyles" '
          'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>');
    final StringBuffer body = StringBuffer();
    int pic = 0;
    for (final DocBlock b in d.blocks) {
      switch (b) {
        case final DocParagraph p:
          body.write(_p(p));
        case final DocTable t:
          body.write(_tbl(t));
        case final DocImage im:
          pic++;
          final String name = 'image$pic.${im.extension}';
          media.add(ZipInput('word/media/$name', im.bytes, modified: now));
          rels.write('<Relationship Id="rIdImg$pic" '
              'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" '
              'Target="media/$name"/>');
          body.write(_drawing(pic, im));
      }
    }
    rels.write('</Relationships>');
    final String document = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<w:document xmlns:w="$_w" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
        'xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" '
        'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
        'xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">'
        '<w:body>$body<w:sectPr><w:pgSz w:w="11906" w:h="16838"/>'
        '<w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="708" w:footer="708" w:gutter="0"/>'
        '</w:sectPr></w:body></w:document>';
    final Set<String> exts = <String>{for (final ZipInput m in media) m.name.split('.').last};
    final String types = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '${exts.map((String e) => '<Default Extension="$e" ContentType="image/${e == 'jpg' ? 'jpeg' : e}"/>').join()}'
        '<Override PartName="/word/document.xml" '
        'ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
        '<Override PartName="/word/styles.xml" '
        'ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>'
        '</Types>';
    const String rootRels = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" '
        'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" '
        'Target="word/document.xml"/></Relationships>';
    return ZipWriter().build(<ZipInput>[
      ZipInput('[Content_Types].xml', utf8.encode(types), modified: now),
      ZipInput('_rels/.rels', utf8.encode(rootRels), modified: now),
      ZipInput('word/document.xml', utf8.encode(document), modified: now),
      ZipInput('word/styles.xml', utf8.encode(_styles()), modified: now),
      ZipInput('word/_rels/document.xml.rels', utf8.encode(rels.toString()), modified: now),
      ...media,
    ], now: now);
  }

  static String _styles() {
    final StringBuffer s = StringBuffer()
      ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
      ..write('<w:styles xmlns:w="$_w">')
      ..write('<w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/>'
          '<w:rPr><w:sz w:val="22"/></w:rPr></w:style>')
      ..write('<w:style w:type="table" w:styleId="TableGrid"><w:name w:val="Table Grid"/><w:tblPr><w:tblBorders>'
          '<w:top w:val="single" w:sz="4"/><w:left w:val="single" w:sz="4"/><w:bottom w:val="single" w:sz="4"/>'
          '<w:right w:val="single" w:sz="4"/><w:insideH w:val="single" w:sz="4"/><w:insideV w:val="single" w:sz="4"/>'
          '</w:tblBorders></w:tblPr></w:style>');
    const List<int> sizes = <int>[40, 32, 28, 26, 24, 22];
    for (int i = 1; i <= 6; i++) {
      s.write('<w:style w:type="paragraph" w:styleId="Heading$i"><w:name w:val="heading $i"/>'
          '<w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:qFormat/>'
          '<w:pPr><w:keepNext/><w:spacing w:before="240" w:after="80"/><w:outlineLvl w:val="${i - 1}"/></w:pPr>'
          '<w:rPr><w:b/><w:sz w:val="${sizes[i - 1]}"/></w:rPr></w:style>');
    }
    s.write('</w:styles>');
    return s.toString();
  }

  static String _p(DocParagraph p) {
    final StringBuffer s = StringBuffer('<w:p>');
    final String? jc = switch (p.align) {
      DocAlign.left => null,
      DocAlign.center => 'center',
      DocAlign.right => 'right',
      DocAlign.justify => 'both',
    };
    if (p.headingLevel > 0 || jc != null) {
      s.write('<w:pPr>');
      if (p.headingLevel > 0) {
        s.write('<w:pStyle w:val="Heading${p.headingLevel.clamp(1, 6)}"/>');
      }
      if (jc != null) {
        s.write('<w:jc w:val="$jc"/>');
      }
      s.write('</w:pPr>');
    }
    for (final DocRun r in p.runs) {
      s.write('<w:r>');
      final StringBuffer pr = StringBuffer();
      if (r.font != null) {
        pr.write('<w:rFonts w:ascii="${_esc(r.font!)}" w:hAnsi="${_esc(r.font!)}"/>');
      }
      if (r.bold) {
        pr.write('<w:b/>');
      }
      if (r.italic) {
        pr.write('<w:i/>');
      }
      if (r.color != null) {
        pr.write('<w:color w:val="${_esc(r.color!)}"/>');
      }
      if (r.sizePt != null) {
        pr.write('<w:sz w:val="${(r.sizePt! * 2).round()}"/>');
      }
      if (r.underline) {
        pr.write('<w:u w:val="single"/>');
      }
      if (pr.isNotEmpty) {
        s.write('<w:rPr>$pr</w:rPr>');
      }
      final List<String> lines = r.text.split('\n');
      for (int li = 0; li < lines.length; li++) {
        if (li > 0) {
          s.write('<w:br/>');
        }
        final List<String> tabs = lines[li].split('\t');
        for (int ti = 0; ti < tabs.length; ti++) {
          if (ti > 0) {
            s.write('<w:tab/>');
          }
          if (tabs[ti].isNotEmpty) {
            s.write('<w:t xml:space="preserve">${_esc(tabs[ti])}</w:t>');
          }
        }
      }
      s.write('</w:r>');
    }
    s.write('</w:p>');
    return s.toString();
  }

  static String _tbl(DocTable t) {
    final StringBuffer s = StringBuffer('<w:tbl><w:tblPr><w:tblStyle w:val="TableGrid"/><w:tblW w:w="0" w:type="auto"/>'
        '</w:tblPr><w:tblGrid>');
    final int cols = t.columns;
    for (int i = 0; i < cols; i++) {
      s.write('<w:gridCol w:w="${(9026 / (cols == 0 ? 1 : cols)).floor()}"/>');
    }
    s.write('</w:tblGrid>');
    for (final List<List<DocParagraph>> row in t.rows) {
      s.write('<w:tr>');
      for (int c = 0; c < cols; c++) {
        s.write('<w:tc>');
        final List<DocParagraph> cell = c < row.length ? row[c] : const <DocParagraph>[];
        if (cell.isEmpty) {
          s.write('<w:p/>');
        } else {
          cell.map(_p).forEach(s.write);
        }
        s.write('</w:tc>');
      }
      s.write('</w:tr>');
    }
    s.write('</w:tbl>');
    return s.toString();
  }

  static String _drawing(int id, DocImage im) {
    final int cx = (im.widthPt * _emuPerPt).round();
    final int cy = (im.heightPt * _emuPerPt).round();
    return '<w:p><w:r><w:drawing><wp:inline><wp:extent cx="$cx" cy="$cy"/><wp:docPr id="$id" name="Picture $id"/>'
        '<a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">'
        '<pic:pic><pic:nvPicPr><pic:cNvPr id="$id" name="image$id"/><pic:cNvPicPr/></pic:nvPicPr>'
        '<pic:blipFill><a:blip r:embed="rIdImg$id"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill>'
        '<pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="$cx" cy="$cy"/></a:xfrm>'
        '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr></pic:pic>'
        '</a:graphicData></a:graphic></wp:inline></w:drawing></w:r></w:p>';
  }
}
