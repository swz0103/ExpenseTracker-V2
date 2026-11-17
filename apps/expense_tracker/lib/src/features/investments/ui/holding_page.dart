import 'dart:math';

import 'package:flutter/material.dart';

import '../../../core/text/figures.dart';
import '../../../core/look/glyphs.dart';
import '../../../core/look/paint.dart';
import '../../../core/look/theme.dart';
import '../../../core/look/widgets.dart';
import '../../../core/ledger/ledger.dart';
import '../../../core/nav.dart';
import '../model/returns.dart';
import 'investments.dart' show yearlyRate;
import '../../../core/ui/shown_amounts.dart';

part 'holding_bento.dart';

/// One holding: its market value and profit, today's move and the
/// dividends it paid, the lots still held against what they are worth
/// now, and every trade of it.
class HoldingPage extends StatelessWidget {
  const HoldingPage({
    super.key,
    required this.ledger,
    required this.nav,
    required this.code,
  });

  final Ledger ledger;
  final Nav nav;
  final String code;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ledger,
      builder: (context, _) {
        final held = ledger.holding(code);
        final trades = ledger.tradesOf(code);
        if (held == null) {
          return HeadedList(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            header: CenterHeader(code, onBack: nav.back),
            children: [
              _SoldOut(ledger: ledger, trades: trades),
              _TradeBoard(
                ledger: ledger,
                nav: nav,
                trades: trades,
                lots: const [],
              ),
            ],
          );
        }
        final tone = held.gain < 0 ? Hue.negative : Hue.positive;
        final quoted = ledger.holdings.hasQuote(code);
        final lots = ledger.holdings.lotsOf(code);
        final average = held.shares == 0 ? 0 : held.cost / held.shares;
        return HeadedList(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          header: CenterHeader('${held.name} $code', onBack: nav.back),
          children: [
            _PriceCard(ledger: ledger, held: held, quoted: quoted),
            const SizedBox(height: 12),
            _PriceChart(
              ledger: ledger,
              nav: nav,
              code: code,
              average: average.toDouble(),
              buys: [
                for (final e in trades)
                  if (e.type == EntryType.buy && e.shares > 0) e,
              ],
            ),
            const SizedBox(height: 12),
            Builder(
              builder: (context) {
                final rate = returnOf(ledger, code: code);
                final next = expectedDividends(ledger)
                    .where((g) => g.code == code)
                    .firstOrNull;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    CardGrid(gap: 10, [
                      _Bento(
                        color: tone,
                        label: held.gain < 0 ? '賠了' : '賺了',
                        value: ledger.orDots(signed(held.gain)),
                        lines: [
                          '${percentOf(held.gain, held.cost)}'
                              '${rate == null ? '' : ' · 年化 ${yearlyRate(rate)}'}',
                        ],
                      ),
                      _Bento(
                        color: Hue.faint,
                        label: '現在值',
                        value: ledger.orDots(groupDigits(held.value)),
                        lines: [
                          '${ledger.orDots(groupDigits(held.shares))} 股 · '
                              '成本 ${ledger.orDots(groupDigits(held.cost))}',
                          if (quoted)
                            '今天 ${ledger.orDots(signed(held.change))}',
                        ],
                      ),
                    ]),
                    const SizedBox(height: 10),
                    _DividendCard(
                      ledger: ledger,
                      total: held.dividends,
                      next: next,
                      months: payingMonths(ledger, code),
                      realized: held.realized,
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                for (final (i, (type, label, color)) in const [
                  (EntryType.buy, '＋ 買進', _buyHue),
                  (EntryType.sell, '賣出', _sellHue),
                  (EntryType.dividend, '記股息', _dividendHue),
                ].indexed) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(
                    child: PanelButton(
                      label,
                      onTap: () => nav.compose(
                        type: type,
                        draft: Entry(
                          id: '',
                          date: ledger.today,
                          type: type,
                          amount: 0,
                          account: ledger.accounts.main,
                          category: '',
                          holding: code,
                        ),
                      ),
                      color: color,
                      tinted: true,
                    ),
                  ),
                ],
              ],
            ),
            _TradeBoard(ledger: ledger, nav: nav, trades: trades, lots: lots),
          ],
        );
      },
    );
  }
}

const _buyHue = Palette.indigo;
const _sellHue = Palette.brick;
const _dividendHue = Palette.gold;

