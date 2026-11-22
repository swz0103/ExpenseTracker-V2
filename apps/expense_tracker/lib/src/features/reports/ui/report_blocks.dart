import 'package:flutter/material.dart';

import '../../../../design_system/display/amount.dart';
import '../../../core/design_system/glyphs.dart';
import '../../../core/widgets/icons.dart';
import '../../../core/design_system/theme.dart';
import '../../../core/design_system/design_system.dart';
import '../../../core/ledger/ledger.dart';
import '../../../core/widgets/shown_amounts.dart';
import '../../../core/formatting/dates.dart';
import '../../../core/design_system/shape.dart';
import '../../../core/design_system/spacing.dart';
import '../../../core/formatting/words.dart';

// The pieces the tabs are made of: the readout, the main card, the tinted blocks.

/// The chosen stretch, or the whole period, in one line.
class ReportReadout extends StatelessWidget {
  const ReportReadout({
    super.key,
    required this.ledger,
    required this.label,
    required this.income,
    required this.expense,
    this.worth,
  });

  final Ledger ledger;
  final String label;
  final int income;
  final int expense;

  /// Net worth at the stretch's end; none for one still ahead.
  final int? worth;

  @override
  Widget build(BuildContext context) {
    final left = income - expense;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.s4,
        vertical: Space.s2,
      ),
      decoration: BoxDecoration(
        color: AppColors.tile,
        borderRadius: BorderRadius.circular(Radii.large),
      ),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: TextSize.small,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: Space.s3),
          // Wraps onto a second line rather than shrinking when the
          // phone's text is large.
          Expanded(
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: 12,
              runSpacing: 2,
              children: [
                _figure('收', income, AppColors.positive),
                _figure('支', expense, AppColors.negative),
                _figure('餘', left, AppColors.ofBalance(left)),
                if (worth case final w?)
                  _figure('淨資產', w, AppColors.investment),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _figure(String label, int value, Color color) => Text.rich(
    TextSpan(
      children: [
        TextSpan(text: '$label ', style: mutedText),
        TextSpan(
          text: ledger.money(value),
          style: TextStyle(fontWeight: FontWeight.w700, color: color),
        ),
      ],
    ),
    style: const TextStyle(fontSize: TextSize.small),
  );
}

/// The main card: 結餘 big on the left, 收入 with what of it was
/// dividends on the right, a bar of spending against what was kept, and
/// 支出 against last year beside how much of the income was kept.
class ReportHero extends StatelessWidget {
  const ReportHero({
    super.key,
    required this.ledger,
    required this.income,
    required this.expense,
    required this.dividends,
    required this.lastExpense,
    this.until,
  });

  final Ledger ledger;
  final int income;
  final int expense;
  final int dividends;
  final int lastExpense;

  /// The period runs past today: its sums are up to this day.
  final DateTime? until;

  @override
  Widget build(BuildContext context) {
    final kept = income - expense;
    final keptShare = income <= 0 ? 0 : percent(kept, income);
    final spentShare = income <= 0
        ? (expense > 0 ? 1.0 : 0.0)
        : (expense / income).clamp(0.0, 1.0);
    final change = lastExpense == 0
        ? null
        : percent(expense - lastExpense, lastExpense);
    final until = this.until;
    return HeroCard(
      padding: const EdgeInsets.fromLTRB(
        Space.s4,
        Space.s4,
        Space.s4,
        Space.s4,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            until == null ? '結餘' : '結餘 · 至 ${formatMd(until)}',
            style: const TextStyle(
              fontSize: TextSize.small,
              fontWeight: FontWeight.w800,
              color: AppColors.accent,
            ),
          ),
          _figures(kept),
          const SizedBox(height: Space.s3),
          _SpentBar(spentShare: spentShare),
          const SizedBox(height: Space.s2),
          _legend(keptShare, change),
        ],
      ),
    );
  }

  /// 結餘 big, and 收入 with what of it was dividends; 收入 goes under 結餘
  /// when both do not fit on a line.
  Widget _figures(int kept) => Wrap(
    alignment: WrapAlignment.spaceBetween,
    crossAxisAlignment: WrapCrossAlignment.end,
    spacing: 12,
    runSpacing: 2,
    children: [
      Text(
        ledger.orDots(groupDigits(kept)),
        style: TextStyle(
          fontSize: TextSize.big,
          fontWeight: FontWeight.w800,
          color: AppColors.ofBalance(kept),
        ),
      ),
      Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '收入 ${ledger.orDots(groupDigits(income))}',
            style: const TextStyle(
              fontSize: TextSize.title,
              fontWeight: FontWeight.w800,
              color: AppColors.positive,
            ),
          ),
          if (dividends > 0)
            Text(
              '含股息 ${ledger.orDots(groupDigits(dividends))}',
              style: mutedSmall,
            ),
        ],
      ),
    ],
  );

  /// The key under the bar: 支出 with its [change] on last year in per
  /// cent, and 存下 the [keptShare] of the income.
  Widget _legend(int keptShare, int? change) => Wrap(
    alignment: WrapAlignment.spaceBetween,
    spacing: 12,
    runSpacing: 4,
    children: [
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const LegendKey(AppColors.negative, Words.expense),
          const SizedBox(width: Space.s2),
          Text(
            ledger.orDots(groupDigits(expense)),
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          if (change != null) ...[
            const SizedBox(width: Space.s2),
            Text(
              '${change >= 0 ? '▲' : '▼'}${change.abs()}%',
              style: TextStyle(
                fontSize: TextSize.caption,
                fontWeight: FontWeight.w800,
                color: AppColors.ofSpendingChange(change),
              ),
            ),
          ],
        ],
      ),
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const LegendKey(AppColors.positive, '存下'),
          const SizedBox(width: Space.s2),
          Text(
            '$keptShare%',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    ],
  );
}

