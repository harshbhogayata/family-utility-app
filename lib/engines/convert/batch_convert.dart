import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../platform/background_jobs.dart';
import 'convert_registry.dart';
import 'file_kind.dart';

/// Feature 031 — Batch convert. Many files, one target format, one tap.
///
/// Each file is converted by whichever registered converter (030) turns its
/// real type into the chosen format. The batch runs as one background job
/// (067) with progress per file; a file that cannot be converted is marked
/// failed with the reason and the batch carries on. All on the phone.

enum BatchItemState { waiting, running, done, failed }

/// One file in the batch.
class BatchFile {
  BatchFile({required this.name, required this.kind, required this.read});

  final String name;

  /// Its real type, read from its bytes.
  final FileKind kind;

  /// Reads the file again when its turn comes, so the whole batch is never
  /// held in memory at once.
  final Future<Uint8List> Function() read;

  BatchItemState state = BatchItemState.waiting;
  String? error;
  String? outputPath;
  String? outputName;

  String get statusLine {
    switch (state) {
      case BatchItemState.waiting:
        return 'Waiting';
      case BatchItemState.running:
        return 'Converting…';
      case BatchItemState.done:
        return 'Done · ${outputName ?? ''}';
      case BatchItemState.failed:
        return 'Failed: ${error ?? 'unknown error'}';
    }
  }
}

/// A format the batch can aim at, and how many of the files can become it.
class BatchTarget {
  const BatchTarget(this.kind, this.label, this.count);

  final FileKind kind;
  final String label;
  final int count;
}

/// What a finished batch did.
class BatchResult {
  const BatchResult({required this.done, required this.failed, required this.outputs, this.cancelled = false});

  final int done;
  final int failed;
  final List<String> outputs;
  final bool cancelled;

  String get summary {
    final String made = '$done converted';
    final String bad = failed == 0 ? '' : ', $failed failed';
    return cancelled ? 'Stopped: $made$bad' : '$made$bad';
  }
}

/// Writes a converted file somewhere and returns its path.
typedef BatchWriter = Future<String> Function(ConvertOutput out);

class BatchConverter extends ChangeNotifier {
  BatchConverter({ConvertRegistry? registry, BackgroundJobs? jobs})
      : _registry = registry,
        _jobs = jobs;

  final ConvertRegistry? _registry;
  final BackgroundJobs? _jobs;

  ConvertRegistry get registry => _registry ?? ConvertRegistry.instance;
  BackgroundJobs get jobs => _jobs ?? BackgroundJobs.instance;

  final List<BatchFile> files = <BatchFile>[];
  bool running = false;

  void setFiles(List<BatchFile> list) {
    files
      ..clear()
      ..addAll(list);
    notifyListeners();
  }

  /// The converter that turns [kind] into [target], or null.
  Converter? converterFor(FileKind kind, FileKind target) {
    for (final Converter c in registry.targetsFor(kind)) {
      if (c.target == target) {
        return c;
      }
    }
    return null;
  }

  /// Every format at least one of the files can become, most files first.
  List<BatchTarget> targets() {
    final Map<FileKind, int> counts = <FileKind, int>{};
    final Map<FileKind, String> labels = <FileKind, String>{};
    for (final BatchFile f in files) {
      final Set<FileKind> seen = <FileKind>{};
      for (final Converter c in registry.targetsFor(f.kind)) {
        if (seen.add(c.target)) {
          counts[c.target] = (counts[c.target] ?? 0) + 1;
          labels[c.target] ??= c.label;
        }
      }
    }
    final List<BatchTarget> out = <BatchTarget>[
      for (final MapEntry<FileKind, int> e in counts.entries) BatchTarget(e.key, labels[e.key]!, e.value),
    ];
    out.sort((BatchTarget a, BatchTarget b) {
      final int c = b.count.compareTo(a.count);
      return c != 0 ? c : a.kind.index.compareTo(b.kind.index);
    });
    return out;
  }

  /// Converts every file to [target] inside one background job. Failures
  /// are recorded on the file and the next file still runs.
  Future<BatchResult> run(FileKind target, BatchWriter write) async {
    if (running) {
      throw const ConvertException('A batch is already running.');
    }
    if (files.isEmpty) {
      throw const ConvertException('Pick some files first.');
    }
    running = true;
    for (final BatchFile f in files) {
      f
        ..state = BatchItemState.waiting
        ..error = null
        ..outputPath = null
        ..outputName = null;
    }
    notifyListeners();
    final List<String> outputs = <String>[];
    int done = 0;
    bool cancelled = false;
    try {
      await jobs.run<void>('Convert ${files.length} files to ${target.label}', (JobContext ctx) async {
        for (int i = 0; i < files.length; i++) {
          final BatchFile f = files[i];
          ctx.report(i / files.length, 'File ${i + 1} of ${files.length}');
          f.state = BatchItemState.running;
          notifyListeners();
          try {
            final Converter? c = converterFor(f.kind, target);
            if (c == null) {
              throw ConvertException('${f.kind.label} files cannot become ${target.label}.');
            }
            final Uint8List bytes = await f.read();
            final ConvertOutput out = await c.convert(ConvertInput(name: f.name, bytes: bytes), f.kind);
            final String path = await write(out);
            outputs.add(path);
            ctx.addOutput(path);
            f
              ..state = BatchItemState.done
              ..outputPath = path
              ..outputName = out.name;
            done++;
          } on ConvertException catch (e) {
            f
              ..state = BatchItemState.failed
              ..error = e.message;
          } catch (e) {
            // One bad file never stops the batch.
            f
              ..state = BatchItemState.failed
              ..error = e is FormatException ? 'could not be read as ${f.kind.label}' : '$e';
          }
          notifyListeners();
        }
        ctx.report(1, '$done converted');
      });
    } on JobCancelled {
      cancelled = true;
      for (final BatchFile f in files) {
        if (f.state == BatchItemState.waiting || f.state == BatchItemState.running) {
          f
            ..state = BatchItemState.failed
            ..error = 'cancelled';
        }
      }
    } finally {
      running = false;
      notifyListeners();
    }
    return BatchResult(done: done, failed: files.length - done, outputs: outputs, cancelled: cancelled);
  }
}
