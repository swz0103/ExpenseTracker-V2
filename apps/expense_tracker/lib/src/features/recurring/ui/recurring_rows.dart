import 'package:flutter/material.dart';

import '../../../core/look/glyphs.dart';
import '../../../core/ui/icons.dart';
import '../../../core/look/theme.dart';
import '../../../core/look/widgets.dart';
import '../../../core/ledger/ledger.dart';
import '../../../core/ui/entry_tile.dart';
import '../../../core/ui/shown_amounts.dart';
import '../../../core/messages/recurring_messages.dart';
import '../../../core/look/shape.dart';
import '../../../core/look/spacing.dart';

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
    final color = grey ? Hue.faint : mark;
    final next = grey || lines != null
        ? ''
        : ledger.recurringService.nextLabel(item);
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
          grey
              ? Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Hue.white,
                    borderRadius: BorderRadius.circular(Radii.medium),
                  ),
                  alignment: Alignment.center,
                  child: GlyphIcon(glyph, size: 20, color: Hue.muted),
                )
              : SquareIcon(glyph, color, size: 40),
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
                  style: const TextStyle(
                    fontSize: TextSize.caption,
                    color: Hue.muted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: Space.s2),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${item.income ? '+' : ''}'
                '${ledger.orDots(recurringAmount(ledger, item))}',
                style: TextStyle(
                  fontSize: TextSize.title,
                  fontWeight: FontWeight.w800,
                  color: item.income && !grey ? Hue.positive : Hue.ink,
                ),
              ),
              if (next.isNotEmpty) ...[
                const SizedBox(height: Space.half),
                RecurringTag('下次 $next', color: color),
              ],
            ],
          ),
          if (trailing case final t?) ...[const SizedBox(width: Space.s2), t],
        ],
      ),
    );
  }
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
