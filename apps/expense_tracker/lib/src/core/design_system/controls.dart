import 'package:flutter/material.dart';

import 'glyphs.dart';
import 'haptics.dart';
import 'components/colours.dart';
import 'components/one_line.dart';
import 'theme.dart';
import 'shape.dart';
import 'spacing.dart';
import 'motion.dart';

/// A row of choices in a tinted track, the chosen one on white.
class Segments extends StatelessWidget {
  const Segments({
    super.key,
    required this.labels,
    required this.selected,
    required this.onChanged,
    this.selectedColor = AppColors.accent,
  });

  final List<String> labels;
  final int selected;
  final ValueChanged<int> onChanged;
  final Color selectedColor;

  @override
  Widget build(BuildContext context) {
    // Each choice is a 48 dp target inside a thin track.
    return Container(
      padding: const EdgeInsets.all(Space.half),
      decoration: BoxDecoration(
        color: AppColors.tile,
        borderRadius: BorderRadius.circular(Radii.large),
      ),
      child: Row(
        children: [
          for (final (i, label) in labels.indexed)
            Expanded(
              child: Semantics(
                button: true,
                selected: i == selected,
                inMutuallyExclusiveGroup: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    if (i != selected) Haptics.selection();
                    onChanged(i);
                  },
                  child: AnimatedContainer(
                    duration: Motion.of(context, Motion.short4),
                    constraints: const BoxConstraints(minHeight: 48),
                    padding: const EdgeInsets.symmetric(vertical: Space.s2),
                    decoration: BoxDecoration(
                      color: i == selected ? AppColors.white : null,
                      borderRadius: BorderRadius.circular(Radii.medium),
                    ),
                    alignment: Alignment.center,
                    child: OneLine(
                      label,
                      alignment: Alignment.center,
                      style: TextStyle(
                        fontSize: TextSize.small,
                        fontWeight: i == selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: i == selected ? selectedColor : AppColors.accent,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Sinks a little under the finger and springs back, so a tap is felt as
/// well as seen.
class Pressable extends StatefulWidget {
  const Pressable({super.key, required this.child, this.depth = 0.97});

  final Widget child;

  /// How far it shrinks while held.
  final double depth;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  var _down = false;

  void _set(bool down) {
    if (mounted && _down != down) setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: _down ? widget.depth : 1,
        duration: Motion.of(context, _down ? Motion.short2 : Motion.short4),
        curve: _down ? Curves.easeOut : Curves.easeOutBack,
        child: widget.child,
      ),
    );
  }
}

/// [child], a card or a chip with words and figures in it, read out by a
/// screen reader as one button called [label], and pressed with [onTap]:
/// the words inside are left out, so they are not read twice. [onTap] is
/// asked for, the button's own: leaving the words out leaves out the tap
/// under them too, and a screen reader would find nothing to press
/// (`accessibility_test`). Null while it cannot be pressed.
class ReadAsButton extends StatelessWidget {
  const ReadAsButton({
    super.key,
    required this.label,
    required this.onTap,
    required this.child,
    this.selected,
    this.toggled,
    this.enabled,
    this.value,
  });

  final String label;
  final VoidCallback? onTap;
  final Widget child;
  final bool? selected;
  final bool? toggled;
  final bool? enabled;

  /// What it holds now, such as the amount, read after [label].
  final String? value;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    value: value,
    selected: selected,
    toggled: toggled,
    enabled: enabled,
    onTap: onTap,
    excludeSemantics: true,
    child: child,
  );
}

/// A small control with a 48 dp target around it: [child] keeps its look,
/// the finger and the screen reader get the larger area and a [label].
class TapArea extends StatelessWidget {
  const TapArea({
    super.key,
    required this.onTap,
    required this.child,
    this.label,
    this.selected,
  });

  final VoidCallback? onTap;
  final Widget child;

  /// What a screen reader says; the words inside when null.
  final String? label;
  final bool? selected;

  @override
  Widget build(BuildContext context) {
    final tap = onTap;
    final VoidCallback? press = tap == null
        ? null
        : () {
            Haptics.selection();
            tap();
          };
    // With a label, the words inside are not read again after it.
    return Semantics(
      button: true,
      enabled: tap != null,
      selected: selected,
      label: label,
      onTap: label == null ? null : press,
      excludeSemantics: label != null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: press,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          child: Center(widthFactor: 1, heightFactor: 1, child: child),
        ),
      ),
    );
  }
}

/// A rounded choice in a row of them, such as 買進 or 支出, filled with the
/// interface colour when chosen. Small to look at, a full 48 dp to tap.
///
/// A [removable] pill is a filter in force, such as a date range over the
/// records: it carries a cross, and a tap takes the filter away.
class ChoicePill extends StatelessWidget {
  const ChoicePill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.background = AppColors.tile,
  }) : removable = false;

  /// A filter in force, chosen-looking with a cross; [onRemove] takes it
  /// away.
  const ChoicePill.removable({
    super.key,
    required this.label,
    required VoidCallback onRemove,
  }) : selected = true,
       onTap = onRemove,
       removable = true,
       background = AppColors.tile;

  final String label;
  final bool selected;

  /// Null when the choice is shown but cannot be changed.
  final VoidCallback? onTap;

  /// Whether a tap takes this away rather than choosing it.
  final bool removable;

  /// The fill when not chosen: the tint on white, white on a tinted
  /// block.
  final Color background;

  @override
  Widget build(BuildContext context) {
    final words = OneLine(
      label,
      alignment: Alignment.center,
      style: TextStyle(
        fontSize: TextSize.small,
        fontWeight: FontWeight.w600,
        color: selected ? chosenInk(AppColors.accent) : AppColors.accent,
      ),
    );
    // Given a set width, as in a row of Expanded, it fills it; in a wrap
    // of pills it is as wide as its words.
    return LayoutBuilder(
      builder: (context, box) => _pill(words, box.hasTightWidth),
    );
  }

  Widget _pill(Widget words, bool fill) {
    return TapArea(
      selected: removable ? null : selected,
      label: removable ? '清除這個篩選' : null,
      onTap: onTap,
      child: Container(
        height: 36,
        width: fill ? double.infinity : null,
        constraints: const BoxConstraints(minWidth: 48),
        padding: const EdgeInsets.symmetric(horizontal: Space.s2),
        decoration: BoxDecoration(
          color: selected ? chosenFill(AppColors.accent) : background,
          borderRadius: BorderRadius.circular(Radii.large),
          border: selected && Shade.dark
              ? Border.all(color: AppColors.accent, width: 1.5)
              : null,
        ),
        // As wide as its words in a wrap of pills, centred when a row
        // makes it wider.
        child: Center(
          widthFactor: 1,
          child: removable
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    words,
                    const SizedBox(width: Space.s1),
                    const GlyphIcon(
                      Glyph.close,
                      size: 14,
                      color: AppColors.onAccent,
                    ),
                  ],
                )
              : words,
        ),
      ),
    );
  }
}

/// A few words in the interface colour that do something, such as 全部
/// or ＋ 再拆一個分類, with a 48 dp target around them.
class SmallLink extends StatelessWidget {
  const SmallLink(this.label, this.onTap, {super.key, this.inset = 10});

  final String label;
  final VoidCallback onTap;

  /// Room on each side of the words.
  final double inset;

  @override
  Widget build(BuildContext context) {
    return TapArea(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: inset),
        child: Text(label, style: accentSmall),
      ),
    );
  }
}
