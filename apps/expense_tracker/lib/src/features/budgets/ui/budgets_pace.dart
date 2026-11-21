part of 'budgets.dart';

/// Two white cards: what can be spent a day and where the month is
/// heading; for a past month, what was spent a day and against the
/// budget.
class _Pace extends StatelessWidget {
  const _Pace({
    required this.ledger,
    required this.year,
    required this.month,
    required this.current,
    required this.spent,
    required this.total,
  });

  final Ledger ledger;
  final int year;
  final int month;
  final bool current;
  final int spent;
  final int total;

  @override
  Widget build(BuildContext context) {
    final (passed, days) = ledger.budgetService.daysGone(year, month);
    String money(int v) => ledger.orDots(groupDigits(v));
    if (!current) {
      final saved = total - spent;
      return CardGrid(gap: 10, [
        _Figure(
          glyph: Glyph.cash,
          color: AppColors.positive,
          label: '平均每天花',
          value: money(spent ~/ days),
          sub: '$month 月 $days 天',
        ),
        _Figure(
          glyph: Glyph.calendar,
          color: AppColors.accent,
          label: '跟預算比',
          value: '${saved >= 0 ? '省' : '超'} ${money(saved.abs())}',
          valueColor: saved >= 0 ? AppColors.accent : AppColors.negative,
          sub: '用了 ${spent * 100 ~/ total}%',
        ),
      ]);
    }
    final left = total - spent;
    final remaining = days - passed + 1;
    final heading = ledger.budgetService.forecast(spent, year, month);
    final over = heading > total;
    return CardGrid(gap: 10, [
      _Figure(
        glyph: Glyph.cash,
        color: AppColors.positive,
        label: '每天可以花',
        value: left > 0 ? money(left ~/ remaining) : '0',
        sub: '剩 $remaining 天',
      ),
      _Figure(
        glyph: Glyph.calendar,
        color: over ? AppColors.negative : AppColors.accent,
        label: '月底預估',
        value: passed >= 7 ? money(heading) : '—',
        valueColor: over && passed >= 7 ? AppColors.negative : null,
        sub: passed < 7
            ? '第 7 天起估算'
            : over
            ? '會超 ${money(heading - total)}'
            : '約剩 ${money(total - heading)}',
      ),
    ]);
  }
}

/// A white card with a solid icon, a label, a figure and a line.
class _Figure extends StatelessWidget {
  const _Figure({
    required this.glyph,
    required this.color,
    required this.label,
    required this.value,
    required this.sub,
    this.valueColor,
  });

  final Glyph glyph;
  final Color color;
  final String label;
  final String value;
  final String sub;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        Space.s2,
        Space.s2,
        Space.s2,
        Space.s2,
      ),
      decoration: BoxDecoration(
        color: AppColors.group,
        borderRadius: BorderRadius.circular(Radii.large),
      ),
      child: Row(
        children: [
          SquareIcon(glyph, color, size: 36),
          const SizedBox(width: Space.s2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                OneLine(
                  label,
                  style: const TextStyle(
                    fontSize: TextSize.small,
                    fontWeight: FontWeight.w700,
                    color: AppColors.muted,
                  ),
                ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: TextStyle(
                      fontSize: TextSize.heading,
                      fontWeight: FontWeight.w800,
                      color: valueColor ?? color,
                    ),
                  ),
                ),
                OneLine(sub, style: mutedSmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A category's or tag's allowance as a square: a small ring of the share
/// used around its icon, 超支 or 快用完, its name, what is left or over,
/// and used against the allowance.
class _Limit extends StatelessWidget {
  const _Limit({
    required this.ledger,
    required this.budget,
    required this.used,
    required this.limit,
    required this.onTap,
  });

  final Ledger ledger;
  final Budget budget;
  final int used;
  final int limit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tag = budget.tag != null;
    final category = tag ? null : ledger.category(budget.category);
    final shade = category?.color;
    final color = shownColor(shade == null ? AppColors.accent : Color(shade));
    final glyph = tag ? Glyph.tag : iconFor(category!.icon);
    final left = limit - used;
    final over = left < 0;
    final near = !over && limit > 0 && used * 100 >= limit * budget.warning;
    final tone = over ? AppColors.negative : (near ? _nearColor : color);
    final share = limit == 0 ? 0.0 : (used / limit).clamp(0.0, 1.0);
    final ink = deepOf(color);
    return ColorCard(
      color: over ? AppColors.negative : (near ? _nearColor : color),
      amount: 0.18,
      onTap: onTap,
      label: '${budget.category}，${over ? '超支' : '剩'} ${left.abs()}',
      padding: const EdgeInsets.fromLTRB(
        Space.s3,
        Space.s2,
        Space.s2,
        Space.s2,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _LimitHead(
            share: share,
            tone: tone,
            glyph: glyph,
            alert: over ? '超支' : (near ? '快用完' : null),
          ),
          const SizedBox(height: Space.s2),
          Text(
            budget.category,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: TextSize.body,
              fontWeight: FontWeight.w800,
              color: over ? deepOf(AppColors.negative) : ink,
            ),
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              '${over ? '超' : '剩'} ${ledger.orDots(groupDigits(left.abs()))}',
              style: TextStyle(
                fontSize: TextSize.heading,
                fontWeight: FontWeight.w800,
                color: over ? AppColors.negative : AppColors.ink,
              ),
            ),
          ),
          Text(
            '${ledger.orDots(groupDigits(used))} / '
            '${ledger.orDots(groupDigits(limit))}',
            style: mutedSmall,
          ),
        ],
      ),
    );
  }
}

/// The top of a [_Limit] square: the ring of [share] used around its
/// [glyph], and [alert] (超支 or 快用完) in the corner when there is one.
class _LimitHead extends StatelessWidget {
  const _LimitHead({
    required this.share,
    required this.tone,
    required this.glyph,
    required this.alert,
  });

  final double share;
  final Color tone;
  final Glyph glyph;
  final String? alert;

  @override
  Widget build(BuildContext context) {
    final alert = this.alert;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox.square(
          dimension: 38,
          child: Stack(
            fit: StackFit.expand,
            children: [
              CircularProgressIndicator(
                value: share,
                strokeWidth: 4,
                strokeCap: StrokeCap.round,
                color: tone,
                backgroundColor: tintOf(tone, 0.3),
              ),
              Center(child: GlyphIcon(glyph, size: 16, color: tone)),
            ],
          ),
        ),
        const Spacer(),
        if (alert != null)
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: Space.s2,
              vertical: Space.half,
            ),
            decoration: BoxDecoration(
              color: tone,
              borderRadius: BorderRadius.circular(Radii.small),
            ),
            child: Text(
              alert,
              textScaler: TextScaler.noScaling,
              style: const TextStyle(
                fontSize: TextSize.caption,
                fontWeight: FontWeight.w800,
                color: AppColors.onAccent,
              ),
            ),
          ),
      ],
    );
  }
}
