import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../../app/tool_registry.dart';
import '../image/exif_strip.dart';
import '../image/image_resizer.dart';
import '../pdf/pdf_compressor.dart';
import '../share/share_engine.dart';
import 'background_jobs.dart';

/// Feature 107 — Batch everywhere: every tool accepts many files.
///
/// Three pieces:
/// * [BatchPolicy] says, for every tool in the grid, how it takes many files:
///   its own picker allows multi-select, or the Batch screen runs it over many
///   files, or (rarely) the tool is one-file by nature and says why.
/// * [BatchRunner] runs one per-file step over many files, keeps going when a
///   file fails, and reports progress through [BackgroundJobs].
/// * [BatchReport] groups the results (done by output type, then failed) and
///   builds one share request for everything.

/// How one tool takes many files.
enum BatchKind {
  /// The tool's own picker allows multi-select.
  multiPicker,

  /// The tool works on one file per screen, and the Batch screen (or the tool
  /// named in [BatchSupport.via]) runs the same step over many.
  viaBatch,

  /// Hands-on work on exactly one thing (place a signature, frame a face).
  single,

  /// Does not open files from a picker at all (camera, settings, links).
  noPicker,
}

@immutable
class BatchSupport {
  const BatchSupport.multiPicker()
      : kind = BatchKind.multiPicker,
        via = null,
        reason = null;

  const BatchSupport.viaBatch(String this.via)
      : kind = BatchKind.viaBatch,
        reason = null;

  const BatchSupport.single(String this.reason)
      : kind = BatchKind.single,
        via = null;

  const BatchSupport.noPicker()
      : kind = BatchKind.noPicker,
        via = null,
        reason = null;

  final BatchKind kind;

  /// Tool id that does the many-file run, for [BatchKind.viaBatch].
  final String? via;

  /// Plain-words reason, for [BatchKind.single].
  final String? reason;
}

abstract final class BatchPolicy {
  /// Tool id of the Batch screen this feature adds.
  static const String batchToolId = 'batch';

  /// Keyed by feature number, so a tool keeps its entry if renamed.
  static const Map<int, BatchSupport> byFeature = <int, BatchSupport>{
    1: BatchSupport.single('Reads one document at a time; open the next from the Files tab.'),
    2: BatchSupport.multiPicker(),
    3: BatchSupport.single('Each PDF is cut with its own page ranges.'),
    4: BatchSupport.single('You choose and order the pages of one PDF by hand.'),
    5: BatchSupport.single('You mark the pages to drop in one PDF at a time.'),
    6: BatchSupport.single('You drag the pages of one PDF into order by hand.'),
    7: BatchSupport.single('You turn the pages of one PDF by hand, page by page or all at once.'),
    11: BatchSupport.single('Each protected PDF gets its own password, typed twice.'),
    12: BatchSupport.single('Each locked PDF has its own password, typed for that file.'),
    13: BatchSupport.single('You mark what to black out by hand on each page of one PDF.'),
    58: BatchSupport.single('Each file is locked with a password typed twice for it; zip several files first.'),
    10: BatchSupport.single('You place the signature by hand on one document.'),
    8: BatchSupport.single('One scan at a time: every page is read by the on-device model.'),
    15: BatchSupport.single('You check each page of a scan before blank ones are removed.'),
    16: BatchSupport.single('One PDF at a time here; the All PDFs tab searches every saved PDF at once.'),
    18: BatchSupport.viaBatch('batch-convert'),
    19: BatchSupport.viaBatch('batch-convert'),
    21: BatchSupport.multiPicker(),
    24: BatchSupport.noPicker(),
    22: BatchSupport.single('Each PDF gets its own page range and image size.'),
    25: BatchSupport.multiPicker(),
    26: BatchSupport.viaBatch('batch-convert'),
    27: BatchSupport.multiPicker(),
    29: BatchSupport.multiPicker(),
    30: BatchSupport.viaBatch('batch-convert'),
    31: BatchSupport.multiPicker(),
    32: BatchSupport.viaBatch(batchToolId),
    33: BatchSupport.viaBatch(batchToolId),
    34: BatchSupport.multiPicker(),
    35: BatchSupport.single('Each photo is tuned to its own exact size.'),
    36: BatchSupport.single('Videos encode one at a time on the phone hardware; queue the next when done.'),
    37: BatchSupport.multiPicker(),
    38: BatchSupport.viaBatch(batchToolId),
    40: BatchSupport.viaBatch(batchToolId),
    41: BatchSupport.single('You frame each crop by hand.'),
    42: BatchSupport.multiPicker(),
    43: BatchSupport.single('Frames one face to the passport rules.'),
    44: BatchSupport.single('Front and back of one card on one page.'),
    45: BatchSupport.single('Each picture needs its own boxes checked before it is covered.'),
    46: BatchSupport.viaBatch(batchToolId),
    47: BatchSupport.noPicker(),
    49: BatchSupport.noPicker(),
    51: BatchSupport.noPicker(),
    52: BatchSupport.single('One QR code holds one logo.'),
    55: BatchSupport.noPicker(),
    57: BatchSupport.noPicker(),
    59: BatchSupport.noPicker(),
    62: BatchSupport.multiPicker(),
    63: BatchSupport.multiPicker(),
    66: BatchSupport.single('The clipboard holds one picture.'),
    67: BatchSupport.noPicker(),
    107: BatchSupport.multiPicker(),
    108: BatchSupport.noPicker(),
    114: BatchSupport.noPicker(),
    118: BatchSupport.multiPicker(),
    123: BatchSupport.noPicker(),
    124: BatchSupport.noPicker(),
    125: BatchSupport.multiPicker(),
    126: BatchSupport.noPicker(),
    127: BatchSupport.noPicker(),
    128: BatchSupport.multiPicker(),
    129: BatchSupport.noPicker(),
  };

