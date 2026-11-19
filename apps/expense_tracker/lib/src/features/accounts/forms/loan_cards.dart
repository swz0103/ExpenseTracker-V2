import 'package:flutter/material.dart';

import '../../../core/formatting/figures.dart';
import '../../../core/design_system/glyphs.dart';
import '../../../core/design_system/theme.dart';
import '../../../core/design_system/design_system.dart';
import '../../../core/ledger/ledger.dart';

import 'package:domain/loans.dart';

import '../../../core/widgets/shown_amounts.dart';
import '../../../core/design_system/shape.dart';
import '../../../core/design_system/spacing.dart';

/// The loan as a card in its colour: the name typed straight onto it, the
/// amount borrowed large and what is still owed, each opening the
/// calculator, and three blocks along the bottom for the rate, the months
/// and the day it is paid.
class LoanCard extends StatelessWidget {
  const LoanCard({
    super.key,
    required this.color,
    required this.name,
    required this.principal,
    required this.owed,
    required this.rate,
    required this.months,
    required this.day,
    required this.onPrincipal,
    required this.onOwed,
    required this.onRate,
    required this.onMonths,
    required this.onDay,
  });

  final Color color;
  final TextEditingController name;
  final String principal;
  final String owed;
  final String rate;
  final String months;
  final String day;
  final VoidCallback onPrincipal;
  final VoidCallback onOwed;
  final VoidCallback onRate;
  final VoidCallback onMonths;
  final VoidCallback onDay;

  @override
  Widget build(BuildContext context) {
    final ink = deepOf(color);
    return Container(
      padding: const EdgeInsets.fromLTRB(
        Space.s4,
        Space.s2,
        Space.s4,
        Space.s4,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.largeIncreased),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [tintOf(color, 0.4), tintOf(color, 0.2)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SquareIcon(Glyph.loan, color, size: 36),
              const SizedBox(width: Space.s2),
              Expanded(
                child: TextField(
                  controller: name,
                  style: const TextStyle(
                    fontSize: TextSize.heading,
                    fontWeight: FontWeight.w800,
                  ),
                  decoration: const InputDecoration(
                    hintText: '貸款名稱，例如房貸',
                    hintStyle: TextStyle(color: Hue.faint),
                    isDense: true,
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: Space.s2),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.s1),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                flex: 3,
                child: LoanFigure(
                  label: '借了多少',
                  value: principal,
                  size: 30,
                  ink: ink,
                  onTap: onPrincipal,
                ),
              ),
              const SizedBox(width: Space.s2),
              Expanded(
                flex: 2,
                child: LoanFigure(
                  label: '目前尚欠',
                  value: owed,
                  size: 18,
                  ink: ink,
                  end: true,
                  onTap: onOwed,
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.s2),
          Row(
            children: [
              for (final (i, (label, value, onTap)) in [
                ('年利率', rate, onRate),
                ('期數', months, onMonths),
                ('每月扣款', day, onDay),
              ].indexed) ...[
                if (i > 0) const SizedBox(width: Space.s2),
                Expanded(
                  child: LoanBlock(
                    label: label,
                    value: value,
                    ink: ink,
                    onTap: onTap,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// A figure on the loan's card, its label over it, tapped to change.
class LoanFigure extends StatelessWidget {
  const LoanFigure({
    super.key,
    required this.label,
    required this.value,
    required this.size,
    required this.ink,
    required this.onTap,
    this.end = false,
  });

  final String label;
  final String value;
  final double size;
  final Color ink;
  final VoidCallback onTap;
  final bool end;

  @override
  Widget build(BuildContext context) {
    return TapArea(
      label: '$label $value',
      onTap: onTap,
      child: Container(
        width: double.infinity,
        alignment: end ? Alignment.centerRight : Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(vertical: Space.s1),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: end
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: TextSize.small,
                fontWeight: FontWeight.w700,
                color: ink,
              ),
            ),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: end ? Alignment.centerRight : Alignment.centerLeft,
              child: Text(
                value,
                style: TextStyle(fontSize: size, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One of the three blocks along the bottom of the loan's card.
class LoanBlock extends StatelessWidget {
  const LoanBlock({
    super.key,
    required this.label,
    required this.value,
    required this.ink,
    required this.onTap,
  });

  final String label;
  final String value;
  final Color ink;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Hue.glass,
      borderRadius: BorderRadius.circular(Radii.large),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.large),
        onTap: onTap,
        child: Semantics(
          button: true,
          label: '$label $value',
          excludeSemantics: true,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Space.s2,
                vertical: Space.s2,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    style: TextStyle(fontSize: TextSize.caption, color: ink),
                  ),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      value,
                      style: const TextStyle(
                        fontSize: TextSize.title,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// What the loan costs as two blocks: a month's payment, and the
/// interest over the whole term.
class LoanEstimate extends StatelessWidget {
  const LoanEstimate({
    super.key,
    required this.ledger,
    required this.plan,
    required this.repay,
    required this.color,
  });

  final Ledger ledger;
  final LoanPlan? plan;
  final LoanRepay repay;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final plan = this.plan;
    String money(int v) => ledger.orDots(groupDigits(v));
    if (plan == null) {
      return ColorCard(
        color: Hue.faint,
        amount: 0.22,
        radius: Radii.largeIncreased,
        padding: const EdgeInsets.symmetric(
          horizontal: Space.s4,
          vertical: Space.s4,
        ),
        child: const Row(
          children: [
            GlyphIcon(Glyph.calculator, size: 22, color: Hue.muted),
            SizedBox(width: Space.s2),
            Expanded(
              child: Text(
                '填好本金、利率、期數就會試算',
                style: TextStyle(fontSize: TextSize.body, color: Hue.muted),
              ),
            ),
          ],
        ),
      );
    }
    Widget block(
      Glyph glyph,
      Color tone,
      String label,
      String value,
      String sub,
    ) => Expanded(
      child: ColorCard(
        color: tone,
        amount: 0.2,
        radius: Radii.largeIncreased,
        padding: const EdgeInsets.fromLTRB(
          Space.s3,
          Space.s3,
          Space.s3,
          Space.s3,
        ),
        child: Row(
          children: [
            GlyphIcon(glyph, size: 22, color: tone),
            const SizedBox(width: Space.s2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: TextSize.caption,
                      fontWeight: FontWeight.w700,
                      color: deepOf(tone),
                    ),
                  ),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      value,
                      style: const TextStyle(
                        fontSize: TextSize.large,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (sub.isNotEmpty)
                    Text(
                      sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: mutedSmall,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    return Row(
      children: [
        block(
          Glyph.cash,
          Hue.accent,
          switch (repay) {
            LoanRepay.even => '每月繳',
            LoanRepay.principal => '第一個月',
            LoanRepay.interest => '每月利息',
          },
          money(plan.first),
          switch (repay) {
            LoanRepay.even => '',
            LoanRepay.principal => '最後 ${money(plan.last)}',
            LoanRepay.interest => '到期還本金',
          },
        ),
        const SizedBox(width: Space.s2),
        block(Glyph.coins, color, '總利息', money(plan.interest), ''),
      ],
    );
  }
}
