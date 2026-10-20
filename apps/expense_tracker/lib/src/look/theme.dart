import 'package:flutter/material.dart';

/// A colour with a light and a dark value, read when painted: the whole
/// palette follows [Shade.dark] without a const widget changing.
final class Shade extends Color {
  const Shade(this.light, this.darkValue) : super(light);

  final int light;
  final int darkValue;

  /// Whether the app shows its dark colours; set by the app root.
  static bool dark = false;

  int get _value => dark ? darkValue : light;

  @override
  double get a => (_value >> 24 & 0xFF) / 255;
  @override
  double get r => (_value >> 16 & 0xFF) / 255;
  @override
  double get g => (_value >> 8 & 0xFF) / 255;
  @override
  double get b => (_value & 0xFF) / 255;

  @override
  bool operator ==(Object other) =>
      other is Shade && other.light == light && other.darkValue == darkValue;

  @override
  int get hashCode => Object.hash(light, darkValue);
}

/// The colours of the app, style 一「霧藍北歐」: misty off-white paper,
/// white cards, slate blue for the interface, teal green for income and
/// gains, brick red for spending and losses.
abstract final class Hue {
  static const paper = Shade(0xFFF3F4F1, 0xFF121619);
  static const panel = Shade(0xFFFFFFFF, 0xFF1C2226);
  static const white = Shade(0xFFFFFFFF, 0xFF1C2226);
  static const surface = Shade(0xFFE9ECEA, 0xFF262D31);
  static const selected = Shade(0xFFDCE8EC, 0xFF23414D);
  static const ink = Shade(0xFF26323A, 0xFFE3E8EA);
  static const muted = Shade(0xFF5E6A70, 0xFF9AA6AC);
  static const faint = Shade(0xFFA7B0B3, 0xFF5E6A70);
  static const line = Shade(0xFFE1E4E0, 0xFF2C3438);

  /// Text and icons on a coloured fill.
  static const onAccent = Color(0xFFFFFFFF);

  /// Cards: white on the paper, lifted by [cardShadow].
  static const mist = Shade(0xFFFFFFFF, 0xFF1C2226);

  /// Summary blocks: the page's main block and the smaller ones, both a
  /// tint of [accent] on the paper.
  static const hero = Shade(0xFFCAD6D8, 0xFF22343C);
  static const tile = Shade(0xFFE0E6E5, 0xFF20282C);

  /// Empty track behind bars.
  static const track = Shade(0xFFE9ECEA, 0xFF2C3438);

  /// The interface colour: tabs, buttons, links, the chosen day.
  static const accent = Shade(0xFF3B6C80, 0xFF5B93A8);

  /// Income, gains and refunds.
  static const positive = Shade(0xFF2F7A65, 0xFF5CB394);

  /// Spending and losses.
  static const negative = Shade(0xFFB5523E, 0xFFE07A64);
  static const transfer = Shade(0xFF4E8A9A, 0xFF6FA9B8);
  static const investment = Shade(0xFF5A6FA8, 0xFF8A9BD6);
  static const gold = Shade(0xFFC9A34A, 0xFFD9B65E);
  static const danger = Shade(0xFFB5523E, 0xFFE07A64);

  /// Soft backgrounds behind each kind of entry.
  static const expenseSoft = Shade(0xFFF6E3DE, 0xFF3A2723);
  static const incomeSoft = Shade(0xFFDDEFE8, 0xFF1F3530);
  static const transferSoft = Shade(0xFFDDECEF, 0xFF1F3338);
  static const investmentSoft = Shade(0xFFE3E7F4, 0xFF262B3D);

  /// Account groups.
  static const cash = Shade(0xFFC9A34A, 0xFFD9B65E);
  static const bank = Shade(0xFF5C9A83, 0xFF74B39A);
  static const wallet = Shade(0xFF5B8DB0, 0xFF78A6C8);
  static const card = Shade(0xFFB5523E, 0xFFE07A64);
  static const holdings = Shade(0xFFD08B5B, 0xFFE0A073);
  static const receivable = Shade(0xFF8E7CC0, 0xFFA898D6);

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
  /// Tiles: just lifted off the paper.
  static const tileShadow = [
    BoxShadow(color: Color(0x0A1E2832), blurRadius: 6, offset: Offset(0, 2)),
  ];

  static const cardShadow = [
    BoxShadow(color: Color(0x0F1E2832), blurRadius: 2, offset: Offset(0, 1)),
    BoxShadow(color: Color(0x0D1E2832), blurRadius: 14, offset: Offset(0, 4)),
  ];
}

/// A light version of [color] for icon backgrounds.
Color softOf(Color color) => Color.lerp(color, Hue.paper, 0.82)!;

/// The Material theme over [Hue], light or dark as [Shade.dark] says.
ThemeData appTheme() {
  final dark = Shade.dark;
  final seeded = ColorScheme.fromSeed(
    seedColor: Hue.accent,
    brightness: dark ? Brightness.dark : Brightness.light,
    dynamicSchemeVariant: DynamicSchemeVariant.neutral,
  );
  final scheme = seeded.copyWith(
    primary: Hue.accent,
    onPrimary: Hue.onAccent,
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
    brightness: dark ? Brightness.dark : Brightness.light,
    colorScheme: scheme,
    scaffoldBackgroundColor: Hue.paper,
    fontFamily: 'Nunito',
    fontFamilyFallback: const ['Huninn'],
    useMaterial3: true,
    // A soft ripple in the accent under the finger, so every tap is felt.
    splashFactory: InkRipple.splashFactory,
    hoverColor: Colors.transparent,
    highlightColor: const Color(0x0F3B6C80),
    splashColor: const Color(0x1F3B6C80),
  );
  return base.copyWith(
    dividerTheme: const DividerThemeData(color: Hue.line, space: 1),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: dark ? Hue.surface : Hue.ink,
      contentTextStyle: TextStyle(color: dark ? Hue.ink : Hue.white),
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    textTheme: base.textTheme.apply(bodyColor: Hue.ink, displayColor: Hue.ink),
  );
}
