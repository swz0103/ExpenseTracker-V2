import 'package:flutter/material.dart';

import '../controls.dart';
import '../glyphs.dart';
import '../haptics.dart';
import '../theme.dart';
import '../components.dart';
import '../shape.dart';
import '../spacing.dart';
import '../motion.dart';

// The square and round icons, the tick-in-a-circle switch, and small
// marks: a legend key, a pill of words, a ring for a share.

/// An icon in white on a rounded square of solid [color]: the mark of a
/// category, a setting or a tool. On the dark theme, the icon in [color]
/// on a deep tint of it, as an account's card has it, not a pale block.
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
        color: Shade.dark ? tintOf(color, 0.34) : color,
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      alignment: Alignment.center,
      child: GlyphIcon(
        glyph,
        size: size * 0.5,
        color: Shade.dark ? color : const Color(0xFFFFFFFF),
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
    this.color = AppColors.accent,
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
        onTap: change == null
            ? null
            : () {
                Haptics.selection();
                change(!value);
              },
        child: AnimatedContainer(
          duration: Motion.of(context, Motion.short3),
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            // On, solid on the light theme; on the dark one a deep tint
            // with the tick in [color], not a bright dot.
            color: value
                ? (Shade.dark ? tintOf(color, 0.6) : color)
                : tintOf(color, 0.3),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: GlyphIcon(
            Glyph.check,
            size: 16,
            weight: 2.2,
            tinted: false,
            color: value
                ? (Shade.dark ? color : const Color(0xFFFFFFFF))
                : Color.lerp(tintOf(color, 0.3), color, 0.35),
          ),
        ),
      ),
    );
  }
}

/// A row with a [TickSwitch] in it, all of which turns the switch: a tap
/// anywhere on it, at least 48 dp high, read out once as [label] and
/// whether it is on.
class ToggleRow extends StatelessWidget {
  const ToggleRow({
    super.key,
    required this.value,
    required this.onChanged,
    required this.label,
    required this.child,
    this.radius = 14,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final String label;
  final Widget child;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final change = onChanged;
    final VoidCallback? tap = change == null
        ? null
        : () {
            Haptics.selection();
            change(!value);
          };
    return ReadAsButton(
      toggled: value,
      label: label,
      onTap: tap,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(radius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: tap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// An icon on a soft circle of its own colour: the mark of a row in a
/// list or a menu ([SquareIcon] is for cards and blocks).
class RoundIcon extends StatelessWidget {
  const RoundIcon(
    this.icon,
    this.color, {
    super.key,
    this.size = 40,
    this.filled = false,
  }) : letter = null;

  /// A letter, such as a merchant's first, in place of an icon.
  const RoundIcon.letter(
    String this.letter,
    this.color, {
    super.key,
    this.size = 40,
  }) : icon = Glyph.store,
       filled = false;

  final Glyph icon;
  final String? letter;
  final Color color;
  final double size;

  /// Solid colour with a light icon, for the chosen option.
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: filled ? color : softOf(color),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: switch (letter) {
        // The row says the merchant already.
        final letter? => ExcludeSemantics(
          child: Text(
            letter,
            textScaler: TextScaler.noScaling,
            style: TextStyle(
              fontSize: size * 0.44,
              height: 1,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ),
        null => GlyphIcon(
          icon,
          size: size * 0.55,
          color: filled ? AppColors.onAccent : color,
        ),
      },
    );
  }
}

/// A legend mark, a dot or a short line, with its label.
class LegendKey extends StatelessWidget {
  const LegendKey(this.color, this.label, {super.key, this.line = false});

  final Color color;
  final String label;
  final bool line;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: line ? 12 : 8,
          height: line ? 2.5 : 8,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(Radii.extraSmall),
          ),
        ),
        const SizedBox(width: Space.s1),
        // Wraps under itself rather than running past a narrow line.
        Flexible(child: Text(label, style: mutedSmall)),
      ],
    );
  }
}

/// A small rounded label, such as 「結餘率 66%」.
class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.color = AppColors.accent});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.s2,
        vertical: Space.half,
      ),
      decoration: BoxDecoration(
        color: AppColors.glass,
        borderRadius: BorderRadius.circular(Radii.small),
      ),
      child: Text(
        text,
        maxLines: 1,
        softWrap: false,
        style: TextStyle(fontSize: TextSize.caption, color: color),
      ),
    );
  }
}

/// One segment for each of [days], the month's days: the [passed] ones
/// filled in [color], the last of them darker when it is [today], the
/// rest pale. 預算's main card and its card on 總覽.
class DayBar extends StatelessWidget {
  const DayBar({
    super.key,
    required this.passed,
    required this.days,
    required this.today,
    this.color = AppColors.accent,
    this.height = 14,
  });

  final int passed;
  final int days;
  final bool today;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SizedBox(
        height: height,
        child: Row(
          children: [
            for (var d = 1; d <= days; d++) ...[
              if (d > 1) const SizedBox(width: Space.half),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(Radii.extraSmall),
                    color: d > passed
                        ? AppColors.white
                        : today && d == passed
                        ? AppColors.ink
                        : color,
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
