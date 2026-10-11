import 'dart:math';

import 'package:flutter/material.dart';

import '../charts/bar_scale.dart';
import '../demo/ledger.dart';
import '../look/figures.dart';
import '../look/glyphs.dart';
import '../look/theme.dart';
import '../look/widgets.dart';
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
  static const _scale = BarScale.proportional;

  /// The lots of [h] still held, oldest first: what a sale takes first.
  void _showLots(Holding h) {
    final lots = widget.ledger.lotsOf(h.code);
    showSheet<void>(
      context,
      (context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${h.name} ${h.code}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            const Text(
              '持有批次：賣出時預設先賣最早的一批',
              style: TextStyle(fontSize: 12, color: Hue.muted),
            ),
            const SizedBox(height: 10),
            for (final (i, lot) in lots.indexed)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  border: i == 0
                      ? null
                      : const Border(top: BorderSide(color: Hue.line)),
                ),
                child: Row(
                  children: [
                    Text(
                      lot.date == DateTime.utc(2025)
                          ? '期初'
                          : '${lot.date.month}/${lot.date.day}',
                      style: const TextStyle(fontSize: 14),
                    ),
                    const Spacer(),
                    Text(
                      '${groupDigits(lot.shares)} 股',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(width: 16),
                    Text(
                      '成本 ${money(lot.cost)}',
                      style: const TextStyle(color: Hue.muted),
                    ),
                  ],
                ),
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
        final anyLoss = holdings.any((h) => h.gain < 0);
        final tone = gain < 0 ? Hue.negative : Hue.positive;
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
                    trailing: const Text(
                      '＋記',
                      style: TextStyle(fontSize: 12, color: Hue.accent),
                    ),
                    onTap: () => widget.nav.compose(type: EntryType.dividend),
                  ),
                  Tile(
                    icon: Glyph.add,
                    label: '買進／賣出',
                    value: '記一筆交易',
                    size: 16,
                    sub: '自動算手續費、證交稅',
                    onTap: () => widget.nav.compose(type: EntryType.buy),
                  ),
                ]),
                SectionHead(
                  '持股損益',
                  trailing: LinkToggle(
                    '示意行情',
                    onTap: () => showNote(context, '價格為示意收盤價，尚未接上自動行情'),
                  ),
                ),
                for (final h in holdings)
                  InkWell(
                    onTap: () => _showLots(h),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: const BoxDecoration(
                        border: Border(bottom: BorderSide(color: Hue.line)),
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 140,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  h.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  '${h.code}  ${percentOf(h.gain, h.cost)}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Hue.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: AxisBar(
                              value: h.gain,
                              largest: largest,
                              scale: _scale,
                              axis: anyLoss ? 0.3 : 0,
                              height: 10,
                              minimum: 0.1,
                            ),
                          ),
                          SizedBox(
                            width: 96,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  moneySigned(h.gain),
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: h.gain < 0
                                        ? Hue.negative
                                        : Hue.positive,
                                  ),
                                ),
                                Text(
                                  '市值 ${money(h.value)}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Hue.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}
