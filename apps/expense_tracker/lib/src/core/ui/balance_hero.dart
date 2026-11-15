import 'package:flutter/material.dart';

import '../ledger/ledger.dart' show Ledger;
import '../look/glyphs.dart';
import '../look/haptics.dart';
import '../look/theme.dart';
import '../look/tiles.dart';
import 'shown_amounts.dart';

/// The page's main tile for a stretch of time: what is left of [income]
/// after [expense] as the figure, in ink or in the spending colour when
/// more went out than came in; the two along its foot with [third]
/// beside them; and, with [rate], the share of income kept.
class BalanceHero extends StatelessWidget {
  const BalanceHero({
    super.key,
    required this.ledger,
    required this.icon,
    required this.label,
    required this.income,
    required this.expense,
    required this.third,
    this.rate = true,
    this.size,
    this.hides = false,
  });

  /// Writes the amounts, as dots while they are hidden.
  final Ledger ledger;

  /// Whether an eye beside the label hides and shows the amounts.
  final bool hides;
  final Glyph icon;
  final String label;
  final int income;
  final int expense;

  /// The third figure along the foot: its mark, label, words and colour.
  final (Glyph, String, String, Color) third;
  final bool rate;

  /// The figure's size; the hero tile's own when null.
  final double? size;

  @override
  Widget build(BuildContext context) {
    final left = income - expense;
    final kept = income == 0 ? 0 : (left * 100 / income).round();
    return Tile(
      hero: true,
      icon: icon,
      label: label,
      value: ledger.money(left),
      valueColor: left < 0 ? Hue.negative : Hue.ink,
      size: size,
      beside: hides ? _HideAmounts(ledger) : null,
      trailing: rate ? Pill('結餘率 $kept%') : null,
      child: TileStats([
        (Glyph.income, '收入', ledger.money(income), Hue.positive),
        (Glyph.payout, '支出', ledger.money(expense), Hue.negative),
        third,
      ]),
    );
  }
}

/// The eye beside a balance: hides every amount in the app, or shows
/// them again.
class _HideAmounts extends StatelessWidget {
  const _HideAmounts(this.ledger);

  final Ledger ledger;

  @override
  Widget build(BuildContext context) {
    final hidden = ledger.hidden;
    // Drawn small beside the label, tapped as a full 48 dp square.
    return SizedBox(
      width: 36,
      height: 28,
      child: OverflowBox(
        maxWidth: 48,
        maxHeight: 48,
        child: Tooltip(
          message: hidden ? '顯示金額' : '隱藏金額',
          child: Semantics(
            button: true,
            child: InkResponse(
              onTap: () {
                Haptics.selection();
                ledger.toggleHidden();
              },
              radius: 20,
              child: SizedBox.square(
                dimension: 48,
                child: Center(
                  child: GlyphIcon(
                    hidden ? Glyph.eyeOff : Glyph.eye,
                    size: 18,
                    color: Hue.accent,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
