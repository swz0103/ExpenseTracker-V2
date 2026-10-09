import 'package:flutter/material.dart';

/// The colours of 日々記帳 (interface v114): warm paper, deep green for
/// income and gains, deep red for spending and losses.
abstract final class Hue {
  static const paper = Color(0xFFF7F2E7);
  static const panel = Color(0xFFFAF6ED);
  static const white = Color(0xFFFFFCF5);
  static const surface = Color(0xFFEEE8DC);
  static const selected = Color(0xFFDCE7D2);
  static const ink = Color(0xFF344638);
  static const muted = Color(0xFF666B5F);
  static const faint = Color(0xFFB9B5A8);
  static const line = Color(0xFFE2DACA);

  /// The soft green of summary panels.
  static const mist = Color(0xFFE6E9DA);

  /// Income, gains and refunds.
  static const positive = Color(0xFF315D47);

  /// Spending and losses.
  static const negative = Color(0xFF8B403B);
  static const transfer = Color(0xFF52777E);
  static const investment = Color(0xFF76658A);
  static const gold = Color(0xFFBD9E60);
  static const danger = Color(0xFF914F44);

  /// Soft backgrounds behind each kind of entry.
  static const expenseSoft = Color(0xFFF1E3D9);
  static const incomeSoft = Color(0xFFE5ECE0);
  static const transferSoft = Color(0xFFE3ECE9);
  static const investmentSoft = Color(0xFFECE5F1);

  /// Account groups.
  static const cash = Color(0xFFB49A55);
  static const bank = Color(0xFF7E9772);
  static const wallet = Color(0xFF6E929B);
  static const card = Color(0xFFA35F58);
  static const holdings = Color(0xFFC08066);
}

/// A light version of [color] for icon backgrounds.
Color softOf(Color color) => Color.lerp(color, Hue.paper, 0.82)!;

ThemeData appTheme() {
  final seeded = ColorScheme.fromSeed(
    seedColor: Hue.positive,
    dynamicSchemeVariant: DynamicSchemeVariant.neutral,
  );
  final scheme = seeded.copyWith(
    primary: Hue.positive,
    onPrimary: Hue.white,
    secondary: Hue.positive,
    surface: Hue.paper,
    onSurface: Hue.ink,
    onSurfaceVariant: Hue.muted,
    outline: Hue.muted,
    outlineVariant: Hue.line,
    surfaceContainerLowest: Hue.white,
    surfaceContainerLow: Hue.panel,
    surfaceContainer: Hue.panel,
    surfaceContainerHigh: Hue.surface,
    surfaceContainerHighest: Hue.surface,
  );
  final base = ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: Hue.paper,
    fontFamily: 'Nunito',
    fontFamilyFallback: const ['Huninn'],
    useMaterial3: true,
    splashFactory: NoSplash.splashFactory,
  );
  return base.copyWith(
    dividerTheme: const DividerThemeData(color: Hue.line, space: 1),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Hue.ink,
    ),
    textTheme: base.textTheme.apply(bodyColor: Hue.ink, displayColor: Hue.ink),
  );
}