/// 股息 on its gold tint: the total, when the next one is due and about
/// how much, and the twelve months with those it pays in filled.
class _DividendCard extends StatelessWidget {
  const _DividendCard({
    required this.ledger,
    required this.total,
    required this.next,
    required this.months,
    required this.realized,
  });

  final Ledger ledger;
  final int total;
  final DividendGuess? next;
  final List<int> months;
  final int realized;

  @override
  Widget build(BuildContext context) {
    final ink = deepOf(_dividendHue);
    final coming = next;
    return ColorCard(
      color: _dividendHue,
      amount: 0.22,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '股息',
                      style: TextStyle(
                        fontSize: TextSize.small,
                        fontWeight: FontWeight.w800,
                        color: ink,
                      ),
                    ),
                    Text(
                      ledger.orDots(groupDigits(total)),
                      style: const TextStyle(
                        fontSize: TextSize.large,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              if (coming != null)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '下次 ${coming.month.month} 月',
                      style: TextStyle(fontSize: TextSize.caption, color: ink),
                    ),
                    Text(
                      '約 ${ledger.orDots(groupDigits(coming.amount))}',
                      style: TextStyle(fontSize: TextSize.caption, color: ink),
                    ),
                  ],
                ),
            ],
          ),
          if (realized != 0)
            Text(
              '已實現 ${ledger.orDots(signed(realized))}',
              style: TextStyle(fontSize: TextSize.caption, color: ink),
            ),
          if (months.isNotEmpty) ...[
            const SizedBox(height: 10),
            Semantics(
              label: '配息月份 ${months.join('、')} 月',
              child: ExcludeSemantics(
                child: Row(
                  children: [
                    for (var m = 1; m <= 12; m++) ...[
                      if (m > 1) const SizedBox(width: 4),
                      Expanded(
                        child: Container(
                          height: 12,
                          decoration: BoxDecoration(
                            color: months.contains(m)
                                ? _dividendHue
                                : Hue.white.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 交易紀錄 on a white board: each buy, sale and dividend with its date,
/// shares and price, and what was held from the start, newest first.
class _TradeBoard extends StatelessWidget {
  const _TradeBoard({
    required this.ledger,
    required this.nav,
    required this.trades,
    required this.lots,
  });

  final Ledger ledger;
  final Nav nav;
  final List<Entry> trades;
  final List<Lot> lots;

  @override
  Widget build(BuildContext context) {
    final opening = [
      for (final l in lots)
        if (l.isOpening) l,
    ];
    final shown = [...trades]..sort((a, b) => b.date.compareTo(a.date));
    final count = shown.length + opening.length;
    if (count == 0) return const SizedBox.shrink();
    String day(DateTime d) => '${d.year}/${d.month}/${d.day}';
    final rows = <Widget>[
      for (final e in shown)
        _TradeRow(
          glyph: switch (e.type) {
            EntryType.sell => Glyph.payout,
            EntryType.dividend => Glyph.dividend,
            _ => Glyph.add,
          },
          color: switch (e.type) {
            EntryType.sell => _sellHue,
            EntryType.dividend => _dividendHue,
            _ => _buyHue,
          },
          title: switch (e.type) {
            EntryType.buy => '買進',
            EntryType.sell => '賣出',
            _ when e.isReduction => '減資',
            _ when e.shares > 0 => '配股',
            _ => '股息',
          },
          when: e.type == EntryType.dividend
              ? '${e.date.month}/${e.date.day}'
              : day(e.date),
          detail: e.shares != 0 && e.type != EntryType.dividend
              ? '${groupDigits(e.shares)} 股 × '
                    '${_price(e.amount / e.shares.abs())}'
              : e.shares != 0
              ? '${groupDigits(e.shares.abs())} 股'
              : null,
          amount: switch (e.type) {
            EntryType.buy => ledger.orDots(signed(-(e.amount + e.fee))),
            EntryType.sell => ledger.orDots(signed(e.amount - e.fee)),
            _ => ledger.orDots(signed(e.dividendNet)),
          },
          amountColor: e.type == EntryType.buy ? Hue.ink : Hue.positive,
          onTap: () => nav.showEntry(e),
        ),
      for (final l in opening)
        _TradeRow(
          glyph: Glyph.add,
          color: _buyHue,
          title: '期初持有',
          when: '',
          detail: '${ledger.orDots(groupDigits(l.shares))} 股',
          amount: '成本 ${ledger.orDots(groupDigits(l.cost))}',
          amountColor: Hue.ink,
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 20),
        TitleRow('交易紀錄', trailing: Text('共 $count 筆', style: mutedSmall)),
        QuoteBoard([
          for (final (i, row) in rows.indexed)
            Container(decoration: i == 0 ? null : ruleAbove, child: row),
        ]),
      ],
    );
  }

  static String _price(double p) =>
      p == p.roundToDouble() ? groupDigits(p.round()) : p.toStringAsFixed(2);
}

class _TradeRow extends StatelessWidget {
  const _TradeRow({
    required this.glyph,
    required this.color,
    required this.title,
    required this.when,
    required this.detail,
    required this.amount,
    required this.amountColor,
    this.onTap,
  });

  final Glyph glyph;
  final Color color;
  final String title;
  final String when;
  final String? detail;
  final String amount;
  final Color amountColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final line = detail;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: tintOf(color, 0.22),
                borderRadius: BorderRadius.circular(14),
              ),
              child: GlyphIcon(glyph, size: 20, color: deepOf(color)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    TextSpan(
                      text: title,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                      children: [
                        if (when.isNotEmpty)
                          TextSpan(
                            text: '  $when',
                            style: const TextStyle(
                              fontWeight: FontWeight.w400,
                              color: Hue.muted,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (line != null) OneLine(line, style: mutedSmall),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              amount,
              style: TextStyle(
                fontSize: TextSize.title,
                fontWeight: FontWeight.w800,
                color: amountColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A stock no longer held: 已賣光, what the sales brought in all and the
/// dividends it paid.
class _SoldOut extends StatelessWidget {
  const _SoldOut({required this.ledger, required this.trades});

  final Ledger ledger;
  final List<Entry> trades;

  @override
  Widget build(BuildContext context) {
    var sold = 0;
    var paid = 0;
    var dividends = 0;
    for (final e in trades) {
      switch (e.type) {
        case EntryType.sell:
          sold += e.amount - e.fee;
        case EntryType.buy:
          paid += e.amount + e.fee;
        case EntryType.dividend:
          dividends += e.dividendNet;
        default:
          break;
      }
    }
    final made = sold + dividends - paid;
    return HeroCard(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '已賣光',
            style: TextStyle(
              fontSize: TextSize.small,
              fontWeight: FontWeight.w800,
              color: Hue.accent,
            ),
          ),
          Text(
            ledger.orDots(signed(made)),
            style: TextStyle(
              fontSize: TextSize.big,
              fontWeight: FontWeight.w800,
              color: made < 0 ? Hue.negative : Hue.positive,
            ),
          ),
          Text(
            '賣出 ${ledger.orDots(groupDigits(sold))} · '
            '買進 ${ledger.orDots(groupDigits(paid))}'
            '${dividends == 0 ? '' : ' · 股息 ${ledger.orDots(groupDigits(dividends))}'}',
            style: mutedSmall,
          ),
        ],
      ),
    );
  }
}

/// The close in big figures with today's move on a solid block.
class _PriceCard extends StatelessWidget {
  const _PriceCard({
    required this.ledger,
    required this.held,
    required this.quoted,
  });

  final Ledger ledger;
  final Holding held;
  final bool quoted;

  @override
  Widget build(BuildContext context) {
    final up = held.change >= 0;
    final before = held.value - held.change;
    final perShare = held.shares == 0 ? 0.0 : held.change / held.shares;
    return HeroCard(
      padding: const EdgeInsets.fromLTRB(20, 14, 14, 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  held.price.toStringAsFixed(held.price < 100 ? 2 : 0),
                  style: const TextStyle(
                    fontSize: TextSize.big,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (!quoted)
                  Text('尚無收盤價，以成本估算', style: mutedSmall)
                else if (ledger.marketData.quotedOn case final d?)
                  Text('${d.month}/${d.day} 收盤', style: mutedSmall),
              ],
            ),
          ),
          if (quoted)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: chosenFill(up ? Hue.positive : Hue.negative),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                children: [
                  Text(
                    before == 0 ? '—' : percentOf(held.change, before),
                    style: TextStyle(
                      fontSize: TextSize.title,
                      fontWeight: FontWeight.w800,
                      color: chosenInk(up ? Hue.positive : Hue.negative),
                    ),
                  ),
                  Text(
                    '${up ? '▲' : '▼'} ${perShare.abs().toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: TextSize.caption,
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
