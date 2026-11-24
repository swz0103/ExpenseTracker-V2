import 'dart:math';

import 'package:domain/investments.dart' show HoldingStatus, holdingStatus;
import 'package:flutter/material.dart';

import '../../../../design_system/display/amount.dart';
import '../../../../design_system/display/status.dart';
import '../../../../design_system/display/amount_text.dart' show AmountText;
import '../../../core/design_system/glyphs.dart';
import '../../../core/design_system/paint.dart';
import '../../../core/design_system/theme.dart';
import '../../../core/design_system/design_system.dart';
import '../../../core/ledger/ledger.dart';
import '../../../core/navigation/nav.dart';
import '../model/returns.dart';
import 'investments.dart' show returnsOf, yearlyRate;
import '../../../core/widgets/shown_amounts.dart';
import '../../../../design_system/display/date.dart';
import '../../../core/design_system/shape.dart';
import '../../../core/design_system/spacing.dart';
import '../../../core/formatting/words.dart';

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
        final trades = ledger.entryQueryService.tradesOf(code);
        if (held == null ||
            holdingStatus(held.shares) == HoldingStatus.soldOut) {
          return HeadedList(
            padding: const EdgeInsets.fromLTRB(Space.s5, 0, Space.s5, Space.s4),
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
        final quoted = ledger.holdings.hasQuote(code);
        final lots = ledger.holdings.lotsOf(code);
        final average = held.shares == 0 ? 0 : held.cost / held.shares;
        return HeadedList(
          padding: const EdgeInsets.fromLTRB(Space.s5, 0, Space.s5, Space.s4),
          header: CenterHeader('${held.name} $code', onBack: nav.back),
          children: [
            _PriceCard(ledger: ledger, held: held, quoted: quoted),
            const SizedBox(height: Space.s3),
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
            const SizedBox(height: Space.s3),
            Builder(builder: (context) => _bento(ledger, code, held, quoted)),
            const SizedBox(height: Space.s3),
            _tradeButtons(),
            _TradeBoard(ledger: ledger, nav: nav, trades: trades, lots: lots),
          ],
        );
      },
    );
  }

  /// ＋ 買進, 賣出 and 記股息, each opening a new entry of this stock.
  Widget _tradeButtons() => Row(
    children: [
      for (final (i, (type, label, color)) in const [
        (EntryType.buy, '＋ 買進', _buyColor),
        (EntryType.sell, '賣出', _sellColor),
        (EntryType.dividend, '記股息', _dividendColor),
      ].indexed) ...[
        if (i > 0) const SizedBox(width: Space.s2),
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
  );
}

const _buyColor = Palette.indigo;
const _sellColor = Palette.brick;
const _dividendColor = Palette.gold;

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
    final ink = deepOf(_dividendColor);
    return ColorCard(
      color: _dividendColor,
      amount: 0.22,
      padding: const EdgeInsets.fromLTRB(
        Space.s4,
        Space.s3,
        Space.s4,
        Space.s4,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _totalAndNext(ink),
          if (realized != 0)
            AmountText.within(
              '已實現 ${ledger.orDots(signed(realized))}',
              realized,
              hidden: ledger.amounts.hidden,
              style: TextStyle(fontSize: TextSize.caption, color: ink),
            ),
          if (months.isNotEmpty) ...[
            const SizedBox(height: Space.s2),
            _payingMonths(),
          ],
        ],
      ),
    );
  }

  /// The dividends paid in all, and when the next is due and about how
  /// much, in [ink].
  Widget _totalAndNext(Color ink) {
    final coming = next;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                Words.dividend,
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
    );
  }

  /// The twelve months, those it pays in filled.
  Widget _payingMonths() => Semantics(
    label: '配息月份 ${months.join('、')} 月',
    child: ExcludeSemantics(
      child: Row(
        children: [
          for (var m = 1; m <= 12; m++) ...[
            if (m > 1) const SizedBox(width: Space.s1),
            Expanded(
              child: Container(
                height: 12,
                decoration: BoxDecoration(
                  color: months.contains(m)
                      ? _dividendColor
                      : AppColors.white.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(Radii.extraSmall),
                ),
              ),
            ),
          ],
        ],
      ),
    ),
  );
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
    final shown = [...trades]..sort(newestFirst(ledger.entries));
    final count = shown.length + opening.length;
    if (count == 0) return const SizedBox.shrink();
    String day(DateTime d) => formatYMd(d);
    final rows = <Widget>[
      for (final e in shown)
        _TradeRow(
          glyph: switch (e.type) {
            EntryType.sell => Glyph.payout,
            EntryType.dividend => Glyph.dividend,
            _ => Glyph.add,
          },
          color: switch (e.type) {
            EntryType.sell => _sellColor,
            EntryType.dividend => _dividendColor,
            _ => _buyColor,
          },
          title: switch (e.type) {
            EntryType.buy => '買進',
            EntryType.sell => '賣出',
            _ when e.isReduction => '減資',
            _ when e.shares > 0 => '配股',
            _ => Words.dividend,
          },
          when: e.type == EntryType.dividend ? formatMd(e.date) : day(e.date),
          detail: e.shares != 0 && e.type != EntryType.dividend
              ? '${groupDigits(e.shares)} 股 × '
                    '${_price(e.amount / e.shares.abs())}'
              : e.shares != 0
              ? '${groupDigits(e.shares.abs())} 股'
              : null,
          // What reached or left the account, as the balances count it.
          amount: ledger.orDots(signed(e.settlement)),
          spoken: ledger.spoken(e.settlement),
          amountColor: e.type == EntryType.buy
              ? AppColors.ink
              : AppColors.positive,
          onTap: () => nav.showEntry(e),
        ),
      for (final l in opening)
        _TradeRow(
          glyph: Glyph.add,
          color: _buyColor,
          title: '期初持有',
          when: '',
          detail: '${ledger.orDots(groupDigits(l.shares))} 股',
          amount: '成本 ${ledger.orDots(groupDigits(l.cost))}',
          amountColor: AppColors.ink,
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: Space.s5),
        TitleRow(
          '交易紀錄',
          trailing: Text(
            '共 ${countOf(count, CountUnit.entries)}',
            style: mutedSmall,
          ),
        ),
        QuoteBoard([
          for (final (i, row) in rows.indexed)
            Container(decoration: i == 0 ? null : ruleAbove, child: row),
        ]),
      ],
    );
  }

  static String _price(double p) => stockPrice(p);
}

