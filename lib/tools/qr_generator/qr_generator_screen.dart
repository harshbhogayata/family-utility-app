import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../app/widgets/result_bar.dart';
import '../../engines/qr/qr_generator.dart';
import '../../engines/share/share_engine.dart';

/// Logo picking and saving for the QR generator, behind an interface so
/// tests need neither the picker nor the disk.
abstract class QrFiles {
  Future<Uint8List?> pickLogo();
  Future<String> write(String name, Uint8List bytes);
  Future<void> remove(String path);
}

class SystemQrFiles implements QrFiles {
  const SystemQrFiles();

  @override
  Future<Uint8List?> pickLogo() async {
    final FilePickerResult? r = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: <String>['png', 'jpg', 'jpeg'],
    );
    final String? path = r?.files.single.path;
    return path == null ? null : File(path).readAsBytes();
  }

  @override
  Future<String> write(String name, Uint8List bytes) async {
    final Directory dir = Directory('${(await getApplicationDocumentsDirectory()).path}/qr');
    await dir.create(recursive: true);
    final int dot = name.lastIndexOf('.');
    String path = '${dir.path}/$name';
    int n = 2;
    while (File(path).existsSync()) {
      path = '${dir.path}/${name.substring(0, dot)} ($n)${name.substring(dot)}';
      n++;
    }
    await File(path).writeAsBytes(bytes, flush: true);
    return path;
  }

  @override
  Future<void> remove(String path) async {
    final File f = File(path);
    if (f.existsSync()) {
      await f.delete();
    }
  }
}

/// Feature 052 — QR generator.
class QrGeneratorScreen extends StatefulWidget {
  const QrGeneratorScreen({super.key, this.files = const SystemQrFiles(), this.share});

  final QrFiles files;
  final ShareEngine? share;

  @override
  State<QrGeneratorScreen> createState() => _QrGeneratorScreenState();
}

class _QrGeneratorScreenState extends State<QrGeneratorScreen> {
  static const Map<String, int> _colours = <String, int>{
    'Black': 0xFF000000,
    'Navy': 0xFF1A237E,
    'Green': 0xFF1B5E20,
    'Maroon': 0xFF7B1F1F,
    'Light grey': 0xFFBDBDBD,
  };

  QrKind _kind = QrKind.url;
  WifiAuth _auth = WifiAuth.wpa;
  int _fg = 0xFF000000;
  Uint8List? _logo;
  final Map<String, TextEditingController> _f = <String, TextEditingController>{};
  final List<String> _saved = <String>[];
  String? _status;

  TextEditingController _c(String key) => _f.putIfAbsent(key, () => TextEditingController());

  @override
  void dispose() {
    for (final TextEditingController c in _f.values) {
      c.dispose();
    }
    super.dispose();
  }

  QrStyle get _style => QrStyle(foreground: _fg, logo: _logo);

  /// The text inside the code, or throws [QrContentError].
  String _content() {
    String t(String k) => _c(k).text;
    switch (_kind) {
      case QrKind.url:
        return QrContent.url(t('url'));
      case QrKind.wifi:
        return QrContent.wifi(t('ssid'), t('wifi-password'), auth: _auth);
      case QrKind.upi:
        return QrContent.upi(t('vpa'), name: t('payee'), amount: t('amount'), note: t('note'));
      case QrKind.vcard:
        return QrContent.vcard(name: t('name'), phone: t('phone'), email: t('email'), organisation: t('org'));
      case QrKind.whatsapp:
        return QrContent.whatsapp(t('wa-phone'), message: t('wa-message'));
      case QrKind.text:
        if (t('text').trim().isEmpty) {
          throw const QrContentError('Type some text');
        }
        return t('text');
    }
  }

  String? get _contentOrNull {
    try {
      return _content();
    } on QrContentError {
      return null;
    }
  }

  String get _baseName => 'qr-${_kind.name}';

