import 'package:flutter/material.dart';

/// The colours of the app, style 一「霧藍北歐」: misty off-white paper,
/// white cards, slate blue for the interface, teal green for income and
/// gains, brick red for spending and losses.
abstract final class Hue {
  static const paper = Color(0xFFF3F4F1);
  static const panel = Color(0xFFFFFFFF);
  static const white = Color(0xFFFFFFFF);
  static const surface = Color(0xFFE9ECEA);
  static const selected = Color(0xFFDCE8EC);
  static const ink = Color(0xFF26323A);
  static const muted = Color(0xFF5E6A70);
  static const faint = Color(0xFFA7B0B3);
  static const line = Color(0xFFE1E4E0);

  /// Cards: white on the paper, lifted by [cardShadow].
  static const mist = Color(0xFFFFFFFF);

  /// Empty track behind bars.
  static const track = Color(0xFFE9ECEA);

  /// The interface colour: tabs, buttons, links, the chosen day.
  static const accent = Color(0xFF3B6C80);

  /// Income, gains and refunds.
  static const positive = Color(0xFF2F7A65);

  /// Spending and losses.
  static const negative = Color(0xFFB5523E);
  static const transfer = Color(0xFF4E8A9A);
  static const investment = Color(0xFF5A6FA8);
  static const gold = Color(0xFFC9A34A);
  static const danger = Color(0xFFB5523E);

  /// Soft backgrounds behind each kind of entry.
  static const expenseSoft = Color(0xFFF6E3DE);
  static const incomeSoft = Color(0xFFDDEFE8);
  static const transferSoft = Color(0xFFDDECEF);
  static const investmentSoft = Color(0xFFE3E7F4);

  /// Account groups.
  static const cash = Color(0xFFC9A34A);
  static const bank = Color(0xFF5C9A83);
  static const wallet = Color(0xFF5B8DB0);
  static const card = Color(0xFFB5523E);
  static const holdings = Color(0xFFD08B5B);

  /// Colours for parts of a whole, in order: categories, the second level
  /// of 財務分布.
  static const shades = [
    Color(0xFF5B8DB0),
    Color(0xFFD08B5B),
    Color(0xFF5C9A83),
    Color(0xFF8E7CC0),
    Color(0xFFC9A34A),
    Color(0xFFB07A8C),
    Color(0xFF4E8A9A),
    Color(0xFFA0866A),
    Color(0xFF7686B8),
    Color(0xFF9AA35E),
    Color(0xFF6E9C93),
    Color(0xFFB08AA6),
  ];

  /// The lift under cards.
  static const cardShadow = [
    BoxShadow(color: Color(0x0F1E2832), blurRadius: 2, offset: Offset(0, 1)),
    BoxShadow(color: Color(0x0D1E2832), blurRadius: 14, offset: Offset(0, 4)),
  ];
}

/// A light version of [color] for icon backgrounds.
Color softOf(Color color) => Color.lerp(color, Hue.paper, 0.82)!;

ThemeData appTheme() {
  final seeded = ColorScheme.fromSeed(
    seedColor: Hue.accent,
    dynamicSchemeVariant: DynamicSchemeVariant.neutral,
  );
  final scheme = seeded.copyWith(
    primary: Hue.accent,
    onPrimary: Hue.white,
    secondary: Hue.accent,
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
