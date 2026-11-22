import 'package:flutter/material.dart';

import '../../../../design_system/display/amount.dart';
import '../../../core/design_system/theme.dart';
import '../../../core/design_system/design_system.dart';
import '../model/tag_summary.dart';
import '../../../core/formatting/dates.dart';
import '../../../core/design_system/shape.dart';
import '../../../core/design_system/spacing.dart';

// The blocks of a tag's summary card (TagSummaryCard, on 標籤與商家 and
// the tag's own page).

/// The top of a tag's summary card: 最近, the tag's days and its name on
/// the cover of 標籤與商家, beside the ⋯ menu on the tag's own page.
class TagSummaryHeading extends StatelessWidget {
  const TagSummaryHeading({
    super.key,
    required this.project,
    required this.recent,
    required this.menu,
  });

  final TagSummary project;

  /// The cover of 標籤與商家: 最近 and the tag's name.
  final bool recent;
  final Widget? menu;

  @override
  Widget build(BuildContext context) {
    final color = nameColor(project.tag);
    final ink = deepOf(color);
    String day(DateTime d) => formatMd(d);
    final days = project.from == project.to
        ? day(project.from)
        : '${day(project.from)} – ${day(project.to)} · ${project.days} 天';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (recent) _RecentBadge(color: color),
              Text(
                days,
                style: TextStyle(
                  fontSize: TextSize.body,
                  fontWeight: FontWeight.w700,
                  color: ink,
                ),
              ),
              if (recent)
                Padding(
                  padding: const EdgeInsets.only(top: Space.s1),
                  child: Text(
                    '#${project.tag}',
                    style: TextStyle(
                      fontSize: TextSize.large,
                      fontWeight: FontWeight.w800,
                      color: ink,
                    ),
                  ),
                ),
            ],
          ),
        ),
        ?menu,
      ],
    );
  }
}

/// 最近: a small solid label in the tag's colour, over the cover's days.
class _RecentBadge extends StatelessWidget {
  const _RecentBadge({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: Space.s2),
      padding: const EdgeInsets.symmetric(
        horizontal: Space.s2,
        vertical: Space.half,
      ),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(Radii.small),
      ),
      child: const Text(
        '最近',
        style: TextStyle(
          fontSize: TextSize.caption,
          fontWeight: FontWeight.w800,
          color: AppColors.onSolid,
        ),
      ),
    );
  }
}

/// What a tag was spent on: a thin bar of its categories, each as wide
/// as its share of [spent] in its colour, and under it the five largest,
/// each with a dot in its colour, its name and its share.
class TagCategoryShares extends StatelessWidget {
  const TagCategoryShares({
    super.key,
    required this.categories,
    required this.spent,
    required this.ink,
  });

  /// Each category's name, what was spent on it and its colour, largest
  /// first.
  final List<(String, int, Color)> categories;
  final int spent;

  /// The colour of the names, the tag's deep colour.
  final Color ink;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(Radii.extraSmall),
          child: SizedBox(
            height: 10,
            child: Row(
              children: [
                for (final (i, (_, amount, color)) in categories.indexed) ...[
                  if (i > 0) const SizedBox(width: Space.half),
                  Expanded(
                    flex: (amount * 1000 ~/ spent).clamp(1, 1000),
                    child: ColoredBox(
                      color: color,
                      child: const SizedBox.expand(),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: Space.s2),
        Wrap(
          spacing: 14,
          runSpacing: 4,
          children: [
            for (final (name, amount, color) in categories.take(5))
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: Space.s2),
                  Text(
                    '$name ${wholePercent(amount, spent)}',
                    style: TextStyle(
                      fontSize: TextSize.small,
                      fontWeight: FontWeight.w700,
                      color: ink,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }
}
