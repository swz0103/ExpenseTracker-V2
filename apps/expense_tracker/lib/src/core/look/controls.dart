import 'package:flutter/material.dart';

import 'glyphs.dart';
import 'haptics.dart';
import 'theme.dart';

/// A row of choices in a tinted track, the chosen one on white.
class Segments extends StatelessWidget {
  const Segments({
    super.key,
    required this.labels,
    required this.selected,
    required this.onChanged,
    this.selectedColor = Hue.accent,
  });

  final List<String> labels;
  final int selected;
  final ValueChanged<int> onChanged;
  final Color selectedColor;

  @override
  Widget build(BuildContext context) {
    // Each choice is a 48 dp target inside a thin track.
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: Hue.tile,
        borderRadius: BorderRadius.circular(14),
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
                    duration: const Duration(milliseconds: 180),
                    constraints: const BoxConstraints(minHeight: 48),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: i == selected ? Hue.white : null,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: i == selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: i == selected ? selectedColor : Hue.accent,
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
    if (_down != down) setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: _down ? widget.depth : 1,
        duration: Duration(milliseconds: _down ? 90 : 220),
        curve: _down ? Curves.easeOut : Curves.easeOutBack,
        child: widget.child,
      ),
    );
  }
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
    return Semantics(
      button: true,
      enabled: tap != null,
      selected: selected,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: tap == null
            ? null
            : () {
                Haptics.selection();
                tap();
              },
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
    this.background = Hue.tile,
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
       background = Hue.tile;

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
    final words = Text(
      label,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: selected ? Hue.onAccent : Hue.accent,
      ),
    );
    return TapArea(
      selected: removable ? null : selected,
      label: removable ? '移除篩選' : null,
      onTap: onTap,
      child: Container(
        height: 36,
        constraints: const BoxConstraints(minWidth: 48),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? Hue.accent : background,
          borderRadius: BorderRadius.circular(18),
        ),
        child: removable
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  words,
                  const SizedBox(width: 4),
                  const GlyphIcon(Glyph.close, size: 14, color: Hue.onAccent),
                ],
              )
            : words,
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
