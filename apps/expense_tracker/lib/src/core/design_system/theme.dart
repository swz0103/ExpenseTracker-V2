import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'type.dart';
import 'shape.dart';
import '../ledger/models/category.dart' show categoryColorValues;

export 'type.dart';

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
  /// those no [AppColors] colour; colour the [Material] itself, or use a
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
abstract final class AppColors {
  static const paper = Shade(0xFFF3F4F1, 0xFF2A3237);

  /// White cards and fills on the paper; a mid grey on the dark theme,
  /// lighter than the paper (2026-11-13: dark is a clear dark grey, not
  /// near-black).
  static const white = Shade(0xFFFFFFFF, 0xFF343F45);

  /// Dialogs, sheets and the tab bar: the same colour as [white], under
  /// its own name for where it is used.
  static const panel = white;
  static const surface = Shade(0xFFE9ECEA, 0xFF3E4A50);
  static const selected = Shade(0xFFDCE8EC, 0xFF2C4753);
  static const ink = Shade(0xFF26323A, 0xFFCDD4D7);
  static const muted = Shade(0xFF525D63, 0xFFB8C2C6);
  static const faint = Shade(0xFFA7B0B3, 0xFF7E8A90);
  static const line = Shade(0xFFE1E4E0, 0xFF46535A);

  /// Text and icons on a coloured fill: white on the light theme's deep
  /// colours, near-black on the dark theme's light ones (4.5:1 or more).
  static const onAccent = Shade(0xFFFFFFFF, 0xFF0F1A1F);

  /// Words that wait to be filled in, such as 未填: quieter than [muted],
  /// still 4.5:1 on every surface.
  static const hint = Shade(0xFF586369, 0xFFB4BEC2);

  /// Green for a gain, red for a loss; nothing changed reads as a gain.
  static Shade ofChange(num change) => change < 0 ? negative : positive;

  /// Red for a market's rise or a holding's gain, green for a fall or a
  /// loss, as Taiwan's exchanges and brokers show them; muted when flat.
  static Shade ofMarket(num change) =>
      change > 0 ? rise : (change < 0 ? fall : muted);

  /// Red when spending went up (or held), green when it went down.
  static Shade ofSpendingChange(num change) =>
      change >= 0 ? negative : positive;

  /// Ink for a balance, red once it is below zero.
  static Shade ofBalance(num balance) => balance < 0 ? negative : ink;

  /// Gold as words, darker than [cash], which is for marks and fills.
  static const goldText = Shade(0xFF7A5E18, 0xFFCAAF68);

  /// Summary blocks: the page's main block and the smaller ones, both a
  /// tint of [accent] on the paper.
  static const hero = Shade(0xFFD8E1E2, 0xFF32464F);
  static const tile = Shade(0xFFE0E6E5, 0xFF313C42);

  /// The flat grey under a group of rows (`GroupBox`): a step off the
  /// paper, as deep as an account's card on the dark theme.
  static const group = Shade(0xFFE8EBE7, 0xFF323C42);

  /// Empty track behind bars.
  static const track = Shade(0xFFE9ECEA, 0xFF46535A);

  /// The interface colour: tabs, buttons, links, the chosen day.
  static const accent = Shade(0xFF35657A, 0xFF98B7C3);

  /// Income, gains and refunds.
  static const positive = Shade(0xFF276B58, 0xFF84BDA8);

  /// Spending and losses.
  static const negative = Shade(0xFF9F4535, 0xFFE0A495);

  /// A market's rise and fall as Taiwan's exchanges and brokers show
  /// them: red up, green down, the reverse of income and spending.
  static const rise = negative;
  static const fall = positive;
  static const transfer = Shade(0xFF356672, 0xFF94B8C1);
  static const investment = Shade(0xFF4A5D99, 0xFFA5B1D7);

  /// Deleting and what went wrong: the spending colour, [negative], under
  /// its own name for where it is used.
  static const danger = negative;

