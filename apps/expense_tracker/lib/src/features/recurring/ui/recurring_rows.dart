part of 'recurring_page.dart';

/// An item as one row in its colour: mark, name over how often and from
/// where, the amount over a small tag with the next date (or [lines] in
/// place of the second line, and [trailing] after it all).
class _ItemRow extends StatelessWidget {
  const _ItemRow({
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
    final (glyph, mark) = _mark(ledger, item);
    final color = grey ? Hue.faint : mark;
    final next = grey || lines != null ? '' : ledger.nextLabel(item);
    final sub =
        lines?.join(' · ') ??
        '${item.rhythm} · ${ledger.account(item.account).name}';
    return ColorCard(
      color: color,
      amount: 0.16,
      radius: 18,
      onTap: onTap,
      label: '${item.name}，$sub${next.isEmpty ? '' : '，下次 $next'}',
      padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
      child: Row(
        children: [
          grey
              ? Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Hue.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: GlyphIcon(glyph, size: 20, color: Hue.muted),
                )
              : SquareIcon(glyph, color, size: 40),
          const SizedBox(width: 12),
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
          const SizedBox(width: 8),
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
                const SizedBox(height: 2),
                _Tag('下次 $next', color: color),
              ],
            ],
          ),
          if (trailing case final t?) ...[const SizedBox(width: 10), t],
        ],
      ),
    );
  }
}
