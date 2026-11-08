import 'package:flutter/material.dart';

import 'app/app.dart';
import 'app/bootstrap.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  bootstrap();
  runApp(const FamilyUtilityApp());
}
