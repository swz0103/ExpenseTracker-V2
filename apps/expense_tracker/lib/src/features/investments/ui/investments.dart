import 'dart:math';

import 'package:flutter/material.dart';

import '../../../core/charts/bar_scale.dart';
import '../../../core/look/figures.dart';
import '../../../core/look/glyphs.dart';
import '../../../core/look/theme.dart';
import '../../../core/look/widgets.dart';
import '../../../core/ledger/ledger.dart';
import '../../../core/nav.dart';

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
  /// accounts; each opens its own page.
  List<Widget> _group(
    String title,
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
      SectionHead(
        title,
        trailing: Text(widget.ledger.money(value), style: mutedSmall),
      ),
      SoftPanel(
        color: Hue.white,
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(children: rows),
      ),
    ];
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
              const Text('尚無收盤價，以成本估算', style: mutedSmall),
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
      listenable: Listenable.merge([ledger, ?market]),
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
                for (final (title, etf) in const [('ETF', true), ('個股', false)])
                  ..._group(
                    title,
                    [
                      for (final h in holdings)
                        if (h.code.startsWith('00') == etf) h,
                    ],
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
