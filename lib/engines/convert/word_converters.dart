import 'convert_registry.dart';
import 'file_kind.dart';
import 'pdf_to_word.dart';
import 'word_document.dart';
import 'word_pdf_renderer.dart';

/// Feature 018 — the Word ↔ PDF converters, registered with Convert anything
/// and used by the Word to PDF tool.

class DocxToPdfConverter extends Converter {
  DocxToPdfConverter({WordPdfRenderer? renderer}) : _renderer = renderer ?? WordPdfRenderer();

  final WordPdfRenderer _renderer;

  @override
  String get id => 'docx-to-pdf';
  @override
  String get label => 'PDF';
  @override
  FileKind get target => FileKind.pdf;
  @override
  bool accepts(FileKind kind) => kind == FileKind.docx;

  @override
  Future<ConvertOutput> convert(ConvertInput input, FileKind kind) async {
    final WordDocument doc = const DocxReader().read(input.bytes);
    return output(input, await _renderer.render(doc));
  }
}

class PdfToDocxConverter extends Converter {
  const PdfToDocxConverter(this.source);

  final PdfTextSource source;

  @override
  String get id => 'pdf-to-docx';
  @override
  String get label => 'Editable Word document';
  @override
  FileKind get target => FileKind.docx;
  @override
  bool accepts(FileKind kind) => kind == FileKind.pdf;

  @override
  Future<ConvertOutput> convert(ConvertInput input, FileKind kind) async {
    final List<List<PdfTextPiece>> pages = await source.read(input.bytes);
    final WordDocument doc = const PdfToWord().build(pages);
    if (doc.blocks.isEmpty) {
      throw const ConvertException('This PDF has no text to edit; it may be a scan. Try the text option in Document scanner.');
    }
    return output(input, const DocxWriter().write(doc));
  }
}

/// Old binary .doc files: said plainly rather than converted badly.
class LegacyDocConverter extends Converter {
  const LegacyDocConverter();

  @override
  String get id => 'doc-to-pdf';
  @override
  String get label => 'PDF';
  @override
  FileKind get target => FileKind.pdf;
  @override
  bool accepts(FileKind kind) => kind == FileKind.doc;

  @override
  Future<ConvertOutput> convert(ConvertInput input, FileKind kind) async {
    throw const ConvertException(
        'Old Word 97-2003 (.doc) files cannot be read on this phone. Save it as .docx in Word, then convert it here.');
  }
}

/// Adds the Word converters to [registry].
void registerWordConverters(ConvertRegistry registry, PdfTextSource source) {
  registry
    ..register(DocxToPdfConverter())
    ..register(PdfToDocxConverter(source))
    ..register(const LegacyDocConverter());
}