  Future<void> _export(String what) async {
    final String data;
    try {
      data = _content();
    } on QrContentError catch (e) {
      setState(() => _status = e.message);
      return;
    }
    if (!_style.scannable) {
      setState(() => _status = 'That colour is too light to scan; pick a darker one');
      return;
    }
    final String path;
    switch (what) {
      case 'svg':
        path = await widget.files.write('$_baseName.svg', Uint8List.fromList(utf8.encode(QrRender.svg(data, _style))));
      case 'pdf':
        path = await widget.files.write('$_baseName-sheet.pdf', await QrRender.printSheet(data, _style));
      default:
        path = await widget.files.write('$_baseName.png', QrRender.png(data, _style));
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _saved.add(path);
      _status = 'Saved ${path.substring(path.lastIndexOf('/') + 1)} in Files › qr';
    });
  }

  Future<void> _pickLogo() async {
    final Uint8List? logo = await widget.files.pickLogo();
    if (!mounted || logo == null) {
      return;
    }
    setState(() => _logo = logo);
  }

  Future<void> _share() async {
    if (_saved.isEmpty) {
      await _export('png');
    }
    if (_saved.isNotEmpty) {
      await (widget.share ?? ShareEngine.instance).shareFiles(<String>[_saved.last]);
    }
  }

  Future<void> _undo() async {
    if (_saved.isEmpty) {
      Navigator.of(context).maybePop();
      return;
    }
    final String last = _saved.removeLast();
    await widget.files.remove(last);
    setState(() => _status = 'Removed ${last.substring(last.lastIndexOf('/') + 1)}');
  }

  Widget _field(String key, String label, {TextInputType? type, bool obscure = false, int lines = 1}) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: TextField(
          key: Key('qr-$key'),
          controller: _c(key),
          keyboardType: type,
          obscureText: obscure,
          maxLines: lines,
          decoration: InputDecoration(labelText: label),
          onChanged: (_) => setState(() {}),
        ),
      );

  List<Widget> _fields() {
    switch (_kind) {
      case QrKind.url:
        return <Widget>[_field('url', 'Link', type: TextInputType.url)];
      case QrKind.wifi:
        return <Widget>[
          _field('ssid', 'Network name'),
          if (_auth != WifiAuth.open) _field('wifi-password', 'Password'),
          Wrap(spacing: 8, children: <Widget>[
            for (final WifiAuth a in WifiAuth.values)
              ChoiceChip(
                materialTapTargetSize: MaterialTapTargetSize.padded,
                label: Text(a == WifiAuth.open ? 'No password' : a.name.toUpperCase()),
                selected: _auth == a,
                onSelected: (_) => setState(() => _auth = a),
              ),
          ]),
        ];
      case QrKind.upi:
        return <Widget>[
          _field('vpa', 'UPI ID (name@bank)', type: TextInputType.emailAddress),
          _field('payee', 'Name shown to the payer'),
          _field('amount', 'Amount in ₹ (optional)', type: const TextInputType.numberWithOptions(decimal: true)),
          _field('note', 'Note (optional)'),
        ];
      case QrKind.vcard:
        return <Widget>[
          _field('name', 'Full name'),
          _field('phone', 'Phone', type: TextInputType.phone),
          _field('email', 'Email', type: TextInputType.emailAddress),
          _field('org', 'Organisation'),
        ];
      case QrKind.whatsapp:
        return <Widget>[
          _field('wa-phone', 'Number with country code', type: TextInputType.phone),
          _field('wa-message', 'Message (optional)', lines: 2),
        ];
      case QrKind.text:
        return <Widget>[_field('text', 'Text', lines: 3)];
    }
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final String? data = _contentOrNull;
    return Scaffold(
      appBar: AppBar(title: const Text('QR generator')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Wrap(spacing: 8, children: <Widget>[
            for (final QrKind k in QrKind.values)
              ChoiceChip(
                key: Key('qr-kind-${k.name}'),
                materialTapTargetSize: MaterialTapTargetSize.padded,
                label: Text(k.label),
                selected: _kind == k,
                onSelected: (_) => setState(() {
                  _kind = k;
                  _status = null;
                }),
              ),
          ]),
          const SizedBox(height: 12),
          ..._fields(),
          const SizedBox(height: 8),
          Text('Colour', style: text.titleSmall),
          Wrap(spacing: 8, children: <Widget>[
            for (final MapEntry<String, int> c in _colours.entries)
              ChoiceChip(
                key: Key('qr-colour-${c.key}'),
                materialTapTargetSize: MaterialTapTargetSize.padded,
                avatar: CircleAvatar(backgroundColor: Color(c.value)),
                label: Text(c.key),
                selected: _fg == c.value,
                onSelected: (_) => setState(() => _fg = c.value),
              ),
          ]),
          if (!_style.scannable)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text('Too light: phones may not scan it.'),
            ),
          const SizedBox(height: 8),
          Row(children: <Widget>[
            Expanded(
              child: OutlinedButton.icon(
                key: const Key('qr-logo'),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                onPressed: _pickLogo,
                icon: const Icon(Icons.image_outlined),
                label: Text(_logo == null ? 'Add a logo' : 'Change logo'),
              ),
            ),
            if (_logo != null)
              IconButton(
                key: const Key('qr-logo-remove'),
                tooltip: 'Remove logo',
                onPressed: () => setState(() => _logo = null),
                icon: const Icon(Icons.close),
              ),
          ]),
          const SizedBox(height: 16),
          Center(
            child: data == null
                ? const SizedBox(height: 120, child: Center(child: Text('Fill in the details to see the code')))
                : Semantics(
                    label: 'QR code preview',
                    image: true,
                    child: Image.memory(
                      QrRender.png(data, _style, size: 480),
                      key: const Key('qr-preview'),
                      width: 240,
                      height: 240,
                      gaplessPlayback: true,
                      excludeFromSemantics: true,
                    ),
                  ),
          ),
          const SizedBox(height: 16),
          Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
            FilledButton.icon(
              key: const Key('qr-save-png'),
              style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: () => _export('png'),
              icon: const Icon(Icons.image),
              label: const Text('PNG'),
            ),
            FilledButton.tonalIcon(
              key: const Key('qr-save-svg'),
              style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: () => _export('svg'),
              icon: const Icon(Icons.polyline),
              label: const Text('SVG'),
            ),
            FilledButton.tonalIcon(
              key: const Key('qr-print'),
              style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: () => _export('pdf'),
              icon: const Icon(Icons.print),
              label: const Text('Print sheet'),
            ),
          ]),
          if (_status != null)
            ListTile(
              key: const Key('qr-status'),
              leading: const Icon(Icons.info_outline, semanticLabel: 'Note'),
              title: Text(_status!),
            ),
        ],
      ),
      bottomNavigationBar: ResultBar(onShare: _share, onSave: () => _export('png'), onUndo: _undo),
    );
  }
}
