import 'package:flutter/material.dart';

import '../../../core/ui/calculator.dart';
import '../../../core/text/figures.dart';
import '../../../core/look/glyphs.dart';
import '../../../core/ui/icons.dart';
import '../../../core/look/theme.dart';
import '../../../core/look/widgets.dart';
import '../../../core/ledger/ledger.dart';
import '../../../core/nav.dart';
import '../../../core/ui/shown_amounts.dart';

part 'budgets_pace.dart';
part 'budgets_month_picker.dart';

/// The colour of 預算管理, as on 更多.
const _budgetHue = Palette.green;

/// Gold for a budget nearly used up.
const _nearHue = Palette.gold;

/// 預算管理: the month in big words (tapped to pick another), the main
/// card with what is left, what is used of the total and a bar of the
/// month's days (swiped to change month), what can be spent a day and
/// where the month is heading, and each category's and tag's allowance as
/// squares, overspent and nearly used up first.
class BudgetsPage extends StatefulWidget {
  const BudgetsPage({super.key, required this.ledger, required this.nav});

  final Ledger ledger;
  final Nav nav;

  @override
  State<BudgetsPage> createState() => _BudgetsPageState();
}

class _BudgetsPageState extends State<BudgetsPage> {
  late var _month = _now;

  Ledger get ledger => widget.ledger;

  (int, int) get _now => (ledger.today.year, ledger.today.month);

  (int, int) get _first {
    final first = ledger.firstDay;
    return (first.year, first.month);
  }

  static int _key((int, int) m) => m.$1 * 12 + m.$2 - 1;

  static (int, int) _of(int key) => (key ~/ 12, key % 12 + 1);

  void _step(int by) {
    final next = _key(_month) + by;
    if (next > _key(_now) || next < _key(_first)) return;
    setState(() => _month = _of(next));
  }

  Future<void> _edit(String category) => showSheet<void>(
    context,
    (_) => _BudgetEditor(ledger: ledger, budget: ledger.budgetFor(category)),
  );

  Future<void> _addLimit() async {
    final picked = await showSheet<String>(
      context,
      (_) => _AddLimit(ledger: ledger),
    );
    if (picked != null && mounted) await _edit(picked);
  }

  Future<void> _pickMonth() async {
    final picked = await showSheet<(int, int)>(
      context,
      (_) => _MonthPicker(
        ledger: ledger,
        chosen: _month,
        first: _first,
        last: _now,
      ),
    );
    if (picked != null && mounted) setState(() => _month = picked);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      // Spending and budgets only: a price or a card change leaves it.
      listenable: ledger.watch(const {
        Area.entries,
        Area.budgets,
        Area.categories,
      }),
      builder: (context, _) {
        final (year, month) = _month;
        final spent = ledger.expense(year, month);
        final whole = ledger.budgetFor(Ledger.allSpending);
        final total = ledger.allowance(whole, year, month);
        final rows = [
          for (final b in ledger.budgets)
            if (b.category != Ledger.allSpending && b.limit > 0)
              (
                b,
                ledger.spentAgainst(b, year, month),
                ledger.allowance(b, year, month),
              ),
        ];
        // Overspent first, then by the share used.
        rows.sort((a, b) {
          double share((Budget, int, int) row) =>
              row.$3 == 0 ? 0 : row.$2 / row.$3;
          return share(b).compareTo(share(a));
        });
        final current = _month == _now;
        return HeadedList(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
          header: CenterHeader('預算管理', onBack: widget.nav.back),
          children: [
            _MonthRow(
              month: month,
              current: current,
              canBack: _key(_month) > _key(_first),
              onPick: _pickMonth,
              onBack: () => _step(-1),
              onNext: () => _step(1),
              onToday: () => setState(() => _month = _now),
            ),
            const SizedBox(height: 8),
            GestureDetector(
              onHorizontalDragEnd: (d) {
                final v = d.primaryVelocity ?? 0;
                if (v.abs() > 200) _step(v < 0 ? 1 : -1);
              },
              child: total == 0
                  ? _NoBudget(
                      ledger: ledger,
                      spent: spent,
                      month: month,
                      current: current,
                      onSet: () => _edit(Ledger.allSpending),
                    )
                  : _Main(
                      ledger: ledger,
                      year: year,
                      month: month,
                      current: current,
                      spent: spent,
                      total: total,
                      whole: whole,
                      onEdit: () => _edit(Ledger.allSpending),
                    ),
            ),
            if (total > 0) ...[
              const SizedBox(height: 10),
              _Pace(
                ledger: ledger,
                year: year,
                month: month,
                current: current,
                spent: spent,
                total: total,
              ),
            ],
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 22, 4, 12),
              child: Row(
                children: [
                  const Expanded(
                    child: OneLine(
                      '分類與標籤額度',
                      style: TextStyle(
                        fontSize: TextSize.heading,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(current ? '超支、快用完的排前面' : '$month 月', style: mutedSmall),
                ],
              ),
            ),
            CardGrid(gap: 10, [
              for (final (budget, used, allowed) in rows)
                _Limit(
                  ledger: ledger,
                  budget: budget,
                  used: used,
                  limit: allowed,
                  onTap: () => _edit(budget.category),
                ),
              ColorCard(
                color: Hue.faint,
                amount: 0.22,
                onTap: _addLimit,
                label: '為分類或標籤設定額度',
                padding: const EdgeInsets.symmetric(vertical: 22),
                child: const Column(
                  children: [
                    GlyphIcon(Glyph.add, size: 24, color: Hue.accent),
                    SizedBox(height: 8),
                    Text(
                      '分類或標籤',
                      style: TextStyle(
                        fontSize: TextSize.body,
                        fontWeight: FontWeight.w800,
                        color: Hue.accent,
                      ),
                    ),
                  ],
                ),
              ),
            ]),
          ],
        );
      },
    );
  }
}

