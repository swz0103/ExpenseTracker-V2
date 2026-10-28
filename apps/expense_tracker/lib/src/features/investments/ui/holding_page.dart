import 'dart:math';

import 'package:flutter/material.dart';

import '../../../core/look/figures.dart';
import '../../../core/look/glyphs.dart';
import '../../../core/look/theme.dart';
import '../../../core/look/widgets.dart';
import '../../../core/ledger/ledger.dart';
import '../../../core/ui/entry_tile.dart';
import '../../../core/nav.dart';
import '../model/returns.dart';
import 'investments.dart' show yearlyRate;

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
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            children: [
              PageHeader(code, onBack: nav.back),
              const Text('已不再持有', style: TextStyle(color: Hue.muted)),
              ..._history(trades),
            ],
          );
        }
        final tone = held.gain < 0 ? Hue.negative : Hue.positive;
        final quoted = ledger.hasQuote(code);
        final lots = ledger.lotsOf(code);
        var largest = 1;
        for (final l in lots) {
          largest = max(largest, max(l.cost, (l.shares * held.price).round()));
        }
        final average = held.shares == 0 ? 0 : held.cost / held.shares;
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          children: [
            PageHeader(held.name, onBack: nav.back),
            Tile(
              hero: true,
              icon: Glyph.investment,
              label: '$code · 市值',
              value: ledger.money(held.value),
              trailing: Pill(percentOf(held.gain, held.cost), color: tone),
              child: TileStats([
                (
                  Glyph.briefcase,
                  '股數',
                  ledger.orDots(groupDigits(held.shares)),
                  Hue.ink,
                ),
                (Glyph.coins, '均價', average.toStringAsFixed(2), Hue.ink),
                (Glyph.reports, '未實現', ledger.moneySigned(held.gain), tone),
              ]),
            ),
            TileRow([
              Tile(
                icon: Glyph.investment,
                label: switch ((quoted, ledger.quotedOn)) {
                  (true, final d?) => '${d.month}/${d.day} 漲跌',
                  _ => '漲跌',
                },
                value: quoted && ledger.quotedOn != null
                    ? ledger.moneySigned(held.change)
                    : '—',
                valueColor: held.change < 0 ? Hue.negative : Hue.positive,
                // Without a close the value stands on the buying price.
                sub: !quoted
                    ? '尚無收盤價，以成本 ${held.price.toStringAsFixed(2)} 估算'
                    : switch (ledger.olderQuote(held.code)) {
                        final day? =>
                          '${day.month}/${day.day} 收盤 ${held.price.toStringAsFixed(2)}',
                        null => '收盤 ${held.price.toStringAsFixed(2)}',
                      },
              ),
              Tile(
                icon: Glyph.dividend,
                label: '已領股息',
                value: ledger.money(held.dividends),
                sub: '已實現 ${ledger.moneySigned(held.realized)}',
              ),
            ]),
            Builder(
              builder: (context) {
                final rate = returnOf(ledger, code: code);
                final months = payingMonths(ledger, code);
                return TileRow([
                  Tile(
                    icon: Glyph.reports,
                    label: '年化報酬',
                    value: rate == null ? '—' : yearlyRate(rate),
                    valueColor: rate == null
                        ? Hue.muted
                        : rate < 0
                        ? Hue.negative
                        : Hue.positive,
                    sub: rate == null ? '有期初持股，買進日不明' : '含股息（XIRR）',
                  ),
                  Tile(
                    icon: Glyph.calendar,
                    label: '配息月份',
                    value: months.isEmpty ? '—' : '${months.join('、')} 月',
                    sub: '近兩年領到股息的月份',
                  ),
                ]);
              },
            ),
            const SectionHead('持有批次'),
            SoftPanel(
              color: Hue.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              child: Column(
                children: [
                  for (final (i, lot) in lots.indexed)
                    _LotRow(
                      ledger: ledger,
                      lot: lot,
                      worth: (lot.shares * held.price).round(),
                      largest: largest,
                      first: i == 0,
                      // One lot has nothing to be set against.
                      bars: lots.length > 1,
                    ),
                ],
              ),
            ),
            ..._history(trades),
          ],
        );
      },
    );
  }

  /// Every trade and dividend of the stock, also once it is all sold.
  List<Widget> _history(List<Entry> trades) => [
    if (trades.isNotEmpty) ...[
      const SectionHead('交易紀錄'),
      SoftPanel(
        color: Hue.white,
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Column(
          children: [
            for (final e in trades)
              EntryRow(
                ledger: ledger,
                entry: e,
                onOpen: nav.showEntry,
                divider: !identical(e, trades.last),
              ),
          ],
        ),
      ),
    ],
  ];
}

/// A lot: when it was bought, how many shares, and its cost against what
/// it is worth now as two bars.
class _LotRow extends StatelessWidget {
  const _LotRow({
    required this.ledger,
    required this.lot,
    required this.worth,
    required this.largest,
    required this.first,
    required this.bars,
  });

  final Ledger ledger;
  final Lot lot;
  final int worth;
  final int largest;
  final bool first;

  /// Whether to draw cost and worth as bars.
  final bool bars;

  @override
  Widget build(BuildContext context) {
    final opening = lot.isOpening;
    final gain = worth - lot.cost;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: first ? null : ruleAbove,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                opening ? '期初持有' : '${lot.date.month}/${lot.date.day} 買進',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${ledger.orDots(groupDigits(lot.shares))} 股',
                style: mutedSmall,
              ),
              const Spacer(),
              Text(
                ledger.moneySigned(gain),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: gain < 0 ? Hue.negative : Hue.positive,
                ),
              ),
            ],
          ),
          if (bars) ...[
            const SizedBox(height: 6),
            PairBars(
              now: worth / largest,
              then: lot.cost / largest,
              color: Hue.investment,
              thenOpacity: 0.7,
            ),
          ],
          const SizedBox(height: 4),
          Text(
            '市值 ${ledger.money(worth)} · 成本 ${ledger.money(lot.cost)}',
            style: const TextStyle(fontSize: 12.5, color: Hue.muted),
          ),
        ],
      ),
    );
  }
}