  static BatchSupport? of(ToolEntry tool) {
    final int? n = tool.featureNumber;
    return n == null ? null : byFeature[n];
  }

  /// Problems with [tools]: a tool with no entry, a single-file tool with no
  /// reason, or a "via" pointing at a tool that is not in the grid.
  static List<String> violations(List<ToolEntry> tools) {
    final Set<String> ids = tools.map((ToolEntry t) => t.id).toSet();
    final List<String> out = <String>[];
    for (final ToolEntry t in tools) {
      final BatchSupport? s = of(t);
      if (s == null) {
        out.add('${t.id}: no batch entry for feature ${t.featureNumber}');
        continue;
      }
      if (s.kind == BatchKind.single && (s.reason ?? '').trim().isEmpty) {
        out.add('${t.id}: single-file tool without a reason');
      }
      if (s.kind == BatchKind.viaBatch && !ids.contains(s.via)) {
        out.add('${t.id}: many-file run goes to missing tool ${s.via}');
      }
    }
    return out;
  }
}

/// One input file.
@immutable
class BatchInput {
  const BatchInput(this.path, this.bytes);

  final String path;
  final Uint8List bytes;

  String get name => path.substring(path.lastIndexOf('/') + 1);
}

/// One produced file, still in memory; the screen writes it out.
@immutable
class BatchOutput {
  const BatchOutput(this.name, this.bytes);

  final String name;
  final Uint8List bytes;
}

/// What happened to one input.
@immutable
class BatchItem {
  const BatchItem.done(this.input, this.outputs, this.paths)
      : error = null;

  const BatchItem.failed(this.input, String this.error)
      : outputs = const <BatchOutput>[],
        paths = const <String>[];

  final String input;
  final List<BatchOutput> outputs;

  /// Where [outputs] were written, same order.
  final List<String> paths;
  final String? error;

  bool get ok => error == null;
}

/// A titled group in the result list.
@immutable
class BatchGroup {
  const BatchGroup(this.title, this.items);

  final String title;
  final List<BatchItem> items;
}

/// The whole run.
@immutable
class BatchReport {
  const BatchReport(this.items, {this.cancelled = false});

  final List<BatchItem> items;
  final bool cancelled;

  List<BatchItem> get done => items.where((BatchItem i) => i.ok).toList();
  List<BatchItem> get failed => items.where((BatchItem i) => !i.ok).toList();

  /// Every written file, in input order.
  List<String> get paths => <String>[for (final BatchItem i in done) ...i.paths];

  /// "3 of 4 done, 1 failed".
  String get summary {
    final String base = '${done.length} of ${items.length} done';
    final String fail = failed.isEmpty ? '' : ', ${failed.length} failed';
    return '$base$fail${cancelled ? ', stopped' : ''}';
  }

  /// Done files grouped by output type ("PDF", "JPG"), then one "Failed" group.
  List<BatchGroup> get groups {
    final Map<String, List<BatchItem>> byType = <String, List<BatchItem>>{};
    for (final BatchItem i in done) {
      final String type = i.outputs.isEmpty ? 'Other' : typeLabel(i.outputs.first.name);
      byType.putIfAbsent(type, () => <BatchItem>[]).add(i);
    }
    final List<String> keys = byType.keys.toList()..sort();
    return <BatchGroup>[
      for (final String k in keys) BatchGroup(k, byType[k]!),
      if (failed.isNotEmpty) BatchGroup('Failed', failed),
    ];
  }

  /// One share request with every result.
  ShareRequest shareRequest() =>
      ShareRequest(files: <ShareFile>[for (final String p in paths) ShareFile(p)]);

  static String typeLabel(String name) {
    final int dot = name.lastIndexOf('.');
    if (dot < 0 || dot == name.length - 1) {
      return 'Other';
    }
    final String ext = name.substring(dot + 1).toUpperCase();
    return ext == 'JPEG' ? 'JPG' : ext;
  }
}

/// The per-file step. Throw to mark that one file failed.
typedef BatchStep = Future<List<BatchOutput>> Function(BatchInput input);

/// Writes one output and returns its path.
typedef BatchWriter = Future<String> Function(BatchOutput output);

class BatchRunner {
  BatchRunner({BackgroundJobs? jobs}) : _jobs = jobs ?? BackgroundJobs.instance;

