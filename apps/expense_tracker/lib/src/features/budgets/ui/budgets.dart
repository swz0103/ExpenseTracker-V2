import 'package:flutter/material.dart';

import '../../../core/text/figures.dart';
import '../../../core/look/glyphs.dart';
import '../../../core/ui/icons.dart';
import '../../../core/look/theme.dart';
import '../../../core/look/widgets.dart';
import '../../../core/ledger/ledger.dart';
import '../compose/budget_editor.dart';
import '../model/budget_month.dart';
import '../../../core/nav.dart';
import '../../../core/ui/shown_amounts.dart';
import '../../../core/look/shape.dart';
import '../../../core/look/spacing.dart';

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

  late final _months = BudgetMonths(ledger);

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
        final shown = BudgetMonth.of(ledger, _month);
        final spent = shown.spent;
        final whole = shown.whole;
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
            ),
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
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.s1,
                Space.s6,
                Space.s1,
                Space.s3,
              ),
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
              for (final line in shown.lines)
                _Limit(
                  ledger: ledger,
                  budget: line.budget,
                  used: line.spent,
                  limit: line.allowance,
                  onTap: () => _edit(line.budget.category),
                ),
              ColorCard(
                color: Hue.faint,
                amount: 0.22,
                onTap: _addLimit,
                label: '為分類或標籤設定額度',
                padding: const EdgeInsets.symmetric(vertical: Space.s6),
                child: const Column(
                  children: [
                    GlyphIcon(Glyph.add, size: 24, color: Hue.accent),
                    SizedBox(height: Space.s2),
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
      padding: const EdgeInsets.only(left: Space.s2),
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
              radius: Radii.largeIncreased,
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
    final (passed, days) = ledger.budgetService.daysGone(year, month);
    final over = left < 0;
    final ink = Hue.accent;
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
                borderRadius: BorderRadius.circular(Radii.large),
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
          const SizedBox(height: Space.s2),
          DayBar(passed: current ? passed : days, days: days, today: current),
          const SizedBox(height: Space.s2),
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
          const SizedBox(width: Space.s2),
          FilledButton(
            onPressed: onSet,
            style: solidButton(
              _budgetHue,
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
