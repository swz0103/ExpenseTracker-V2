import 'package:flutter/material.dart';

import '../../../../../design_system/display/amount.dart';
import '../../../../../design_system/display/status.dart';
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
    final whole = ledger.budgets.forCategory(allSpending);
    final status = limit == 0
        ? null
        : budgetStatus(
            spent: spent,
            limit: limit,
            warningPercent: whole.warning,
          );
    final used = limit <= 0 ? 0 : percent(spent, limit);
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
      label: status == null
          ? '預算，本月花了 ${ledger.money(spent)}'
          : '預算，本月${budgetLead(status)} ${ledger.money(budgetFigure(status))}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _budgetHead(
            status == null ? '本月花了' : '本月${budgetLead(status)}',
            status == null || status is BudgetWithin
                ? null
                : budgetLook(status),
          ),
          const SizedBox(height: Space.s2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              ledger.money(status == null ? spent : budgetFigure(status)),
              style: const TextStyle(
                fontSize: TextSize.large,
                fontWeight: FontWeight.w800,
                height: 1.15,
                color: AppColors.ink,
              ),
            ),
          ),
          const SizedBox(height: Space.s2),
          if (status == null)
            const OneLine('設定預算 ›', style: accentSmall)
          else
            _tenths(current ? (gone * 10 / days).ceil() : 10, current, used),
        ],
      ),
    );
  }

  /// The budget's icon and [title], 本月剩, 本月超支 or 本月花了, with the
  /// badge of [alert] (快用完 or 超支) when there is one.
  Widget _budgetHead(String title, StatusLook? alert) => Row(
    children: [
      const SquareIcon(Glyph.budget, ToolColors.budgets, size: 28),
      const SizedBox(width: Space.s2),
      Expanded(
        child: OneLine(
          title,
          style: TextStyle(
            fontSize: TextSize.small,
            fontWeight: FontWeight.w800,
            color: deepOf(ToolColors.budgets),
          ),
        ),
      ),
      if (alert != null) StatusBadge(alert),
    ],
  );

  /// Ten segments for the month, [passed] of them filled (the last one
  /// today's when [current]), and the share of the budget [used] at their
  /// end.
  Widget _tenths(int passed, bool current, int used) => Row(
    children: [
      Expanded(
        child: DayBar(passed: passed, days: 10, today: current, height: 10),
      ),
      const SizedBox(width: Space.s2),
      Text('$used%', style: mutedCaption),
    ],
  );

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
      _ when due.isNotEmpty => (
        '已到期 ${countOf(due.length, CountUnit.entries)}',
        AppColors.negative,
      ),
      0 => (Words.today, AppColors.negative),
      final n => ('${countOf(n, CountUnit.days)}後', AppColors.ink),
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
