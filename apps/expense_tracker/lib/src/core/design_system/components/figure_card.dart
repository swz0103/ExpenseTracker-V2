import 'package:flutter/material.dart';

import '../controls.dart';
import '../glyphs.dart';
import '../haptics.dart';
import '../theme.dart';
import '../components.dart';
import '../shape.dart';
import '../spacing.dart';

// Cards that carry a figure, their row, the cells under a main figure,
// the grey group of rows, section and form titles, and small marks.

/// A small card with a figure, in the tint of [color]: its mark on a
/// solid square at the top left with [label] beside it, then the figure
/// ([value]) and a line ([sub]) under it; [lead] goes to its left and
/// [child] underneath. The 預算, 即將扣款 and 行情 cards of 總覽.
class FigureCard extends StatelessWidget {
  const FigureCard({
    super.key,
    required this.icon,
    required this.label,
    this.color = AppColors.accent,
    this.value,
    this.spokenValue,
    this.valueColor = AppColors.ink,
    this.size,
    this.sub,
    this.trailing,
    this.lead,
    this.child,
    this.onTap,
  });

  final Glyph icon;
  final String label;
  final Color color;
  final String? value;

  /// What a screen reader says for [value] when it is an amount with a
  /// sign: its direction in words.
  final String? spokenValue;
  final Color valueColor;

  /// The figure's size; [TextSize.heading] when null.
  final double? size;
  final String? sub;
  final Widget? trailing;
  final Widget? lead;
  final Widget? child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final figure = value;
    final note = sub;
    final side = lead;
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (figure != null)
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              figure,
              semanticsLabel: spokenValue,
              style: TextStyle(
                fontSize: size ?? TextSize.heading,
                fontWeight: FontWeight.w800,
                height: 1.2,
                color: valueColor,
              ),
            ),
          ),
        if (note != null) OneLine(note, style: mutedSmall),
      ],
    );
    return ColorCard(
      color: color,
      radius: Radii.largeIncreased,
      padding: const EdgeInsets.fromLTRB(
        Space.s4,
        Space.s3,
        Space.s4,
        Space.s3,
      ),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SquareIcon(icon, color, size: 30),
              const SizedBox(width: Space.s2),
              Expanded(
                child: OneLine(
                  label,
                  style: TextStyle(
                    fontSize: TextSize.small,
                    fontWeight: FontWeight.w700,
                    color: deepOf(color),
                  ),
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: Space.s2),
          if (side != null)
            // Beside the figure when there is room for both, over it on a
            // narrow phone or with large text, rather than the figure
            // shrinking to fit.
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [side, text],
            )
          else
            text,
          ?child,
        ],
      ),
    );
  }
}

/// A page's main figure on its [HeroCard]: the mark and [label] on top,
/// then the large figure with [trailing] (such as 比上月 or 結餘率) right
/// beside it, level with the number, and [child] (often [FigureCells])
/// underneath.
class HeroFigure extends StatelessWidget {
  const HeroFigure({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor = AppColors.ink,
    this.size,
    this.sub,
    this.beside,
    this.trailing,
    this.lead,
    this.child,
  });

  final Glyph icon;
  final String label;
  final String value;

  /// A line under the figure, such as when a statement is due.
  final String? sub;
  final Color valueColor;

  /// The figure's size; [TextSize.big] when null.
  final double? size;

  /// Right after the label, such as the eye that hides the amounts.
  final Widget? beside;

  /// Right after the figure, on its line.
  final Widget? trailing;

  /// To the left of the figure, such as an account's mark.
  final Widget? lead;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return HeroCard(
      padding: const EdgeInsets.fromLTRB(
        Space.s4,
        Space.s4,
        Space.s4,
        Space.s4,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SquareIcon(icon, AppColors.accent, size: 30),
              const SizedBox(width: Space.s2),
              Flexible(child: OneLine(label, style: accentLabel)),
              ?beside,
            ],
          ),
          const SizedBox(height: Space.s2),
          Wrap(
            spacing: 10,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ?lead,
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  style: TextStyle(
                    fontSize: size ?? TextSize.big,
                    fontWeight: FontWeight.w800,
                    height: 1.15,
                    color: valueColor,
                  ),
                ),
              ),
              ?trailing,
            ],
          ),
          if (sub case final note?) ...[
            const SizedBox(height: Space.half),
            OneLine(note, style: mutedSmall),
          ],
          ?child,
        ],
      ),
    );
  }
}

