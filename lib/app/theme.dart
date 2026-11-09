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

/// One set of colours per brightness (feature 109 adds dark). Every text
/// role meets 4.5:1 on its ground and surface.
@immutable
class AppPalette {
  const AppPalette({
    required this.brightness,
    required this.ground,
    required this.surface,
    required this.line,
    required this.divider,
    required this.ink,
    required this.muted,
    required this.accent,
    required this.accentDark,
    required this.accentTint,
    required this.onAccent,
    required this.error,
  });

  final Brightness brightness;
  final Color ground;
  final Color surface;
  final Color line;
  final Color divider;
  final Color ink;
  final Color muted;
  final Color accent;
  final Color accentDark;
  final Color accentTint;
  final Color onAccent;
  final Color error;

  static const AppPalette light = AppPalette(
    brightness: Brightness.light,
    ground: AppColors.ground,
    surface: AppColors.surface,
    line: AppColors.line,
    divider: AppColors.divider,
    ink: AppColors.ink,
    muted: AppColors.muted,
    accent: AppColors.accent,
    accentDark: AppColors.accentDark,
    accentTint: AppColors.accentTint,
    onAccent: Colors.white,
    error: Color(0xFFB3261E),
  );

  static const AppPalette dark = AppPalette(
    brightness: Brightness.dark,
    ground: Color(0xFF121416),
    surface: Color(0xFF1B1E21),
    line: Color(0xFF34393E),
    divider: Color(0xFF25292D),
    ink: Color(0xFFECEDEF),
    muted: Color(0xFFA9AFB8),
    accent: Color(0xFF5CC7BA),
    accentDark: Color(0xFF9BE3D9),
    accentTint: Color(0xFF173431),
    onAccent: Color(0xFF00201D),
    error: Color(0xFFF2B8B5),
  );
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
TextTheme buildTextTheme([AppPalette p = AppPalette.light]) {
  return TextTheme(
    headlineSmall: _grotesk(22, p.ink),
    titleLarge: _grotesk(22, p.ink),
    titleMedium: _inter(15, FontWeight.w600, p.ink),
    titleSmall: _inter(13, FontWeight.w600, p.ink),
    bodyLarge: _inter(15, FontWeight.w400, p.ink, height: 1.4),
    bodyMedium: _inter(13, FontWeight.w400, p.muted, height: 1.4),
    bodySmall: _inter(12, FontWeight.w400, p.muted),
    labelLarge: _inter(15, FontWeight.w600, p.ink),
    labelMedium: _inter(12, FontWeight.w500, p.muted),
    labelSmall: _inter(11, FontWeight.w500, p.muted),
  );
}

ThemeData buildAppTheme({Brightness brightness = Brightness.light}) {
  final AppPalette p = brightness == Brightness.dark ? AppPalette.dark : AppPalette.light;
  final ColorScheme scheme = ColorScheme(
    brightness: p.brightness,
    primary: p.accent,
    onPrimary: p.onAccent,
    primaryContainer: p.accentTint,
    onPrimaryContainer: p.accentDark,
    secondary: p.accentDark,
    onSecondary: p.onAccent,
    secondaryContainer: p.accentTint,
    onSecondaryContainer: p.accentDark,
    error: p.error,
    onError: p.onAccent,
    surface: p.surface,
    onSurface: p.ink,
    onSurfaceVariant: p.muted,
    outline: p.line,
    outlineVariant: p.divider,
    surfaceContainerHighest: p.divider,
  );

  final TextTheme text = buildTextTheme(p);
  final RoundedRectangleBorder cardShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(AppRadius.card),
    side: BorderSide(color: p.line),
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: p.ground,
    fontFamily: AppFonts.body,
    textTheme: text,
    dividerColor: p.divider,
    appBarTheme: AppBarTheme(
      backgroundColor: p.ground,
      foregroundColor: p.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: text.titleLarge,
    ),
    cardTheme: CardThemeData(
      color: p.surface,
      elevation: 0,
      shape: cardShape,
      margin: EdgeInsets.zero,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.input),
        borderSide: BorderSide(color: p.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.input),
        borderSide: BorderSide(color: p.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.input),
        borderSide: BorderSide(color: p.accent, width: 1.5),
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
        side: BorderSide(color: p.line),
        foregroundColor: p.ink,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.round),
        ),
        textStyle: text.labelLarge,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(kMinTouchTarget, kMinTouchTarget),
        foregroundColor: p.accent,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: const Size(kMinTouchTarget, kMinTouchTarget),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: p.surface,
      selectedColor: p.accentTint,
      side: BorderSide(color: p.line),
      labelStyle: text.labelMedium?.copyWith(color: p.ink),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.round),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: p.surface,
      indicatorColor: p.accentTint,
      height: 64,
      labelTextStyle: WidgetStatePropertyAll<TextStyle?>(text.labelSmall),
      iconTheme: WidgetStateProperty.resolveWith<IconThemeData>(
        (Set<WidgetState> states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? p.accentDark
              : p.muted,
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
    listTileTheme: ListTileThemeData(
      minVerticalPadding: 10,
      iconColor: p.muted,
    ),
  );
}