  /// Account groups.
  static const cash = Shade(0xFFC9A34A, 0xFFB19146);
  static const bank = Shade(0xFF5C9A83, 0xFF6E9F8D);
  static const wallet = Shade(0xFF5B8DB0, 0xFF7699B2);
  static const card = Shade(0xFFB5523E, 0xFFC48579);
  static const holdings = Shade(0xFFD08B5B, 0xFFC28860);
  static const receivable = Shade(0xFF625199, 0xFFC2BADE);

  /// Thin rules and empty tracks on the tinted blocks, in the interface
  /// colour: the rule over a hero tile's figures, the ring behind a
  /// share, the track behind a split's bars.
  static const accentRule = Shade(0x2E3B6C80, 0x3372A8BC);
  static const accentTrack = Shade(0x263B6C80, 0x2E72A8BC);

  /// The guided tour's card: the light theme's own colours on both
  /// themes, for the card stands on the dimmed screen, not on the page;
  /// and the dim spread over the screen around the light.
  static const tourPaper = Color(0xFFF3F4F1);
  static const tourTint = Color(0xFFDCE6E8);
  static const tourInk = Color(0xFF26323A);
  static const tourAccent = Color(0xFF35657A);
  static const tourMuted = Color(0xFF66737A);
  static const tourDim = Color(0xA30C1216);
  static const tourShadow = Color(0x4D000000);

  /// White on a solid mark of any colour, the same on both themes.
  static const onSolid = Color(0xFFFFFFFF);

  /// Nothing: a border or a fade's far end that should not show.
  static const none = Color(0x00000000);

  /// A frosted fill on a tinted card, such as an icon's circle or a small
  /// label: white mist on the light theme, a whisper on the dark one.
  static const glass = Shade(0xC0FFFFFF, 0x1FFFFFFF);

  /// The soft light behind the lock screen's mark.
  static const halo = Shade(0xBFFFFFFF, 0x1A72A8BC);

  /// The dark over the page behind a panel in the middle.
  static const scrim = Color(0x66222B30);

  /// The shadow of something lifted by a finger, such as a card dragged.
  static const lift = Color(0x40000000);

  /// The soft shadow under a floating card, such as the widget's face.
  static const float = Color(0x1F1E2832);

  /// The shadows of a card in a stack: far above it, and close under it.
  static const stackFar = Shade(0x141E2832, 0x00000000);
  static const stackNear = Shade(0x0F1E2832, 0x00000000);

  /// The glow under the round 記一筆 button.
  static const accentGlow = Shade(0x553B6C80, 0x66000000);

  /// The tint under a finger: held, and the ripple spreading.
  static const pressHighlight = Shade(0x0F3B6C80, 0x1472A8BC);
  static const pressSplash = Shade(0x1F3B6C80, 0x2972A8BC);

  /// Colours for parts of a whole in the charts, in order: the second
  /// level of 財務分布. Dark values follow [darkFill].
  static const shades = [
    Shade(0xFF5B8DB0, 0xFF7699B2),
    Shade(0xFFD08B5B, 0xFFC28860),
    Shade(0xFF5C9A83, 0xFF6E9F8D),
    Shade(0xFF8E7CC0, 0xFF9B8EBF),
    Shade(0xFFC9A34A, 0xFFB19146),
    Shade(0xFFB07A8C, 0xFFB28A98),
    Shade(0xFF4E8A9A, 0xFF6C9CA9),
    Shade(0xFFA0866A, 0xFFA5927E),
    Shade(0xFF7686B8, 0xFF8894B8),
    Shade(0xFF9AA35E, 0xFF929963),
    Shade(0xFF6E9C93, 0xFF799C95),
    Shade(0xFFB08AA6, 0xFFAB8CA3),
  ];

