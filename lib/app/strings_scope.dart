import 'package:flutter/widgets.dart';

import '../engines/family/member_profiles.dart';
import '../engines/platform/app_strings.dart';

/// Feature 110: hands the active profile's strings to every screen.
class AppStringsScope extends InheritedWidget {
  const AppStringsScope({super.key, required this.strings, required super.child});

  final AppStrings strings;

  /// The strings in force here; English when no scope is above.
  static AppStrings of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppStringsScope>()?.strings ?? AppStrings.english;

  @override
  bool updateShouldNotify(AppStringsScope oldWidget) => oldWidget.strings.code != strings.code;
}

/// Rebuilds the scope whenever the active profile or its language changes.
class ProfileStringsScope extends StatelessWidget {
  const ProfileStringsScope({super.key, this.profiles, required this.child});

  final MemberProfiles? profiles;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final MemberProfiles p = profiles ?? MemberProfiles.instance;
    return ListenableBuilder(
      listenable: p,
      builder: (BuildContext context, Widget? _) =>
          AppStringsScope(strings: AppStrings.forProfile(p.active), child: child),
    );
  }
}
