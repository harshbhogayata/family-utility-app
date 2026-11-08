import 'package:flutter/material.dart';

/// Design tokens from DESIGN.md. Light, warm, one accent.
abstract final class AppColors {
  static const Color ground = Color(0xFFF6F5F2);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color line = Color(0xFFE3E1DC);
  static const Color divider = Color(0xFFF0EEE9);
  static const Color ink = Color(0xFF16181D);
  static const Color muted = Color(0xFF5B6069);
  static const Color accent = Color(0xFF0F766E);
  static const Color accentDark = Color(0xFF0B5A54);
  static const Color accentTint = Color(0xFFE5F4F1);

  /// Member colours differ in lightness, not only hue.
  static const List<Color> members = <Color>[
    Color(0xFF0F766E),
    Color(0xFFB45309),
    Color(0xFF1D4ED8),
    Color(0xFF6D28D9),
  ];
}

abstract final class AppRadius {
  static const double card = 16;
  static const double input = 14;
  static const double round = 22;
  static const double gridGap = 10;
}

/// Minimum touch target from DESIGN.md.
const double kMinTouchTarget = 44;

abstract final class AppFonts {
  static const String title = 'SpaceGrotesk';
  static const String body = 'Inter';
}

TextStyle _inter(double size, FontWeight weight, Color color,
    {double? height}) {
  return TextStyle(
    fontFamily: AppFonts.body,
    fontSize: size,
    fontWeight: weight,
    fontVariations: <FontVariation>[FontVariation('wght', weight.value.toDouble())],
    color: color,
    height: height,
  );
}

TextStyle _grotesk(double size, Color color) {
  return TextStyle(
    fontFamily: AppFonts.title,
    fontSize: size,
    fontWeight: FontWeight.w700,
    fontVariations: const <FontVariation>[FontVariation('wght', 700)],
    color: color,
  );
}

/// The app's text scale: Space Grotesk 700 for titles (22 px), Inter for
/// everything else (15 body, 13 secondary, 12 caption, 11 nav).
TextTheme buildTextTheme() {
  return TextTheme(
    headlineSmall: _grotesk(22, AppColors.ink),
    titleLarge: _grotesk(22, AppColors.ink),
    titleMedium: _inter(15, FontWeight.w600, AppColors.ink),
    titleSmall: _inter(13, FontWeight.w600, AppColors.ink),
    bodyLarge: _inter(15, FontWeight.w400, AppColors.ink, height: 1.4),
    bodyMedium: _inter(13, FontWeight.w400, AppColors.muted, height: 1.4),
    bodySmall: _inter(12, FontWeight.w400, AppColors.muted),
    labelLarge: _inter(15, FontWeight.w600, AppColors.ink),
    labelMedium: _inter(12, FontWeight.w500, AppColors.muted),
    labelSmall: _inter(11, FontWeight.w500, AppColors.muted),
  );
}

ThemeData buildAppTheme() {
  const ColorScheme scheme = ColorScheme(
    brightness: Brightness.light,
    primary: AppColors.accent,
    onPrimary: Colors.white,
    primaryContainer: AppColors.accentTint,
    onPrimaryContainer: AppColors.accentDark,
    secondary: AppColors.accentDark,
    onSecondary: Colors.white,
    secondaryContainer: AppColors.accentTint,
    onSecondaryContainer: AppColors.accentDark,
    error: Color(0xFFB3261E),
    onError: Colors.white,
    surface: AppColors.surface,
    onSurface: AppColors.ink,
    onSurfaceVariant: AppColors.muted,
    outline: AppColors.line,
    outlineVariant: AppColors.divider,
    surfaceContainerHighest: AppColors.divider,
  );

  final TextTheme text = buildTextTheme();
  final RoundedRectangleBorder cardShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(AppRadius.card),
    side: const BorderSide(color: AppColors.line),
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.ground,
    fontFamily: AppFonts.body,
    textTheme: text,
    dividerColor: AppColors.divider,
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.ground,
      foregroundColor: AppColors.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: text.titleLarge,
    ),
    cardTheme: CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      shape: cardShape,
      margin: EdgeInsets.zero,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.input),
        borderSide: const BorderSide(color: AppColors.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.input),
        borderSide: const BorderSide(color: AppColors.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.input),
        borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(kMinTouchTarget, kMinTouchTarget + 4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.round),
        ),
        textStyle: text.labelLarge,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(kMinTouchTarget, kMinTouchTarget + 4),
        side: const BorderSide(color: AppColors.line),
        foregroundColor: AppColors.ink,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.round),
        ),
        textStyle: text.labelLarge,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(kMinTouchTarget, kMinTouchTarget),
        foregroundColor: AppColors.accent,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: const Size(kMinTouchTarget, kMinTouchTarget),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.surface,
      selectedColor: AppColors.accentTint,
      side: const BorderSide(color: AppColors.line),
      labelStyle: text.labelMedium?.copyWith(color: AppColors.ink),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.round),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.surface,
      indicatorColor: AppColors.accentTint,
      height: 64,
      labelTextStyle: WidgetStatePropertyAll<TextStyle?>(text.labelSmall),
      iconTheme: WidgetStateProperty.resolveWith<IconThemeData>(
        (Set<WidgetState> states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? AppColors.accentDark
              : AppColors.muted,
          size: 22,
        ),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.input),
      ),
    ),
    listTileTheme: const ListTileThemeData(
      minVerticalPadding: 10,
      iconColor: AppColors.muted,
    ),
  );
}
