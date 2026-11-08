import 'package:flutter/material.dart';

import 'shell.dart';
import 'theme.dart';

class FamilyUtilityApp extends StatelessWidget {
  const FamilyUtilityApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Family Utility',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: const AppShell(),
    );
  }
}
