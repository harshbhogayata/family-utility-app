import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../image/exact_kb.dart';
import '../pdf/pdf_compressor.dart';
import '../video/video_compressor.dart';

/// Feature 038 — Shrink-to-send presets.
///
/// One tap such as "Under 25 MB for email": the file type picks the engine
/// (032 PDF, 035 image to exact size, 036 video) and the preset gives the
/// limit. The preset list is the person's to edit.

@immutable
class ShrinkPreset {
  const ShrinkPreset({required this.id, required this.label, required this.targetBytes});

  final String id;
  final String label;
  final int targetBytes;

  Map<String, Object?> toJson() => <String, Object?>{'id': id, 'label': label, 'bytes': targetBytes};

  static ShrinkPreset? fromJson(Object? json) {
    if (json is! Map) {
      return null;
    }
    final Object? id = json['id'];
    final Object? label = json['label'];
    final Object? bytes = json['bytes'];
    if (id is! String || label is! String || bytes is! int || bytes < 1024) {
      return null;
    }
    return ShrinkPreset(id: id, label: label, targetBytes: bytes);
  }

  @override
  bool operator ==(Object other) =>
      other is ShrinkPreset && other.id == id && other.label == label && other.targetBytes == targetBytes;

  @override
  int get hashCode => Object.hash(id, label, targetBytes);
}

const int _mb = 1000 * 1000;

const List<ShrinkPreset> defaultShrinkPresets = <ShrinkPreset>[
  ShrinkPreset(id: 'email', label: 'Under 25 MB for email', targetBytes: 25 * _mb),
  ShrinkPreset(id: 'whatsapp', label: 'WhatsApp (16 MB)', targetBytes: 16 * _mb),
  ShrinkPreset(id: 'whatsapp-doc', label: 'WhatsApp document (100 MB)', targetBytes: 100 * _mb),
  ShrinkPreset(id: 'form', label: 'Form upload (200 KB)', targetBytes: 200 * 1024),
];

enum ShrinkKind { pdf, image, video, unsupported }

abstract final class ShrinkKinds {
  static const Set<String> _images = <String>{'jpg', 'jpeg', 'png', 'webp', 'bmp', 'gif'};
  static const Set<String> _videos = <String>{'mp4', 'mov', 'm4v', '3gp', 'mkv', 'webm'};

  static ShrinkKind of(String path) {
    final String name = path.substring(path.lastIndexOf('/') + 1);
    final int dot = name.lastIndexOf('.');
    final String ext = dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
    if (ext == 'pdf') {
      return ShrinkKind.pdf;
    }
    if (_images.contains(ext)) {
      return ShrinkKind.image;
    }
    if (_videos.contains(ext)) {
      return ShrinkKind.video;
    }
    return ShrinkKind.unsupported;
  }
}

class ShrinkOutcome {
  const ShrinkOutcome({
    required this.kind,
    required this.before,
    required this.after,
    required this.reached,
    this.bytes,
    this.outputPath,
    this.extension = '',
    this.unchanged = false,
  });

  final ShrinkKind kind;
  final int before;
  final int after;
  final bool reached;

  /// PDF and image results come back in memory; video as a file.
  final Uint8List? bytes;
  final String? outputPath;
  final String extension;

  /// Already under the limit; the original is sent as it is.
  final bool unchanged;
}

