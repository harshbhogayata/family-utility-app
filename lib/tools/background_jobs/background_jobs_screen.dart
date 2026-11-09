import 'package:flutter/material.dart';

import '../../app/widgets/result_bar.dart';
import '../../engines/platform/background_jobs.dart';
import '../../engines/share/share_engine.dart';

/// Feature 067 — Background jobs: what is running, with progress and Cancel.
class BackgroundJobsScreen extends StatefulWidget {
  const BackgroundJobsScreen({super.key, this.engine, this.share, this.highlight, this.note});

  final BackgroundJobs? engine;
  final ShareEngine? share;

  /// 113: the job whose notification was tapped; shown first and marked.
  final int? highlight;

  /// 113: a line to show on open, such as a file that is gone.
  final String? note;

  @override
  State<BackgroundJobsScreen> createState() => _BackgroundJobsScreenState();
}

class _BackgroundJobsScreenState extends State<BackgroundJobsScreen> {
  List<JobRecord> _cleared = <JobRecord>[];
  late String? _status = widget.note;

  BackgroundJobs get _jobs => widget.engine ?? BackgroundJobs.instance;

  JobRecord? get _lastOutput {
    for (final JobRecord j in _jobs.jobs) {
      if (!j.active && j.outputs.isNotEmpty) {
        return j;
      }
    }
    return null;
  }

  Future<void> _share() async {
    final JobRecord? j = _lastOutput;
    if (j == null) {
      setState(() => _status = 'No finished file to share yet');
      return;
    }
    await _shareJob(j);
  }

  /// 113: the same files the notification's Share button sends.
  Future<void> _shareJob(JobRecord j) async {
    await (widget.share ?? ShareEngine.instance).shareFiles(List<String>.of(j.outputs));
  }

  void _clear() {
    final List<JobRecord> gone = _jobs.clearFinished();
    setState(() {
      _cleared = gone;
      _status = gone.isEmpty ? 'Nothing finished to clear' : 'Cleared ${gone.length} finished';
    });
  }

  void _undo() {
    if (_cleared.isEmpty) {
      Navigator.of(context).maybePop();
      return;
    }
    _jobs.restore(_cleared);
    setState(() {
      _status = 'Put back ${_cleared.length}';
      _cleared = <JobRecord>[];
    });
  }

  IconData _icon(JobState s) {
    switch (s) {
      case JobState.running:
        return Icons.autorenew;
      case JobState.done:
        return Icons.check_circle_outline;
      case JobState.failed:
        return Icons.error_outline;
      case JobState.cancelled:
        return Icons.cancel_outlined;
    }
  }

  Widget _tile(JobRecord j) {
    final bool marked = j.id == widget.highlight;
    return Card(
      key: Key('job-${j.id}'),
      shape: marked
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Theme.of(context).colorScheme.primary, width: 2),
            )
          : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(children: <Widget>[
              Icon(_icon(j.state), semanticLabel: j.state.name),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                  Text(j.title, style: Theme.of(context).textTheme.titleSmall),
                  Text(j.statusLine, key: Key('job-status-${j.id}')),
                ]),
              ),
              if (j.active)
                TextButton(
                  key: Key('job-cancel-${j.id}'),
                  style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                  onPressed: () => _jobs.cancel(j.id),
                  child: Text('Cancel', semanticsLabel: 'Cancel ${j.title}'),
                ),
              if (!j.active && j.outputs.isNotEmpty)
                TextButton.icon(
                  key: Key('job-share-${j.id}'),
                  style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                  onPressed: () => _shareJob(j),
                  icon: const Icon(Icons.share_outlined),
                  label: Text(
                    j.outputs.length == 1 ? 'Share' : 'Share ${j.outputs.length}',
                    semanticsLabel: 'Share what ${j.title} made',
                  ),
                ),
            ]),
            if (j.active)
              Padding(
                padding: const EdgeInsets.only(top: 8, right: 8),
                child: LinearProgressIndicator(
                  value: j.fraction,
                  semanticsLabel: '${j.title} progress',
                  semanticsValue: '${j.percent}%',
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Background jobs')),
      body: ListenableBuilder(
        listenable: _jobs,
        builder: (BuildContext context, Widget? _) {
          final List<JobRecord> all = List<JobRecord>.of(_jobs.jobs);
          final int at = all.indexWhere((JobRecord j) => j.id == widget.highlight);
          if (at > 0) {
            all.insert(0, all.removeAt(at));
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              const Text('Long conversions keep going when you leave the app. '
                  'Progress and Cancel show in the notification; when a job ends, tap it to share the result. '
                  'Everything stays on this phone.'),
              const SizedBox(height: 12),
              if (all.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Center(child: Text('No jobs yet', key: Key('jobs-empty'))),
                ),
              for (final JobRecord j in all) _tile(j),
              if (_status != null)
                ListTile(
                  key: const Key('jobs-status'),
                  leading: const Icon(Icons.info_outline, semanticLabel: 'Note'),
                  title: Text(_status!),
                ),
            ],
          );
        },
      ),
      bottomNavigationBar: ResultBar(onShare: _share, onSave: _clear, onUndo: _undo, saveLabel: 'Clear done'),
    );
  }
}
