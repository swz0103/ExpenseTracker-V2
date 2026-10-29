import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// A colour with a light and a dark value, read when painted: the whole
/// palette follows [Shade.dark] without a const widget changing.
final class Shade extends Color {
  const Shade(this.light, this.darkValue) : super(light);

  final int light;
  final int darkValue;

  /// Whether the app shows its dark colours; [show] changes it.
  static bool dark = false;

  /// Turns the palette light or dark and draws every screen again in
  /// place, so open pages, sheets and what was typed in them stay as they
  /// were.
  ///
  /// A [Shade] is the same colour object in both modes, so the framework
  /// sees nothing new and keeps what it painted: every widget is built
  /// again (colours worked out while building, such as [softOf], change),
  /// and every box drops the paint and the laid-out words it holds on to
  /// before it is painted again, custom painters too.
  ///
  /// Only words, text fields and decorated boxes are let go of that way
  /// (see [_repaint]). Anything else that keeps a painter of its own past
  /// a build will go on painting the old colour: an `Ink` or other
  /// `InkDecoration` on a [Material], and `ListTile.tileColor` or
  /// `selectedTileColor`, which become ink on the nearest [Material]. Give
  /// those no [Hue] colour; colour the [Material] itself, or use a
  /// [DecoratedBox] or [Container] instead.
  static void show({required bool dark}) {
    if (dark == Shade.dark) return;
    Shade.dark = dark;
    final root = WidgetsBinding.instance.rootElement;
    if (root == null) return;
    void visit(Element element) {
      element.markNeedsBuild();
      if (element is RenderObjectElement) _repaint(element.renderObject);
      element.visitChildren(visit);
    }

    visit(root);
  }

  /// Makes [box] lay out and paint afresh. Words and decorations are set
  /// to something else and back, which is how their render objects let go
  /// of what they made with the old colours.
  static void _repaint(RenderObject box) {
    if (box is RenderParagraph) {
      final text = box.text;
      box
        ..text = const TextSpan()
        ..text = text;
    } else if (box is RenderEditable) {
      // Empty words rather than none: a text field with no words at all
      // fails when it describes itself to the screen reader.
      final text = box.text;
      box
        ..text = const TextSpan()
        ..text = text;
    } else if (box is RenderDecoratedBox) {
      final decoration = box.decoration;
      box
        ..decoration = const BoxDecoration()
        ..decoration = decoration;
    }
    box
      ..markNeedsLayout()
      ..markNeedsPaint();
  }

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

  /// White cards and fills on the paper; a dark slate on the dark theme.
  static const white = Shade(0xFFFFFFFF, 0xFF1C2226);

  /// Dialogs, sheets and the tab bar: the same colour as [white], under
  /// its own name for where it is used.
  static const panel = white;
  static const surface = Shade(0xFFE9ECEA, 0xFF262D31);
  static const selected = Shade(0xFFDCE8EC, 0xFF1E3742);
  static const ink = Shade(0xFF26323A, 0xFFE3E8EA);
  static const muted = Shade(0xFF525D63, 0xFFA6B1B6);
  static const faint = Shade(0xFFA7B0B3, 0xFF5E6A70);
  static const line = Shade(0xFFE1E4E0, 0xFF2C3438);

  /// Text and icons on a coloured fill: white on the light theme's deep
  /// colours, near-black on the dark theme's light ones (4.5:1 or more).
  static const onAccent = Shade(0xFFFFFFFF, 0xFF0F1A1F);

  /// Words that wait to be filled in, such as 未填: quieter than [muted],
  /// still 4.5:1 on every surface.
  static const hint = Shade(0xFF586369, 0xFF98A3A9);

  /// Gold as words, darker than [cash], which is for marks and fills.
  static const goldText = Shade(0xFF7A5E18, 0xFFDDBC66);

  /// Cards: [white] on the paper, lifted by [cardShadow]. The same
  /// object as [white], so [SoftPanel] lifts either.
  static const mist = white;

  /// Summary blocks: the page's main block and the smaller ones, both a
  /// tint of [accent] on the paper.
  static const hero = Shade(0xFFD8E1E2, 0xFF1F2E35);
  static const tile = Shade(0xFFE0E6E5, 0xFF20282C);

  /// Empty track behind bars.
  static const track = Shade(0xFFE9ECEA, 0xFF2C3438);

  /// The interface colour: tabs, buttons, links, the chosen day.
  static const accent = Shade(0xFF35657A, 0xFF72A8BC);

  /// Income, gains and refunds.
  static const positive = Shade(0xFF276B58, 0xFF66BD9E);

  /// Spending and losses.
  static const negative = Shade(0xFF9F4535, 0xFFEA8A74);
  static const transfer = Shade(0xFF356672, 0xFF7DB4C2);
  static const investment = Shade(0xFF4A5D99, 0xFF97A7DE);

  /// Deleting and what went wrong: the spending colour, [negative], under
  /// its own name for where it is used.
  static const danger = negative;

