part of 'budgets.dart';

/// Two white cards: what can be spent a day and where the month is
/// heading; for a past month, what was spent a day and against the
/// budget.
class _Pace extends StatelessWidget {
  const _Pace({
    required this.ledger,
    required this.year,
    required this.month,
    required this.spent,
    required this.total,
  });

  final Ledger ledger;
  final int year;
  final int month;
  final int spent;
  final int total;

  @override
  Widget build(BuildContext context) {
    String money(int v) => ledger.orDots(groupDigits(v));
    switch (ledger.budgetService.pace(spent, total, year, month)) {
      case PastPace(:final days, :final perDay, :final saved):
        return CardGrid(gap: 10, [
          _Figure(
            glyph: Glyph.cash,
            color: AppColors.positive,
            label: '平均每天花',
            value: money(perDay),
            sub: '$month 月 ${countOf(days, CountUnit.days)}',
          ),
          _Figure(
            glyph: Glyph.calendar,
            color: AppColors.accent,
            label: '跟預算比',
            value: '${saved >= 0 ? '省' : '超'} ${money(saved.abs())}',
            valueColor: saved >= 0 ? AppColors.accent : AppColors.negative,
            sub: '用了 ${wholePercent(spent, total)}',
          ),
        ]);
      case final CurrentPace pace:
        final heading = pace.forecast;
        final over = pace.overBudget;
        return CardGrid(gap: 10, [
          _Figure(
            glyph: Glyph.cash,
            color: AppColors.positive,
            label: '每天可以花',
            value: money(pace.perDay),
            sub: '剩 ${countOf(pace.daysLeft, CountUnit.days)}',
          ),
          _Figure(
            glyph: Glyph.calendar,
            color: over ? AppColors.negative : AppColors.accent,
            label: '月底預估',
            value: heading == null ? '—' : money(heading),
            valueColor: over ? AppColors.negative : null,
            sub: heading == null
                ? '第 ${BudgetService.forecastFrom} 天起估算'
                : over
                ? '會超 ${money(heading - total)}'
                : '約剩 ${money(total - heading)}',
          ),
        ]);
    }
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
    final status = budgetStatus(
      spent: used,
      limit: limit,
      warningPercent: budget.warning,
    );
    final look = budgetLook(status);
    final figure = budgetFigure(status);
    final share = limit == 0 ? 0.0 : (used / limit).clamp(0.0, 1.0);
    final ink = deepOf(color);
    // The badge is the one mark of 快用完 and 超支: the square keeps its
    // category's colour and the figure is written as it is.
    return ColorCard(
      color: color,
      amount: 0.18,
      onTap: onTap,
      label: '${budget.category}，${budgetLead(status)} $figure',
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
            tone: color,
            glyph: glyph,
            alert: status is BudgetWithin ? null : look,
          ),
          const SizedBox(height: Space.s2),
          Text(
            budget.category,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: TextSize.body,
              fontWeight: FontWeight.w800,
              color: ink,
            ),
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              status is BudgetOver
                  ? ledger.orDots(groupDigits(figure))
                  : '${StatusWords.left} ${ledger.orDots(groupDigits(figure))}',
              style: const TextStyle(
                fontSize: TextSize.heading,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
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
  final StatusLook? alert;

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
                semanticsLabel: ProgressWords.used,
                semanticsValue: ratioWholePercent(share),
                strokeWidth: 4,
                strokeCap: StrokeCap.round,
                color: markOf(tone),
                backgroundColor: tintOf(tone, 0.3),
              ),
              Center(child: GlyphIcon(glyph, size: 16, color: tone)),
            ],
          ),
        ),
        const Spacer(),
        if (alert != null) StatusBadge(alert),
      ],
    );
  }
}
