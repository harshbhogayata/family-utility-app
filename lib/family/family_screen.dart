import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../app/theme.dart';
import '../engines/family/family_board.dart';
import '../engines/family/family_identity.dart';
import '../engines/family/family_space.dart';
import '../engines/family/family_store.dart';
import '../engines/share/share_engine.dart';
import '../platform/calendar_platform.dart';
import 'board/family_board_screen.dart';
import 'calendar/shared_calendar_screen.dart';
import 'checkin/check_in_screen.dart';
import 'documents/document_vault_screen.dart';
import 'location/family_location_screen.dart';
import 'shopping/shared_shopping_screen.dart';

/// Opens the camera and returns the first QR text, or null on cancel.
typedef FamilyQrScan = Future<String?> Function(BuildContext context);

/// Asks for the own-cloud folder; null on cancel.
typedef FamilyFolderPick = Future<String?> Function();

/// Family tab (feature 068): start or join a family space, invite with a
/// QR, see who is in it and how sync is doing.
class FamilyScreen extends StatefulWidget {
  const FamilyScreen({super.key, this.space, this.scan, this.pickFolder});

  final FamilySpace? space;
  final FamilyQrScan? scan;
  final FamilyFolderPick? pickFolder;

  @override
  State<FamilyScreen> createState() => _FamilyScreenState();
}

class _FamilyScreenState extends State<FamilyScreen> {
  final TextEditingController _me = TextEditingController();
  final TextEditingController _family = TextEditingController();
  bool _busy = false;

  FamilySpace get _space => widget.space ?? FamilySpace.instance;

  @override
  void dispose() {
    _me.dispose();
    _family.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() f) async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      await f();
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _create() => _run(() async {
        await _space.create(familyName: _family.text, memberName: _me.text);
      });

  Future<void> _join() => _run(() async {
        final String? text = await (widget.scan ?? _scanWithCamera)(context);
        if (text == null || !mounted) {
          return;
        }
        final FamilyIdentity? id = await _space.join(text, memberName: _me.text);
        if (!mounted) {
          return;
        }
        final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
        if (id == null) {
          messenger.showSnackBar(const SnackBar(content: Text('That QR is not a family invite')));
          return;
        }
        messenger.showSnackBar(SnackBar(
          content: Text('Joined ${id.familyName}'),
          action: SnackBarAction(label: 'Undo', onPressed: () => unawaited(_space.leave())),
        ));
      });

