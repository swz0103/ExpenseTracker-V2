import 'dart:math';

import 'package:flutter/material.dart';

import '../ledger/ledger.dart' show Ledger;
import '../look/glyphs.dart';
import '../look/haptics.dart';
import '../look/theme.dart';
import '../look/kit.dart';
import 'shown_amounts.dart';
import '../look/shape.dart';
import '../look/spacing.dart';
import '../text/words.dart';

/// The page's main card for a stretch of time: what is left of [income]
/// after [expense] as the figure, in ink or in the spending colour when
/// more went out than came in; under it one bar of what came in against
/// what went out, and the two sums at its ends, [middle] between them.
/// No blocks inside the card: the bar says the share at a glance.
class BalanceHero extends StatelessWidget {
  const BalanceHero({
    super.key,
    required this.ledger,
    required this.icon,
    required this.label,
    required this.income,
    required this.expense,
    this.middle,
    this.note,
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

  /// A third figure between the two, such as 其中股息: its label and words.
  final (String, String)? middle;

  /// A few words at the right of the label, such as 轉帳 2 筆.
  final String? note;

  /// Whether 結餘率 shows at the right of the label.
  final bool rate;

  /// The figure's size; [TextSize.big] when null.
  final double? size;

  @override
  Widget build(BuildContext context) {
    final left = income - expense;
    final kept = income == 0 ? 0 : (left * 100 / income).round();
    final total = income + expense;
    // Each side at least a sliver of the bar, so a small one still shows.
    int share(int v) => total == 0
        ? 1
        : max(1, (max(v / total, v == 0 ? 0 : 0.06) * 1000).round());
    return HeroCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SquareIcon(icon, Hue.accent, size: 30),
              const SizedBox(width: Space.s2),
              Expanded(child: OneLine(label, style: accentLabel)),
              if (note case final words?) OneLine(words, style: mutedSmall),
              // The eye that hides every amount, in the corner.
              if (hides) _HideAmounts(ledger),
            ],
          ),
          const SizedBox(height: Space.s2),
          // 結餘率 at the right, on the figure's line.
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    ledger.money(left),
                    style: TextStyle(
                      fontSize: size ?? TextSize.big,
                      fontWeight: FontWeight.w800,
                      height: 1.15,
                      color: left < 0 ? Hue.negative : Hue.ink,
                    ),
                  ),
                ),
              ),
              if (rate) ...[
                const SizedBox(width: Space.s2),
                Pill('結餘率 $kept%'),
              ],
            ],
          ),
          const SizedBox(height: Space.s3),
          SizedBox(
            height: 8,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (total == 0)
                  const Expanded(child: _Bar(Hue.line))
                else ...[
                  if (income > 0)
                    Expanded(
                      flex: share(income),
                      child: const _Bar(Hue.positive),
                    ),
                  if (income > 0 && expense > 0)
                    const SizedBox(width: Space.half),
                  if (expense > 0)
                    Expanded(
                      flex: share(expense),
                      child: const _Bar(Hue.negative),
                    ),
                ],
              ],
            ),
          ),
          const SizedBox(height: Space.s2),
          _Ends(
            ends: [
              (Words.income, ledger.money(income), Hue.positive),
              if (middle case (final name, final value)) (name, value, Hue.ink),
              (Words.expense, ledger.money(expense), Hue.negative),
            ],
          ),
        ],
      ),
    );
  }
}

/// 收入 at the left and 支出 at the right, each its name over its
/// figure, with a third figure between when there is one; one under
/// another, each name and figure on a line, when a figure would not fit
/// its third, as with large text on a narrow phone, rather than broken
/// over two lines.
class _Ends extends StatelessWidget {
  const _Ends({required this.ends});

  final List<(String, String, Color)> ends;

  static const _name = TextStyle(fontSize: TextSize.caption, color: Hue.muted);

  static TextStyle _figure(Color color) => TextStyle(
    fontSize: TextSize.title,
    fontWeight: FontWeight.w800,
    color: color,
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final each = box.maxWidth / ends.length;
      final fit = ends.every(
        (end) => wordsWidth(context, end.$2, _figure(end.$3)) <= each,
      );
      return fit ? _side() : _stacked();
    },
  );

  Widget _stacked() => Column(
    children: [
      for (final (name, value, color) in ends)
        Row(
          children: [
            Expanded(child: Text(name, style: _name)),
            Text(value, style: _figure(color)),
          ],
        ),
    ],
  );

  Widget _side() {
    return Row(
      children: [
        for (final (i, (name, value, color)) in ends.indexed)
          Expanded(
            child: Column(
              crossAxisAlignment: i == 0
                  ? CrossAxisAlignment.start
                  : i == ends.length - 1
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.center,
              children: [
                Text(name, style: _name),
                Text(value, style: _figure(color)),
              ],
            ),
          ),
      ],
    );
  }
}

/// A rounded piece of the income and spending bar.
class _Bar extends StatelessWidget {
  const _Bar(this.color);

  final Color color;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(Radii.extraSmall),
    ),
  );
}

/// The eye beside a balance: hides every amount in the app, or shows
/// them again.
class _HideAmounts extends StatelessWidget {
  const _HideAmounts(this.ledger);

  final Ledger ledger;

  @override
  Widget build(BuildContext context) {
    final hidden = ledger.amounts.hidden;
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
                ledger.amounts.toggle();
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
