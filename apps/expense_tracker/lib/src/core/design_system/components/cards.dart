import 'package:flutter/material.dart';

import '../controls.dart';
import '../findable.dart';
import '../glyphs.dart';
import '../haptics.dart';
import '../theme.dart';
import '../components.dart';
import '../shape.dart';
import '../spacing.dart';
import 'package:shell/setting_topic.dart';

// Flat tinted cards, their grid, the main card and the big segment buttons.

/// A flat card in the tint of [color], no shadow: the cards of the
/// settings pages, the tools' tiles, the 預算 blocks.
class ColorCard extends StatelessWidget {
  const ColorCard({
    super.key,
    required this.color,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.padding = const EdgeInsets.all(Space.s4),
    this.radius = 22,
    this.amount = 0.2,
    this.label,
    this.controlsInside = false,
  });

  final Color color;
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final EdgeInsets padding;
  final double radius;

  /// How much of [color] is in the tint.
  final double amount;

  /// What the screen reader says for the whole card, in place of the
  /// words inside, so they are not read twice.
  final String? label;

  /// The card holds switches or buttons of its own: with a [label], they
  /// are still read and pressed apart, and only the words around them are
  /// read twice.
  final bool controlsInside;

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
        child: Padding(
          padding: padding,
          child: label == null || controlsInside
              ? child
              : ExcludeSemantics(child: child),
        ),
      ),
    );
    final framed = label == null
        ? card
        : Semantics(
            container: true,
            button: onTap != null,
            label: label,
            child: card,
          );
    return onTap == null ? framed : Pressable(depth: 0.98, child: framed);
  }
}

/// A setting as a card: its icon on a solid square at the top left, a
/// [TickSwitch] (or nothing) at the top right, its name and one line of
/// state below. A tap opens its details in a [showCenterPanel]. Search
/// finds it by [topic], declared where the card is built (N8).
class SettingCard extends StatelessWidget {
  const SettingCard({
    super.key,
    required this.topic,
    required this.glyph,
    required this.color,
    required this.title,
    required this.detail,
    this.value,
    this.onChanged,
    this.onTap,
  });

  final SettingTopic topic;
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
    // Switched off, the card fades to a light grey: on and off read at a
    // glance, not only by the small tick.
    final off = on == false;
    final tone = off ? AppColors.faint : color;
    final words = off ? AppColors.muted : deepOf(color);
    return Findable(
      topic: topic,
      child: ColorCard(
        color: tone,
        onTap: onTap,
        padding: const EdgeInsets.fromLTRB(
          Space.s4,
          Space.s4,
          Space.s2,
          Space.s4,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SquareIcon(glyph, tone, size: 46),
                const Spacer(),
                if (on != null)
                  TickSwitch(
                    value: on,
                    color: tone,
                    label: title,
                    onChanged: onChanged,
                  ),
              ],
            ),
            const SizedBox(height: Space.s4),
            OneLine(
              title,
              style: TextStyle(
                fontSize: TextSize.title,
                fontWeight: FontWeight.w700,
                color: words,
              ),
            ),
            const SizedBox(height: Space.half),
            OneLine(
              detail,
              style: TextStyle(fontSize: TextSize.small, color: words),
            ),
          ],
        ),
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
  Widget build(BuildContext context) => Column(
    children: rowsOf(children, columns: columns, gap: gap),
  );

  /// The grid's rows, each one widget with [gap] above it but the first:
  /// in a list, a long grid (every merchant) is built a row at a time as
  /// it comes on screen.
  static List<Widget> rowsOf(
    List<Widget> children, {
    int columns = 2,
    double gap = 12,
  }) => [
    for (var i = 0; i < children.length; i += columns)
      Padding(
        padding: EdgeInsets.only(top: i == 0 ? 0 : gap),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var j = 0; j < columns; j++) ...[
                if (j > 0) SizedBox(width: gap),
                Expanded(
                  child: i + j < children.length
                      ? children[i + j]
                      : const SizedBox(),
                ),
              ],
            ],
          ),
        ),
      ),
  ];
}

/// Big buttons that switch a page between its parts, such as 持股 and
/// 股息, or 收支, 分類, 比較 and 習慣: each its own colour, tinted, the
/// chosen one solid. Two lay their icon beside the word; more, above it.
class BigSegments extends StatelessWidget {
  const BigSegments({
    super.key,
    required this.items,
    required this.selected,
    required this.onChanged,
  });

  final List<(Glyph, String, Color)> items;
  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final stacked = items.length > 2;
    return Row(
      children: [
        for (final (i, (glyph, label, color)) in items.indexed) ...[
          if (i > 0) SizedBox(width: stacked ? 8 : 10),
          Expanded(
            child: _BigSegment(
              glyph: glyph,
              label: label,
              color: color,
              chosen: i == selected,
              stacked: stacked,
              onTap: () => onChanged(i),
            ),
          ),
        ],
      ],
    );
  }
}

class _BigSegment extends StatelessWidget {
  const _BigSegment({
    required this.glyph,
    required this.label,
    required this.color,
    required this.chosen,
    required this.stacked,
    required this.onTap,
  });

  final Glyph glyph;
  final String label;
  final Color color;
  final bool chosen;
  final bool stacked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ink = chosen ? chosenInk(color) : deepOf(color);
    final icon = GlyphIcon(glyph, size: stacked ? 24 : 20, color: ink);
    final word = Text(
      label,
      style: TextStyle(
        fontSize: stacked ? TextSize.body : TextSize.title,
        fontWeight: FontWeight.w800,
        color: ink,
      ),
    );
    return ReadAsButton(
      selected: chosen,
      label: label,
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Radii.large),
          boxShadow: chosen ? AppColors.tileShadow : null,
        ),
        child: Material(
          color: chosen ? chosenFill(color) : tintOf(color, 0.2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.large),
            side: chosen ? chosenEdge(color) : BorderSide.none,
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(Radii.large),
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 52),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  vertical: stacked ? Space.s3 : Space.s2,
                ),
                child: stacked
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          icon,
                          const SizedBox(height: Space.s1),
                          word,
                        ],
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          icon,
                          const SizedBox(width: Space.s2),
                          word,
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A page's main card: its figures on the soft blue that runs from
/// [AppColors.hero] to [AppColors.tile], with round corners; the same on every page.
class HeroCard extends StatelessWidget {
  const HeroCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(
      Space.s5,
      Space.s4,
      Space.s5,
      Space.s4,
    ),
    this.margin,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.largeIncreased),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.hero, AppColors.tile],
        ),
      ),
      child: child,
    );
  }
}
