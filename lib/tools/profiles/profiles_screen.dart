import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../app/tool_registry.dart';
import '../../engines/family/member_profiles.dart';
import '../../engines/security/app_lock.dart';

/// Feature 069 — the profile chip on the home screen, the switcher sheet
/// and the screen where members are added and set up.

Color profileColour(MemberProfiles profiles, MemberProfile p) {
  final int i = profiles.profiles.indexWhere((MemberProfile x) => x.id == p.id);
  return AppColors.members[(i < 0 ? 0 : i) % AppColors.members.length];
}

/// Asks for a 4–6 digit PIN. Returns null when cancelled.
Future<String?> askProfilePin(BuildContext context, {required String title, String? message}) {
  final TextEditingController field = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (BuildContext dialogContext) => AlertDialog(
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (message != null) Text(message),
          TextField(
            key: const Key('profile-pin-field'),
            controller: field,
            autofocus: true,
            obscureText: true,
            keyboardType: TextInputType.number,
            maxLength: PinHasher.maxLength,
            decoration: const InputDecoration(labelText: 'PIN, 4 to 6 digits'),
            onSubmitted: (String v) => Navigator.of(dialogContext).pop(v),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel')),
        TextButton(
          key: const Key('profile-pin-ok'),
          onPressed: () => Navigator.of(dialogContext).pop(field.text),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

/// Switches to [p], asking for its PIN when it has one.
Future<bool> switchProfile(BuildContext context, MemberProfiles profiles, MemberProfile p) async {
  SwitchOutcome out = await profiles.switchTo(p.id);
  if (out == SwitchOutcome.needsPin) {
    if (!context.mounted) {
      return false;
    }
    final String? pin = await askProfilePin(context, title: 'PIN for ${p.name}');
    if (pin == null) {
      return false;
    }
    out = await profiles.switchTo(p.id, pin: pin);
  }
  if (!context.mounted) {
    return out == SwitchOutcome.switched;
  }
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
    SnackBar(
      content: Text(out == SwitchOutcome.switched ? 'Now using ${p.name}' : 'Wrong PIN, still ${profiles.active.name}'),
    ),
  );
  return out == SwitchOutcome.switched;
}

/// The round avatar at the top of the home screen. Tap to switch member.
class ProfileChip extends StatelessWidget {
  const ProfileChip({super.key, this.profiles});

  final MemberProfiles? profiles;

  @override
  Widget build(BuildContext context) {
    final MemberProfiles ps = profiles ?? MemberProfiles.instance;
    return ListenableBuilder(
      listenable: ps,
      builder: (BuildContext context, Widget? _) {
        final MemberProfile me = ps.active;
        final Color c = profileColour(ps, me);
        return Semantics(
          button: true,
          label: 'Profile: ${me.name}. Switch profile',
          excludeSemantics: true,
          child: InkResponse(
            key: const Key('profile-chip'),
            radius: 24,
            onTap: () => showProfileSwitcher(context, ps),
            child: SizedBox(
              width: 48,
              height: 48,
              child: Center(
                child: CircleAvatar(
                  radius: 18,
                  backgroundColor: c.withValues(alpha: 0.15),
                  child: Text(me.initial, style: TextStyle(color: c, fontWeight: FontWeight.w600)),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

Future<void> showProfileSwitcher(BuildContext context, MemberProfiles profiles) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (BuildContext sheetContext) => SafeArea(
      child: ListenableBuilder(
        listenable: profiles,
        builder: (BuildContext _, Widget? __) => Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Who is using the phone?', style: Theme.of(sheetContext).textTheme.titleMedium),
              ),
            ),
            for (final MemberProfile p in profiles.profiles)
              ListTile(
                key: Key('switch-${p.id}'),
                minVerticalPadding: 12,
                leading: CircleAvatar(
                  backgroundColor: profileColour(profiles, p).withValues(alpha: 0.15),
                  child: Text(p.initial, style: TextStyle(color: profileColour(profiles, p))),
                ),
                title: Text(p.name),
                subtitle: Text(
                  '${ProfileLanguages.nameOf(p.language)}${p.hasPin ? ' · PIN' : ''}',
                ),
                trailing: p.id == profiles.active.id
                    ? const Icon(Icons.check, semanticLabel: 'Current profile')
                    : (p.hasPin ? const Icon(Icons.lock_outline, semanticLabel: 'Needs PIN') : null),
                onTap: () async {
                  final bool ok = await switchProfile(sheetContext, profiles, p);
                  if (ok && sheetContext.mounted) {
                    Navigator.of(sheetContext).pop();
                  }
                },
              ),
            const Divider(height: 1),
            ListTile(
              key: const Key('manage-profiles'),
              minVerticalPadding: 12,
              leading: const Icon(Icons.manage_accounts_outlined),
              title: const Text('Manage profiles'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(builder: (BuildContext _) => ProfilesScreen(profiles: profiles)),
                );
              },
            ),
          ],
        ),
      ),
    ),
  );
}

/// Home-screen row of the active member's favourites and recent tools.
class ProfileShortcuts extends StatelessWidget {
  const ProfileShortcuts({super.key, this.profiles, required this.onOpen});

  final MemberProfiles? profiles;
  final void Function(ToolEntry tool) onOpen;

  @override
  Widget build(BuildContext context) {
    final MemberProfiles ps = profiles ?? MemberProfiles.instance;
    return ListenableBuilder(
      listenable: ps,
      builder: (BuildContext context, Widget? _) {
        final MemberProfile me = ps.active;
        final List<String> ids = <String>[
          ...me.favourites,
          ...me.recents.where((String r) => !me.favourites.contains(r)),
        ];
        final List<ToolEntry> tools = <ToolEntry>[];
        for (final String id in ids) {
          final ToolEntry? t = ToolRegistry.byId(id);
          if (t != null) {
            tools.add(t);
          }
        }
        if (tools.isEmpty) {
          return const SizedBox.shrink();
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('${me.name}: favourites and recent', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: <Widget>[
                for (final ToolEntry t in tools)
                  ActionChip(
                    key: Key('recent-${t.id}'),
                    materialTapTargetSize: MaterialTapTargetSize.padded,
                    avatar: Icon(me.favourites.contains(t.id) ? Icons.star : t.icon, size: 18),
                    label: Text(t.name),
                    tooltip: me.favourites.contains(t.id) ? '${t.name}, favourite' : '${t.name}, recent',
                    onPressed: () => onOpen(t),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class ProfilesScreen extends StatelessWidget {
  const ProfilesScreen({super.key, required this.profiles});

  final MemberProfiles profiles;

  Future<String?> _askName(BuildContext context, {String initial = '', required String title}) {
    final TextEditingController field = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          key: const Key('profile-name-field'),
          controller: field,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Name'),
          onSubmitted: (String v) => Navigator.of(dialogContext).pop(v),
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel')),
          TextButton(
            key: const Key('profile-name-ok'),
            onPressed: () => Navigator.of(dialogContext).pop(field.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _add(BuildContext context) async {
    final String? name = await _askName(context, title: 'Add a family member');
    if (name == null) {
      return;
    }
    await profiles.add(name);
  }

  Future<void> _pin(BuildContext context, MemberProfile p) async {
    if (p.hasPin) {
      await profiles.clearPin(p.id);
      if (context.mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text('PIN removed for ${p.name}')));
      }
      return;
    }
    final String? pin = await askProfilePin(
      context,
      title: 'PIN for ${p.name}',
      message: 'Asked when someone switches to this profile.',
    );
    if (pin == null) {
      return;
    }
    final bool ok = await profiles.setPin(p.id, pin);
    if (context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(ok ? 'PIN set for ${p.name}' : 'Use 4 to 6 digits')),
      );
    }
  }

  Future<void> _language(BuildContext context, MemberProfile p) async {
    final String? code = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) => SimpleDialog(
        title: Text('Language for ${p.name}'),
        children: <Widget>[
          for (final MapEntry<String, String> e in ProfileLanguages.names.entries)
            SimpleDialogOption(
              key: Key('lang-${e.key}'),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              onPressed: () => Navigator.of(dialogContext).pop(e.key),
              child: Text(e.value),
            ),
        ],
      ),
    );
    if (code != null) {
      await profiles.setLanguage(p.id, code);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profiles')),
      floatingActionButton: ListenableBuilder(
        listenable: profiles,
        builder: (BuildContext _, Widget? __) => profiles.canAdd
            ? FloatingActionButton.extended(
                key: const Key('add-profile'),
                onPressed: () => _add(context),
                icon: const Icon(Icons.person_add_alt),
                label: const Text('Add member'),
              )
            : const SizedBox.shrink(),
      ),
      body: ListenableBuilder(
        listenable: profiles,
        builder: (BuildContext context, Widget? _) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          children: <Widget>[
            Text(
              'Each member has their own recents, favourites, language and an optional PIN. '
              'Profiles stay on this phone.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            for (final MemberProfile p in profiles.profiles)
              Card(
                key: Key('profile-card-${p.id}'),
                child: Column(
                  children: <Widget>[
                    ListTile(
                      leading: CircleAvatar(
                        backgroundColor: profileColour(profiles, p).withValues(alpha: 0.15),
                        child: Text(p.initial, style: TextStyle(color: profileColour(profiles, p))),
                      ),
                      title: Text(p.name),
                      subtitle: Text(p.id == profiles.active.id ? 'In use now' : '${p.recents.length} recent'),
                      trailing: IconButton(
                        tooltip: 'Rename ${p.name}',
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () async {
                          final String? name = await _askName(context, initial: p.name, title: 'Rename');
                          if (name != null) {
                            await profiles.rename(p.id, name);
                          }
                        },
                      ),
                    ),
                    ListTile(
                      key: Key('language-${p.id}'),
                      leading: const Icon(Icons.translate),
                      title: const Text('Language'),
                      subtitle: Text(ProfileLanguages.nameOf(p.language)),
                      onTap: () => _language(context, p),
                    ),
                    SwitchListTile(
                      key: Key('pin-${p.id}'),
                      secondary: const Icon(Icons.pin_outlined),
                      title: const Text('PIN to switch in'),
                      value: p.hasPin,
                      onChanged: (bool _) => _pin(context, p),
                    ),
                    OverflowBar(
                      alignment: MainAxisAlignment.end,
                      children: <Widget>[
                        if (p.recents.isNotEmpty && p.id == profiles.active.id)
                          TextButton(
                            onPressed: () => profiles.clearRecents(),
                            child: const Text('Clear recents'),
                          ),
                        if (profiles.profiles.length > 1)
                          TextButton(
                            key: Key('remove-${p.id}'),
                            onPressed: () => profiles.remove(p.id),
                            child: Text('Remove ${p.name}'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
