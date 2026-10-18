import 'dart:math';

import 'package:flutter/material.dart';

import '../look/figures.dart';
import '../look/glyphs.dart';
import '../look/theme.dart';
import '../look/widgets.dart';
import '../model/ledger.dart';
import 'entry_tile.dart';
import 'nav.dart';

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
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
            children: [
              PageHeader(code, onBack: nav.back),
              const Text('已不再持有', style: TextStyle(color: Hue.muted)),
              ..._history(trades),
            ],
          );
        }
        final tone = held.gain < 0 ? Hue.negative : Hue.positive;
        final lots = ledger.lotsOf(code);
        var largest = 1;
        for (final l in lots) {
          largest = max(largest, max(l.cost, (l.shares * held.price).round()));
        }
        final average = held.shares == 0 ? 0 : held.cost / held.shares;
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
          children: [
            PageHeader(held.name, onBack: nav.back),
            Tile(
              hero: true,
              icon: Glyph.investment,
              label: '$code · 市值',
              value: money(held.value),
              trailing: Pill(percentOf(held.gain, held.cost), color: tone),
              child: TileStats([
                (Glyph.briefcase, '股數', groupDigits(held.shares), Hue.ink),
                (Glyph.coins, '均價', average.toStringAsFixed(2), Hue.ink),
                (Glyph.reports, '未實現', moneySigned(held.gain), tone),
              ]),
            ),
            TileRow([
              Tile(
                icon: Glyph.investment,
                label: '今日',
                value: moneySigned(held.change),
                valueColor: held.change < 0 ? Hue.negative : Hue.positive,
                sub: '參考價 ${held.price}',
              ),
              Tile(
                icon: Glyph.dividend,
                label: '已領股息',
                value: money(held.dividends),
                sub: '已實現 ${moneySigned(held.realized)}',
              ),
            ]),
            const SectionHead('持有批次'),
            SoftPanel(
              color: Hue.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              child: Column(
                children: [
                  for (final (i, lot) in lots.indexed)
                    _LotRow(
                      lot: lot,
                      worth: (lot.shares * held.price).round(),
                      largest: largest,
                      first: i == 0,
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
              EntryTile(
                ledger: ledger,
                entry: e,
                onTap: () => nav.showEntry(e),
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
    required this.lot,
    required this.worth,
    required this.largest,
    required this.first,
  });

  final Lot lot;
  final int worth;
  final int largest;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final opening = lot.date == DateTime.utc(2025);
    final gain = worth - lot.cost;
    Widget bar(int value, Color color, double height) => ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: SizedBox(
        height: height,
        child: Align(
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: (value / largest).clamp(0.02, 1.0),
            child: Container(color: color),
          ),
        ),
      ),
    );
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: first ? null : const Border(top: BorderSide(color: Hue.line)),
      ),
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
                '${groupDigits(lot.shares)} 股',
                style: const TextStyle(fontSize: 12, color: Hue.muted),
              ),
              const Spacer(),
              Text(
                moneySigned(gain),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: gain < 0 ? Hue.negative : Hue.positive,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          bar(worth, Hue.investment, 7),
          const SizedBox(height: 3),
          bar(lot.cost, Hue.faint.withValues(alpha: 0.7), 4),
          const SizedBox(height: 4),
          Text(
            '市值 ${money(worth)} · 成本 ${money(lot.cost)}',
            style: const TextStyle(fontSize: 11.5, color: Hue.muted),
          ),
        ],
      ),
    );
  }
}
