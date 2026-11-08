import 'package:flutter/material.dart';

import '../tools/qr_scanner/qr_scanner_screen.dart';
import 'tool_registry.dart';

/// Registers every tool with the registry. Each feature adds its entry here
/// so the home grid is driven by one list.
void bootstrap() {
  ToolRegistry.registerAll(<ToolEntry>[
    ToolEntry(
      id: 'qr-scanner',
      name: 'QR scanner',
      section: ToolSection.scan,
      icon: Icons.qr_code_scanner,
      featureNumber: 51,
      builder: (BuildContext context) => const QrScannerScreen(),
    ),
  ]);
}
