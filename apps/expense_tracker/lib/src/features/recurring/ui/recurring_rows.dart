import 'package:flutter/material.dart';

import '../../../../design_system/display/amount.dart';
import '../../../../design_system/display/date.dart';
import '../../../core/design_system/glyphs.dart';
import '../../../core/widgets/icons.dart';
import '../../../core/design_system/theme.dart';
import '../../../core/design_system/design_system.dart';
import '../../../core/ledger/ledger.dart';
import '../../../core/widgets/entry_tile.dart';
import '../../../core/widgets/shown_amounts.dart';
import '../../../core/messages/recurring_messages.dart';
import '../../../core/design_system/shape.dart';
import '../../../core/design_system/spacing.dart';

/// An item's colour and mark: its category's.
(Glyph, Color) recurringMark(Ledger ledger, Recurring item) {
  final c = ledger.category(item.category);
  return (iconFor(c.icon), shownColor(Color(c.color)));
}

/// An item as one row in its colour: mark, name over how often and from
/// where, the amount over a small tag with the next date (or [lines] in
/// place of the second line, and [trailing] after it all).
class RecurringRow extends StatelessWidget {
  const RecurringRow({
    super.key,
    required this.ledger,
    required this.item,
    required this.onTap,
    this.grey = false,
    this.trailing,
    this.lines,
  });

  final Ledger ledger;
  final Recurring item;
  final VoidCallback onTap;
  final bool grey;
  final Widget? trailing;
  final List<String>? lines;

  @override
  Widget build(BuildContext context) {
    final (glyph, mark) = recurringMark(ledger, item);
    final color = grey ? AppColors.faint : mark;
    final next = grey || lines != null
        ? ''
        : switch (ledger.recurringService.nextDate(item)) {
            final d? => formatMd(d),
            null => '',
          };
    final sub =
        lines?.join(' · ') ??
        '${rhythmOf(item)} · ${ledger.account(item.account).name}';
    return ColorCard(
      color: color,
      amount: 0.16,
      radius: Radii.large,
      onTap: onTap,
      label: '${item.name}，$sub${next.isEmpty ? '' : '，下次 $next'}',
      padding: const EdgeInsets.fromLTRB(
        Space.s2,
        Space.s2,
        Space.s3,
        Space.s2,
      ),
      child: Row(
        children: [
          _mark(glyph, color),
          const SizedBox(width: Space.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: TextSize.body,
                    fontWeight: FontWeight.w800,
                    color: deepOf(color),
                  ),
                ),
                Text(
                  sub,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: mutedCaption,
                ),
              ],
            ),
          ),
          const SizedBox(width: Space.s2),
          _amountAndNext(color, next),
          if (trailing case final t?) ...[const SizedBox(width: Space.s2), t],
        ],
      ),
    );
  }

  /// The item's [glyph] in [color], or on white in grey when paused.
  Widget _mark(Glyph glyph, Color color) => grey
      ? Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(Radii.medium),
          ),
          alignment: Alignment.center,
          child: GlyphIcon(glyph, size: 20, color: AppColors.muted),
        )
      : SquareIcon(glyph, color, size: 40);

  /// The amount, over a tag in [color] with the [next] date when there is
  /// one.
  Widget _amountAndNext(Color color, String next) => Column(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      Text(
        '${item.income ? '+' : ''}'
        '${ledger.orDots(recurringAmount(ledger, item))}',
        semanticsLabel: ledger.spoken(
          item.amount,
          currency: ledger.account(item.account).currency,
          sense: item.income ? AmountSense.income : AmountSense.spending,
        ),
        style: TextStyle(
          fontSize: TextSize.title,
          fontWeight: FontWeight.w800,
          color: item.income && !grey ? AppColors.positive : AppColors.ink,
        ),
      ),
      if (next.isNotEmpty) ...[
        const SizedBox(height: Space.half),
        RecurringTag('下次 $next', color: color),
      ],
    ],
  );
}

/// A small rounded tag in [color]'s tint: the next date.
class RecurringTag extends StatelessWidget {
  const RecurringTag(this.text, {super.key, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: Space.s2,
      vertical: Space.half,
    ),
    decoration: BoxDecoration(
      color: tintOf(color, 0.22),
      borderRadius: BorderRadius.circular(Radii.small),
    ),
    child: Text(
      text,
      style: TextStyle(
        fontSize: TextSize.caption,
        fontWeight: FontWeight.w800,
        color: deepOf(color),
      ),
    ),
  );
}
