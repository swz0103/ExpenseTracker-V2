import 'package:flutter/material.dart';

import '../../../core/design_system/glyphs.dart';
import '../../../core/design_system/shape.dart';
import '../../../core/design_system/spacing.dart';
import '../../../core/design_system/theme.dart';
import '../../../core/design_system/design_system.dart';

// The pieces of a category's form, each told what to show and what a
// tap does; the form holds the state.

/// The colours offered in a row that scrolls, [chosen] ticked.
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
      // 56 apart, as on the account's colour panel.
      child: Row(
        children: [
          for (final (i, color) in colors.indexed) ...[
            if (i > 0) const SizedBox(width: Space.s2),
            _dot(color),
          ],
        ],
      ),
    );
  }

  Widget _dot(Color color) => SwatchButton(
    color: color,
    selected: color == chosen,
    onTap: () => onChosen(color),
  );
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
          const Expanded(
            child: Text(
              '放在哪個分類下',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: Space.s2),
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
