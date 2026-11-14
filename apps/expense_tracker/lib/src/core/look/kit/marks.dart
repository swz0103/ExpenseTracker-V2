import 'package:flutter/material.dart';

import '../controls.dart';
import '../glyphs.dart';
import '../haptics.dart';
import '../theme.dart';
import '../kit.dart';

// A solid square icon and the tick-in-a-circle switch.

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
        onTap: change == null
            ? null
            : () {
                Haptics.selection();
                change(!value);
              },
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
    return Semantics(
      toggled: value,
      label: label,
      button: true,
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(radius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: change == null
              ? null
              : () {
                  Haptics.selection();
                  change(!value);
                },
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: child,
          ),
        ),
      ),
    );
  }
}
