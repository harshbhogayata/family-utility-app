import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../app/theme.dart';
import '../../app/widgets/result_bar.dart';
import '../../engines/family/family_location.dart';
import '../../engines/share/share_engine.dart';
import '../../platform/location_platform.dart';

typedef LocationTextAction = Future<String?> Function(String text);

/// Feature 076 — live family location: a sharing switch per member, an
/// offline map of everyone and the family's places, and arrive / leave
/// alerts. The map is drawn on the phone; no map tiles are downloaded.
class FamilyLocationScreen extends StatefulWidget {
  const FamilyLocationScreen({super.key, this.location, this.source, this.share, this.save});

  final FamilyLocation? location;
  final PositionSource? source;
  final LocationTextAction? share;
  final LocationTextAction? save;

  @override
  State<FamilyLocationScreen> createState() => _FamilyLocationScreenState();
}

class _FamilyLocationScreenState extends State<FamilyLocationScreen> {
  final TextEditingController _place = TextEditingController();

  FamilyLocation get _loc => widget.location ?? FamilyLocation.instance;

  @override
  void dispose() {
    _place.dispose();
    super.dispose();
  }

  void _snack(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _toggle(bool on) async {
    _loc.setSharing(on);
    if (on) {
      final LocationFix? f = await _fix();
      if (f != null) {
        await _loc.report(f);
      } else if (mounted) {
        _snack('Location is off or not allowed. Sharing starts when it is on.');
      }
    }
  }

  Future<LocationFix?> _fix() async {
    try {
      return await (widget.source ?? const GeolocatorPositionSource()).current();
    } catch (_) {
      return null;
    }
  }

  Future<void> _addPlace() async {
    final String name = _place.text.trim();
    if (name.isEmpty) {
      _snack('Name the place first, like Home or School');
      return;
    }
    final LocationFix? f = (_loc.trail.isEmpty ? null : _loc.trail.last) ?? await _fix();
    if (f == null) {
      if (mounted) {
        _snack('Could not find where you are. Turn location on and try again.');
      }
      return;
    }
    _loc.addPlace(name, f.lat, f.lng);
    _place.clear();
  }

  Future<void> _share() async {
    final String text = _loc.toText();
    final LocationTextAction? s = widget.share;
    if (s != null) {
      await s(text);
    } else {
      await ShareEngine.instance.shareText(text, subject: 'Family locations');
    }
  }

  Future<void> _save() async {
    final String text = _loc.toText();
    final LocationTextAction s = widget.save ?? _saveToDocuments;
    String? where;
    try {
      where = await s(text);
    } catch (_) {
      where = null;
    }
    if (mounted) {
      _snack(where == null ? 'Could not save' : 'Saved to $where');
    }
  }

  static Future<String?> _saveToDocuments(String text) async {
    final Directory dir = await getApplicationDocumentsDirectory();
    final File f = File('${dir.path}/Family locations.txt');
    await f.writeAsString(text);
    return f.path;
  }

  static String _initial(String s) => s.trim().isEmpty ? '?' : s.trim().substring(0, 1).toUpperCase();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Family location')),
      bottomNavigationBar: ResultBar(
        onShare: () => unawaited(_share()),
        onSave: () => unawaited(_save()),
        onUndo: () => _snack(_loc.undo() ? 'Undone' : 'Nothing to undo'),
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge(<Listenable>[_loc, _loc.store]),
        builder: (BuildContext context, Widget? _) => _body(context),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final List<MemberLocation> members = _loc.members;
    final List<FamilyPlace> places = _loc.placeList;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      children: <Widget>[
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Share my location with the family'),
          subtitle: const Text('Every 2 min while moving, 15 min while still. Only to family phones.'),
          value: _loc.sharing,
          onChanged: (bool v) => unawaited(_toggle(v)),
        ),
        const SizedBox(height: 8),
        Semantics(
          label: 'Map of family members and places',
          child: SizedBox(
            height: 200,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.accentTint,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.line),
              ),
              child: CustomPaint(painter: FamilyMapPainter(_loc, members, places)),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Semantics(header: true, child: Text('Members', style: text.titleMedium)),
        for (int i = 0; i < members.length; i++)
          ListTile(
            contentPadding: EdgeInsets.zero,
            minTileHeight: 48,
            leading: CircleAvatar(
              backgroundColor: AppColors.members[i % AppColors.members.length],
              foregroundColor: Colors.white,
              child: Text(_initial(_loc.memberName(members[i].member))),
            ),
            title: Text(_loc.memberName(members[i].member)),
            subtitle: Text(_loc.lineFor(members[i])),
          ),
        const SizedBox(height: 12),
        Semantics(header: true, child: Text('Places', style: text.titleMedium)),
        Row(children: <Widget>[
          Expanded(
            child: TextField(
              controller: _place,
              decoration: const InputDecoration(labelText: 'Save where I am as'),
              textCapitalization: TextCapitalization.words,
              onSubmitted: (_) => unawaited(_addPlace()),
            ),
          ),
          const SizedBox(width: 4),
          IconButton.filled(
            tooltip: 'Add place',
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            onPressed: () => unawaited(_addPlace()),
            icon: const Icon(Icons.add_location_alt_outlined),
          ),
        ]),
        for (final FamilyPlace p in places)
          ListTile(
            contentPadding: EdgeInsets.zero,
            minTileHeight: 48,
            leading: const Icon(Icons.place_outlined),
            title: Text(p.name),
            subtitle: Text('Alerts when someone arrives or leaves · ${p.radius.round()} m'),
            trailing: IconButton(
              tooltip: 'Remove ${p.name}',
              icon: const Icon(Icons.close),
              onPressed: () => _loc.removePlace(p.id),
            ),
          ),
        const SizedBox(height: 12),
        Text(
          'Your trail of the last 7 days stays on this phone: ${_loc.trail.length} points.',
          style: text.bodySmall?.copyWith(color: AppColors.muted),
        ),
      ],
    );
  }
}