/// 「11 月 ⌄」 big on the left, tapped to pick a month; 回到本月 when
/// another month is shown, and two round buttons to step.
class _MonthRow extends StatelessWidget {
  const _MonthRow({
    required this.month,
    required this.current,
    required this.canBack,
    required this.onPick,
    required this.onBack,
    required this.onNext,
    required this.onToday,
  });

  final int month;
  final bool current;
  final bool canBack;
  final VoidCallback onPick;
  final VoidCallback onBack;
  final VoidCallback onNext;
  final VoidCallback onToday;

  @override
  Widget build(BuildContext context) {
    Widget round(Glyph glyph, String label, VoidCallback? onTap) => Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Material(
        color: onTap == null ? Hue.paper : Hue.surface,
        shape: const CircleBorder(),
        child: IconButton(
          tooltip: label,
          onPressed: onTap,
          icon: GlyphIcon(
            glyph,
            size: 20,
            color: onTap == null ? Hue.faint : Hue.ink,
          ),
        ),
      ),
    );
    return Row(
      children: [
        Semantics(
          button: true,
          label: '$month 月，選月份',
          excludeSemantics: true,
          child: InkWell(
            onTap: onPick,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
              child: Row(
                children: [
                  Text(
                    '$month 月',
                    style: const TextStyle(
                      fontSize: TextSize.big,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Transform.rotate(
                    angle: 1.5708,
                    child: const GlyphIcon(
                      Glyph.next,
                      size: 16,
                      color: Hue.muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const Spacer(),
        if (!current)
          TextButton(
            onPressed: onToday,
            style: wordButton(
              Hue.accent,
              fill: Hue.selected,
              minimumSize: Size(0, 44),
              radius: 22,
            ),
            child: const Text(
              '回到本月',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        round(Glyph.back, '上個月', canBack ? onBack : null),
        round(Glyph.next, '下個月', current ? null : onNext),
      ],
    );
  }
}

/// The main card: what is left, what is used of the total (with what came
/// over from last month), and the month's days as a bar.
class _Main extends StatelessWidget {
  const _Main({
    required this.ledger,
    required this.year,
    required this.month,
    required this.current,
    required this.spent,
    required this.total,
    required this.whole,
    required this.onEdit,
  });

  final Ledger ledger;
  final int year;
  final int month;
  final bool current;
  final int spent;
  final int total;
  final Budget whole;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final left = total - spent;
    final carried = total - whole.limit;
    final (passed, days) = ledger.daysGone(year, month);
    final over = left < 0;
    final ink = Hue.accent;
    final next = month == 12 ? 1 : month + 1;
    return HeroCard(
      padding: const EdgeInsets.fromLTRB(18, 14, 12, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${current ? '本月' : '$month 月'}${over ? '超支' : '剩'}',
                      style: TextStyle(
                        fontSize: TextSize.body,
                        fontWeight: FontWeight.w800,
                        color: over ? Hue.negative : ink,
                      ),
                    ),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        ledger.orDots(groupDigits(left.abs())),
                        style: TextStyle(
                          fontSize: TextSize.big,
                          fontWeight: FontWeight.w800,
                          color: over ? Hue.negative : Hue.ink,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Material(
                color: Hue.white,
                borderRadius: BorderRadius.circular(14),
                child: IconButton(
                  tooltip: '改總預算',
                  onPressed: onEdit,
                  icon: const GlyphIcon(
                    Glyph.edit,
                    size: 18,
                    color: Hue.accent,
                  ),
                ),
              ),
            ],
          ),
          Text.rich(
            TextSpan(
              children: [
                const TextSpan(text: '已用 '),
                TextSpan(
                  text: ledger.orDots(groupDigits(spent)),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                TextSpan(
                  text:
                      ' / 總預算 ${ledger.orDots(groupDigits(total))}'
                      '${carried > 0 ? '（含上月剩 ${ledger.orDots(groupDigits(carried))}）' : ''}'
                      '${current ? '' : ' · 已結束'}',
                ),
              ],
            ),
            style: const TextStyle(fontSize: TextSize.body, color: Hue.muted),
          ),
          const SizedBox(height: 10),
          _DayBar(passed: current ? passed : days, days: days, today: current),
          const SizedBox(height: 6),
          if (current)
            Row(
              children: [
                Text('$month/1', style: mutedSmall),
                const Spacer(),
                Text(
                  '今天 $month/$passed',
                  style: const TextStyle(
                    fontSize: TextSize.small,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                Text('$month/$days', style: mutedSmall),
              ],
            )
          else if (whole.carry && left > 0)
            Text(
              '剩下的 ${ledger.orDots(groupDigits(left))} 已加到 $next 月',
              style: mutedSmall,
            ),
        ],
      ),
    );
  }
}

/// One segment for each day of the month: the days gone filled, today
/// darker, the rest pale.
class _DayBar extends StatelessWidget {
  const _DayBar({
    required this.passed,
    required this.days,
    required this.today,
  });

  final int passed;
  final int days;
  final bool today;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SizedBox(
        height: 14,
        child: Row(
          children: [
            for (var d = 1; d <= days; d++) ...[
              if (d > 1) const SizedBox(width: 2),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(3),
                    color: d > passed
                        ? Hue.white
                        : today && d == passed
                        ? Hue.ink
                        : Hue.accent,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// No total budget yet: what the month has cost, and 設定預算.
class _NoBudget extends StatelessWidget {
  const _NoBudget({
    required this.ledger,
    required this.spent,
    required this.month,
    required this.current,
    required this.onSet,
  });

  final Ledger ledger;
  final int spent;
  final int month;
  final bool current;
  final VoidCallback onSet;

  @override
  Widget build(BuildContext context) {
    return HeroCard(
      padding: const EdgeInsets.fromLTRB(18, 12, 12, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                OneLine(
                  '${current ? '本月' : '$month 月'}花了',
                  style: const TextStyle(
                    fontSize: TextSize.small,
                    fontWeight: FontWeight.w800,
                    color: Hue.accent,
                  ),
                ),
                OneLine(
                  ledger.orDots(groupDigits(spent)),
                  style: const TextStyle(
                    fontSize: TextSize.figure,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          FilledButton(
            onPressed: onSet,
            style: solidButton(
              _budgetHue,
              minimumSize: Size(0, 48),
              radius: 14,
              padding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            child: const Text(
              '設定預算',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}
