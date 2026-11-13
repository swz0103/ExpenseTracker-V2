import 'package:flutter/material.dart';

import '../../../core/look/figures.dart';
import '../../../core/look/glyphs.dart';
import '../../../core/look/theme.dart';
import '../../../core/look/widgets.dart';
import '../../../core/ledger/ledger.dart';
import '../../../core/nav.dart';
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
  /// 持股 or 股息.
  var _tab = 0;

  late final _month = (widget.ledger.today.year, widget.ledger.today.month);

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
        final (year, month) = _month;
        final holdings = ledger.holdings;
        final list = ListView(
          // Pulled down to fetch the closes again, even when empty.
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          children: [
            PageHeader('投資與股息', onBack: widget.nav.back),
            _InvestHero(ledger: ledger),
            const SizedBox(height: 12),
            Row(
              children: [
                for (final (i, (glyph, label, color)) in const [
                  (Glyph.pie, '持股', Shade(0xFF4A5D99, 0xFF9FAEE0)),
                  (Glyph.dividend, '股息', Shade(0xFFC9A34A, 0xFFDDBE73)),
                ].indexed) ...[
                  if (i > 0) const SizedBox(width: 10),
                  Expanded(
                    child: Semantics(
                      selected: _tab == i,
                      button: true,
                      label: label,
                      excludeSemantics: true,
                      child: Material(
                        color: _tab == i ? color : tintOf(color, 0.22),
                        borderRadius: BorderRadius.circular(16),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () => setState(() => _tab = i),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(minHeight: 52),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                GlyphIcon(
                                  glyph,
                                  size: 20,
                                  color: _tab == i
                                      ? const Color(0xFFFFFFFF)
                                      : deepOf(color),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  label,
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800,
                                    color: _tab == i
                                        ? const Color(0xFFFFFFFF)
                                        : deepOf(color),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 14),
            if (_tab == 0) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
                child: Row(
                  children: [
                    const Text(
                      '持股',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Spacer(),
                    Text(switch ((market?.problem, ledger.quotedOn)) {
                      (final problem?, _) => problem,
                      (_, null) => '連上網路後更新收盤價',
                      _ when market?.busy ?? false => '更新收盤價中…',
                      (_, final d?) => '${d.month}/${d.day} 收盤 · 下拉更新',
                    }, style: mutedSmall),
                  ],
                ),
              ),
              if (holdings.isEmpty)
                EmptyState(
                  glyph: Glyph.pie,
                  color: const Shade(0xFF4A5D99, 0xFF9FAEE0),
                  message: '還沒有持股',
                  action: '記一筆買進',
                  onAction: () => widget.nav.compose(type: EntryType.buy),
                )
              else
                QuoteBoard([
                  for (final h in [
                    ...holdings,
                  ]..sort((a, b) => b.value.compareTo(a.value)))
                    _HoldingRow(
                      ledger: ledger,
                      held: h,
                      onTap: () => widget.nav.open(Pages.holding(h.code)),
                    ),
                ]),
            ] else ...[
              Container(
                padding: const EdgeInsets.fromLTRB(14, 12, 16, 12),
                decoration: BoxDecoration(
                  color: Hue.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: Hue.cardShadow,
                ),
                child: Row(
                  children: [
                    const SquareIcon(
                      Glyph.dividend,
                      Shade(0xFFC9A34A, 0xFFDDBE73),
                      size: 44,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('$month 月領到', style: mutedSmall),
                          Text(
                            ledger.orDots(
                              groupDigits(ledger.dividends(year, month)),
                            ),
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Text('累計', style: mutedSmall),
                        Text(
                          ledger.orDots(groupDigits(ledger.totalDividends)),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              _Returns(ledger: ledger),
            ],
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
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
              ),
              Text(
                sub,
                style: const TextStyle(fontSize: 11.5, color: Hue.muted),
              ),
            ],
          ),
        );
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Hue.hero, Hue.tile],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '市值',
            style: TextStyle(
              fontSize: 13,
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
                  fontSize: 34,
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
                    color: day < 0 ? Hue.negative : Hue.positive,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '今日 ${ledger.orDots(signed(day))}'
                    '${before == 0 ? '' : ' · ${percentOf(day, before)}'}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: Hue.onAccent,
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
                  : up
                  ? Hue.positive
                  : Hue.negative,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Text(
                  !quoted || before == 0 ? '—' : percentOf(held.change, before),
                  textScaler: TextScaler.noScaling,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: quoted ? Hue.onAccent : Hue.muted,
                  ),
                ),
                if (quoted)
                  Text(
                    '${up ? '▲' : '▼'}${perShare.abs().toStringAsFixed(2)}',
                    textScaler: TextScaler.noScaling,
                    style: const TextStyle(fontSize: 11.5, color: Hue.onAccent),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
