import 'package:flutter/material.dart';

import '../controls.dart';
import '../glyphs.dart';
import '../haptics.dart';
import '../theme.dart';
import '../kit.dart';

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
    final ink = chosen ? wordsOn(color) : deepOf(color);
    final icon = GlyphIcon(glyph, size: stacked ? 24 : 20, color: ink);
    final word = Text(
      label,
      style: TextStyle(
        fontSize: stacked ? 14 : 17,
        fontWeight: FontWeight.w800,
        color: ink,
      ),
    );
    return Semantics(
      selected: chosen,
      button: true,
      label: label,
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          boxShadow: chosen ? Hue.tileShadow : null,
        ),
        child: Material(
          color: chosen ? color : tintOf(color, 0.2),
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 52),
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: stacked ? 12 : 8),
                child: stacked
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [icon, const SizedBox(height: 4), word],
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [icon, const SizedBox(width: 8), word],
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
/// [Hue.hero] to [Hue.tile], with round corners; the same on every page.
class HeroCard extends StatelessWidget {
  const HeroCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(20, 16, 20, 16),
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
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Hue.hero, Hue.tile],
        ),
      ),
      child: child,
    );
  }
}
