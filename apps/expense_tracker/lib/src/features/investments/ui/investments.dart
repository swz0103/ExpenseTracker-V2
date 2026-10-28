import 'dart:math';

import 'package:flutter/material.dart';

import '../../../core/charts/bar_scale.dart';
import '../../../core/look/figures.dart';
import '../../../core/look/glyphs.dart';
import '../../../core/look/theme.dart';
import '../../../core/look/widgets.dart';
import '../../../core/ledger/ledger.dart';
import '../../../core/nav.dart';
import '../../../core/ui/entry_tile.dart' show holdingLabel;
import '../model/returns.dart';

/// 投資與股息: unrealised and realised profit, dividends by month, and
/// each holding's profit as a bar on a shared scale.
class InvestmentsPage extends StatefulWidget {
  const InvestmentsPage({super.key, required this.ledger, required this.nav});

  final Ledger ledger;
  final Nav nav;

  @override
  State<InvestmentsPage> createState() => _InvestmentsPageState();
}

class _InvestmentsPageState extends State<InvestmentsPage> {
  late final _month = (widget.ledger.today.year, widget.ledger.today.month);

  /// A group of holdings two to a row in a white card, as 帳戶 shows
  /// accounts; each opens its own page. Its [title] only when there are
  /// other groups, as its value would repeat the one above.
  List<Widget> _group(
    String? title,
    List<Holding> holdings,
    int largest,
    double axis,
  ) {
    if (holdings.isEmpty) return const [];
    final value = holdings.fold(0, (sum, h) => sum + h.value);
    final rows = <Widget>[];
    for (var i = 0; i < holdings.length; i += 2) {
      rows.add(
        Row(
          children: [
            Expanded(child: _cell(holdings[i], largest, axis)),
            Expanded(
              child: i + 1 < holdings.length
                  ? _cell(holdings[i + 1], largest, axis)
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      );
    }
    return [
      if (title != null)
        SectionHead(
          title,
          trailing: Text(widget.ledger.money(value), style: mutedSmall),
        )
      else
        const SizedBox(height: 12),
      SoftPanel(
        color: Hue.white,
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(children: rows),
      ),
    ];
  }

  /// The only holding, across the page: with nothing to compare it to,
  /// no bar, and its shares and today's move written out.
  Widget _solo(Holding h) {
    final ledger = widget.ledger;
    final tone = h.gain < 0 ? Hue.negative : Hue.positive;
    final quoted = ledger.hasQuote(h.code) && ledger.quotedOn != null;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: SoftPanel(
        color: Hue.white,
        onTap: () => widget.nav.open(Pages.holding(h.code)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    holdingLabel(h),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  '${ledger.orDots(groupDigits(h.shares))} 股',
                  style: mutedSmall,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              ledger.money(h.value),
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
            if (!ledger.hasQuote(h.code))
              const Text('尚無收盤價，以成本估算', style: mutedSmall)
            else if (ledger.olderQuote(h.code) case final day?)
              Text('以 ${day.month}/${day.day} 收盤計', style: mutedSmall),
            const SizedBox(height: 6),
            Row(
              children: [
                Text(
                  '損益 ${ledger.moneySigned(h.gain)}　${percentOf(h.gain, h.cost)}',
                  style: TextStyle(fontSize: 13, color: tone),
                ),
                const Spacer(),
                Text(
                  quoted ? '今日 ${ledger.moneySigned(h.change)}' : '今日 —',
                  style: TextStyle(
                    fontSize: 13,
                    color: !quoted
                        ? Hue.muted
                        : h.change < 0
                        ? Hue.negative
                        : Hue.positive,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _cell(Holding h, int largest, double axis) {
    final tone = h.gain < 0 ? Hue.negative : Hue.positive;
    return InkWell(
      onTap: () => widget.nav.open(Pages.holding(h.code)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              h.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: mutedSmall,
            ),
            Text(
              widget.ledger.money(h.value),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            // Without a close the value is the buying price: said so.
            if (!widget.ledger.hasQuote(h.code))
              const Text('尚無收盤價，以成本估算', style: mutedSmall)
            else if (widget.ledger.olderQuote(h.code) case final day?)
              Text('以 ${day.month}/${day.day} 收盤計', style: mutedSmall),
            const SizedBox(height: 4),
            AxisBar(
              value: h.gain,
              largest: largest,
              axis: axis,
              height: 6,
              minimum: 0.1,
            ),
            const SizedBox(height: 2),
            Text(
              '${widget.ledger.moneySigned(h.gain)}　${percentOf(h.gain, h.cost)}',
              style: TextStyle(fontSize: 12.5, color: tone),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ledger = widget.ledger;
    final market = widget.nav.market;
    return ListenableBuilder(
      listenable: Listenable.merge([
        ledger.watch(const {Area.entries, Area.market}),
        ?market,
      ]),
      builder: (context, _) {
        final value = ledger.investValue;
        final cost = ledger.investCost;
        final gain = value - cost;
        final (year, month) = _month;
        final holdings = ledger.holdings;
        final largest = holdings.fold(0, (m, h) => max(m, h.gain.abs()));
        final tone = gain < 0 ? Hue.negative : Hue.positive;
        final axis = holdings.any((h) => h.gain < 0) ? 0.3 : 0.0;
        final today = ledger.today;
        final groups = [
          for (final (title, etf) in const [('ETF', true), ('個股', false)])
            (
              title,
              [
                for (final h in holdings)
                  if (h.code.startsWith('00') == etf) h,
              ],
            ),
        ].where((g) => g.$2.isNotEmpty).toList();
        final list = ListView(
          // Pulled down to fetch the closes again, even when empty.
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          children: [
            PageHeader('投資與股息', onBack: widget.nav.back),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Tile(
                  hero: true,
                  icon: Glyph.investment,
                  label: '未實現損益',
                  value: ledger.moneySigned(gain),
                  valueColor: tone,
                  trailing: Pill(percentOf(gain, cost), color: tone),
                  child: TileStats([
                    (Glyph.briefcase, '市值', ledger.money(value), Hue.ink),
                    (Glyph.coins, '成本', ledger.money(cost), Hue.ink),
                    (
                      Glyph.reports,
                      '已實現',
                      ledger.moneySigned(ledger.realized),
                      ledger.realized < 0 ? Hue.negative : Hue.ink,
                    ),
                  ]),
                ),
                TileRow([
                  Tile(
                    icon: Glyph.dividend,
                    label: '${today.month} 月股息',
                    value: ledger.money(ledger.dividends(year, month)),
                    sub: '累計 ${ledger.money(ledger.totalDividends)}',
                    onTap: () => widget.nav.compose(type: EntryType.dividend),
                  ),
                  Tile(
                    icon: Glyph.reports,
                    label: switch (ledger.quotedOn) {
                      final d? => '${d.month}/${d.day} 漲跌',
                      null => '漲跌',
                    },
                    value: ledger.quotedOn == null
                        ? '—'
                        : ledger.moneySigned(ledger.dayChange),
                    valueColor: ledger.dayChange < 0
                        ? Hue.negative
                        : Hue.positive,
                    sub: switch ((market?.problem, ledger.quotedOn)) {
                      (final problem?, _) => problem,
                      (_, null) => '連上網路後更新收盤價',
                      _ when market?.busy ?? false => '更新收盤價中…',
                      _ => '${holdings.length} 檔 · 下拉可更新',
                    },
                  ),
                ]),
                _Returns(ledger: ledger),
                if (holdings.length == 1)
                  _solo(holdings.single)
                else
                  for (final (title, group) in groups)
                    ..._group(
                      groups.length > 1 ? title : null,
                      group,
                      largest,
                      axis,
                    ),
              ],
            ),
          ],
        );
        if (market == null) return list;
        return RefreshIndicator(
          onRefresh: () => market.refresh(force: true),
          child: list,
        );
      },
    );
  }
}

/// A rate as 「+8.4%」.
String yearlyRate(double rate) =>
    '${rate > 0 ? '+' : ''}${(rate * 100).toStringAsFixed(1)}%';

/// What the money invested earned a year, and the dividends to expect
/// over the next twelve months, month by month.
class _Returns extends StatelessWidget {
  const _Returns({required this.ledger});

  final Ledger ledger;

  @override
  Widget build(BuildContext context) {
    final rate = returnOf(ledger);
    final opening = ledger.holdings.any(
      (h) => ledger.lotsOf(h.code).any((l) => l.isOpening),
    );
    final since = investedSince(ledger);
    final guesses = expectedDividends(ledger);
    final total = guesses.fold(0, (sum, g) => sum + g.amount);
    final young = since != null && ledger.today.difference(since).inDays < 365;
    final months = <DateTime, List<DividendGuess>>{};
    for (final g in guesses) {
      (months[g.month] ??= []).add(g);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TileRow([
          Tile(
            icon: Glyph.reports,
            label: '年化報酬',
            value: rate == null ? '—' : yearlyRate(rate),
            valueColor: rate == null
                ? Hue.muted
                : rate < 0
                ? Hue.negative
                : Hue.positive,
            sub: rate == null
                ? opening
                      ? '有期初持股，買進日不明，無法計算'
                      : since == null
                      ? '還沒有交易'
                      : '交易還不夠計算'
                : young
                ? '投資未滿一年，僅供參考'
                : '含股息、已賣出（XIRR）',
          ),
          Tile(
            icon: Glyph.dividend,
            label: '未來 12 個月股息',
            value: total == 0 ? '—' : '約 ${ledger.money(total)}',
            sub: total == 0 ? '記下領到的股息後才能推估' : '依過去一年配息與目前股數推估',
          ),
        ]),
        if (months.isNotEmpty) ...[
          const SectionHead('預計配息'),
          SoftPanel(
            color: Hue.white,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: Column(
              children: [
                for (final (i, MapEntry(key: month, value: list))
                    in months.entries.indexed)
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: i == 0 ? null : ruleAbove,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 56,
                          child: Text(
                            '${month.month} 月',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (final g in list)
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        g.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Text(
                                      '約 ${ledger.money(g.amount)}',
                                      style: const TextStyle(
                                        color: Hue.positive,
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(top: 6, left: 4),
            child: Text('依去年同月的配息推估，實際以公司公告為準', style: mutedSmall),
          ),
        ],
      ],
    );
  }
}
