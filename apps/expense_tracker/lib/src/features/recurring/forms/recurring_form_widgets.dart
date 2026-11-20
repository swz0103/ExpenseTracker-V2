import 'package:flutter/material.dart';

import '../../../core/ledger/ledger.dart';
import '../../../core/design_system/glyphs.dart';
import '../../../core/design_system/shape.dart';
import '../../../core/design_system/spacing.dart';
import '../../../core/design_system/theme.dart';
import '../../../core/design_system/design_system.dart';
import '../../../core/widgets/icons.dart';
import '../../../core/formatting/words.dart';

// The pieces of the recurring item's form, each told what to show and
// what a tap does; the form holds the state.

/// 支出 and 收入 on two big buttons, the side chosen in its colour.
class SideChoice extends StatelessWidget {
  const SideChoice({super.key, required this.income, required this.onChanged});

  final bool income;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final (i, side) in const [false, true].indexed) ...[
          if (i > 0) const SizedBox(width: Space.s2),
          Expanded(child: _button(side)),
        ],
      ],
    );
  }

  Widget _button(bool side) {
    final chosen = income == side;
    return Semantics(
      selected: chosen,
      child: Material(
        color: chosen
            ? (side ? AppColors.positive : AppColors.negative)
            : AppColors.surface,
        borderRadius: BorderRadius.circular(Radii.large),
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.large),
          onTap: () => onChanged(side),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 50),
            child: Center(
              child: Text(
                side ? Words.income : Words.expense,
                style: TextStyle(
                  fontSize: TextSize.title,
                  fontWeight: FontWeight.w800,
                  color: chosen ? AppColors.onAccent : AppColors.muted,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A white tile on the card with what a field holds, [label] above its
/// [value], that opens its choice.
class FormFieldTile extends StatelessWidget {
  const FormFieldTile({
    super.key,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.white,
      borderRadius: BorderRadius.circular(Radii.large),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.large),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            Space.s3,
            Space.s2,
            Space.s2,
            Space.s2,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: mutedTiny),
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: TextSize.body,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const GlyphIcon(Glyph.next, size: 14, color: AppColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}

/// The usual categories in a row, [chosen] marked, and the grid button
/// that opens them all.
class CategoryChoiceRow extends StatelessWidget {
  const CategoryChoiceRow({
    super.key,
    required this.choices,
    required this.chosen,
    required this.onChosen,
    required this.onAll,
  });

  final List<Category> choices;
  final String chosen;
  final ValueChanged<String> onChosen;
  final VoidCallback onAll;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final c in choices) ...[
          Expanded(
            child: CategoryChoice(
              category: c,
              chosen: c.name == chosen,
              onTap: () => onChosen(c.name),
            ),
          ),
          const SizedBox(width: Space.s2),
        ],
        Expanded(
          child: Semantics(
            button: true,
            label: '全部分類',
            child: InkWell(
              onTap: onAll,
              borderRadius: BorderRadius.circular(Radii.large),
              child: Column(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(Radii.large),
                    ),
                    alignment: Alignment.center,
                    child: const GlyphIcon(
                      Glyph.grid,
                      size: 22,
                      color: AppColors.muted,
                    ),
                  ),
                  const SizedBox(height: Space.s4),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// One usual category: its icon on a tint, solid with a tick when
/// [chosen], and its name under it.
class CategoryChoice extends StatelessWidget {
  const CategoryChoice({
    super.key,
    required this.category,
    required this.chosen,
    required this.onTap,
  });

  final Category category;
  final bool chosen;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = shownColor(Color(category.color));
    return ReadAsButton(
      selected: chosen,
      label: category.name,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.large),
        child: Column(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                chosen
                    ? SquareIcon(iconFor(category.icon), color, size: 48)
                    : Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: tintOf(color, 0.22),
                          borderRadius: BorderRadius.circular(Radii.large),
                        ),
                        alignment: Alignment.center,
                        child: GlyphIcon(
                          iconFor(category.icon),
                          size: 22,
                          color: color,
                        ),
                      ),
                if (chosen)
                  Positioned(
                    right: -4,
                    top: -4,
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: const BoxDecoration(
                        color: AppColors.white,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: GlyphIcon(Glyph.check, size: 11, color: color),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: Space.s1),
            Text(
              category.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: TextSize.caption,
                fontWeight: chosen ? FontWeight.w800 : FontWeight.w400,
                color: chosen ? deepOf(color) : AppColors.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The strip with what differs from the defaults, [notes], that opens
/// 其他設定.
class OtherSettingsStrip extends StatelessWidget {
  const OtherSettingsStrip({
    super.key,
    required this.notes,
    required this.onTap,
  });

  final List<String> notes;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ColorCard(
      color: AppColors.faint,
      amount: 0.18,
      radius: Radii.large,
      onTap: onTap,
      label: '其他設定',
      padding: const EdgeInsets.symmetric(
        horizontal: Space.s4,
        vertical: Space.s4,
      ),
      child: Row(
        children: [
          const GlyphIcon(Glyph.calendar, size: 18, color: AppColors.muted),
          const SizedBox(width: Space.s2),
          Expanded(
            child: Text(
              notes.join(' · '),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          const GlyphIcon(Glyph.next, size: 14, color: AppColors.muted),
        ],
      ),
    );
  }
}
