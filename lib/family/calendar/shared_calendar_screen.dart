import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../app/widgets/result_bar.dart';
import '../../engines/family/family_store.dart';
import '../../engines/family/shared_calendar.dart';
import '../../engines/share/share_engine.dart';

typedef CalendarShare = Future<void> Function(String ics);

/// Feature 071 — the shared calendar: the next weeks of family events, a
/// colour per member, add / edit / repeat / remind, and Share (.ics), Save
/// (one-way to the phone calendar) and Undo at the bottom.
class SharedCalendarScreen extends StatefulWidget {
  const SharedCalendarScreen({
    super.key,
    this.calendar,
    this.export,
    this.share,
    this.now,
    this.days = 42,
  });

  final SharedCalendar? calendar;
  final PhoneCalendarExport? export;
  final CalendarShare? share;
  final DateTime Function()? now;
  final int days;

  @override
  State<SharedCalendarScreen> createState() => _SharedCalendarScreenState();
}

class _SharedCalendarScreenState extends State<SharedCalendarScreen> {
  SharedCalendar get _cal => widget.calendar ?? SharedCalendar.instance;
  DateTime _now() => (widget.now ?? DateTime.now)();

  static const List<String> _weekdays = <String>['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const List<String> _months = <String>[
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec', //
  ];

  static String dayLabel(DateTime d) => '${_weekdays[d.weekday - 1]} ${d.day} ${_months[d.month - 1]}';

  static String timeLabel(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  List<FamilyRecord> get _members => _cal.space.memberRecords;

  Color _colourOf(String memberId) {
    final List<FamilyRecord> m = _members;
    final int i = m.indexWhere((FamilyRecord r) => r.id == memberId);
    return AppColors.members[(i < 0 ? 0 : i) % AppColors.members.length];
  }

  String _nameOf(String memberId) {
    for (final FamilyRecord r in _members) {
      if (r.id == memberId) {
        return '${r.fields['name'] ?? 'Member'}';
      }
    }
    return 'Member';
  }

  void _snack(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _edit([CalendarEvent? existing]) async {
    final DateTime n = _now();
    final CalendarEvent start = existing ??
        CalendarEvent(
          id: _cal.newId(),
          title: '',
          start: DateTime(n.year, n.month, n.day, n.hour + 1),
          duration: const Duration(hours: 1),
          memberId: _cal.space.identity?.deviceId ?? 'local',
        );
    final _EditResult? r = await Navigator.of(context).push<_EditResult>(MaterialPageRoute<_EditResult>(
      builder: (BuildContext context) => CalendarEventEditor(
        event: start,
        isNew: existing == null,
        members: <String, String>{for (final FamilyRecord m in _members) m.id: '${m.fields['name'] ?? 'Member'}'},
      ),
    ));
    if (r == null || !mounted) {
      return;
    }
    if (r.delete) {
      _cal.delete(start.id);
      _snack('Event deleted');
    } else if (r.event != null) {
      _cal.save(r.event!);
      _snack(existing == null ? 'Event added for everyone' : 'Event updated for everyone');
    }
  }

  Future<void> _share() async {
    final String ics = _cal.toIcs();
    final CalendarShare? s = widget.share;
    if (s != null) {
      await s(ics);
    } else {
      await ShareEngine.instance.shareText(ics, subject: 'Family calendar');
    }
  }

  Future<void> _save() async {
    final PhoneCalendarExport? ex = widget.export;
    if (ex == null) {
      _snack('Phone calendar is not available here');
      return;
    }
    final DateTime n = _now();
    final List<CalendarEvent> upcoming = _cal.events
        .where((CalendarEvent e) => e.occurrencesBetween(n, n.add(const Duration(days: 3660))).isNotEmpty)
        .toList();
    int added = 0;
    for (final CalendarEvent e in upcoming) {
      if (await ex.add(e)) {
        added++;
      }
    }
    if (mounted) {
      _snack(added == 0 ? 'Nothing added to the phone calendar' : 'Added $added to the phone calendar');
    }
  }

  void _undo() {
    _snack(_cal.undo() ? 'Undone' : 'Nothing to undo');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Shared calendar')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => unawaited(_edit()),
        icon: const Icon(Icons.add),
        label: const Text('Add event'),
      ),
      bottomNavigationBar: ResultBar(
        onShare: () => unawaited(_share()),
        onSave: () => unawaited(_save()),
        onUndo: _undo,
        saveLabel: 'To phone',
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge(<Listenable>[_cal, _cal.store]),
        builder: (BuildContext context, Widget? _) => _list(context),
      ),
    );
  }

