import 'dart:math';

import 'package:flutter/material.dart';

import '../../../../core/charts/bar_scale.dart';
import '../../../../core/text/figures.dart';
import '../../../../core/look/glyphs.dart';
import '../../../../core/look/theme.dart';
import '../../../../core/look/widgets.dart';
import '../../../../core/ledger/ledger.dart';
import '../../../../core/nav.dart';
import '../../../../core/ui/entry_tile.dart' show holdingLabel;
import '../../../../core/ui/shown_amounts.dart';
import '../../../../core/text/dates.dart';

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
    if (holdings.all.isEmpty) return const [];
    final change = ledger.holdings.dayChange;
    final before = ledger.holdings.marketValue - change;
    final largest = holdings.all.fold(0, (m, h) => max(m, h.change.abs()));
    final anyLoss = holdings.all.any((h) => h.change < 0);
    final code = _holding;
    final picked = code == null ? null : ledger.holding(code);
    final tone = change < 0 ? Hue.negative : Hue.positive;
    return [
      SectionTitle(
        '投資行情',
        trailing: Text(switch (ledger.marketData.quotedOn) {
          final d? => '${formatMd(d)} 收盤',
          null => '尚未取得收盤價',
        }, style: mutedSmall),
      ),
      CardRow([
        // Before any close there is no move to tell, not a move of zero.
        if (ledger.marketData.quotedOn == null)
          const FigureCard(
            icon: Glyph.investment,
            color: ToolHue.investments,
            label: '當日損益',
            value: '—',
            sub: '尚無收盤價',
          )
        else
          FigureCard(
            icon: Glyph.investment,
            color: ToolHue.investments,
            label: '當日損益',
            value: ledger.moneySigned(change),
            valueColor: tone,
            sub: '當日 ${percentOf(change, before)}',
          ),
        FigureCard(
          icon: Glyph.briefcase,
          color: ToolHue.investments,
          label: '持股市值',
          value: ledger.money(ledger.holdings.marketValue),
          sub: '${holdings.all.length} 檔',
          onTap: () => widget.nav.open(Pages.investments),
        ),
      ]),
      const SizedBox(height: 8),
      for (final h in holdings.all)
        _moveRow(h, largest, anyLoss ? 0.5 : 0, bar: holdings.all.length > 1),
      if (picked != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text.rich(
            TextSpan(
              style: mutedSmall,
              children: [
                TextSpan(
                  text: '${holdingLabel(picked)}　',
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
  Widget _moveRow(Holding h, int largest, double axis, {required bool bar}) {
    final picked = h.code == _holding;
    final quoted =
        widget.ledger.holdings.hasQuote(h.code) &&
        widget.ledger.marketData.quotedOn != null;
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
                style: const TextStyle(fontSize: TextSize.small),
              ),
            ),
            // A single holding's bar would only ever be full.
            Expanded(
              child: bar && quoted
                  ? AxisBar(
                      value: h.change,
                      largest: largest,
                      axis: axis,
                      height: 8,
                      minimum: 0.08,
                    )
                  : const SizedBox.shrink(),
            ),
            SizedBox(
              width: 50,
              child: Text(
                quoted ? widget.ledger.moneySigned(h.change) : '—',
                textAlign: TextAlign.end,
                style: TextStyle(
                  fontSize: TextSize.small,
                  fontWeight: FontWeight.w600,
                  color: !quoted
                      ? Hue.muted
                      : h.change < 0
                      ? Hue.negative
                      : Hue.positive,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