  Future<void> _invite() async {
    final String? code = await _space.inviteCode();
    if (code == null || !mounted) {
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext context) => InviteSheet(code: code, familyName: _space.identity?.familyName ?? ''),
    );
  }

  Future<void> _folder() async {
    final String? dir = await (widget.pickFolder ?? _systemFolder)();
    if (dir != null) {
      await _space.setSyncFolder(dir);
    }
  }

  Future<void> _leave() async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Leave this family?'),
        content: const Text('This phone forgets the family key and its copy. Other phones keep everything.'),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Leave')),
        ],
      ),
    );
    if (ok == true) {
      await _space.leave();
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListenableBuilder(
        listenable: Listenable.merge(<Listenable>[_space, _space.store]),
        builder: (BuildContext context, Widget? _) =>
            _space.inFamily ? _inFamily(context) : _start(context),
      ),
    );
  }

  Widget _start(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Text('Family', style: text.titleLarge),
        const SizedBox(height: 8),
        Text(
          'One shared space for your family. It syncs phone to phone on your Wi-Fi '
          'or through your own folder. Nothing goes to any company server.',
          style: text.bodyMedium,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _me,
          decoration: const InputDecoration(labelText: 'Your name'),
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _family,
          decoration: const InputDecoration(labelText: 'Family name (when starting one)'),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 48,
          child: FilledButton.icon(
            onPressed: _busy ? null : _create,
            icon: const Icon(Icons.add_home_outlined),
            label: const Text('Start a family space'),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 48,
          child: OutlinedButton.icon(
            onPressed: _busy ? null : _join,
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Join by scanning a QR'),
          ),
        ),
      ],
    );
  }

  Widget _inFamily(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final FamilyIdentity id = _space.identity!;
    final List<FamilyRecord> members = _space.memberRecords;
    return ListView(
      padding: const EdgeInsets.all(16),
      // Short list: build it all, so every row is reachable by screen readers.
      cacheExtent: 2000,
      children: <Widget>[
        Text(id.familyName, style: text.titleLarge),
        const SizedBox(height: 4),
        Text(
          '${members.length} ${members.length == 1 ? 'member' : 'members'} · ${_space.store.liveCount} shared items',
          style: text.bodyMedium,
        ),
        // 073: notes pinned to the family screen.
        for (final FamilyNote n in FamilyBoard.pinnedIn(_space.store))
          Card(
            key: Key('pinned-${n.id}'),
            margin: const EdgeInsets.only(top: 8),
            child: Semantics(
              label: 'Pinned note: ${n.text}',
              excludeSemantics: true,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(children: <Widget>[
                  const Icon(Icons.push_pin, size: 18, color: AppColors.accent),
                  const SizedBox(width: 8),
                  Expanded(child: Text(n.text, style: text.bodyMedium)),
                ]),
              ),
            ),
          ),
        const SizedBox(height: 12),
        for (final String line in _space.statusLines)
          Semantics(
            label: 'Sync status: $line',
            excludeSemantics: true,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(children: <Widget>[
                const Icon(Icons.sync, size: 18, color: AppColors.accent),
                const SizedBox(width: 8),
                Expanded(child: Text(line, style: text.bodySmall)),
              ]),
            ),
          ),
        const SizedBox(height: 16),
        Text('Members', style: text.titleMedium),
        for (int i = 0; i < members.length; i++)
          ListTile(
            contentPadding: EdgeInsets.zero,
            minTileHeight: 48,
            leading: CircleAvatar(
              backgroundColor: AppColors.members[i % AppColors.members.length],
              foregroundColor: Colors.white,
              child: Text(_initial(members[i].fields['name'])),
            ),
            title: Text('${members[i].fields['name'] ?? 'Member'}'),
            subtitle: members[i].id == id.deviceId ? const Text('This phone') : null,
          ),
        const SizedBox(height: 12),
        SizedBox(
          height: 48,
          child: FilledButton.icon(
            onPressed: _invite,
            icon: const Icon(Icons.qr_code_2),
            label: const Text('Invite a member'),
          ),
        ),
        const SizedBox(height: 8),
        ListTile(
          contentPadding: EdgeInsets.zero,
          minTileHeight: 48,
          leading: const Icon(Icons.calendar_month_outlined),
          title: const Text('Shared calendar'),
          subtitle: const Text('Events, repeats and reminders for everyone'),
          onTap: () => unawaited(Navigator.of(context).push<void>(MaterialPageRoute<void>(
            builder: (BuildContext context) => SharedCalendarScreen(export: Add2CalendarExport()),
          ))),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          minTileHeight: 48,
          leading: const Icon(Icons.shopping_cart_outlined),
          title: const Text('Shopping list'),
          subtitle: const Text('Ticked live by whoever is at the shop'),
          onTap: () => unawaited(Navigator.of(context).push<void>(MaterialPageRoute<void>(
            builder: (BuildContext context) => const SharedShoppingScreen(),
          ))),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          minTileHeight: 48,
          leading: const Icon(Icons.checklist_outlined),
          title: const Text('To-do and notices'),
          subtitle: const Text('Tasks with an owner and due date; pinned notes'),
          onTap: () => unawaited(Navigator.of(context).push<void>(MaterialPageRoute<void>(
            builder: (BuildContext context) => FamilyBoardScreen(board: FamilyBoard(space: _space)),
          ))),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          minTileHeight: 48,
          leading: const Icon(Icons.badge_outlined),
          title: const Text('Documents'),
          subtitle: const Text('ID papers per member, with expiry reminders'),
          onTap: () => unawaited(Navigator.of(context).push<void>(MaterialPageRoute<void>(
            builder: (BuildContext context) => const DocumentVaultScreen(),
          ))),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          minTileHeight: 48,
          leading: const Icon(Icons.location_on_outlined),
          title: const Text('Family location'),
          subtitle: const Text('Live location with arrive and leave alerts'),
          onTap: () => unawaited(Navigator.of(context).push<void>(MaterialPageRoute<void>(
            builder: (BuildContext context) => const FamilyLocationScreen(),
          ))),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          minTileHeight: 48,
          leading: const Icon(Icons.verified_user_outlined),
          title: const Text('Check in'),
          subtitle: const Text("'Reached safely' in one tap, or automatic at saved places"),
          onTap: () => unawaited(Navigator.of(context).push<void>(MaterialPageRoute<void>(
            builder: (BuildContext context) => const CheckInScreen(),
          ))),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          minTileHeight: 48,
          leading: const Icon(Icons.folder_shared_outlined),
          title: const Text('Sync folder (your own Drive or iCloud)'),
          subtitle: Text(id.syncFolder ?? 'Off · Wi-Fi only'),
          onTap: _folder,
          trailing: id.syncFolder == null
              ? null
              : IconButton(
                  tooltip: 'Stop folder sync',
                  icon: const Icon(Icons.close),
                  onPressed: () => unawaited(_space.setSyncFolder(null)),
                ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            style: TextButton.styleFrom(minimumSize: const Size(44, 48)),
            onPressed: _leave,
            child: const Text('Leave family on this phone'),
          ),
        ),
        // 079: which path each change took (this phone, Wi-Fi, own folder).
        const SizedBox(height: 16),
        Text('Recent changes', style: text.titleMedium),
        for (final FamilyChange c in _space.store.recentChanges.take(5))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              '${changeLabel(c)} · via ${c.via} · ${c.at.hour.toString().padLeft(2, '0')}:${c.at.minute.toString().padLeft(2, '0')}',
              style: text.bodySmall,
            ),
          ),
      ],
    );
  }

  /// "Calendar event removed", "Shopping item changed"...
  static String changeLabel(FamilyChange c) {
    const Map<String, String> names = <String, String>{
      FamilySpace.members: 'Member',
      'calendar': 'Calendar event',
      'shopping': 'Shopping item',
      FamilyBoard.tasksCollection: 'Task',
      FamilyBoard.notesCollection: 'Note',
      'documents': 'Document',
      'locations': 'Location',
      'places': 'Place',
      'checkins': 'Check-in',
    };
    return '${names[c.collection] ?? c.collection} ${c.deleted ? 'removed' : 'changed'}';
  }

  static String _initial(Object? name) {
    final String s = '${name ?? ''}'.trim();
    return s.isEmpty ? '?' : s.substring(0, 1).toUpperCase();
  }
}

