import 'package:flutter/material.dart';

import '../../../core/look/glyphs.dart';
import '../../../core/look/shape.dart';
import '../../../core/look/spacing.dart';
import '../../../core/look/theme.dart';
import '../../../core/look/widgets.dart';
import '../../../core/ui/icons.dart';

// The pieces of a category's form, each told what to show and what a
// tap does; the form holds the state.

/// One of the icons offered, solid in [color] when [picked].
class IconChoice extends StatelessWidget {
  const IconChoice({
    super.key,
    required this.icon,
    required this.color,
    required this.picked,
    required this.onTap,
  });

  /// The key of the icon, as [iconFor] reads it.
  final String icon;
  final Color color;
  final bool picked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.medium),
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: picked ? color : Hue.surface,
          borderRadius: BorderRadius.circular(Radii.medium),
        ),
        child: GlyphIcon(
          iconFor(icon),
          color: picked ? Hue.onSolid : Hue.muted,
          tinted: !picked,
        ),
      ),
    );
  }
}

/// The colours offered in a row that scrolls, [chosen] larger and ringed.
class ColorChoiceRow extends StatelessWidget {
  const ColorChoiceRow({
    super.key,
    required this.colors,
    required this.chosen,
    required this.onChosen,
  });

  final List<Color> colors;
  final Color chosen;
  final ValueChanged<Color> onChosen;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [for (final color in colors) _dot(color)]),
    );
  }

  Widget _dot(Color color) {
    final picked = color == chosen;
    return Semantics(
      button: true,
      selected: picked,
      label: '顏色',
      child: InkResponse(
        onTap: () => onChosen(color),
        radius: 24,
        child: Container(
          width: 48,
          height: 48,
          alignment: Alignment.center,
          child: Container(
            width: picked ? 34 : 28,
            height: picked ? 34 : 28,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: picked ? Border.all(color: Hue.white, width: 3) : null,
              boxShadow: picked
                  ? [BoxShadow(color: color, spreadRadius: 2)]
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}

/// A category under the one edited, or ＋子分類 when [add].
class SubcategoryTile extends StatelessWidget {
  const SubcategoryTile({
    super.key,
    required this.label,
    required this.glyph,
    required this.color,
    required this.onTap,
    this.add = false,
  });

  final String label;
  final Glyph glyph;
  final Color color;
  final VoidCallback onTap;
  final bool add;

  @override
  Widget build(BuildContext context) {
    return ColorCard(
      color: add ? Hue.faint : color,
      amount: add ? 0.25 : 0.2,
      radius: Radii.large,
      onTap: onTap,
      label: label,
      padding: const EdgeInsets.symmetric(
        vertical: Space.s2,
        horizontal: Space.half,
      ),
      child: Column(
        children: [
          add
              ? Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Hue.white,
                    borderRadius: BorderRadius.circular(Radii.medium),
                  ),
                  alignment: Alignment.center,
                  child: const GlyphIcon(Glyph.add, size: 18, color: Hue.ink),
                )
              : SquareIcon(glyph, color, size: 36),
          const SizedBox(height: Space.s2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: TextSize.small,
              fontWeight: FontWeight.w700,
              color: add ? Hue.ink : deepOf(color),
            ),
          ),
        ],
      ),
    );
  }
}

/// 放在哪個分類下 with the category it sits under, [parent], or 不放.
class ParentCategoryChoice extends StatelessWidget {
  const ParentCategoryChoice({
    super.key,
    required this.parent,
    required this.onTap,
  });

  final String? parent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ColorCard(
      color: Hue.faint,
      amount: 0.18,
      radius: Radii.large,
      onTap: onTap,
      padding: const EdgeInsets.symmetric(
        horizontal: Space.s4,
        vertical: Space.s4,
      ),
      child: Row(
        children: [
          const Text('放在哪個分類下', style: TextStyle(fontWeight: FontWeight.w700)),
          const Spacer(),
          Text(
            '${parent ?? '不放'} ›',
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: Hue.muted,
            ),
          ),
        ],
      ),
    );
  }
}
