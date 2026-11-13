import 'package:flutter/material.dart';

import 'controls.dart';
import 'glyphs.dart';
import 'haptics.dart';
import 'theme.dart';

/// The pieces the 0.9.0 pages are built from: a tick in a circle for a
/// switch, a panel in the middle of the screen for a setting's details,
/// flat tinted cards, the white board of rows, the ⋯ menu, a small heading
/// with a thin rule, and what a page shows when it has nothing yet. Each
/// reads its colours from [Hue] when built, so each has a dark version.

/// [color] mixed into the paper: the flat tint of a card in that colour.
/// The same mix on the dark paper gives the dark card.
Color tintOf(Color color, [double amount = 0.2]) =>
    Color.lerp(Hue.paper, color, Shade.dark ? amount + 0.08 : amount)!;

/// [color] a step deeper for words on its own tint, or a step lighter on
/// the dark theme.
Color deepOf(Color color) => Shade.dark
    ? Color.lerp(color, const Color(0xFFFFFFFF), 0.35)!
    : Color.lerp(color, const Color(0xFF1A2228), 0.3)!;

/// A colour picked from [name], the same each time: for what has no
/// colour of its own, such as a tag, a merchant, a person or a loan.
Color nameColor(String name) {
  var sum = 0;
  for (final unit in name.codeUnits) {
    sum = (sum * 31 + unit) & 0x7fffffff;
  }
  return nameColors[sum % nameColors.length];
}

/// The colours [nameColor] picks from, light and dark.
const nameColors = [
  Shade(0xFFD08B5B, 0xFFE3AA82),
  Shade(0xFFB07A8C, 0xFFD3A2B3),
  Shade(0xFF5C9A83, 0xFF8CC3AE),
  Shade(0xFFC9A34A, 0xFFDDBE73),
  Shade(0xFF7686B8, 0xFFA5B1D8),
  Shade(0xFF4E8A9A, 0xFF86B5C1),
  Shade(0xFF8E7CC0, 0xFFB5A8DD),
  Shade(0xFF5B8DB0, 0xFF8DB5D1),
];

/// An icon in white on a rounded square of solid [color]: the mark of a
/// category, a setting or a tool.
class SquareIcon extends StatelessWidget {
  const SquareIcon(this.glyph, this.color, {super.key, this.size = 44});

  final Glyph glyph;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      alignment: Alignment.center,
      child: GlyphIcon(
        glyph,
        size: size * 0.5,
        color: const Color(0xFFFFFFFF),
        tinted: false,
      ),
    );
  }
}

/// The switch of every setting: a 28 dp circle with a tick. On, it is
/// solid [color] with a white tick; off, a pale circle with a pale tick.
class TickSwitch extends StatelessWidget {
  const TickSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    required this.label,
    this.color = Hue.accent,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;

  /// What the screen reader says, such as 到期提醒.
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final change = onChanged;
    return Semantics(
      toggled: value,
      label: label,
      child: TapArea(
        onTap: change == null ? null : () => change(!value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: value ? color : tintOf(color, 0.3),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: GlyphIcon(
            Glyph.check,
            size: 16,
            weight: 2.2,
            tinted: false,
            color: value
                ? const Color(0xFFFFFFFF)
                : Color.lerp(tintOf(color, 0.3), color, 0.35),
          ),
        ),
      ),
    );
  }
}

/// A flat card in the tint of [color], no shadow: the cards of the
/// settings pages, the tools' tiles, the 預算 blocks.
class ColorCard extends StatelessWidget {
  const ColorCard({
    super.key,
    required this.color,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.padding = const EdgeInsets.all(16),
    this.radius = 22,
    this.amount = 0.2,
    this.label,
  });

  final Color color;
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final EdgeInsets padding;
  final double radius;

  /// How much of [color] is in the tint.
  final double amount;

  /// What the screen reader says for the whole card, when it is a button.
  final String? label;

  @override
  Widget build(BuildContext context) {
    final shape = BorderRadius.circular(radius);
    final card = Material(
      color: tintOf(color, amount),
      borderRadius: shape,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: shape,
        onTap: onTap == null
            ? null
            : () {
                Haptics.selection();
                onTap!();
              },
        onLongPress: onLongPress,
        child: Padding(padding: padding, child: child),
      ),
    );
    final framed = label == null
        ? card
        : Semantics(button: onTap != null, label: label, child: card);
    return onTap == null ? framed : Pressable(depth: 0.98, child: framed);
  }
}

/// A setting as a card: its icon on a solid square at the top left, a
/// [TickSwitch] (or nothing) at the top right, its name and one line of
/// state below. A tap opens its details in a [showCenterPanel].
class SettingCard extends StatelessWidget {
  const SettingCard({
    super.key,
    required this.glyph,
    required this.color,
    required this.title,
    required this.detail,
    this.value,
    this.onChanged,
    this.onTap,
  });

  final Glyph glyph;
  final Color color;
  final String title;
  final String detail;