  /// The colours a category may be given, in the order new ones take
  /// them ([categoryColorValues], the one list). Plain colours, not
  /// [Shade]s: the one chosen is kept with the category, the same in both
  /// modes.
  static final categoryColors = [
    for (final value in categoryColorValues) Color(value),
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
}

/// A light version of [color] for icon backgrounds.
Color softOf(Color color) => Color.lerp(color, AppColors.paper, 0.82)!;

/// Secondary words in 13 px, such as a count or a date beside a heading.
const mutedSmall = TextStyle(fontSize: TextSize.small, color: AppColors.muted);

/// Quiet words at caption size: a label over a figure, a footnote.
const mutedCaption = TextStyle(
  fontSize: TextSize.caption,
  color: AppColors.muted,
);

/// Quiet words at body size: a hint, a placeholder, a value set aside.
const mutedBody = TextStyle(fontSize: TextSize.body, color: AppColors.muted);

/// Quiet words at the smallest size, such as 到期 under a day.
const mutedTiny = TextStyle(fontSize: TextSize.tiny, color: AppColors.muted);

/// Words in the quiet colour at the size around them.
const mutedText = TextStyle(color: AppColors.muted);

/// A field's hint, fainter than words typed.
const hintText = TextStyle(color: AppColors.faint);

/// Words that warn, at the size around them.
const dangerText = TextStyle(color: AppColors.danger);

/// Words in 13 px in the interface colour that do something, such as a
/// small link or 調整 on a tile. Words that only label stay [mutedSmall].
const accentSmall = TextStyle(
  fontSize: TextSize.small,
  color: AppColors.accent,
);

/// A tile's or a form block's own label in 13 px, in the interface
/// colour and a little heavier than [accentSmall].
const accentLabel = TextStyle(
  fontSize: TextSize.small,
  fontWeight: FontWeight.w600,
  color: AppColors.accent,
);

/// The thin rule between rows of a list on a card, in [AppColors.line].
const rowRule = BorderSide(color: AppColors.line);

/// A row's [rowRule] above it, as each row after a list's first has.
const ruleAbove = BoxDecoration(border: Border(top: rowRule));

/// A row's [rowRule] below it, as each row before a list's last has.
const ruleBelow = BoxDecoration(border: Border(bottom: rowRule));

/// The colours the pages give their cards, icons and charts, each with
/// its lighter self for the dark theme: one list, so the same blue is
/// the same blue everywhere. Words on their tints use deepOf (components.dart).
abstract final class Palette {
  /// 金：股息、預算快用完、救援碼
  static const gold = Shade(0xFFC9A34A, 0xFFB19146);

  /// 橘：飲食、提醒
  static const orange = Shade(0xFFD08B5B, 0xFFC28860);

  /// 綠：居家、預算、安全
  static const green = Shade(0xFF5C9A83, 0xFF6E9F8D);

  /// 靛：持股、買進、密碼
  static const indigo = Shade(0xFF4A5D99, 0xFF8794BC);

  /// 玫瑰
  static const rose = Shade(0xFFB07A8C, 0xFFB28A98);

  /// 紫：外觀、每日記帳
  static const violet = Shade(0xFF8E7CC0, 0xFF9B8EBF);

  /// 藍紫：資料夾、匯入
  static const periwinkle = Shade(0xFF7686B8, 0xFF8894B8);

  /// 藍：交通
  static const blue = Shade(0xFF5B8DB0, 0xFF7699B2);

  /// 青：備份、日曆
  static const teal = Shade(0xFF4E8A9A, 0xFF6C9CA9);

  /// 磚紅：賣出
  static const brick = Shade(0xFF9F4535, 0xFFC68579);

  /// 灰藍：關於
  static const slate = Shade(0xFF6B767C, 0xFF8E969B);

  /// 橄欖
  static const olive = Shade(0xFF9AA35E, 0xFF929963);

