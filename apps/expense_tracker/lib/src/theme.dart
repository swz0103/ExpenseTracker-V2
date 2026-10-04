import 'package:flutter/material.dart';

/// Warm, light and quiet: paper backgrounds, ink text, hairlines instead
/// of shadows, and a few muted earth colours for data.
abstract final class Palette {
  static const paper = Color(0xFFF6F2EB);
  static const card = Color(0xFFFCFAF6);
  static const ink = Color(0xFF3B3631);
  static const muted = Color(0xFF8E867B);
  static const line = Color(0xFFE6DFD4);
  static const wash = Color(0xFFEFE9DF);

  /// Spending, and the one accent.
  static const clay = Color(0xFFA9634A);

  /// Income and gains.
  static const olive = Color(0xFF6F7C57);

  /// Data colours, in the order categories and holdings take them.
  static const series = [
    Color(0xFFA9634A),
    Color(0xFFC9A273),
    Color(0xFF7E8664),
    Color(0xFF9E8C79),
    Color(0xFFBC8D84),
    Color(0xFF6F8088),
    Color(0xFFD7BE97),
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
        borderRadius: BorderRadius.all(Radius.circular(14)),
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
