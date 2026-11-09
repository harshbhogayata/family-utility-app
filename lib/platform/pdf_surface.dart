import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../engines/pdf/pdf_reader.dart';

/// Draws PDF pages. Behind an interface so tests need no native renderer.
abstract class PdfSurface {
  /// The main reading area. Must call [PdfReader.opened] once the page count
  /// is known, [PdfReader.scrolledTo] as the person scrolls, and follow
  /// [PdfReader.jumpRequest].
  Widget viewer(BuildContext context, String path, PdfReader reader);

  Widget thumbnail(BuildContext context, String path, int page);
}

/// Last-read page per file in the app's preferences.
class PrefsLastPageStore implements LastPageStore {
  const PrefsLastPageStore();

  static String _key(String fileKey) => 'pdf_last_page:$fileKey';

  @override
  Future<int?> read(String fileKey) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_key(fileKey));
  }

  @override
  Future<void> write(String fileKey, int page) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_key(fileKey), page);
  }
}

/// pdfrx (PDFium on device): fast first page, text selection, no network.
class PdfrxSurface implements PdfSurface {
  const PdfrxSurface();

  @override
  Widget viewer(BuildContext context, String path, PdfReader reader) {
    return _PdfrxViewer(key: ValueKey<String>('${reader.layout}:$path'), path: path, reader: reader);
  }

  @override
  Widget thumbnail(BuildContext context, String path, int page) {
    return PdfDocumentViewBuilder.file(
      path,
      builder: (BuildContext ctx, PdfDocument? document) => PdfPageView(document: document, pageNumber: page),
    );
  }
}

class _PdfrxViewer extends StatefulWidget {
  const _PdfrxViewer({super.key, required this.path, required this.reader});

  final String path;
  final PdfReader reader;

  @override
  State<_PdfrxViewer> createState() => _PdfrxViewerState();
}

class _PdfrxViewerState extends State<_PdfrxViewer> {
  final PdfViewerController _controller = PdfViewerController();
  PageController? _pages;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    widget.reader.jumpRequest.addListener(_jump);
  }

  @override
  void dispose() {
    widget.reader.jumpRequest.removeListener(_jump);
    _pages?.dispose();
    super.dispose();
  }

  void _jump() {
    final int? n = widget.reader.jumpRequest.value;
    if (n == null || !_ready) {
      return;
    }
    if (widget.reader.layout == PdfLayout.continuous) {
      _controller.goToPage(pageNumber: n);
    } else {
      _pages?.jumpToPage(n - 1);
    }
  }

  Future<void> _opened(int count) async {
    final int start = await widget.reader.opened(count);
    _ready = true;
    if (start != 1) {
      if (widget.reader.layout == PdfLayout.continuous) {
        await _controller.goToPage(pageNumber: start);
      } else {
        _pages?.jumpToPage(start - 1);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final PdfReader r = widget.reader;
    if (r.layout == PdfLayout.continuous) {
      return PdfViewer.file(
        widget.path,
        controller: _controller,
        params: PdfViewerParams(
          onViewerReady: (PdfDocument document, PdfViewerController controller) {
            _opened(document.pages.length);
          },
          onPageChanged: (int? page) {
            if (page != null) {
              r.scrolledTo(page);
            }
          },
        ),
      );
    }
    return PdfDocumentViewBuilder.file(
      widget.path,
      builder: (BuildContext ctx, PdfDocument? document) {
        if (document == null) {
          return const Center(child: CircularProgressIndicator());
        }
        if (_pages == null) {
          _pages = PageController(initialPage: r.page - 1);
          WidgetsBinding.instance.addPostFrameCallback((_) => _opened(document.pages.length));
        }
        return PageView.builder(
          controller: _pages,
          itemCount: document.pages.length,
          onPageChanged: (int i) => r.scrolledTo(i + 1),
          itemBuilder: (BuildContext c, int i) => InteractiveViewer(
            maxScale: 6,
            child: PdfPageView(document: document, pageNumber: i + 1),
          ),
        );
      },
    );
  }
}