/// Members and places drawn to scale around their centre, no tiles.
class FamilyMapPainter extends CustomPainter {
  FamilyMapPainter(this.loc, this.members, this.places);

  final FamilyLocation loc;
  final List<MemberLocation> members;
  final List<FamilyPlace> places;

  @override
  void paint(Canvas canvas, Size size) {
    final List<(double, double)> pts = <(double, double)>[
      for (final MemberLocation m in members)
        if (m.fix != null) (m.fix!.lat, m.fix!.lng),
      for (final FamilyPlace p in places) (p.lat, p.lng),
    ];
    if (pts.isEmpty) {
      return;
    }
    double minLat = pts.first.$1, maxLat = pts.first.$1, minLng = pts.first.$2, maxLng = pts.first.$2;
    for (final (double, double) p in pts) {
      minLat = math.min(minLat, p.$1);
      maxLat = math.max(maxLat, p.$1);
      minLng = math.min(minLng, p.$2);
      maxLng = math.max(maxLng, p.$2);
    }
    final double span = math.max(math.max(maxLat - minLat, maxLng - minLng), 0.005);
    final double cLat = (minLat + maxLat) / 2;
    final double cLng = (minLng + maxLng) / 2;
    final double scale = math.min(size.width, size.height) * 0.8 / span;
    Offset at(double lat, double lng) =>
        Offset(size.width / 2 + (lng - cLng) * scale, size.height / 2 - (lat - cLat) * scale);

    final Paint place = Paint()..color = AppColors.accent.withValues(alpha: 0.18);
    for (final FamilyPlace p in places) {
      final Offset o = at(p.lat, p.lng);
      canvas.drawCircle(o, math.max(10, p.radius / 111000 * scale), place);
      _label(canvas, p.name, o + const Offset(0, 12));
    }
    for (int i = 0; i < members.length; i++) {
      final LocationFix? f = members[i].fix;
      if (f == null) {
        continue;
      }
      final Offset o = at(f.lat, f.lng);
      canvas.drawCircle(o, 8, Paint()..color = AppColors.members[i % AppColors.members.length]);
      _label(canvas, loc.memberName(members[i].member), o + const Offset(0, -24));
    }
  }

  void _label(Canvas canvas, String s, Offset o) {
    final TextPainter tp = TextPainter(
      text: TextSpan(text: s, style: const TextStyle(color: AppColors.ink, fontSize: 12)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, o - Offset(tp.width / 2, 0));
  }

  @override
  bool shouldRepaint(FamilyMapPainter old) => true;
}
