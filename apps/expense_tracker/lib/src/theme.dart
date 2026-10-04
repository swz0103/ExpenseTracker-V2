import 'package:flutter/material.dart';

/// Warm off-white paper, white panels, soft sage tiles and one warm
/// green accent.
abstract final class Palette {
  static const paper = Color(0xFFF6F4EC);
  static const card = Color(0xFFFFFFFF);
  static const ink = Color(0xFF2F3A33);
  static const muted = Color(0xFF8A9187);
  static const line = Color(0xFFE4E7DC);

  /// Sage tiles and selected backgrounds.
  static const wash = Color(0xFFEAF0E2);

  /// The accent: buttons, icons, the selected tab, income.
  static const clay = Color(0xFF668F5A);

  /// Income.
  static const olive = Color(0xFF668F5A);

  /// Warnings, overspending and market gains (red for up in Taiwan).
  static const warn = Color(0xFFB8613F);

  /// Light bars and other quiet data.
  static const peach = Color(0xFFCADBB9);

  /// Data colours, in the order categories and holdings take them.
  static const series = [
    Color(0xFF668F5A),
    Color(0xFF9DB886),
    Color(0xFFC9D7AE),
    Color(0xFF8F7D5C),
    Color(0xFFBCA77E),
    Color(0xFF5E7C6E),
    Color(0xFFDCE3C8),
  ];
}

ThemeData appTheme() {
  final seeded = ColorScheme.fromSeed(
    seedColor: Palette.clay,
    dynamicSchemeVariant: DynamicSchemeVariant.neutral,
  );
  final scheme = seeded.copyWith(
    primary: Palette.ink,
    onPrimary: Palette.card,
    secondary: Palette.clay,
    surface: Palette.paper,
    onSurface: Palette.ink,
    onSurfaceVariant: Palette.muted,
    outline: Palette.muted,
    outlineVariant: Palette.line,
    surfaceContainerLowest: Palette.card,
    surfaceContainerLow: Palette.card,
    surfaceContainer: Palette.card,
    surfaceContainerHigh: Palette.wash,
    surfaceContainerHighest: Palette.wash,
    secondaryContainer: Palette.wash,
    onSecondaryContainer: Palette.ink,
  );
  final base = ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: Palette.paper,
    fontFamily: 'NotoSansTC',
    useMaterial3: true,
    splashFactory: NoSplash.splashFactory,
  );
  return base.copyWith(
    appBarTheme: const AppBarTheme(
      backgroundColor: Palette.paper,
      foregroundColor: Palette.ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
    ),
    cardTheme: const CardThemeData(
      color: Palette.card,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
        side: BorderSide(color: Palette.line),
      ),
    ),
    dividerTheme: const DividerThemeData(color: Palette.line, space: 1),
    textTheme: base.textTheme.apply(
      bodyColor: Palette.ink,
      displayColor: Palette.ink,
    ),
  );
}