  /// Whether it is on; null when the card has no switch.
  final bool? value;
  final ValueChanged<bool>? onChanged;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final on = value;
    return ColorCard(
      color: color,
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(16, 16, 10, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SquareIcon(glyph, color, size: 46),
              const Spacer(),
              if (on != null)
                TickSwitch(
                  value: on,
                  color: color,
                  label: title,
                  onChanged: onChanged,
                ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            title,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: deepOf(color),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            detail,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13, color: deepOf(color)),
          ),
        ],
      ),
    );
  }
}

/// Cards two to a row, each row as tall as its tallest card, so a card
/// grows with larger text and its neighbour grows with it.
class CardGrid extends StatelessWidget {
  const CardGrid(this.children, {super.key, this.columns = 2, this.gap = 12});

  final List<Widget> children;
  final int columns;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i += columns) {
      final cells = <Widget>[];
      for (var j = 0; j < columns; j++) {
        if (j > 0) cells.add(SizedBox(width: gap));
        final k = i + j;
        cells.add(
          Expanded(child: k < children.length ? children[k] : const SizedBox()),
        );
      }
      if (rows.isNotEmpty) rows.add(SizedBox(height: gap));
      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: cells,
          ),
        ),
      );
    }
    return Column(children: rows);
  }
}

/// A small heading with a thin rule running to the right: 報表與投資 ——.
class RuleHead extends StatelessWidget {
  const RuleHead(this.title, {super.key, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 10),
      child: Row(
        children: [
          Semantics(
            header: true,
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Hue.muted,
              ),
            ),
          ),
          const SizedBox(width: 10),
          const Expanded(child: Divider(height: 1, color: Hue.line)),
          if (trailing != null) ...[const SizedBox(width: 10), trailing!],
        ],
      ),
    );
  }
}

/// A sub-page's title row: back on the left, the title in the middle and
/// up to two buttons on the right.
class CenterHeader extends StatelessWidget {
  const CenterHeader(
    this.title, {
    super.key,
    required this.onBack,
    this.actions = const [],
  });

  final String title;
  final VoidCallback onBack;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 60),
      margin: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          SizedBox(
            width: 96,
            child: Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                tooltip: '返回',
                onPressed: onBack,
                icon: const GlyphIcon(Glyph.back, size: 24),
              ),
            ),
          ),
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                title,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          SizedBox(
            width: 96,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: actions,
            ),
          ),
        ],
      ),
    );
  }
}

/// A round icon button for a header's right side, such as ＋ or ⋯.
class HeaderButton extends StatelessWidget {
  const HeaderButton({
    super.key,
    required this.glyph,
    required this.label,
    required this.onTap,
  });

  final Glyph glyph;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: label,
    onPressed: onTap,
    icon: GlyphIcon(glyph, size: 24),
  );
}

/// The white board of rows, as on a quote board: each row an icon, a name
/// with one line under it, and a figure on the right, thin rules between.
class QuoteBoard extends StatelessWidget {
  const QuoteBoard(this.rows, {super.key});

  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Hue.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: Hue.cardShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          children: [
            for (final (i, row) in rows.indexed) ...[
              if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
              row,
            ],
          ],
        ),
      ),
    );
  }
}

/// One row of a [QuoteBoard].
class QuoteRow extends StatelessWidget {
  const QuoteRow({
    super.key,
    required this.title,
    this.lead,
    this.detail,
    this.trailing,
    this.onTap,
  });

  final Widget? lead;
  final String title;
  final String? detail;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final words = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        if (detail != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(detail!, style: mutedSmall),
          ),
      ],
    );
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 64),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              if (lead != null) ...[lead!, const SizedBox(width: 14)],
              Expanded(child: words),
              if (trailing != null) ...[const SizedBox(width: 10), trailing!],
            ],
          ),
        ),
      ),
    );
  }
}

/// A big figure on the right of a [QuoteRow].
class RowFigure extends StatelessWidget {
  const RowFigure(this.text, {super.key, this.color = Hue.ink});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(
      fontSize: 17,
      fontWeight: FontWeight.w800,
      color: color,
      fontFeatures: const [FontFeature.tabularFigures()],
    ),
  );
}

/// One choice of a [DotsMenu].
class DotsItem {
  const DotsItem(this.glyph, this.label, this.onTap, {this.danger = false});

  final Glyph glyph;
  final String label;
  final VoidCallback onTap;
  final bool danger;
}

/// The ⋯ in a card's corner, opening a small menu of what can be done to
/// it, the one that cannot be taken back in red at the end.
class DotsMenu extends StatelessWidget {
  const DotsMenu(this.items, {super.key, this.label = '更多選項'});

