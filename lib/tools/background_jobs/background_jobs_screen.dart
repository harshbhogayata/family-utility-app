import 'package:flutter/material.dart';

import '../../app/widgets/result_bar.dart';
import '../../engines/platform/background_jobs.dart';
import '../../engines/share/share_engine.dart';

/// Feature 067 — Background jobs: what is running, with progress and Cancel.
class BackgroundJobsScreen extends StatefulWidget {
  const BackgroundJobsScreen({super.key, this.engine, this.share});

  final BackgroundJobs? engine;
  final ShareEngine? share;

  @override
  State<BackgroundJobsScreen> createState() => _BackgroundJobsScreenState();
}

class _BackgroundJobsScreenState extends State<BackgroundJobsScreen> {
  List<JobRecord> _cleared = <JobRecord>[];
  String? _status;

  BackgroundJobs get _jobs => widget.engine ?? BackgroundJobs.instance;

  JobRecord? get _lastOutput {
    for (final JobRecord j in _jobs.jobs) {
      if (j.state == JobState.done && j.outputPath != null) {
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
    await (widget.share ?? ShareEngine.instance).shareFiles(<String>[j.outputPath!]);
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
    return Card(
      key: Key('job-${j.id}'),
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
          final List<JobRecord> all = _jobs.jobs;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              const Text('Long conversions keep going when you leave the app. '
                  'Progress and Cancel also show in the notification. Everything stays on this phone.'),
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
