import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:pasteboard/pasteboard.dart';

import '../engines/share/copy_result.dart';

/// The system clipboard: Flutter's for text, `pasteboard` for images.
class SystemClipboardBackend implements ClipboardBackend {
  const SystemClipboardBackend();

  @override
  Future<void> setText(String text) => Clipboard.setData(ClipboardData(text: text));

  @override
  Future<bool> setImage(Uint8List png) async {
    try {
      await Pasteboard.writeImage(png);
      return true;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    } on UnimplementedError {
      return false;
    }
  }

  @override
  Future<String?> getText() async => (await Clipboard.getData(Clipboard.kTextPlain))?.text;

  @override
  Future<void> clear() => Clipboard.setData(const ClipboardData(text: ''));
}
