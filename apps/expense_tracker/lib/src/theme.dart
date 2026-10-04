import 'package:flutter/material.dart';

/// Cream paper, white panels, soft peach tiles and one terracotta
/// accent, after the ExpenseTracker V2 mock-ups.
abstract final class Palette {
  static const paper = Color(0xFFFBF6F1);
  static const card = Color(0xFFFFFFFF);
  static const ink = Color(0xFF3E3631);
  static const muted = Color(0xFF9C9189);
  static const line = Color(0xFFF0E6DC);

  /// Peach tiles and selected backgrounds.
  static const wash = Color(0xFFFCEEE3);

  /// The accent: buttons, icons, the selected tab.
  static const clay = Color(0xFFD9845A);

  /// Income.
  static const olive = Color(0xFF6E9A5B);

  /// Light bars and other quiet data.
  static const peach = Color(0xFFF4CDB4);

  /// Data colours, in the order categories take them.
  static const series = [
    Color(0xFFE28B5F),
    Color(0xFFF0B48C),
    Color(0xFFC9A27E),
    Color(0xFFB98568),
    Color(0xFFE9C9A6),
    Color(0xFFD9A48A),
    Color(0xFFF3D7BF),
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
