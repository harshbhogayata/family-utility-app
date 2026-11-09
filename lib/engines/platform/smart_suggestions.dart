import '../convert/file_kind.dart';

/// Feature 106 — Smart suggestions.
///
/// Which tools to offer for a file the person just opened: a fixed rule list
/// per kind of file (open a PDF, see sign, merge, compress; open a photo, see
/// resize, remove metadata), reordered so the tools this member has used
/// recently come first. Pure Dart; it looks only at the file's name or the
/// kind detected on device, and never reads or uploads the file itself.
enum SuggestKind { pdf, image, heic, word, sheet, slides, video, audio, archive, text, other }

abstract final class SmartSuggestions {
  /// The default order per kind, best first. Tool ids from the registry.
  static const Map<SuggestKind, List<String>> rules = <SuggestKind, List<String>>{
    SuggestKind.pdf: <String>[
      'merge-pdf',
      'sign-pdf',
      'compress-pdf',
      'split-pdf',
      'protect-pdf',
      'pdf-to-images',
      'extract-pages',
      'page-numbers',
      'redact-pdf',
      'pdf-search',
      'unlock-pdf',
    ],
    SuggestKind.image: <String>[
      'resize',
      'exif',
      'compress-images',
      'crop',
      'images-to-pdf',
      'rotate-flip',
      'redact',
      'convert-anything',
      'webp',
    ],
    SuggestKind.heic: <String>['heic', 'resize', 'exif', 'compress-images', 'images-to-pdf'],
    SuggestKind.word: <String>['word-pdf', 'convert-anything', 'encrypt-file'],
    SuggestKind.sheet: <String>['excel-pdf', 'convert-anything', 'encrypt-file'],
    SuggestKind.slides: <String>['powerpoint-pdf', 'convert-anything', 'encrypt-file'],
    SuggestKind.video: <String>['compress-video', 'shrink-to-send', 'send-original'],
    SuggestKind.audio: <String>['send-original', 'encrypt-file'],
    SuggestKind.archive: <String>['archives', 'encrypt-file'],
    SuggestKind.text: <String>['text-to-pdf', 'convert-anything', 'encrypt-file'],
    SuggestKind.other: <String>['encrypt-file', 'archives', 'nearby-share'],
  };

  static const Map<String, SuggestKind> _byExtension = <String, SuggestKind>{
    'pdf': SuggestKind.pdf,
    'jpg': SuggestKind.image,
    'jpeg': SuggestKind.image,
    'png': SuggestKind.image,
    'gif': SuggestKind.image,
    'webp': SuggestKind.image,
    'bmp': SuggestKind.image,
    'tif': SuggestKind.image,
    'tiff': SuggestKind.image,
    'avif': SuggestKind.image,
    'heic': SuggestKind.heic,
    'heif': SuggestKind.heic,
    'doc': SuggestKind.word,
    'docx': SuggestKind.word,
    'odt': SuggestKind.word,
    'rtf': SuggestKind.word,
    'xls': SuggestKind.sheet,
    'xlsx': SuggestKind.sheet,
    'ods': SuggestKind.sheet,
    'csv': SuggestKind.sheet,
    'ppt': SuggestKind.slides,
    'pptx': SuggestKind.slides,
    'odp': SuggestKind.slides,
    'mp4': SuggestKind.video,
    'mov': SuggestKind.video,
    'mkv': SuggestKind.video,
    'webm': SuggestKind.video,
    '3gp': SuggestKind.video,
    'mp3': SuggestKind.audio,
    'm4a': SuggestKind.audio,
    'aac': SuggestKind.audio,
    'wav': SuggestKind.audio,
    'ogg': SuggestKind.audio,
    'opus': SuggestKind.audio,
    'zip': SuggestKind.archive,
    'rar': SuggestKind.archive,
    '7z': SuggestKind.archive,
    'gz': SuggestKind.archive,
    'tar': SuggestKind.archive,
    'txt': SuggestKind.text,
    'md': SuggestKind.text,
    'json': SuggestKind.text,
  };

  /// Kind from the file name's extension (case-insensitive).
  static SuggestKind kindForName(String path) {
    final String name = path.split(RegExp(r'[/\\]')).last;
    final int dot = name.lastIndexOf('.');
    if (dot <= 0 || dot == name.length - 1) {
      return SuggestKind.other;
    }
    return _byExtension[name.substring(dot + 1).toLowerCase()] ?? SuggestKind.other;
  }

  /// Kind from the type read out of the file's bytes (feature 030).
  static SuggestKind kindForFileKind(FileKind kind) {
    switch (kind) {
      case FileKind.pdf:
        return SuggestKind.pdf;
      case FileKind.heic:
        return SuggestKind.heic;
      case FileKind.jpeg:
      case FileKind.png:
      case FileKind.gif:
      case FileKind.webp:
      case FileKind.bmp:
      case FileKind.tiff:
      case FileKind.avif:
        return SuggestKind.image;
      case FileKind.docx:
      case FileKind.doc:
        return SuggestKind.word;
      case FileKind.xlsx:
      case FileKind.xls:
      case FileKind.csv:
        return SuggestKind.sheet;
      case FileKind.pptx:
      case FileKind.ppt:
        return SuggestKind.slides;
      case FileKind.zip:
      case FileKind.rar:
      case FileKind.sevenZip:
      case FileKind.gzip:
        return SuggestKind.archive;
      case FileKind.mp4:
        return SuggestKind.video;
      case FileKind.mp3:
        return SuggestKind.audio;
      case FileKind.json:
      case FileKind.text:
        return SuggestKind.text;
      case FileKind.unknown:
        return SuggestKind.other;
    }
  }

  /// Tools to offer for [kind], at most [limit].
  ///
  /// Tools from the rule list that appear in [history] (tool ids, most recent
  /// first) move to the front in that order; the rest keep the rule order.
  /// When [available] is given, only those ids are returned (tools that are
  /// registered and allowed right now).
  static List<String> suggest(
    SuggestKind kind, {
    List<String> history = const <String>[],
    Set<String>? available,
    int limit = 4,
  }) {
    final List<String> rule = rules[kind] ?? const <String>[];
    bool ok(String id) => available == null || available.contains(id);
    final Set<String> inRule = rule.toSet();
    final List<String> out = <String>[];
    for (final String id in history) {
      if (inRule.contains(id) && ok(id) && !out.contains(id)) {
        out.add(id);
      }
    }
    for (final String id in rule) {
      if (ok(id) && !out.contains(id)) {
        out.add(id);
      }
    }
    return out.length > limit ? out.sublist(0, limit) : out;
  }

  /// Shortcut: suggestions for a file path.
  static List<String> forPath(
    String path, {
    List<String> history = const <String>[],
    Set<String>? available,
    int limit = 4,
  }) =>
      suggest(kindForName(path), history: history, available: available, limit: limit);

  /// Plain-words name of a kind, for the suggestions heading.
  static String label(SuggestKind kind) {
    switch (kind) {
      case SuggestKind.pdf:
        return 'PDF';
      case SuggestKind.image:
      case SuggestKind.heic:
        return 'photo';
      case SuggestKind.word:
        return 'document';
      case SuggestKind.sheet:
        return 'spreadsheet';
      case SuggestKind.slides:
        return 'slides';
      case SuggestKind.video:
        return 'video';
      case SuggestKind.audio:
        return 'audio';
      case SuggestKind.archive:
        return 'archive';
      case SuggestKind.text:
        return 'text file';
      case SuggestKind.other:
        return 'file';
    }
  }
}
