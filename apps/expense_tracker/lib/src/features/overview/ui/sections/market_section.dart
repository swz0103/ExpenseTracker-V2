import 'dart:math';

import 'package:flutter/material.dart';

import '../../../../core/charts/bar_scale.dart';
import '../../../../../design_system/display/amount.dart';
import '../../../../core/design_system/glyphs.dart';
import '../../../../core/design_system/theme.dart';
import '../../../../core/design_system/design_system.dart';
import '../../../../core/ledger/ledger.dart';
import '../../../../core/navigation/nav.dart';
import '../../../../core/widgets/entry_tile.dart' show holdingLabel;
import '../../../../core/widgets/shown_amounts.dart';
import '../../../../core/formatting/dates.dart';
import '../../../../core/design_system/shape.dart';
import '../../../../core/design_system/spacing.dart';

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
      // Only what it shows: a change elsewhere leaves it as it is.
      listenable: widget.ledger.watch(const {Topic.entries, Topic.market}),
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
    // Only the stocks still held: one sold out is no longer a holding.
    final held = ledger.holdings.held;
    if (held.isEmpty) return const [];
    final change = ledger.holdings.dayChange;
    final before = ledger.holdings.marketValue - change;
    final largest = held.fold(0, (m, h) => max(m, h.change.abs()));
    final anyLoss = held.any((h) => h.change < 0);
    final code = _holding;
    final picked = code == null ? null : ledger.holding(code);
    final tone = AppColors.ofMarket(change);
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
            color: ToolColors.investments,
            label: '當日損益',
            value: '—',
            sub: '尚無收盤價',
          )
        else
          FigureCard(
            icon: Glyph.investment,
            color: ToolColors.investments,
            label: '當日損益',
            value: ledger.moneySigned(change),
            spokenValue: ledger.spoken(change),
            valueColor: tone,
            sub: '當日 ${percentOf(change, before)}',
          ),
        FigureCard(
          icon: Glyph.briefcase,
          color: ToolColors.investments,
          label: '持股市值',
          value: ledger.money(ledger.holdings.marketValue),
          sub: countOf(held.length, CountUnit.stocks),
          onTap: () => widget.nav.open(AppRoutes.investments),
        ),
      ]),
      const SizedBox(height: Space.s2),
      for (final h in held)
        _moveRow(h, largest, anyLoss ? 0.5 : 0, bar: held.length > 1),
      if (picked != null)
        Padding(
          padding: const EdgeInsets.only(top: Space.s2),
          child: Text.rich(
            TextSpan(
              style: mutedSmall,
              children: [
                TextSpan(
                  text: '${holdingLabel(picked)}　',
                  style: const TextStyle(
                    color: AppColors.ink,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                TextSpan(text: '市值 ${ledger.money(picked.value)}　累計 '),
                TextSpan(
                  text: ledger.orDots(
                    '${signed(picked.gain)}'
                    '（${percentOf(picked.gain, picked.cost)}）',
                  ),
                  semanticsLabel: ledger.readAloud(
                    ledger.orDots(
                      '${signed(picked.gain)}'
                      '（${percentOf(picked.gain, picked.cost)}）',
                    ),
                    picked.gain,
                  ),
                  style: TextStyle(color: AppColors.ofMarket(picked.gain)),
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
      borderRadius: BorderRadius.circular(Radii.small),
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(horizontal: Space.s1),
        decoration: BoxDecoration(
          color: picked ? AppColors.selected.withValues(alpha: 0.6) : null,
          borderRadius: BorderRadius.circular(Radii.small),
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
                      positive: AppColors.rise,
                      negative: AppColors.fall,
                    )
                  : const SizedBox.shrink(),
            ),
            // As wide on every row, so the bars share one axis, and wider
            // with the phone's text, so the amount stays on one line.
            SizedBox(
              width: 50 * textGrowth(context),
              child: Text(
                quoted ? widget.ledger.moneySigned(h.change) : '—',
                semanticsLabel: quoted ? widget.ledger.spoken(h.change) : null,
                textAlign: TextAlign.end,
                style: TextStyle(
                  fontSize: TextSize.small,
                  fontWeight: FontWeight.w600,
                  color: !quoted
                      ? AppColors.muted
                      : AppColors.ofMarket(h.change),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
