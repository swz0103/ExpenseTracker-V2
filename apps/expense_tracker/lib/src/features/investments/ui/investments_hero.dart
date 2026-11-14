part of 'investments.dart';

/// 市值 big with today's move on a solid block, and under a rule what is
/// unrealized, realized, and the yearly return.
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: mutedSmall),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  figure,
                  style: TextStyle(
                    fontSize: TextSize.heading,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
              ),
              Text(
                sub,
                style: const TextStyle(
                  fontSize: TextSize.tiny,
                  color: Hue.muted,
                ),
              ),
            ],
          ),
        );
    return HeroCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '市值',
            style: TextStyle(
              fontSize: TextSize.small,
              fontWeight: FontWeight.w800,
              color: Hue.accent,
            ),
          ),
          // The chip goes under the figure when both do not fit on a line,
          // rather than shrinking the figure.
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
                ),
              ),
              if (ledger.quotedOn != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: chosenFill(day < 0 ? Hue.negative : Hue.positive),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '今日 ${ledger.orDots(signed(day))}'
                    '${before == 0 ? '' : ' · ${percentOf(day, before)}'}',
                    style: TextStyle(
                      fontSize: TextSize.small,
                      fontWeight: FontWeight.w800,
                      color: chosenInk(day < 0 ? Hue.negative : Hue.positive),
                    ),
                  ),
                ),
            ],
          ),
          const Divider(height: 22, color: Hue.accentRule),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              column(
                '未實現',
                ledger.orDots(signed(gain)),
                gain < 0 ? Hue.negative : Hue.positive,
                '${percentOf(gain, cost)} · 成本 ${ledger.orDots(groupDigits(cost))}',
              ),
              column(
                '已實現',
                ledger.orDots(signed(ledger.realized)),
                ledger.realized < 0 ? Hue.negative : Hue.positive,
                '已賣出',
              ),
              column(
                '年化報酬',
                rate == null ? '—' : yearlyRate(rate),
                rate == null || rate >= 0 ? Hue.positive : Hue.negative,
                rate == null ? '有期初持股' : '含股息',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A holding on the quote board: name, code and kind, shares and gain;
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
      title:
          '${held.name}  ${held.code} · ${held.code.startsWith('00') ? 'ETF' : '個股'}',
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
