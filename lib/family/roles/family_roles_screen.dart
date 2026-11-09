import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../app/widgets/result_bar.dart';
import '../../engines/family/family_roles.dart';
import '../../engines/family/family_store.dart';
import '../../engines/share/share_engine.dart';

/// Feature 070 — who can see and edit what, per section.
class FamilyRolesScreen extends StatefulWidget {
  const FamilyRolesScreen({super.key, this.roles, this.share, this.save});

  final FamilyRoles? roles;
  final Future<void> Function(String text)? share;
  final Future<String?> Function(String text)? save;

  @override
  State<FamilyRolesScreen> createState() => _FamilyRolesScreenState();
}

class _FamilyRolesScreenState extends State<FamilyRolesScreen> {
  FamilyRoles get _r => widget.roles ?? FamilyRoles.instance;

  void _snack(String s) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
    }
  }

  Future<void> _share() async {
    final Future<void> Function(String)? s = widget.share;
    if (s != null) {
      await s(_r.toText());
    } else {
      await ShareEngine.instance.shareText(_r.toText(), subject: 'Family roles');
    }
  }

  static Future<String?> _saveToDocuments(String text) async {
    final Directory dir = await getApplicationDocumentsDirectory();
    final File f = File('${dir.path}/Family roles.txt');
    await f.writeAsString(text);
    return f.path;
  }

  Future<void> _save() async {
    String? where;
    try {
      where = await (widget.save ?? _saveToDocuments)(_r.toText());
    } catch (_) {
      where = null;
    }
    _snack(where == null ? 'Could not save the roles' : 'Saved to $where');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Family roles')),
      bottomNavigationBar: ResultBar(
        onShare: () => unawaited(_share()),
        onSave: () => unawaited(_save()),
        onUndo: () => _snack(_r.undo() ? 'Undone' : 'Nothing to undo'),
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge(<Listenable>[_r, _r.store]),
        builder: (BuildContext context, Widget? _) => _body(context),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final bool manage = _r.iManage;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Text(
          manage
              ? 'Choose each member\'s role, then what each role can see and edit.'
              : 'Only an adult can change roles. You are a ${_r.myRole.label.toLowerCase()}.',
          style: text.bodyMedium,
        ),
        const SizedBox(height: 8),
        Text('Members', style: text.titleMedium),
        for (final FamilyRecord m in _r.space.memberRecords)
          ListTile(
            contentPadding: EdgeInsets.zero,
            minTileHeight: 48,
            title: Text('${m.fields['name'] ?? 'Member'}'),
            trailing: DropdownButton<FamilyRole>(
              key: Key('role-${m.id}'),
              value: _r.roleOf(m.id),
              onChanged: manage
                  ? (FamilyRole? v) {
                      if (v != null && !_r.setRole(m.id, v)) {
                        _snack('The family needs at least one adult');
                      }
                    }
                  : null,
              items: <DropdownMenuItem<FamilyRole>>[
                for (final FamilyRole r in FamilyRole.values) DropdownMenuItem<FamilyRole>(value: r, child: Text(r.label)),
              ],
            ),
          ),
        for (final FamilyRole role in <FamilyRole>[FamilyRole.child, FamilyRole.guest]) ...<Widget>[
          const SizedBox(height: 16),
          Text('What a ${role.label.toLowerCase()} can do', style: text.titleMedium),
          for (final String s in FamilySections.all)
            ListTile(
              contentPadding: EdgeInsets.zero,
              minTileHeight: 48,
              title: Text(FamilySections.labels[s]!),
              trailing: DropdownButton<SectionAccess>(
                key: Key('access-${role.name}-$s'),
                value: _r.access(role, s),
                onChanged: manage
                    ? (SectionAccess? a) {
                        if (a != null) {
                          _r.setAccess(role, s, a);
                        }
                      }
                    : null,
                items: <DropdownMenuItem<SectionAccess>>[
                  for (final SectionAccess a in SectionAccess.values)
                    DropdownMenuItem<SectionAccess>(value: a, child: Text(a.label)),
                ],
              ),
            ),
        ],
        const SizedBox(height: 16),
        Text('Adults can see and edit everything.', style: text.bodySmall),
      ],
    );
  }
}
