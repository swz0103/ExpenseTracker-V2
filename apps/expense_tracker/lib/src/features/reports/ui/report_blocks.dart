part of 'reports.dart';

// The pieces the tabs are made of: the readout, the main card, the tinted blocks.

/// The chosen stretch, or the whole period, in one line.
class _Readout extends StatelessWidget {
  const _Readout({
    required this.ledger,
    required this.label,
    required this.income,
    required this.expense,
    this.worth,
  });

  final Ledger ledger;
  final String label;
  final int income;
  final int expense;

  /// Net worth at the stretch's end; none for one still ahead.
  final int? worth;

  @override
  Widget build(BuildContext context) {
    final left = income - expense;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Hue.tile,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: 12),
          // Wraps onto a second line rather than shrinking when the
          // phone's text is large.
          Expanded(
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: 12,
              runSpacing: 2,
              children: [
                _figure('收', income, Hue.positive),
                _figure('支', expense, Hue.negative),
                _figure('餘', left, left < 0 ? Hue.negative : Hue.ink),
                if (worth case final w?) _figure('淨資產', w, Hue.investment),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _figure(String label, int value, Color color) => Text.rich(
    TextSpan(
      children: [
        TextSpan(
          text: '$label ',
          style: const TextStyle(color: Hue.muted),
        ),
        TextSpan(
          text: ledger.money(value),
          style: TextStyle(fontWeight: FontWeight.w700, color: color),
        ),
      ],
    ),
    style: const TextStyle(fontSize: 13),
  );
}

/// The main card: 結餘 big on the left, 收入 with what of it was
/// dividends on the right, a bar of spending against what was kept, and
/// 支出 against last year beside how much of the income was kept.
class _Hero extends StatelessWidget {
  const _Hero({
    required this.ledger,
    required this.income,
    required this.expense,
    required this.dividends,
    required this.lastExpense,
    this.until,
  });

  final Ledger ledger;
  final int income;
  final int expense;
  final int dividends;
  final int lastExpense;

  /// The period runs past today: its sums are up to this day.
  final DateTime? until;

  @override
  Widget build(BuildContext context) {
    final kept = income - expense;
    final keptShare = income <= 0 ? 0 : (kept * 100 / income).round();
    final spentShare = income <= 0
        ? (expense > 0 ? 1.0 : 0.0)
        : (expense / income).clamp(0.0, 1.0);
    final change = lastExpense == 0
        ? null
        : (expense - lastExpense) * 100 ~/ lastExpense;
    final until = this.until;
    return HeroCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            until == null ? '結餘' : '結餘 · 至 ${until.month}/${until.day}',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: Hue.accent,
            ),
          ),
          // 收入 goes under 結餘 when both do not fit on a line.
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.end,
            spacing: 12,
            runSpacing: 2,
            children: [
              Text(
                ledger.orDots(groupDigits(kept)),
                style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.w800,
                  color: kept < 0 ? Hue.negative : Hue.ink,
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '收入 ${ledger.orDots(groupDigits(income))}',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: Hue.positive,
                    ),
                  ),
                  if (dividends > 0)
                    Text(
                      '含股息 ${ledger.orDots(groupDigits(dividends))}',
                      style: mutedSmall,
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: SizedBox(
              height: 10,
              child: Row(
                children: [
                  if (spentShare > 0)
                    Expanded(
                      flex: (spentShare * 1000).round().clamp(1, 1000),
                      child: const ColoredBox(
                        color: Hue.negative,
                        child: SizedBox.expand(),
                      ),
                    ),
                  if (spentShare > 0 && spentShare < 1)
                    const SizedBox(width: 3),
                  if (spentShare < 1)
                    Expanded(
                      flex: ((1 - spentShare) * 1000).round().clamp(1, 1000),
                      child: const ColoredBox(
                        color: Hue.positive,
                        child: SizedBox.expand(),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 12,
            runSpacing: 4,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const LegendKey(Hue.negative, '支出'),
                  const SizedBox(width: 6),
                  Text(
                    ledger.orDots(groupDigits(expense)),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  if (change != null) ...[
                    const SizedBox(width: 6),
                    Text(
                      '${change >= 0 ? '▲' : '▼'}${change.abs()}%',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: change >= 0 ? Hue.negative : Hue.positive,
                      ),
                    ),
                  ],
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const LegendKey(Hue.positive, '存下'),
                  const SizedBox(width: 6),
                  Text(
                    '$keptShare%',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A tinted block: a solid icon and a label over a figure and a line.
class _Block extends StatelessWidget {
  const _Block({
    required this.glyph,
    required this.color,
    required this.label,
    required this.value,
    required this.sub,
  });

  final Glyph glyph;
  final Color color;
  final String label;
  final String value;
  final String sub;

  @override
  Widget build(BuildContext context) {
    final ink = deepOf(color);
    return ColorCard(
      color: color,
      padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SquareIcon(glyph, color, size: 32),
              const SizedBox(width: 8),
              Expanded(
                child: OneLine(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: ink,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          OneLine(
            value,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          if (sub.isNotEmpty)
            OneLine(sub, style: TextStyle(fontSize: 12.5, color: ink)),
        ],
      ),
    );
  }
}

/// A category as a block of the mosaic: its icon, name and share, what
/// it came to, and against last year's same stretch.
class _CategoryBlock extends StatelessWidget {
  const _CategoryBlock({
    required this.ledger,
    required this.category,
    required this.amount,
    required this.share,
    required this.change,
    required this.large,
    required this.onTap,
  });

  final Ledger ledger;
  final Category category;
  final int amount;
  final int share;
  final int? change;
  final bool large;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = shownColor(category.color);
    final ink = deepOf(color);
    final change = this.change;
    return ColorCard(
      color: color,
      amount: 0.24,
      radius: 18,
      onTap: onTap,
      label: '${category.name} $share%',
      padding: const EdgeInsets.all(8),
      child: LayoutBuilder(
        builder: (context, box) {
          final roomy = box.maxHeight > 70 && box.maxWidth > 70;
          return Stack(
            children: [
              if (roomy)
                Positioned(
                  left: 0,
                  top: 0,
                  child: SquareIcon(
                    iconFor(category.icon),
                    color,
                    size: large ? 40 : 28,
                  ),
                ),
              if (change != null && box.maxWidth > 60)
                Positioned(
                  right: 0,
                  top: 0,
                  child: Text(
                    '${change >= 0 ? '▲' : '▼'} ${change.abs()}%',
                    textScaler: TextScaler.noScaling,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: change >= 0 ? Hue.negative : Hue.positive,
                    ),
                  ),
                ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.bottomLeft,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${category.name} · $share%',
                        style: TextStyle(
                          fontSize: large ? 15 : 12.5,
                          fontWeight: FontWeight.w800,
                          color: ink,
                        ),
                      ),
                      Text(
                        ledger.orDots(groupDigits(amount)),
                        style: TextStyle(
                          fontSize: large ? 26 : 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// A dashed rule across, for an average.
class _Dashes extends CustomPainter {
  _Dashes(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (var x = 0.0; x < size.width; x += 7) {
      canvas.drawLine(Offset(x, 0), Offset(x + 4, 0), paint);
    }
  }

  @override
  bool shouldRepaint(_Dashes old) => old.color != color;
}
