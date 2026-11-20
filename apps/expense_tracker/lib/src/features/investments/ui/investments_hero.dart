part of 'investments.dart';

/// 市值 big with today's move beside the label, and under a rule three
/// even columns, thin lines between: unrealized, realized, and the
/// yearly return, each a label, a figure and one short line.
class _InvestHero extends StatelessWidget {
  const _InvestHero({required this.ledger});

  final Ledger ledger;

  @override
  Widget build(BuildContext context) {
    final value = ledger.holdings.marketValue;
    final cost = ledger.holdings.costBasis;
    final gain = value - cost;
    final day = ledger.holdings.dayChange;
    final before = value - day;
    final rate = returnOf(ledger);
    final figures = [
      _HeroFigure(
        '未實現',
        ledger.orDots(signed(gain)),
        AppColors.ofChange(gain),
        percentOf(gain, cost),
      ),
      _HeroFigure(
        '已實現',
        ledger.orDots(signed(ledger.holdings.realizedGain)),
        AppColors.ofChange(ledger.holdings.realizedGain),
        '已賣出',
      ),
      _HeroFigure(
        '年化',
        rate == null ? '—' : yearlyRate(rate),
        rate == null || rate >= 0 ? AppColors.positive : AppColors.negative,
        rate == null ? '資料不足' : '含股息',
      ),
    ];
    return HeroCard(
      padding: const EdgeInsets.fromLTRB(
        Space.s4,
        Space.s4,
        Space.s4,
        Space.s4,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const SquareIcon(Glyph.pie, Palette.indigo, size: 30),
              const SizedBox(width: Space.s2),
              const Text('市值', style: accentLabel),
            ],
          ),
          const SizedBox(height: Space.s2),
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
              if (ledger.marketData.quotedOn != null)
                Pill(
                  '今日 ${ledger.orDots(signed(day))}'
                  '${before == 0 ? '' : ' · ${percentOf(day, before)}'}',
                  color: AppColors.ofChange(day),
                ),
            ],
          ),
          const Divider(height: 24, color: AppColors.accentRule),
          _HeroFigures(figures),
        ],
      ),
    );
  }
}

/// One of the hero's three figures: a label, the figure and one short line.
class _HeroFigure extends StatelessWidget {
  const _HeroFigure(this.label, this.figure, this.color, this.sub);

  final String label;
  final String figure;
  final Color color;
  final String sub;

  @override
  Widget build(BuildContext context) {
    const note = mutedCaption;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.s2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          OneLine(label, style: note),
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
          OneLine(sub, style: note),
        ],
      ),
    );
  }
}

/// The hero's figures as even columns with thin lines between; with the
/// phone's largest text one under another, each with the card's whole
/// width, rather than shrunk to fit a third.
class _HeroFigures extends StatelessWidget {
  const _HeroFigures(this.figures);

  final List<Widget> figures;

  @override
  Widget build(BuildContext context) {
    if (textGrowth(context) > 1.6) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, figure) in figures.indexed) ...[
            if (i > 0) const Divider(height: 16, color: AppColors.accentRule),
            figure,
          ],
        ],
      );
    }
    const rule = VerticalDivider(
      width: 1,
      thickness: 1,
      color: AppColors.accentRule,
    );
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, figure) in figures.indexed) ...[
            if (i > 0) rule,
            Expanded(child: figure),
          ],
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
    final quoted = ledger.holdings.hasQuote(held.code);
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
          const SizedBox(width: Space.s2),
          Container(
            width: 72,
            padding: const EdgeInsets.symmetric(vertical: Space.s2),
            decoration: BoxDecoration(
              color: !quoted
                  ? AppColors.surface
                  : chosenFill(up ? AppColors.positive : AppColors.negative),
              borderRadius: BorderRadius.circular(Radii.medium),
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
                        ? chosenInk(
                            up ? AppColors.positive : AppColors.negative,
                          )
                        : AppColors.muted,
                  ),
                ),
                if (quoted)
                  Text(
                    '${up ? '▲' : '▼'}${perShare.abs().toStringAsFixed(2)}',
                    textScaler: TextScaler.noScaling,
                    style: TextStyle(
                      fontSize: TextSize.tiny,
                      color: chosenInk(
                        up ? AppColors.positive : AppColors.negative,
                      ),
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