  final List<DotsItem> items;
  final String label;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<int>(
      tooltip: label,
      color: Hue.white,
      elevation: 8,
      position: PopupMenuPosition.under,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      onSelected: (i) => items[i].onTap(),
      itemBuilder: (context) => [
        for (final (i, item) in items.indexed) ...[
          if (i > 0) const PopupMenuDivider(height: 1),
          PopupMenuItem<int>(
            value: i,
            height: 52,
            child: Row(
              children: [
                GlyphIcon(
                  item.glyph,
                  size: 20,
                  tinted: false,
                  color: item.danger ? Hue.danger : Hue.ink,
                ),
                const SizedBox(width: 14),
                Text(
                  item.label,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: item.danger ? Hue.danger : Hue.ink,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: const Color(0x33FFFFFF),
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.center,
        child: const GlyphIcon(Glyph.more, size: 22, color: Hue.ink),
      ),
    );
  }
}

/// The panel in the middle of the screen that every setting's details
/// open in, never a sheet from the bottom: its icon, name and a line on
/// what it does at the top, [trailing] on the right of that, then [body]
/// and the [actions] along the bottom.
class CenterPanel extends StatelessWidget {
  const CenterPanel({
    super.key,
    required this.glyph,
    required this.color,
    required this.title,
    this.detail,
    this.trailing,
    this.body,
    this.actions = const [],
  });

  final Glyph glyph;
  final Color color;
  final String title;
  final String? detail;
  final Widget? trailing;
  final Widget? body;

  /// Buttons side by side along the bottom, each as wide as the others.
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Hue.paper,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                SquareIcon(glyph, color, size: 56),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Semantics(
                        header: true,
                        child: Text(
                          title,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      if (detail != null)
                        Text(
                          detail!,
                          style: const TextStyle(
                            fontSize: 14,
                            color: Hue.muted,
                          ),
                        ),
                    ],
                  ),
                ),
                ?trailing,
              ],
            ),
            if (body != null) ...[const SizedBox(height: 18), body!],
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 20),
              Row(
                children: [
                  for (final (i, action) in actions.indexed) ...[
                    if (i > 0) const SizedBox(width: 12),
                    Expanded(child: action),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Opens a [CenterPanel] with 完成 along the bottom and, when [value] is
/// given, a [TickSwitch] at the top. A tap on the dark around it closes
/// it as well. [body] is built again after the switch is touched.
Future<void> showCenterPanel(
  BuildContext context, {
  required Glyph glyph,
  required Color color,
  required String title,
  String? detail,
  bool Function()? value,
  ValueChanged<bool>? onChanged,
  WidgetBuilder? body,
  String done = '完成',
}) {
  return showPanel<void>(
    context,
    (context) => StatefulBuilder(
      builder: (context, setState) {
        final on = value?.call();
        return CenterPanel(
          glyph: glyph,
          color: color,
          title: title,
          detail: detail,
          trailing: on == null
              ? null
              : TickSwitch(
                  value: on,
                  color: color,
                  label: title,
                  onChanged: onChanged == null
                      ? null
                      : (v) {
                          onChanged(v);
                          setState(() {});
                        },
                ),
          body: body == null ? null : Builder(builder: body),
          actions: [
            PanelButton(done, onTap: () => Navigator.of(context).pop()),
          ],
        );
      },
    ),
  );
}

/// Opens [builder] over a dimmed page, as the middle-of-the-screen panels
/// are; a tap on the dark closes it unless [dismissible] is off.
Future<T?> showPanel<T>(
  BuildContext context,
  WidgetBuilder builder, {
  bool dismissible = true,
}) => showDialog<T>(
  context: context,
  barrierDismissible: dismissible,
  barrierColor: const Color(0x66222B30),
  builder: builder,
);

/// A wide button: grey by default, solid [color] when given.
class PanelButton extends StatelessWidget {
  const PanelButton(this.label, {super.key, required this.onTap, this.color});

  final String label;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final solid = color;
    return Pressable(
      child: Material(
        color: solid ?? Hue.surface,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: solid == null ? Hue.ink : Hue.onAccent,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// What a page shows with nothing on it yet: a big pale icon in the
/// page's colour, one sentence, and a button when something can be added
/// from here.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.glyph,
    required this.color,
    required this.message,
    this.action,
    this.onAction,
  });

  final Glyph glyph;
  final Color color;
  final String message;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final act = onAction;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: tintOf(color, 0.22),
              borderRadius: BorderRadius.circular(30),
            ),
            alignment: Alignment.center,
            child: GlyphIcon(
              glyph,
              size: 48,
              color: Color.lerp(tintOf(color, 0.22), color, 0.7),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 15, color: Hue.muted),
          ),
          if (action != null && act != null) ...[
            const SizedBox(height: 18),
            FilledButton(
              onPressed: act,
              style: FilledButton.styleFrom(
                backgroundColor: color,
                foregroundColor: Hue.onAccent,
                minimumSize: const Size(0, 52),
                padding: const EdgeInsets.symmetric(horizontal: 24),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                textStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              child: Text(action!),
            ),
          ],
        ],
      ),
    );
  }
}