class ShrinkError implements Exception {
  const ShrinkError(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The three engines, behind one interface so tests can stand in.
abstract class ShrinkBackend {
  Future<ShrinkOutcome> pdf(Uint8List input, int target);
  Future<ShrinkOutcome> image(Uint8List input, int target);
  Future<ShrinkOutcome> video(String path, int target, String label);
}

class EngineShrinkBackend implements ShrinkBackend {
  EngineShrinkBackend(this.videos);

  final VideoCompressor videos;

  @override
  Future<ShrinkOutcome> pdf(Uint8List input, int target) async {
    final PdfTargetResult r = PdfCompressor.toTarget(input, target);
    return ShrinkOutcome(
      kind: ShrinkKind.pdf,
      before: input.length,
      after: r.result.after,
      reached: r.reached,
      bytes: r.result.bytes,
      extension: 'pdf',
    );
  }

  @override
  Future<ShrinkOutcome> image(Uint8List input, int target) async {
    final ExactKbResult r = ExactKb.fit(input, target ~/ 1024);
    return ShrinkOutcome(
      kind: ShrinkKind.image,
      before: input.length,
      after: r.bytes.length,
      reached: r.fits,
      bytes: r.bytes,
      extension: 'jpg',
    );
  }

  @override
  Future<ShrinkOutcome> video(String path, int target, String label) async {
    final VideoResult r = await videos.compress(path, VideoPreset.target(target, label));
    return ShrinkOutcome(
      kind: ShrinkKind.video,
      before: r.input.bytes,
      after: r.outputBytes,
      reached: r.hitTarget,
      outputPath: r.outputPath,
      extension: 'mp4',
      unchanged: r.outputPath == r.input.path,
    );
  }
}

abstract class ShrinkPresetStore {
  Future<String?> read();
  Future<void> write(String json);
}

class MemoryShrinkPresetStore implements ShrinkPresetStore {
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String json) async => value = json;
}

/// The editable preset list plus the one-tap run.
class ShrinkPresets extends ChangeNotifier {
  ShrinkPresets({required this.backend, required this.store});

  final ShrinkBackend backend;
  final ShrinkPresetStore store;
  List<ShrinkPreset> _presets = List<ShrinkPreset>.of(defaultShrinkPresets);

  List<ShrinkPreset> get presets => List<ShrinkPreset>.unmodifiable(_presets);

  Future<void> load() async {
    final String? raw = await store.read();
    if (raw == null) {
      return;
    }
    try {
      final Object? list = jsonDecode(raw);
      if (list is List) {
        _presets = list.map(ShrinkPreset.fromJson).whereType<ShrinkPreset>().toList();
        notifyListeners();
      }
    } on FormatException {
      // Keep the defaults.
    }
  }

  Future<void> _save() async {
    notifyListeners();
    await store.write(jsonEncode(_presets.map((ShrinkPreset p) => p.toJson()).toList()));
  }

  /// Adds or replaces (same id) a preset. Limits under 1 KB are refused.
  Future<void> put(ShrinkPreset preset) async {
    if (preset.targetBytes < 1024) {
      throw const ShrinkError('Choose a limit of at least 1 KB');
    }
    if (preset.label.trim().isEmpty) {
      throw const ShrinkError('Give the preset a name');
    }
    final int i = _presets.indexWhere((ShrinkPreset p) => p.id == preset.id);
    if (i < 0) {
      _presets.add(preset);
    } else {
      _presets[i] = preset;
    }
    await _save();
  }

  /// Removes a preset; returns it and its place so Undo can put it back.
  Future<(ShrinkPreset, int)?> remove(String id) async {
    final int i = _presets.indexWhere((ShrinkPreset p) => p.id == id);
    if (i < 0) {
      return null;
    }
    final ShrinkPreset gone = _presets.removeAt(i);
    await _save();
    return (gone, i);
  }

  Future<void> insert(ShrinkPreset preset, int index) async {
    _presets.insert(index.clamp(0, _presets.length).toInt(), preset);
    await _save();
  }

  Future<void> move(int from, int to) async {
    final ShrinkPreset p = _presets.removeAt(from);
    _presets.insert(to.clamp(0, _presets.length).toInt(), p);
    await _save();
  }

  Future<void> reset() async {
    _presets = List<ShrinkPreset>.of(defaultShrinkPresets);
    await _save();
  }

  /// Picks the engine from the file type and shrinks under the preset's limit.
  Future<ShrinkOutcome> run(String path, ShrinkPreset preset, Future<Uint8List> Function(String path) read) async {
    final ShrinkKind kind = ShrinkKinds.of(path);
    switch (kind) {
      case ShrinkKind.video:
        return backend.video(path, preset.targetBytes, preset.label);
      case ShrinkKind.pdf:
      case ShrinkKind.image:
        final Uint8List input = await read(path);
        if (input.length <= preset.targetBytes) {
          return ShrinkOutcome(kind: kind, before: input.length, after: input.length, reached: true, bytes: input, unchanged: true);
        }
        return kind == ShrinkKind.pdf ? backend.pdf(input, preset.targetBytes) : backend.image(input, preset.targetBytes);
      case ShrinkKind.unsupported:
        throw const ShrinkError('This file type can\'t be shrunk yet. PDFs, pictures and videos can.');
    }
  }
}