  Widget _list(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final DateTime n = _now();
    final DateTime from = DateTime(n.year, n.month, n.day);
    final DateTime to = DateTime(n.year, n.month, n.day + widget.days);
    final List<EventOccurrence> occ = _cal.occurrences(from, to);
    final Set<EventOccurrence> clashing = <EventOccurrence>{
      for (final (EventOccurrence, EventOccurrence) c in _cal.clashes(from, to)) ...<EventOccurrence>[c.$1, c.$2],
    };
    if (occ.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Text('Nothing in the next ${widget.days ~/ 7} weeks', style: text.titleMedium),
          const SizedBox(height: 8),
          Text(
            'Add an event and it shows on every family phone, in its owner\'s colour. '
            'It syncs over your Wi-Fi or your own folder; nothing goes to a server.',
            style: text.bodyMedium,
          ),
        ],
      );
    }
    final List<Widget> rows = <Widget>[];
    DateTime? day;
    for (final EventOccurrence o in occ) {
      final DateTime d = DateTime(o.start.year, o.start.month, o.start.day);
      if (day == null || d != day) {
        day = d;
        rows.add(Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Semantics(header: true, child: Text(dayLabel(d), style: text.titleSmall)),
        ));
      }
      rows.add(_tile(o, clashing.contains(o)));
    }
    rows.add(const SizedBox(height: 88));
    return ListView(children: rows);
  }

  Widget _tile(EventOccurrence o, bool clash) {
    final CalendarEvent e = o.event;
    final String who = _nameOf(e.memberId);
    final String title = e.title.isEmpty ? 'Event' : e.title;
    final List<String> bits = <String>[
      '${timeLabel(o.start)}–${timeLabel(o.end)}',
      who,
      if (e.repeat != EventRepeat.none) e.repeat.label.toLowerCase(),
      if (e.remindBefore != null) 'reminder',
      if (clash) 'clashes',
    ];
    return Semantics(
      label: '$title, ${dayLabel(o.start)}, ${bits.join(', ')}',
      button: true,
      excludeSemantics: true,
      child: ListTile(
        minTileHeight: 56,
        leading: Container(width: 6, height: 40, decoration: BoxDecoration(color: _colourOf(e.memberId), borderRadius: BorderRadius.circular(3))),
        title: Text(title),
        subtitle: Text(bits.join(' · ')),
        trailing: clash ? const Icon(Icons.warning_amber_rounded, color: Color(0xFFB45309)) : null,
        onTap: () => unawaited(_edit(e)),
      ),
    );
  }
}

class _EditResult {
  const _EditResult.save(this.event) : delete = false;
  const _EditResult.delete()
      : event = null,
        delete = true;

  final CalendarEvent? event;
  final bool delete;
}

/// Add or edit one event.
class CalendarEventEditor extends StatefulWidget {
  const CalendarEventEditor({super.key, required this.event, required this.isNew, required this.members});

  final CalendarEvent event;
  final bool isNew;

  /// Member device id to name.
  final Map<String, String> members;

  @override
  State<CalendarEventEditor> createState() => _CalendarEventEditorState();
}

class _CalendarEventEditorState extends State<CalendarEventEditor> {
  late final TextEditingController _title = TextEditingController(text: widget.event.title);
  late final TextEditingController _note = TextEditingController(text: widget.event.note);
  late CalendarEvent _e = widget.event;

