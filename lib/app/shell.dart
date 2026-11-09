import 'package:flutter/material.dart';

import '../engines/platform/app_strings.dart';
import '../engines/platform/guest_mode.dart';
import '../engines/security/app_lock.dart';
import '../family/family_screen.dart';
import '../platform/files_screen.dart';
import '../records/records_screen.dart';
import '../tools/app_lock/lock_screen.dart';
import '../tools/tools_home.dart';
import 'strings_scope.dart';

/// The four-tab shell: Tools, Family, Records, Files.
class AppShell extends StatefulWidget {
  const AppShell({super.key, this.initialIndex = 0});

  final int initialIndex;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late int _index = widget.initialIndex;

  static const List<Widget> _pages = <Widget>[
    ToolsHome(),
    FamilyScreen(),
    LockedSection(id: LockableIds.records, child: RecordsScreen()),
    FilesScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: GuestMode.instance,
      builder: (BuildContext context, Widget? _) {
        // 119: a guest gets the Tools tab only, with the allowed tools.
        if (GuestMode.instance.active) {
          return const Scaffold(body: ToolsHome());
        }
        return _owner(context);
      },
    );
  }

  Widget _owner(BuildContext context) {
    final AppStrings t = AppStringsScope.of(context);
    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (int i) => setState(() => _index = i),
        destinations: <NavigationDestination>[
          NavigationDestination(
            icon: const Icon(Icons.grid_view_outlined),
            selectedIcon: const Icon(Icons.grid_view),
            label: t.tabTools,
          ),
          NavigationDestination(
            icon: const Icon(Icons.people_outline),
            selectedIcon: const Icon(Icons.people),
            label: t.tabFamily,
          ),
          NavigationDestination(
            icon: const Icon(Icons.receipt_long_outlined),
            selectedIcon: const Icon(Icons.receipt_long),
            label: t.tabRecords,
          ),
          NavigationDestination(
            icon: const Icon(Icons.folder_outlined),
            selectedIcon: const Icon(Icons.folder),
            label: t.tabFiles,
          ),
        ],
      ),
    );
  }
}
