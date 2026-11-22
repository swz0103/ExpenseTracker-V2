import 'package:flutter/material.dart';

import '../../../../design_system/display/amount.dart';
import '../../../core/design_system/glyphs.dart';
import '../../../core/widgets/icons.dart';
import '../../../core/design_system/theme.dart';
import '../../../core/design_system/design_system.dart';
import '../../../core/ledger/ledger.dart';
import '../forms/budget_editor.dart';
import '../model/budget_month.dart';
import '../../../core/navigation/nav.dart';
import '../../../core/widgets/shown_amounts.dart';
import '../../../core/design_system/shape.dart';
import '../../../core/design_system/spacing.dart';
import '../../../core/formatting/words.dart';

part 'budgets_pace.dart';
part 'budgets_month_picker.dart';

/// The colour of 預算管理, as on 更多.
const _budgetColor = Palette.green;

/// Gold for a budget nearly used up.
const _nearColor = Palette.gold;

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

  late final _months = BudgetMonths(
    ledger.reportService,
    today: () => ledger.today,
  );

  YearMonth get _now => _months.now;

  YearMonth get _first => _months.first;

  void _step(int by) {
    final next = _months.step(_month, by);
    if (next != null) setState(() => _month = next);
  }

  Future<void> _edit(String category) =>
      editBudget(context, ledger, ledger.budgets.forCategory(category));

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

  /// The month's main card, or what to do when it has no budget; swiped
  /// sideways, it goes to the month before or after.
  Widget _monthCard(
    BudgetMonth shown, {
    required int year,
    required int month,
    required bool current,
  }) {
    final spent = shown.spent;
    final total = shown.total;
    final whole = shown.whole;
    return GestureDetector(
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
              onSet: () => _edit(allSpending),
            )
          : _Main(
              ledger: ledger,
              year: year,
              month: month,
              current: current,
              spent: spent,
              total: total,
              whole: whole,
              onEdit: () => _edit(allSpending),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      // Spending and budgets only: a price or a card change leaves it.
      listenable: ledger.watch(const {
        Topic.entries,
        Topic.budgets,
        Topic.categories,
      }),
      builder: (context, _) {
        final (year, month) = _month;
        final shown = budgetMonthOf(ledger, _month);
        final spent = shown.spent;
        final total = shown.total;
        final current = _month == _now;
        return HeadedList(
          padding: const EdgeInsets.fromLTRB(Space.s5, 0, Space.s5, Space.s8),
          header: CenterHeader('預算管理', onBack: widget.nav.back),
          children: [
            _MonthRow(
              month: month,
              current: current,
              canBack: _months.canGoBack(_month),
              onPick: _pickMonth,
              onBack: () => _step(-1),
              onNext: () => _step(1),
              onToday: () => setState(() => _month = _now),
            ),
            const SizedBox(height: Space.s2),
            _monthCard(shown, year: year, month: month, current: current),
            if (total > 0) ...[
              const SizedBox(height: Space.s2),
              _Pace(
                ledger: ledger,
                year: year,
                month: month,
                current: current,
                spent: spent,
                total: total,
              ),
            ],
            _LimitsHeading(month: month, current: current),
            CardGrid(gap: 10, [
              for (final line in shown.lines)
                _Limit(
                  ledger: ledger,
                  budget: line.budget,
                  used: line.spent,
                  limit: line.allowance,
                  onTap: () => _edit(line.budget.category),
                ),
              _AddLimitCard(onTap: _addLimit),
            ]),
          ],
        );
      },
    );
  }
}

/// The heading over the allowances: 分類與標籤額度, and on the right how
/// they are ordered this month or which month they are.
class _LimitsHeading extends StatelessWidget {
  const _LimitsHeading({required this.month, required this.current});

  final int month;

  /// Whether [month] is this month.
  final bool current;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(Space.s1, Space.s6, Space.s1, Space.s3),
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
  );
}

