import 'dart:math';

import 'package:flutter/material.dart';

import '../charts/bar_scale.dart';
import '../look/figures.dart';
import '../look/glyphs.dart';
import '../look/theme.dart';
import '../look/widgets.dart';
import '../model/ledger.dart';
import 'nav.dart';

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
        trailing: Text(
          money(value),
          style: const TextStyle(fontSize: 12, color: Hue.muted),
        ),
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
              style: const TextStyle(fontSize: 13, color: Hue.muted),
            ),
            Text(
              money(h.value),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
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
              '${moneySigned(h.gain)}　${percentOf(h.gain, h.cost)}',
              style: TextStyle(fontSize: 11.5, color: tone),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ledger = widget.ledger;
    return ListenableBuilder(
      listenable: ledger,
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
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
          children: [
            PageHeader('投資與股息', onBack: widget.nav.back),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Tile(
                  hero: true,
                  icon: Glyph.investment,
                  label: '未實現損益',
                  value: moneySigned(gain),
                  valueColor: tone,
                  trailing: Pill(percentOf(gain, cost), color: tone),
                  child: TileStats([
                    (Glyph.briefcase, '市值', money(value), Hue.ink),
                    (Glyph.coins, '成本', money(cost), Hue.ink),
                    (
                      Glyph.reports,
                      '已實現',
                      moneySigned(ledger.realized),
                      ledger.realized < 0 ? Hue.negative : Hue.ink,
                    ),
                  ]),
                ),
                TileRow([
                  Tile(
                    icon: Glyph.dividend,
                    label: '${today.month} 月股息',
                    value: money(ledger.dividends(year, month)),
                    sub: '累計 ${money(ledger.totalDividends)}',
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
                        : moneySigned(ledger.dayChange),
                    valueColor: ledger.dayChange < 0
                        ? Hue.negative
                        : Hue.positive,
                    sub: ledger.quotedOn == null
                        ? '連上網路後更新收盤價'
                        : '${holdings.length} 檔 · 收盤價',
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
      },
    );
  }
}