/// The hero's bar: what was spent, then what was kept, as shares of the
/// income.
class _SpentBar extends StatelessWidget {
  const _SpentBar({required this.spentShare});

  /// How much of the income was spent, 0 to 1.
  final double spentShare;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(Radii.extraSmall),
    child: SizedBox(
      height: 10,
      child: Row(
        children: [
          if (spentShare > 0)
            Expanded(
              flex: (spentShare * 1000).round().clamp(1, 1000),
              child: ColoredBox(
                color: markOf(AppColors.negative),
                child: SizedBox.expand(),
              ),
            ),
          if (spentShare > 0 && spentShare < 1)
            const SizedBox(width: Space.half),
          if (spentShare < 1)
            Expanded(
              flex: ((1 - spentShare) * 1000).round().clamp(1, 1000),
              child: ColoredBox(
                color: markOf(AppColors.positive),
                child: SizedBox.expand(),
              ),
            ),
        ],
      ),
    ),
  );
}

/// A tinted block: a solid icon and a label over a figure and a line.
class ReportBlock extends StatelessWidget {
  const ReportBlock({
    super.key,
    required this.glyph,
    required this.color,
    required this.label,
    required this.value,
    required this.sub,
  });

  final Glyph glyph;
  final Color color;
  final String label;
  final String value;
  final String sub;

  @override
  Widget build(BuildContext context) {
    final ink = deepOf(color);
    return ColorCard(
      color: color,
      padding: const EdgeInsets.fromLTRB(
        Space.s4,
        Space.s4,
        Space.s3,
        Space.s4,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SquareIcon(glyph, color, size: 32),
              const SizedBox(width: Space.s2),
              Expanded(
                child: OneLine(
                  label,
                  style: TextStyle(
                    fontSize: TextSize.small,
                    fontWeight: FontWeight.w800,
                    color: ink,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.s2),
          OneLine(
            value,
            style: const TextStyle(
              fontSize: TextSize.large,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (sub.isNotEmpty)
            OneLine(
              sub,
              style: TextStyle(fontSize: TextSize.caption, color: ink),
            ),
        ],
      ),
    );
  }
}

/// A category as a block of the mosaic: its icon, name and share, what
/// it came to, and against last year's same stretch.
class CategoryBlock extends StatelessWidget {
  const CategoryBlock({
    super.key,
    required this.ledger,
    required this.category,
    required this.amount,
    required this.share,
    required this.change,
    required this.large,
    required this.onTap,
  });

  final Ledger ledger;
  final Category category;
  final int amount;
  final int share;
  final int? change;
  final bool large;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = shownColor(Color(category.color));
    final ink = deepOf(color);
    final change = this.change;
    return ColorCard(
      color: color,
      amount: 0.24,
      radius: Radii.large,
      onTap: onTap,
      label: '${category.name} $share%',
      padding: const EdgeInsets.all(Space.s2),
      child: LayoutBuilder(
        builder: (context, box) {
          final roomy = box.maxHeight > 70 && box.maxWidth > 70;
          final top = roomy || (change != null && box.maxHeight > 52);
          // A column, not a stack: the words at the foot shrink to the
          // room under the top row and never run into it.
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (top)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (roomy)
                      SquareIcon(
                        iconFor(category.icon),
                        color,
                        size: large ? 40 : 28,
                      ),
                    const Spacer(),
                    if (change != null && box.maxWidth > 60)
                      Text(
                        '${change >= 0 ? '▲' : '▼'} ${change.abs()}%',
                        textScaler: TextScaler.noScaling,
                        style: TextStyle(
                          fontSize: TextSize.caption,
                          fontWeight: FontWeight.w800,
                          color: AppColors.ofSpendingChange(change),
                        ),
                      ),
                  ],
                ),
              Expanded(
                child: Align(
                  alignment: Alignment.bottomLeft,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.bottomLeft,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${category.name} · $share%',
                          style: TextStyle(
                            fontSize: large ? TextSize.body : TextSize.caption,
                            fontWeight: FontWeight.w800,
                            color: ink,
                          ),
                        ),
                        Text(
                          ledger.orDots(groupDigits(amount)),
                          style: TextStyle(
                            fontSize: large ? TextSize.large : TextSize.title,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// A dashed rule across, for an average.
class DashesPainter extends CustomPainter {
  DashesPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (var x = 0.0; x < size.width; x += 7) {
      canvas.drawLine(Offset(x, 0), Offset(x + 4, 0), paint);
    }
  }

  @override
  bool shouldRepaint(DashesPainter old) => old.color != color;
}