/// Two or three small figures side by side under a main figure, each on
/// a tinted cell of its own colour with its mark and label.
class FigureCells extends StatelessWidget {
  const FigureCells(this.items, {super.key});

  /// Mark, label, figure and its colour.
  final List<(Glyph, String, String, Color)> items;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: Space.s4),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (i, (icon, label, value, color)) in items.indexed) ...[
              if (i > 0) const SizedBox(width: Space.s2),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.fromLTRB(
                    Space.s2,
                    Space.s2,
                    Space.s2,
                    Space.s2,
                  ),
                  decoration: BoxDecoration(
                    color: tintOf(color, 0.16),
                    borderRadius: BorderRadius.circular(Radii.large),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          GlyphIcon(icon, size: 14, color: deepOf(color)),
                          const SizedBox(width: Space.s1),
                          Expanded(child: OneLine(label, style: mutedCaption)),
                        ],
                      ),
                      const SizedBox(height: Space.half),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          value,
                          style: TextStyle(
                            fontSize: TextSize.body,
                            fontWeight: FontWeight.w800,
                            color: deepOf(color),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Cards side by side, as tall as the tallest.
class CardRow extends StatelessWidget {
  const CardRow(this.cards, {super.key});

  final List<Widget> cards;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: Space.s2),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (i, card) in cards.indexed) ...[
              if (i > 0) const SizedBox(width: Space.s2),
              Expanded(child: card),
            ],
          ],
        ),
      ),
    );
  }
}

/// Rows grouped on a flat light grey, no shadow: a day of entries, a
/// list of accounts or of a statement's charges.
///
/// A long list can draw its box a row at a time, each row a slice of it
/// ([top] and [bottom] say whether a slice is the first or the last), so
/// only the rows on screen are built.
class GroupBox extends StatelessWidget {
  const GroupBox({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(Space.s4),
    this.onTap,
    this.top = true,
    this.bottom = true,
  });

  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;

  /// Whether this is the box's top, with its round corners; false for a
  /// slice under another.
  final bool top;

  /// Whether this is the box's bottom, with its round corners; false for
  /// a slice with another under it.
  final bool bottom;

  @override
  Widget build(BuildContext context) {
    const round = Radius.circular(Radii.large);
    final radius = BorderRadius.vertical(
      top: top ? round : Radius.zero,
      bottom: bottom ? round : Radius.zero,
    );
    final tap = onTap;
    final group = Material(
      color: AppColors.group,
      borderRadius: radius,
      clipBehavior: top || bottom ? Clip.antiAlias : Clip.hardEdge,
      child: tap == null
          ? Padding(padding: padding, child: child)
          : InkWell(
              borderRadius: radius,
              onTap: () {
                Haptics.selection();
                tap();
              },
              child: Padding(padding: padding, child: child),
            ),
    );
    return tap == null ? group : Pressable(depth: 0.985, child: group);
  }
}

/// A section's title: bold on the left, and [trailing] (a few words or
/// ›) on the right; no rule, the space above sets it apart.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: Space.s6, bottom: Space.s2),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: OneLine(
                title,
                style: const TextStyle(
                  fontSize: TextSize.title,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// A group of a form: a small title over [child], whose choices sit on
/// a flat light grey of their own, so 類型, 圖示 and 幣別 read as three
/// separate groups.
class FormGroup extends StatelessWidget {
  const FormGroup({super.key, this.title, required this.child});

  final String? title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final head = title;
    return Padding(
      padding: const EdgeInsets.only(top: Space.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (head != null)
            Padding(
              padding: const EdgeInsets.only(left: Space.s1, bottom: Space.s2),
              child: OneLine(
                head,
                style: const TextStyle(
                  fontSize: TextSize.small,
                  fontWeight: FontWeight.w800,
                  color: AppColors.muted,
                ),
              ),
            ),
          DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.group,
              borderRadius: BorderRadius.circular(Radii.large),
            ),
            child: Padding(
              padding: const EdgeInsets.all(Space.s2),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}