class _TradeRow extends StatelessWidget {
  const _TradeRow({
    required this.glyph,
    required this.color,
    required this.title,
    required this.when,
    required this.detail,
    required this.amount,
    this.spoken,
    required this.amountColor,
    this.onTap,
  });

  final Glyph glyph;
  final Color color;
  final String title;
  final String when;
  final String? detail;
  final String amount;

  /// What a screen reader says for [amount]: its direction in words.
  final String? spoken;
  final Color amountColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final line = detail;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.s4,
          vertical: Space.s3,
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: tintOf(color, 0.22),
                borderRadius: BorderRadius.circular(Radii.large),
              ),
              child: GlyphIcon(glyph, size: 20, color: deepOf(color)),
            ),
            const SizedBox(width: Space.s3),
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
                              color: AppColors.muted,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (line != null) OneLine(line, style: mutedSmall),
                ],
              ),
            ),
            const SizedBox(width: Space.s2),
            Text(
              amount,
              semanticsLabel: spoken,
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
          sold += e.settlement;
        case EntryType.buy:
          paid -= e.settlement;
        case EntryType.dividend:
          dividends += e.dividendNet;
        default:
          break;
      }
    }
    final made = sold + dividends - paid;
    return HeroCard(
      margin: const EdgeInsets.only(bottom: Space.s3),
      padding: const EdgeInsets.fromLTRB(
        Space.s5,
        Space.s4,
        Space.s5,
        Space.s4,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            holdingLook(HoldingStatus.soldOut).words,
            style: const TextStyle(
              fontSize: TextSize.small,
              fontWeight: FontWeight.w800,
              color: AppColors.accent,
            ),
          ),
          Text(
            ledger.orDots(signed(made)),
            semanticsLabel: ledger.spoken(made),
            style: TextStyle(
              fontSize: TextSize.big,
              fontWeight: FontWeight.w800,
              color: AppColors.ofMarket(made),
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
    final tone = up ? AppColors.rise : AppColors.fall;
    final before = held.value - held.change;
    final perShare = held.shares == 0 ? 0.0 : held.change / held.shares;
    return HeroCard(
      padding: const EdgeInsets.fromLTRB(
        Space.s5,
        Space.s4,
        Space.s4,
        Space.s4,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  stockPrice(held.price),
                  style: const TextStyle(
                    fontSize: TextSize.big,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (!quoted)
                  Text('尚無收盤價，以成本估算', style: mutedSmall)
                else if (ledger.marketData.quotedOn case final d?)
                  Text('${formatMd(d)} 收盤', style: mutedSmall),
              ],
            ),
          ),
          if (quoted)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: Space.s3,
                vertical: Space.s2,
              ),
              decoration: BoxDecoration(
                color: chosenFill(tone),
                borderRadius: BorderRadius.circular(Radii.large),
              ),
              child: Column(
                children: [
                  Text(
                    before == 0 ? '—' : percentOf(held.change, before),
                    style: TextStyle(
                      fontSize: TextSize.title,
                      fontWeight: FontWeight.w800,
                      color: chosenInk(tone),
                    ),
                  ),
                  Text(
                    '${up ? '▲' : '▼'} ${priceMove(perShare)}',
                    style: TextStyle(
                      fontSize: TextSize.caption,
                      color: chosenInk(tone),
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