  final BackgroundJobs _jobs;

  /// Runs [step] over every input as one background job. A failing file is
  /// recorded and the run moves on; cancelling stops before the next file and
  /// keeps what is done.
  Future<BatchReport> run(
    String title,
    List<BatchInput> inputs,
    BatchStep step,
    BatchWriter write,
  ) async {
    final List<BatchItem> items = <BatchItem>[];
    bool cancelled = false;
    try {
      await _jobs.run<int>(title, (JobContext ctx) async {
        for (int i = 0; i < inputs.length; i++) {
          ctx.report(i / inputs.length, '${i + 1} of ${inputs.length}: ${inputs[i].name}');
          final BatchInput input = inputs[i];
          try {
            final List<BatchOutput> outs = await step(input);
            if (outs.isEmpty) {
              throw const FormatException('Nothing came out');
            }
            final List<String> paths = <String>[];
            for (final BatchOutput o in outs) {
              final String path = await write(o);
              paths.add(path);
              ctx.addOutput(path);
            }
            items.add(BatchItem.done(input.name, outs, paths));
          } on JobCancelled {
            rethrow;
          } catch (e) {
            items.add(BatchItem.failed(input.name, _plain(e)));
          }
        }
        ctx.report(1);
        return items.length;
      });
    } on JobCancelled {
      cancelled = true;
    }
    return BatchReport(List<BatchItem>.unmodifiable(items), cancelled: cancelled);
  }

  static String _plain(Object e) {
    final String s = e.toString();
    return s.startsWith('FormatException: ') ? s.substring(17) : s;
  }
}

/// A tool step the Batch screen can run over many files.
@immutable
class BatchAction {
  const BatchAction({
    required this.id,
    required this.feature,
    required this.label,
    required this.hint,
    required this.extensions,
    required this.step,
  });

  final String id;
  final int feature;
  final String label;
  final String hint;

  /// Lower-case extensions the picker offers.
  final List<String> extensions;
  final BatchStep step;

  bool accepts(String path) {
    final int dot = path.lastIndexOf('.');
    return dot >= 0 && extensions.contains(path.substring(dot + 1).toLowerCase());
  }
}

String _stem(String name) {
  final int dot = name.lastIndexOf('.');
  return dot > 0 ? name.substring(0, dot) : name;
}

/// The built-in many-file steps, pure Dart on the phone.
abstract final class BatchActions {
  static const List<String> _photos = <String>['jpg', 'jpeg', 'png'];

  static final BatchAction compressPdf = BatchAction(
    id: 'compress-pdf',
    feature: 32,
    label: 'Compress PDFs',
    hint: 'Medium preset, good for email and forms',
    extensions: const <String>['pdf'],
    step: (BatchInput i) async {
      final PdfCompressResult r = PdfCompressor.compress(i.bytes, PdfPreset.medium);
      return <BatchOutput>[BatchOutput('${_stem(i.name)}-compressed.pdf', r.smaller ? r.bytes : i.bytes)];
    },
  );

  static final BatchAction pdfUnder1Mb = BatchAction(
    id: 'pdf-target-size',
    feature: 33,
    label: 'PDFs under 1 MB',
    hint: 'Each PDF squeezed under 1 MB for upload forms',
    extensions: const <String>['pdf'],
    step: (BatchInput i) async {
      final PdfTargetResult r = PdfCompressor.toTarget(i.bytes, 1024 * 1024);
      if (!r.reached) {
        throw FormatException(r.message);
      }
      return <BatchOutput>[BatchOutput('${_stem(i.name)}-1mb.pdf', r.result.bytes)];
    },
  );

  static final BatchAction shrinkPhotos = BatchAction(
    id: 'shrink-to-send',
    feature: 38,
    label: 'Shrink photos to send',
    hint: 'Half size, ready for chat apps',
    extensions: _photos,
    step: (BatchInput i) async => <BatchOutput>[_resized(i, 50, 'small')],
  );

  static final BatchAction resizeHalf = BatchAction(
    id: 'resize',
    feature: 40,
    label: 'Resize photos to 50%',
    hint: 'Same shape, half the width and height',
    extensions: _photos,
    step: (BatchInput i) async => <BatchOutput>[_resized(i, 50, 'resized')],
  );

  static final BatchAction stripExif = BatchAction(
    id: 'exif',
    feature: 46,
    label: 'Remove location and camera data',
    hint: 'Strips EXIF from JPG and PNG photos',
    extensions: _photos,
    step: (BatchInput i) async => <BatchOutput>[BatchOutput(ExifTool.cleanName(i.path), ExifTool.strip(i.bytes))],
  );

  static BatchOutput _resized(BatchInput i, double percent, String tag) {
    final ResizeResult r = ImageResizer.resize(i.bytes, ResizeSpec.percent(percent));
    return BatchOutput('${_stem(i.name)}-$tag.${r.extension}', r.bytes);
  }

  static List<BatchAction> get all => <BatchAction>[
        compressPdf,
        pdfUnder1Mb,
        shrinkPhotos,
        resizeHalf,
        stripExif,
      ];
}
