import 'package:flutter/material.dart';

import '../../../../core/design_system/glyphs.dart';
import '../../../../core/design_system/theme.dart';
import '../../../../core/design_system/design_system.dart';
import '../../../../core/ledger/ledger.dart';
import '../../../../core/widgets/entry_tile.dart';
import '../../../../core/navigation/nav.dart';
import '../../../../core/widgets/shown_amounts.dart';
import '../../../../core/design_system/spacing.dart';
import '../../../../core/design_system/shape.dart';
import '../../../../core/formatting/words.dart';

/// 預算 and 即將扣款 side by side: what is left of the month's limit, and
/// what falls due.
class PlanSection extends StatelessWidget {
  const PlanSection({
    super.key,
    required this.ledger,
    required this.nav,
    required this.month,
  });

  final Ledger ledger;
  final Nav nav;
  final (int, int) month;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      // Only what it shows: a change elsewhere leaves it as it is.
      listenable: ledger.watch(const {
        Topic.budgets,
        Topic.recurring,
        Topic.entries,
      }),
      builder: (context, _) => CardRow([_budgetTile(), _dueTile()]),
    );
  }

  /// 預算 as on its own page, made small: what is left of the month's
  /// limit, what is spent of it, and a segment a day, the days gone
  /// filled. Every line stays on one line. Without a total budget, what
  /// the month has cost and 設定預算.
  Widget _budgetTile() {
    final (year, m) = month;
    final spent = ledger.reportService.expense(year, m);
    final limit = ledger.budgetService.allowance(
      ledger.budgets.forCategory(allSpending),
      year,
      m,
    );
    final (gone, days) = ledger.budgetService.daysGone(year, m);
    final today = ledger.today;
    final current = today.year == year && today.month == m;
    final left = limit - spent;
    final used = limit <= 0 ? 0 : (spent * 100 / limit).round();
    const muted = mutedCaption;
    return ColorCard(
      color: ToolColors.budgets,
      radius: Radii.largeIncreased,
      padding: const EdgeInsets.fromLTRB(
        Space.s4,
        Space.s3,
        Space.s4,
        Space.s3,
      ),
      onTap: () => nav.open(AppRoutes.budgets),
      label: limit == 0
          ? '預算，本月花了 ${ledger.money(spent)}'
          : '預算，本月剩 ${ledger.money(left)}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const SquareIcon(Glyph.budget, ToolColors.budgets, size: 28),
              const SizedBox(width: Space.s2),
              Expanded(
                child: OneLine(
                  limit == 0 ? '本月花了' : '本月剩',
                  style: TextStyle(
                    fontSize: TextSize.small,
                    fontWeight: FontWeight.w800,
                    color: deepOf(ToolColors.budgets),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.s2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              ledger.money(limit == 0 ? spent : left),
              style: TextStyle(
                fontSize: TextSize.large,
                fontWeight: FontWeight.w800,
                height: 1.15,
                color: limit == 0 ? AppColors.ink : AppColors.ofBalance(left),
              ),
            ),
          ),
          const SizedBox(height: Space.s2),
          if (limit == 0)
            const OneLine('設定預算 ›', style: accentSmall)
          else
            // Ten segments for the month, as many filled as tenths gone,
            // and the share of the budget spent at their end.
            Row(
              children: [
                Expanded(
                  child: DayBar(
                    passed: current ? (gone * 10 / days).ceil() : 10,
                    days: 10,
                    today: current,
                    height: 10,
                  ),
                ),
                const SizedBox(width: Space.s2),
                Text('$used%', style: muted),
              ],
            ),
        ],
      ),
    );
  }

  /// 即將扣款 as a countdown: how many days until the next item falls
  /// due (今天, or 已到期 in red for one not yet booked), and under it
  /// that item's name and amount; nothing more.
  Widget _dueTile() {
    final due = ledger.recurringService.due;
    final items = [...due, ...ledger.recurringService.upcoming];
    final next = items.isEmpty ? null : items.first;
    final day = next == null ? null : ledger.recurringService.nextDate(next);
    final today = ledger.today;
    final until = day?.difference(today).inDays;
    final (String figure, Color tone) = switch (until) {
      null => ('—', AppColors.ink),
      _ when due.isNotEmpty => ('已到期 ${due.length} 筆', AppColors.negative),
      0 => (Words.today, AppColors.negative),
      final n => ('$n 天後', AppColors.ink),
    };
    return ColorCard(
      color: ToolColors.recurring,
      radius: Radii.largeIncreased,
      padding: const EdgeInsets.fromLTRB(
        Space.s4,
        Space.s3,
        Space.s4,
        Space.s3,
      ),
      onTap: () => nav.open(AppRoutes.recurring),
      label: '即將扣款，$figure',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const SquareIcon(
                Glyph.cycleCalendar,
                ToolColors.recurring,
                size: 28,
              ),
              const SizedBox(width: Space.s2),
              Expanded(
                child: OneLine(
                  '即將扣款',
                  style: TextStyle(
                    fontSize: TextSize.small,
                    fontWeight: FontWeight.w800,
                    color: deepOf(ToolColors.recurring),
                  ),
                ),
              ),
              const GlyphIcon(Glyph.next, size: 16, color: AppColors.muted),
            ],
          ),
          const SizedBox(height: Space.s2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              figure,
              style: TextStyle(
                fontSize: TextSize.large,
                fontWeight: FontWeight.w800,
                height: 1.15,
                color: tone,
              ),
            ),
          ),
          const SizedBox(height: Space.half),
          OneLine(
            next == null
                ? '沒有待扣款項目'
                : '${next.name} ${ledger.orDots(recurringAmount(ledger, next))}',
            style: const TextStyle(
              fontSize: TextSize.small,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
