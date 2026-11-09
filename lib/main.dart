import 'dart:async';

import 'package:flutter/material.dart';

import 'app/app.dart';
import 'app/bootstrap.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  bootstrap();
  // 113: taps on job notifications, including one that launched the app.
  unawaited(jobNotificationHost?.attach());
  runApp(const FamilyUtilityApp());
}