/// The invite: a QR for another phone to scan, and the same code to share.
class InviteSheet extends StatelessWidget {
  const InviteSheet({super.key, required this.code, required this.familyName});

  final String code;
  final String familyName;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text('Join $familyName', style: text.titleMedium),
            const SizedBox(height: 8),
            Text(
              'On the other phone open Family and tap Join by scanning a QR. '
              'Anyone with this code can join, so only show it to family.',
              style: text.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Semantics(
              label: 'Family invite QR code',
              image: true,
              excludeSemantics: true,
              child: Container(
                color: Colors.white,
                padding: const EdgeInsets.all(8),
                child: QrImageView(data: code, size: 240),
              ),
            ),
            const SizedBox(height: 12),
            Row(children: <Widget>[
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: OutlinedButton.icon(
                    onPressed: () => unawaited(ShareEngine.instance.shareText(code, subject: 'Family invite')),
                    icon: const Icon(Icons.share_outlined),
                    label: const Text('Share code'),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Done'),
                  ),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

Future<String?> _systemFolder() => FilePicker.platform.getDirectoryPath(dialogTitle: 'Family sync folder');

Future<String?> _scanWithCamera(BuildContext context) => Navigator.of(context).push<String>(
      MaterialPageRoute<String>(builder: (BuildContext context) => const _InviteScanner()),
    );

class _InviteScanner extends StatefulWidget {
  const _InviteScanner();

  @override
  State<_InviteScanner> createState() => _InviteScannerState();
}

class _InviteScannerState extends State<_InviteScanner> {
  final MobileScannerController _controller = MobileScannerController();
  bool _done = false;

  @override
  void dispose() {
    unawaited(_controller.dispose());
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) {
      return;
    }
    for (final Barcode b in capture.barcodes) {
      final String? v = b.rawValue;
      if (v != null && v.startsWith(FamilyInvite.prefix)) {
        _done = true;
        Navigator.of(context).pop(v);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan the family QR')),
      body: Semantics(
        label: 'Point the camera at the family invite QR',
        child: MobileScanner(controller: _controller, onDetect: _onDetect),
      ),
    );
  }
}
