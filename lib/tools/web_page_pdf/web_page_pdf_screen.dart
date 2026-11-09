import 'package:flutter/material.dart';

import '../../app/widgets/result_bar.dart';
import '../../engines/download/web_page_fetcher.dart';
import '../../engines/pdf/web_page_to_pdf.dart';
import '../../engines/share/share_engine.dart';
import '../text_to_pdf/text_to_pdf_screen.dart' show SystemTextPdfFiles, TextPdfFiles;

/// Feature 023 — Web page to PDF.
class WebPagePdfScreen extends StatefulWidget {
  const WebPagePdfScreen({super.key, this.files = const SystemTextPdfFiles(), this.maker, this.share});

  /// Writes into Files › converted, like Text to PDF.
  final TextPdfFiles files;

  /// Null uses the phone's HTTP stack.
  final WebPdfMaker? maker;
  final ShareEngine? share;

  @override
  State<WebPagePdfScreen> createState() => _WebPagePdfScreenState();
}

class _WebPagePdfScreenState extends State<WebPagePdfScreen> {
  final TextEditingController _url = TextEditingController();
  late final WebPdfMaker _maker = widget.maker ?? WebPdfMaker(source: HttpWebPageSource());
  WebPdfMode _mode = WebPdfMode.reader;
  WebPdfResult? _result;
  String? _path;
  String? _status;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _url.addListener(_edited);
  }

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  void _edited() {
    if (_path != null || _result != null) {
      setState(() {
        _result = null;
        _path = null;
        _status = null;
      });
    }
  }

  void _toast(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(m)));
    }
  }

  Future<void> _paste() async {
    final String? t = await widget.files.paste();
    if (!mounted) {
      return;
    }
    if (t == null || t.trim().isEmpty) {
      _toast('Nothing to paste');
      return;
    }
    _url.text = t.trim();
  }

  Future<void> _save() async {
    if (_working) {
      return;
    }
    if (_path != null) {
      _toast('Saved in Files › converted');
      return;
    }
    setState(() {
      _working = true;
      _status = 'Fetching the page…';
    });
    try {
      final WebPdfResult r = await _maker.make(_url.text, _mode);
      final String path = await widget.files.write(r.name, r.bytes);
      if (!mounted) {
        return;
      }
      setState(() {
        _result = r;
        _path = path;
        _status = 'Saved ${r.pages} ${r.pages == 1 ? 'page' : 'pages'} in Files › converted. '
            'Only the page was fetched; nothing of yours was sent.';
      });
    } on WebPdfError catch (e) {
      if (mounted) {
        setState(() => _status = e.message);
      }
    } finally {
      if (mounted) {
        setState(() => _working = false);
      }
    }
  }

  Future<void> _share() async {
    if (_path == null) {
      await _save();
    }
    final String? path = _path;
    if (path == null) {
      return;
    }
    await (widget.share ?? ShareEngine.instance).shareFiles(<String>[path]);
  }

  Future<void> _undo() async {
    final String? path = _path;
    if (path != null) {
      await widget.files.remove(path);
      setState(() {
        _result = null;
        _path = null;
        _status = 'Removed the PDF; the address is still here';
      });
      return;
    }
    if (_url.text.isNotEmpty) {
      _url.clear();
      setState(() => _status = 'Cleared the address');
      return;
    }
    if (mounted) {
      await Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final WebPdfResult? r = _result;
    return Scaffold(
      appBar: AppBar(title: const Text('Web page to PDF')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          TextField(
            key: const Key('web-pdf-url'),
            controller: _url,
            keyboardType: TextInputType.url,
            autocorrect: false,
            textInputAction: TextInputAction.go,
            onSubmitted: (String _) => _save(),
            decoration: const InputDecoration(
              labelText: 'Web address',
              hintText: 'https://example.com/article',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.link),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const Key('web-pdf-paste'),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: _working ? null : _paste,
            icon: const Icon(Icons.content_paste),
            label: const Text('Paste link'),
          ),
          const SizedBox(height: 16),
          Text('What to keep', style: text.titleSmall),
          const SizedBox(height: 4),
          SegmentedButton<WebPdfMode>(
            key: const Key('web-pdf-mode'),
            style: SegmentedButton.styleFrom(minimumSize: const Size(0, 48)),
            segments: <ButtonSegment<WebPdfMode>>[
              for (final WebPdfMode m in WebPdfMode.values)
                ButtonSegment<WebPdfMode>(value: m, label: Text(m.label), tooltip: m.hint),
            ],
            selected: <WebPdfMode>{_mode},
            onSelectionChanged: (Set<WebPdfMode> s) => setState(() {
              _mode = s.first;
              _result = null;
              _path = null;
            }),
          ),
          const SizedBox(height: 4),
          Text(_mode.hint, key: const Key('web-pdf-mode-hint'), style: text.bodySmall),
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const Key('web-pdf-make'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: _working ? null : _save,
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: const Text('Make PDF'),
          ),
          const SizedBox(height: 8),
          Text('Works for pages that open without a login. The page is read on this phone.', style: text.bodySmall),
          if (_status != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Semantics(liveRegion: true, child: Text(_status!, key: const Key('web-pdf-status'), style: text.bodyMedium)),
            ),
          if (r != null)
            ListTile(
              key: const Key('web-pdf-result'),
              leading: const Icon(Icons.description_outlined),
              title: Text(r.name),
              subtitle: Text('${r.pages} ${r.pages == 1 ? 'page' : 'pages'} · ${r.article.wordCount} words · ${r.article.url.host}'),
            ),
        ],
      ),
      bottomNavigationBar: ResultBar(onShare: _share, onSave: _save, onUndo: _undo),
    );
  }
}