  /// Account groups.
  static const cash = Shade(0xFFC9A34A, 0xFFD9B65E);
  static const bank = Shade(0xFF5C9A83, 0xFF74B39A);
  static const wallet = Shade(0xFF5B8DB0, 0xFF78A6C8);
  static const card = Shade(0xFFB5523E, 0xFFE07A64);
  static const holdings = Shade(0xFFD08B5B, 0xFFE0A073);
  static const receivable = Shade(0xFF625199, 0xFFB2A4DD);

  /// Thin rules and empty tracks on the tinted blocks, in the interface
  /// colour: the rule over a hero tile's figures, the ring behind a
  /// share, the track behind a split's bars.
  static const accentRule = Shade(0x2E3B6C80, 0x3372A8BC);
  static const accentTrack = Shade(0x263B6C80, 0x2E72A8BC);

  /// The glow under the round 記一筆 button.
  static const accentGlow = Shade(0x553B6C80, 0x66000000);

  /// The tint under a finger: held, and the ripple spreading.
  static const pressHighlight = Shade(0x0F3B6C80, 0x1472A8BC);
  static const pressSplash = Shade(0x1F3B6C80, 0x2972A8BC);

  /// Colours for parts of a whole in the charts, in order: the second
  /// level of 財務分布. Lighter on the dark theme.
  static const shades = [
    Shade(0xFF5B8DB0, 0xFF79A2BE),
    Shade(0xFFD08B5B, 0xFFD8A079),
    Shade(0xFF5C9A83, 0xFF79AC99),
    Shade(0xFF8E7CC0, 0xFFA294CB),
    Shade(0xFFC9A34A, 0xFFD3B46B),
    Shade(0xFFB07A8C, 0xFFBE92A1),
    Shade(0xFF4E8A9A, 0xFF6E9FAC),
    Shade(0xFFA0866A, 0xFFB19C85),
    Shade(0xFF7686B8, 0xFF8F9CC5),
    Shade(0xFF9AA35E, 0xFFACB47B),
    Shade(0xFF6E9C93, 0xFF88AEA6),
    Shade(0xFFB08AA6, 0xFFBE9FB6),
  ];

  /// The colours a category may be given, in the order new ones take
  /// them. Plain colours, not [Shade]s: the one chosen is kept with the
  /// category, the same in both modes.
  static const categoryColors = [
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

  /// The lift under tiles: just off the paper. None on the dark theme,
  /// where a shadow would not show on the dark paper and the lighter
  /// surface already sets the tile apart.
  static const tileShadow = [
    BoxShadow(
      color: Shade(0x0A1E2832, 0x00000000),
      blurRadius: 6,
      offset: Offset(0, 2),
    ),
  ];

  /// The lift under white cards; none on the dark theme, as [tileShadow].
  static const cardShadow = [
    BoxShadow(
      color: Shade(0x0F1E2832, 0x00000000),
      blurRadius: 2,
      offset: Offset(0, 1),
    ),
    BoxShadow(
      color: Shade(0x0D1E2832, 0x00000000),
      blurRadius: 14,
      offset: Offset(0, 4),
    ),
  ];
}

/// A light version of [color] for icon backgrounds.
Color softOf(Color color) => Color.lerp(color, Hue.paper, 0.82)!;

/// Secondary words in 13 px, such as a count or a date beside a heading.
const mutedSmall = TextStyle(fontSize: 13, color: Hue.muted);

/// Words in 13 px in the interface colour that do something, such as a
/// small link or 調整 on a tile. Words that only label stay [mutedSmall].
const accentSmall = TextStyle(fontSize: 13, color: Hue.accent);

/// A tile's or a form block's own label in 13 px, in the interface
/// colour and a little heavier than [accentSmall].
const accentLabel = TextStyle(
  fontSize: 13,
  fontWeight: FontWeight.w600,
  color: Hue.accent,
);

/// The thin rule between rows of a list on a card, in [Hue.line].
const rowRule = BorderSide(color: Hue.line);

/// A row's [rowRule] above it, as each row after a list's first has.
const ruleAbove = BoxDecoration(border: Border(top: rowRule));

/// A row's [rowRule] below it, as each row before a list's last has.
const ruleBelow = BoxDecoration(border: Border(bottom: rowRule));

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
    fontFamilyFallback: const ['NotoSansTC'],
    useMaterial3: true,
    // A soft ripple in the accent under the finger, so every tap is felt.
    splashFactory: InkRipple.splashFactory,
    hoverColor: Colors.transparent,
    highlightColor: Hue.pressHighlight,
    splashColor: Hue.pressSplash,
  );
  return base.copyWith(
    dividerTheme: const DividerThemeData(color: Hue.line, space: 1),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: dark ? Hue.surface : Hue.ink,
      // Named outright: this style replaces the theme's, font included.
      contentTextStyle: TextStyle(
        fontFamily: 'Nunito',
        fontFamilyFallback: const ['NotoSansTC'],
        fontSize: 14,
        color: dark ? Hue.ink : Hue.white,
      ),
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    textTheme: base.textTheme.apply(bodyColor: Hue.ink, displayColor: Hue.ink),
  );
}