/// The last square of the allowances: tapped, it sets one for another
/// category or tag.
class _AddLimitCard extends StatelessWidget {
  const _AddLimitCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ColorCard(
    color: AppColors.faint,
    amount: 0.22,
    onTap: onTap,
    label: '為分類或標籤設定額度',
    padding: const EdgeInsets.symmetric(vertical: Space.s6),
    child: const Column(
      children: [
        GlyphIcon(Glyph.add, size: 24, color: AppColors.accent),
        SizedBox(height: Space.s2),
        Text(
          '分類或標籤',
          style: TextStyle(
            fontSize: TextSize.body,
            fontWeight: FontWeight.w800,
            color: AppColors.accent,
          ),
        ),
      ],
    ),
  );
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
      padding: const EdgeInsets.only(left: Space.s2),
      child: Material(
        color: onTap == null ? AppColors.paper : AppColors.surface,
        shape: const CircleBorder(),
        child: IconButton(
          tooltip: label,
          onPressed: onTap,
          icon: GlyphIcon(
            glyph,
            size: 20,
            color: onTap == null ? AppColors.faint : AppColors.ink,
          ),
        ),
      ),
    );
    return Row(
      children: [
        ReadAsButton(
          label: '$month 月，選月份',
          onTap: onPick,
          child: InkWell(
            onTap: onPick,
            borderRadius: BorderRadius.circular(Radii.medium),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                vertical: Space.s1,
                horizontal: Space.s1,
              ),
              child: Row(
                children: [
                  Text(
                    '$month 月',
                    style: const TextStyle(
                      fontSize: TextSize.big,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: Space.s2),
                  Transform.rotate(
                    angle: 1.5708,
                    child: const GlyphIcon(
                      Glyph.next,
                      size: 16,
                      color: AppColors.muted,
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
              AppColors.accent,
              fill: AppColors.selected,
              minimumSize: Size(0, 44),
              radius: Radii.largeIncreased,
            ),
            child: const Text(
              '回到本月',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        round(Glyph.back, Words.previousMonth, canBack ? onBack : null),
        round(Glyph.next, Words.nextMonth, current ? null : onNext),
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
    final (passed, days) = ledger.budgetService.daysGone(year, month);
    final next = month == 12 ? 1 : month + 1;
    return HeroCard(
      padding: const EdgeInsets.fromLTRB(
        Space.s4,
        Space.s4,
        Space.s3,
        Space.s4,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _head(left),
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
            style: mutedBody,
          ),
          const SizedBox(height: Space.s2),
          DayBar(passed: current ? passed : days, days: days, today: current),
          const SizedBox(height: Space.s2),
          if (current)
            _dayMarks(passed, days)
          else if (whole.carry && left > 0)
            Text(
              '剩下的 ${ledger.orDots(groupDigits(left))} 已加到 $next 月',
              style: mutedSmall,
            ),
        ],
      ),
    );
  }

  /// 剩 or 超支 over what is left, and the button to change the total.
  Widget _head(int left) {
    final over = left < 0;
    const ink = AppColors.accent;
    return Row(
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
                  color: over ? AppColors.negative : ink,
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
                    color: over ? AppColors.negative : AppColors.ink,
                  ),
                ),
              ),
            ],
          ),
        ),
        Material(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(Radii.large),
          child: IconButton(
            tooltip: '改總預算',
            onPressed: onEdit,
            icon: const GlyphIcon(
              Glyph.edit,
              size: 18,
              color: AppColors.accent,
            ),
          ),
        ),
      ],
    );
  }

  /// The first day, today and the last day under this month's bar.
  Widget _dayMarks(int passed, int days) {
    return Row(
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
      padding: const EdgeInsets.fromLTRB(
        Space.s4,
        Space.s3,
        Space.s3,
        Space.s3,
      ),
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
                    color: AppColors.accent,
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
          const SizedBox(width: Space.s2),
          FilledButton(
            onPressed: onSet,
            style: solidButton(
              _budgetColor,
              minimumSize: Size(0, 48),
              radius: Radii.large,
              padding: const EdgeInsets.symmetric(horizontal: Space.s4),
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

/// [month] of [ledger]'s budgets as the screens show it, from the parts
/// the model reads (docs/adr/0013-models-take-what-they-use.md).
BudgetMonth budgetMonthOf(Ledger ledger, YearMonth month) => BudgetMonth.of(
  month,
  reports: ledger.reportService,
  budgets: ledger.budgets,
  service: ledger.budgetService,
);