  static const Map<int, String> _durations = <int, String>{
    15: '15 min', 30: '30 min', 60: '1 hour', 90: '1½ hours', 120: '2 hours', 180: '3 hours', 1440: 'All day', //
  };
  static const Map<int, String> _reminders = <int, String>{
    -1: 'No reminder', 0: 'At the time', 10: '10 min before', 30: '30 min before', 60: '1 hour before', 1440: '1 day before', //
  };

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final DateTime? d = await showDatePicker(
      context: context,
      initialDate: _e.start,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (d != null) {
      setState(() => _e = _e.copyWith(start: DateTime(d.year, d.month, d.day, _e.start.hour, _e.start.minute)));
    }
  }

  Future<void> _pickTime() async {
    final TimeOfDay? t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_e.start));
    if (t != null) {
      setState(() => _e = _e.copyWith(start: DateTime(_e.start.year, _e.start.month, _e.start.day, t.hour, t.minute)));
    }
  }

  void _save() {
    Navigator.of(context).pop(_EditResult.save(_e.copyWith(title: _title.text.trim(), note: _note.text.trim())));
  }

  Widget _drop<T>(String label, T value, Map<T, String> items, ValueChanged<T> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: InputDecorator(
        decoration: InputDecoration(labelText: label),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<T>(
            key: Key('calendar-$label'),
            value: items.containsKey(value) ? value : items.keys.first,
            isExpanded: true,
            isDense: true,
            items: <DropdownMenuItem<T>>[
              for (final MapEntry<T, String> m in items.entries) DropdownMenuItem<T>(value: m.key, child: Text(m.value)),
            ],
            onChanged: (T? v) {
              if (v != null) {
                onChanged(v);
              }
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Map<String, String> members = widget.members.isEmpty
        ? <String, String>{_e.memberId: 'Me'}
        : <String, String>{...widget.members, if (!widget.members.containsKey(_e.memberId)) _e.memberId: 'Member'};
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isNew ? 'New event' : 'Edit event'),
        actions: <Widget>[
          if (!widget.isNew)
            IconButton(
              tooltip: 'Delete event',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => Navigator.of(context).pop(const _EditResult.delete()),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          TextField(
            controller: _title,
            decoration: const InputDecoration(labelText: 'Title'),
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 12),
          Row(children: <Widget>[
            Expanded(
              child: SizedBox(
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: () => unawaited(_pickDate()),
                  icon: const Icon(Icons.event),
                  label: Text(_SharedCalendarScreenState.dayLabel(_e.start)),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: SizedBox(
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: () => unawaited(_pickTime()),
                  icon: const Icon(Icons.schedule),
                  label: Text(_SharedCalendarScreenState.timeLabel(_e.start)),
                ),
              ),
            ),
          ]),
          _drop<int>('Length', _e.duration.inMinutes, _durations,
              (int m) => setState(() => _e = _e.copyWith(duration: Duration(minutes: m)))),
          _drop<EventRepeat>('Repeat', _e.repeat, <EventRepeat, String>{for (final EventRepeat r in EventRepeat.values) r: r.label},
              (EventRepeat r) => setState(() => _e = _e.copyWith(repeat: r))),
          _drop<int>('Reminder', _e.remindBefore?.inMinutes ?? -1, _reminders,
              (int m) => setState(() => _e = m < 0 ? _e.copyWith(clearRemind: true) : _e.copyWith(remindBefore: Duration(minutes: m)))),
          _drop<String>('Whose event', _e.memberId, members, (String id) => setState(() => _e = _e.copyWith(memberId: id))),
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            decoration: const InputDecoration(labelText: 'Note (optional)'),
            maxLines: 3,
            minLines: 1,
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 48,
            child: FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.check),
              label: const Text('Save event'),
            ),
          ),
        ],
      ),
    );
  }
}