  /// Every one of them, by name, as the contrast check reads them.
  static const all = {
    'gold': gold,
    'orange': orange,
    'green': green,
    'indigo': indigo,
    'rose': rose,
    'violet': violet,
    'periwinkle': periwinkle,
    'blue': blue,
    'teal': teal,
    'brick': brick,
    'slate': slate,
    'olive': olive,
  };
}

/// A colour kept with a record, such as a category's, as the screen
/// shows it: itself on the light theme, [darkFill] of it on the dark one,
/// as bright as every other fill there. What is saved stays [color] itself.
Color shownColor(Color color) {
  if (color is Shade) return color;
  final argb = color.toARGB32();
  return Shade(argb, darkFill(argb));
}

/// A colour drawn as a mark — a chart's bars and lines, a legend's key, a
/// progress bar — on the dark theme as [darkFill] of its light value, a
/// step under the words in the same colour; itself on the light theme.
Color markOf(Color color) {
  if (!Shade.dark) return color;
  return Color(darkFill(color is Shade ? color.light : color.toARGB32()));
}

/// The one rule for colours drawn as fills on the dark theme (the
/// palette, account groups, categories, charts): the light value's hue
/// at 80% of its saturation, as light as reads at 3.6:1 on a card, so all
/// of them are equally bright. Words keep their own, brighter values
/// (4.5:1 on every surface).
int darkFill(int argb) {
  final hsl = HSLColor.fromColor(Color(argb));
  final quiet = hsl.withSaturation(hsl.saturation * 0.8);
  final card = Color(AppColors.white.darkValue).computeLuminance() + 0.05;
  var (low, high) = (0.0, 1.0);
  for (var i = 0; i < 30; i++) {
    final middle = (low + high) / 2;
    final shown = quiet.withLightness(middle).toColor().computeLuminance();
    if ((shown + 0.05) / card < darkFillContrast) {
      low = middle;
    } else {
      high = middle;
    }
  }
  return quiet.withLightness(high).toColor().toARGB32();
}

/// How far a [darkFill] stands off a card on the dark theme.
const darkFillContrast = 3.6;

/// The app's own fonts, for a style that replaces the theme's own, as a
/// button's `textStyle` does: without them the phone draws its own font.
/// The one place the font stack is named; the theme, canvas text and the
/// preview's frame take it from here.
const appFont = TextStyle(
  fontFamily: 'Nunito',
  fontFamilyFallback: ['NotoSansTC'],
);

/// The Material theme over [AppColors], light or dark as [Shade.dark] says.
ThemeData appTheme() {
  final dark = Shade.dark;
  final seeded = ColorScheme.fromSeed(
    seedColor: AppColors.accent,
    brightness: dark ? Brightness.dark : Brightness.light,
    dynamicSchemeVariant: DynamicSchemeVariant.neutral,
  );
  final scheme = seeded.copyWith(
    primary: AppColors.accent,
    onPrimary: AppColors.onAccent,
    secondary: AppColors.accent,
    surface: AppColors.paper,
    onSurface: AppColors.ink,
    onSurfaceVariant: AppColors.muted,
    outline: AppColors.muted,
    outlineVariant: AppColors.line,
    surfaceContainerLowest: AppColors.white,
    surfaceContainerLow: AppColors.panel,
    surfaceContainer: AppColors.panel,
    surfaceContainerHigh: AppColors.surface,
    surfaceContainerHighest: AppColors.surface,
  );
  final base = ThemeData(
    brightness: dark ? Brightness.dark : Brightness.light,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.paper,
    fontFamily: appFont.fontFamily,
    fontFamilyFallback: appFont.fontFamilyFallback,
    useMaterial3: true,
    // A soft ripple in the accent under the finger, so every tap is felt.
    splashFactory: InkRipple.splashFactory,
    hoverColor: Colors.transparent,
    highlightColor: AppColors.pressHighlight,
    splashColor: AppColors.pressSplash,
  );
  return base.copyWith(
    dividerTheme: const DividerThemeData(color: AppColors.line, space: 1),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: dark ? AppColors.surface : AppColors.ink,
      // Named outright: this style replaces the theme's, font included.
      contentTextStyle: appFont.copyWith(
        fontSize: TextSize.body,
        color: dark ? AppColors.ink : AppColors.white,
      ),
      elevation: 6,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.large),
      ),
    ),
    textTheme: base.textTheme.apply(
      bodyColor: AppColors.ink,
      displayColor: AppColors.ink,
    ),
  );
}

/// The colour of each tool, on its tile in 更多, its own page and its card in 總覽.
abstract final class ToolColors {
  static const reports = Palette.blue;
  static const investments = Palette.indigo;
  static const budgets = Palette.green;
  static const recurring = Palette.orange;
  static const debts = Palette.violet;
  static const categories = Palette.rose;
  static const tags = Palette.gold;
  static const settings = Palette.slate;
}
