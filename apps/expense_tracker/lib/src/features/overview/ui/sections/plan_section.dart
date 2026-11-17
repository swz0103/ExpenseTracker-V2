import 'package:flutter/material.dart';

import '../../../../core/look/glyphs.dart';
import '../../../../core/look/theme.dart';
import '../../../../core/look/widgets.dart';
import '../../../../core/ledger/ledger.dart';
import '../../../../core/ui/entry_tile.dart';
import '../../../../core/nav.dart';
import '../../../../core/ui/shown_amounts.dart';

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
      listenable: ledger,
      builder: (context, _) => CardRow([_budgetTile(), _dueTile()]),
    );
  }

  /// 預算 as on its own page, made small: what is left of the month's
  /// limit, what is spent of it, and a segment a day, the days gone
  /// filled. Every line stays on one line. Without a total budget, what
  /// the month has cost and 設定預算.
  Widget _budgetTile() {
    final (year, m) = month;
    final spent = ledger.expense(year, m);
    final limit = ledger.allowance(
      ledger.budgets.forCategory(allSpending),
      year,
      m,
    );
    final (gone, days) = ledger.daysGone(year, m);
    final today = ledger.today;
    final current = today.year == year && today.month == m;
    final left = limit - spent;
    final used = limit <= 0 ? 0 : (spent * 100 / limit).round();
    const muted = TextStyle(fontSize: TextSize.caption, color: Hue.muted);
    return ColorCard(
      color: ToolHue.budgets,
      radius: 20,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      onTap: () => nav.open(Pages.budgets),
      label: limit == 0
          ? '預算，本月花了 ${ledger.money(spent)}'
          : '預算，本月剩 ${ledger.money(left)}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const SquareIcon(Glyph.budget, ToolHue.budgets, size: 28),
              const SizedBox(width: 8),
              Expanded(
                child: OneLine(
                  limit == 0 ? '本月花了' : '本月剩',
                  style: TextStyle(
                    fontSize: TextSize.small,
                    fontWeight: FontWeight.w800,
                    color: deepOf(ToolHue.budgets),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              ledger.money(limit == 0 ? spent : left),
              style: TextStyle(
                fontSize: TextSize.large,
                fontWeight: FontWeight.w800,
                height: 1.15,
                color: limit != 0 && left < 0 ? Hue.negative : Hue.ink,
              ),
            ),
          ),
          const SizedBox(height: 6),
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
                const SizedBox(width: 8),
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
    final due = ledger.due;
    final items = [...due, ...ledger.upcoming];
    final next = items.isEmpty ? null : items.first;
    final day = next == null ? null : ledger.nextDate(next);
    final today = ledger.today;
    final until = day?.difference(today).inDays;
    final (String figure, Color tone) = switch (until) {
      null => ('—', Hue.ink),
      _ when due.isNotEmpty => ('已到期 ${due.length} 筆', Hue.negative),
      0 => ('今天', Hue.negative),
      final n => ('$n 天後', Hue.ink),
    };
    return ColorCard(
      color: ToolHue.recurring,
      radius: 20,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      onTap: () => nav.open(Pages.recurring),
      label: '即將扣款，$figure',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const SquareIcon(
                Glyph.cycleCalendar,
                ToolHue.recurring,
                size: 28,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OneLine(
                  '即將扣款',
                  style: TextStyle(
                    fontSize: TextSize.small,
                    fontWeight: FontWeight.w800,
                    color: deepOf(ToolHue.recurring),
                  ),
                ),
              ),
              const GlyphIcon(Glyph.next, size: 16, color: Hue.muted),
            ],
          ),
          const SizedBox(height: 6),
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
          const SizedBox(height: 2),
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
