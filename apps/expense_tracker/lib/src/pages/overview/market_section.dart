import 'dart:math';

import 'package:flutter/material.dart';

import '../../charts/bar_scale.dart';
import '../../look/figures.dart';
import '../../look/glyphs.dart';
import '../../look/theme.dart';
import '../../look/widgets.dart';
import '../../model/ledger.dart';
import '../nav.dart';

/// 投資行情: today's profit and the market value, then each holding's move
/// as a bar; a tap on one shows its value and gain so far.
class MarketSection extends StatefulWidget {
  const MarketSection({super.key, required this.ledger, required this.nav});

  final Ledger ledger;
  final Nav nav;

  @override
  State<MarketSection> createState() => _MarketSectionState();
}

class _MarketSectionState extends State<MarketSection> {
  String? _holding;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.ledger,
      builder: (context, _) {
        final parts = _market();
        // Nothing to show before the first trade.
        if (parts.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: parts,
        );
      },
    );
  }

  List<Widget> _market() {
    final ledger = widget.ledger;
    final holdings = ledger.holdings;
    if (holdings.isEmpty) return const [];
    final change = ledger.dayChange;
    final before = ledger.investValue - change;
    final largest = holdings.fold(0, (m, h) => max(m, h.change.abs()));
    final anyLoss = holdings.any((h) => h.change < 0);
    final code = _holding;
    final picked = code == null ? null : ledger.holding(code);
    final tone = change < 0 ? Hue.negative : Hue.positive;
    return [
      SectionHead(
        '投資行情',
        trailing: Text(switch (ledger.quotedOn) {
          final d? => '${d.month}/${d.day} 收盤',
          null => '尚未取得收盤價',
        }, style: mutedSmall),
      ),
      TileRow([
        Tile(
          icon: Glyph.investment,
          label: '當日損益',
          value: ledger.moneySigned(change),
          valueColor: tone,
          sub: '當日 ${percentOf(change, before)}',
        ),
        Tile(
          icon: Glyph.briefcase,
          label: '持股市值',
          value: ledger.money(ledger.investValue),
          sub: '${holdings.length} 檔',
          onTap: () => widget.nav.open(Pages.investments),
        ),
      ]),
      const SizedBox(height: 8),
      for (final h in holdings) _moveRow(h, largest, anyLoss ? 0.5 : 0),
      if (picked != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text.rich(
            TextSpan(
              style: mutedSmall,
              children: [
                TextSpan(
                  text: '${picked.name} ${picked.code}　',
                  style: const TextStyle(
                    color: Hue.ink,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                TextSpan(text: '市值 ${ledger.money(picked.value)}　累計 '),
                TextSpan(
                  text: ledger.orDots(
                    '${signed(picked.gain)}'
                    '（${percentOf(picked.gain, picked.cost)}）',
                  ),
                  style: TextStyle(
                    color: picked.gain < 0 ? Hue.negative : Hue.positive,
                  ),
                ),
              ],
            ),
          ),
        ),
    ];
  }

  /// One holding as a row of a bar chart: its name, today's move as a bar
  /// from a shared axis, and the amount.
  Widget _moveRow(Holding h, int largest, double axis) {
    final picked = h.code == _holding;
    return InkWell(
      onTap: () => setState(() => _holding = picked ? null : h.code),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: picked ? Hue.selected.withValues(alpha: 0.6) : null,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 112,
              child: Text(
                h.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13),
              ),
            ),
            Expanded(
              child: AxisBar(
                value: h.change,
                largest: largest,
                axis: axis,
                height: 8,
                minimum: 0.08,
              ),
            ),
            SizedBox(
              width: 50,
              child: Text(
                widget.ledger.moneySigned(h.change),
                textAlign: TextAlign.end,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: h.change < 0 ? Hue.negative : Hue.positive,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
