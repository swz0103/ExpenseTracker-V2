part of 'investments.dart';

/// 市值 big with today's move beside the label, and under a rule three
/// even columns, thin lines between: unrealized, realized, and the
/// yearly return, each a label, a figure and one short line.
class _InvestHero extends StatelessWidget {
  const _InvestHero({required this.ledger});

  final Ledger ledger;

  @override
  Widget build(BuildContext context) {
    final value = ledger.investValue;
    final cost = ledger.investCost;
    final gain = value - cost;
    final day = ledger.dayChange;
    final before = value - day;
    final rate = returnOf(ledger);
    Widget column(String label, String figure, Color color, String sub) =>
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                OneLine(
                  label,
                  style: const TextStyle(
                    fontSize: TextSize.caption,
                    color: Hue.muted,
                  ),
                ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    figure,
                    style: TextStyle(
                      fontSize: TextSize.title,
                      fontWeight: FontWeight.w800,
                      color: color,
                    ),
                  ),
                ),
                OneLine(
                  sub,
                  style: const TextStyle(
                    fontSize: TextSize.caption,
                    color: Hue.muted,
                  ),
                ),
              ],
            ),
          ),
        );
    const rule = VerticalDivider(width: 1, thickness: 1, color: Hue.accentRule);
    return HeroCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const SquareIcon(Glyph.pie, Palette.indigo, size: 30),
              const SizedBox(width: 8),
              const Text('市值', style: accentLabel),
            ],
          ),
          const SizedBox(height: 8),
          // Today's move beside the figure, or under it when both do not
          // fit on a line, rather than either shrinking.
          Wrap(
            spacing: 10,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                ledger.orDots(groupDigits(value)),
                style: const TextStyle(
                  fontSize: TextSize.big,
                  fontWeight: FontWeight.w800,
                  height: 1.15,
                ),
              ),
              if (ledger.quotedOn != null)
                Pill(
                  '今日 ${ledger.orDots(signed(day))}'
                  '${before == 0 ? '' : ' · ${percentOf(day, before)}'}',
                  color: day < 0 ? Hue.negative : Hue.positive,
                ),
            ],
          ),
          const Divider(height: 24, color: Hue.accentRule),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                column(
                  '未實現',
                  ledger.orDots(signed(gain)),
                  gain < 0 ? Hue.negative : Hue.positive,
                  percentOf(gain, cost),
                ),
                rule,
                column(
                  '已實現',
                  ledger.orDots(signed(ledger.realized)),
                  ledger.realized < 0 ? Hue.negative : Hue.positive,
                  '已賣出',
                ),
                rule,
                column(
                  '年化',
                  rate == null ? '—' : yearlyRate(rate),
                  rate == null || rate >= 0 ? Hue.positive : Hue.negative,
                  rate == null ? '資料不足' : '含股息',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A holding on the quote board: its code, shares and gain;
/// the close big and today's move on a solid block.
class _HoldingRow extends StatelessWidget {
  const _HoldingRow({
    required this.ledger,
    required this.held,
    required this.onTap,
  });

  final Ledger ledger;
  final Holding held;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final quoted = ledger.hasQuote(held.code);
    final before = held.value - held.change;
    final up = held.change >= 0;
    final perShare = held.shares == 0 ? 0.0 : held.change / held.shares;
    return QuoteRow(
      onTap: onTap,
      // The code alone: the group above says 個股 or ETF, and the
      // holding's page has its name.
      title: held.code,
      detail:
          '${ledger.orDots(groupDigits(held.shares))} 股 · 損益 '
          '${ledger.orDots(signed(held.gain))}',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          RowFigure(held.price.toStringAsFixed(held.price < 100 ? 2 : 0)),
          const SizedBox(width: 10),
          Container(
            width: 72,
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: !quoted
                  ? Hue.surface
                  : chosenFill(up ? Hue.positive : Hue.negative),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Text(
                  !quoted || before == 0 ? '—' : percentOf(held.change, before),
                  textScaler: TextScaler.noScaling,
                  style: TextStyle(
                    fontSize: TextSize.small,
                    fontWeight: FontWeight.w800,
                    color: quoted
                        ? chosenInk(up ? Hue.positive : Hue.negative)
                        : Hue.muted,
                  ),
                ),
                if (quoted)
                  Text(
                    '${up ? '▲' : '▼'}${perShare.abs().toStringAsFixed(2)}',
                    textScaler: TextScaler.noScaling,
                    style: TextStyle(
                      fontSize: TextSize.tiny,
                      color: chosenInk(up ? Hue.positive : Hue.negative),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
