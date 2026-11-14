import 'package:flutter/material.dart';

import '../../../core/ui/calculator.dart';
import '../../../core/look/figures.dart';
import '../../../core/look/glyphs.dart';
import '../../../core/look/icons.dart';
import '../../../core/look/theme.dart';
import '../../../core/look/widgets.dart';
import '../../../core/ledger/ledger.dart';
import '../../../core/nav.dart';

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
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
          children: [
            CenterHeader('預算管理', onBack: widget.nav.back),
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
              const SizedBox(height: 12),
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
                    child: Text(
                      '分類與標籤額度',
                      style: TextStyle(
                        fontSize: 18,
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
                padding: const EdgeInsets.symmetric(vertical: 34),
                child: const Column(
                  children: [
                    GlyphIcon(Glyph.add, size: 24, color: Hue.accent),
                    SizedBox(height: 8),
                    Text(
                      '分類或標籤',
                      style: TextStyle(
                        fontSize: 15,
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
                      fontSize: 32,
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
            style: TextButton.styleFrom(
              backgroundColor: Hue.selected,
              foregroundColor: Hue.accent,
              minimumSize: const Size(0, 44),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22),
              ),
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
      padding: const EdgeInsets.fromLTRB(20, 18, 14, 18),
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
                        fontSize: 14,
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
                          fontSize: 44,
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
            style: const TextStyle(fontSize: 14, color: Hue.muted),
          ),
          const SizedBox(height: 14),
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
                    fontSize: 13,
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
        height: 22,
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

/// No total budget yet: what the month has cost, and 設定每月預算.
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
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${current ? '本月' : '$month 月'}花了',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: Hue.accent,
            ),
          ),
          Text(
            ledger.orDots(groupDigits(spent)),
            style: const TextStyle(fontSize: 44, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          PanelButton('設定每月預算', color: _budgetHue, onTap: onSet),
        ],
      ),
    );
  }
}

/// Two white cards: what can be spent a day and where the month is
/// heading; for a past month, what was spent a day and against the
/// budget.
class _Pace extends StatelessWidget {
  const _Pace({
    required this.ledger,
    required this.year,
    required this.month,
    required this.current,
    required this.spent,
    required this.total,
  });

  final Ledger ledger;
  final int year;
  final int month;
  final bool current;
  final int spent;
  final int total;

  @override
  Widget build(BuildContext context) {
    final (passed, days) = ledger.daysGone(year, month);
    String money(int v) => ledger.orDots(groupDigits(v));
    if (!current) {
      final saved = total - spent;
      return CardGrid(gap: 10, [
        _Figure(
          glyph: Glyph.cash,
          color: Hue.positive,
          label: '平均每天花',
          value: money(spent ~/ days),
          sub: '$month 月 $days 天',
        ),
        _Figure(
          glyph: Glyph.calendar,
          color: Hue.accent,
          label: '跟預算比',
          value: '${saved >= 0 ? '省' : '超'} ${money(saved.abs())}',
          valueColor: saved >= 0 ? Hue.accent : Hue.negative,
          sub: '用了 ${spent * 100 ~/ total}%',
        ),
      ]);
    }
    final left = total - spent;
    final remaining = days - passed + 1;
    final heading = ledger.forecast(spent, year, month);
    final over = heading > total;
    return CardGrid(gap: 10, [
      _Figure(
        glyph: Glyph.cash,
        color: Hue.positive,
        label: '每天可以花',
        value: left > 0 ? money(left ~/ remaining) : '0',
        sub: '剩 $remaining 天',
      ),
      _Figure(
        glyph: Glyph.calendar,
        color: over ? Hue.negative : Hue.accent,
        label: '月底預估',
        value: passed >= 7 ? money(heading) : '—',
        valueColor: over && passed >= 7 ? Hue.negative : null,
        sub: passed < 7
            ? '第 7 天起估算'
            : over
            ? '會超 ${money(heading - total)}'
            : '約剩 ${money(total - heading)}',
      ),
    ]);
  }
}

/// A white card with a solid icon, a label, a figure and a line.
class _Figure extends StatelessWidget {
  const _Figure({
    required this.glyph,
    required this.color,
    required this.label,
    required this.value,
    required this.sub,
    this.valueColor,
  });

  final Glyph glyph;
  final Color color;
  final String label;
  final String value;
  final String sub;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
      decoration: BoxDecoration(
        color: Hue.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: Hue.cardShadow,
      ),
      child: Row(
        children: [
          SquareIcon(glyph, color, size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Hue.muted,
                  ),
                ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: valueColor ?? color,
                    ),
                  ),
                ),
                Text(sub, style: mutedSmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A category's or tag's allowance as a square: a small ring of the share
/// used around its icon, 超支 or 快用完, its name, what is left or over,
/// and used against the allowance.
class _Limit extends StatelessWidget {
  const _Limit({
    required this.ledger,
    required this.budget,
    required this.used,
    required this.limit,
    required this.onTap,
  });

  final Ledger ledger;
  final Budget budget;
  final int used;
  final int limit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tag = budget.tag != null;
    final category = tag ? null : ledger.category(budget.category);
    final color = category?.color ?? Hue.accent;
    final glyph = tag ? Glyph.tag : iconFor(category!.icon);
    final left = limit - used;
    final over = left < 0;
    final near = !over && limit > 0 && used * 100 >= limit * budget.warning;
    final tone = over ? Hue.negative : (near ? _nearHue : color);
    final share = limit == 0 ? 0.0 : (used / limit).clamp(0.0, 1.0);
    final ink = deepOf(color);
    return ColorCard(
      color: over ? Hue.negative : (near ? _nearHue : color),
      amount: 0.18,
      onTap: onTap,
      label: '${budget.category}，${over ? '超支' : '剩'} ${left.abs()}',
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox.square(
                dimension: 52,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CircularProgressIndicator(
                      value: share,
                      strokeWidth: 5,
                      strokeCap: StrokeCap.round,
                      color: tone,
                      backgroundColor: tintOf(tone, 0.3),
                    ),
                    Center(child: GlyphIcon(glyph, size: 20, color: tone)),
                  ],
                ),
              ),
              const Spacer(),
              if (over || near)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: tone,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    over ? '超支' : '快用完',
                    textScaler: TextScaler.noScaling,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFFFFFFFF),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            budget.category,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: over ? deepOf(Hue.negative) : ink,
            ),
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              '${over ? '超' : '剩'} ${ledger.orDots(groupDigits(left.abs()))}',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: over ? Hue.negative : Hue.ink,
              ),
            ),
          ),
          Text(
            '${ledger.orDots(groupDigits(used))} / '
            '${ledger.orDots(groupDigits(limit))}',
            style: mutedSmall,
          ),
        ],
      ),
    );
  }
}

/// A year of months, each saying how much of its budget was used: red
/// when over, gold from nine in ten.
class _MonthPicker extends StatefulWidget {
  const _MonthPicker({
    required this.ledger,
    required this.chosen,
    required this.first,
    required this.last,
  });

  final Ledger ledger;
  final (int, int) chosen;
  final (int, int) first;
  final (int, int) last;

  @override
  State<_MonthPicker> createState() => _MonthPickerState();
}

class _MonthPickerState extends State<_MonthPicker> {
  late var _year = widget.chosen.$1;

  @override
  Widget build(BuildContext context) {
    final ledger = widget.ledger;
    final whole = ledger.budgetFor(Ledger.allSpending);
    int key((int, int) m) => m.$1 * 12 + m.$2;
    Widget arrow(Glyph glyph, String label, bool on, int by) => Material(
      color: on ? Hue.surface : Hue.paper,
      shape: const CircleBorder(),
      child: IconButton(
        tooltip: label,
        onPressed: on ? () => setState(() => _year += by) : null,
        icon: GlyphIcon(glyph, size: 20, color: on ? Hue.ink : Hue.faint),
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              arrow(Glyph.back, '前一年', _year > widget.first.$1, -1),
              Expanded(
                child: Text(
                  '$_year',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              arrow(Glyph.next, '下一年', _year < widget.last.$1, 1),
            ],
          ),
          const SizedBox(height: 14),
          CardGrid(columns: 4, gap: 8, [
            for (var m = 1; m <= 12; m++)
              () {
                final on =
                    key((_year, m)) >= key(widget.first) &&
                    key((_year, m)) <= key(widget.last);
                final total = ledger.allowance(whole, _year, m);
                final spent = ledger.expense(_year, m);
                final share = total == 0 ? null : spent * 100 ~/ total;
                final chosen = (_year, m) == widget.chosen;
                final tone = share == null
                    ? Hue.muted
                    : share > 100
                    ? Hue.negative
                    : share >= 90
                    ? Hue.goldText
                    : Hue.muted;
                return Semantics(
                  button: true,
                  selected: chosen,
                  enabled: on,
                  label: '$m 月',
                  excludeSemantics: true,
                  child: Material(
                    color: chosen ? Hue.selected : Hue.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: chosen
                          ? const BorderSide(color: Hue.accent, width: 2)
                          : BorderSide.none,
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: on
                          ? () => Navigator.of(context).pop((_year, m))
                          : null,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Column(
                          children: [
                            Text(
                              '$m 月',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                color: on ? Hue.ink : Hue.faint,
                              ),
                            ),
                            Text(
                              !on || share == null
                                  ? ' '
                                  : share > 100
                                  ? '超支'
                                  : '$share%',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: tone,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }(),
          ]),
          const SizedBox(height: 12),
          const Text(
            '每個月下面寫用了幾成；超支紅、九成以上金色',
            textAlign: TextAlign.center,
            style: mutedSmall,
          ),
        ],
      ),
    );
  }
}

/// 幫哪個設額度: the spending categories without one, as squares, and the
/// tags without one, as chips.
class _AddLimit extends StatelessWidget {
  const _AddLimit({required this.ledger});

  final Ledger ledger;

  @override
  Widget build(BuildContext context) {
    final categories = [
      for (final c in ledger.categoriesFor(income: false))
        if (ledger.budgetFor(c.name).limit == 0) c,
    ];
    final tags = [
      for (final tag in ledger.tags)
        if (ledger.budgetFor('#$tag').limit == 0) tag,
    ];
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Center(
            child: Text(
              '幫哪個設額度',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
            ),
          ),
          if (categories.isNotEmpty) ...[
            const RuleHead('分類'),
            CardGrid(columns: 4, gap: 8, [
              for (final c in categories)
                ColorCard(
                  color: shownColor(c.color),
                  radius: 16,
                  label: c.name,
                  onTap: () => Navigator.of(context).pop(c.name),
                  padding: const EdgeInsets.symmetric(
                    vertical: 10,
                    horizontal: 2,
                  ),
                  child: Column(
                    children: [
                      GlyphIcon(
                        iconFor(c.icon),
                        size: 26,
                        color: shownColor(c.color),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        c.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: deepOf(shownColor(c.color)),
                        ),
                      ),
                    ],
                  ),
                ),
            ]),
          ],
          if (tags.isNotEmpty) ...[
            const RuleHead('標籤'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final tag in tags)
                  ActionChip(
                    backgroundColor: Hue.surface,
                    side: BorderSide.none,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    label: Text(
                      '#$tag',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    onPressed: () => Navigator.of(context).pop('#$tag'),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 14),
          const Text(
            '已經設過額度的不會出現在這裡',
            textAlign: TextAlign.center,
            style: mutedSmall,
          ),
        ],
      ),
    );
  }
}

/// A budget's form, the card itself: its icon and name, the monthly
/// allowance in big figures (the calculator beside), this month's use on
/// a bar with the warning line; then the share to warn at, whether what
/// is left carries over, and 儲存. A category's or tag's has a bin.
class _BudgetEditor extends StatefulWidget {
  const _BudgetEditor({required this.ledger, required this.budget});

  final Ledger ledger;
  final Budget budget;

  @override
  State<_BudgetEditor> createState() => _BudgetEditorState();
}

class _BudgetEditorState extends State<_BudgetEditor> {
  late var _limit = widget.budget.limit;
  late var _warning = widget.budget.warning;
  late var _carry = widget.budget.carry;

  static const _shares = [70, 80, 90, 100];

  Future<void> _calculate() async {
    final value = await showCalculator(
      context,
      title: '每月額度',
      initial: _limit,
      color: Hue.accent,
    );
    if (value != null) setState(() => _limit = value);
  }

  @override
  Widget build(BuildContext context) {
    final ledger = widget.ledger;
    final name = widget.budget.category;
    final total = name == Ledger.allSpending;
    final tag = name.startsWith('#');
    final category = total || tag ? null : ledger.category(name);
    final color = category?.color ?? Hue.accent;
    final glyph = total
        ? Glyph.cash
        : tag
        ? Glyph.tag
        : iconFor(category!.icon);
    final today = ledger.today;
    final used = total
        ? ledger.expense(today.year, today.month)
        : ledger.spentAgainst(widget.budget, today.year, today.month);
    final ink = deepOf(color);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(18, 18, 14, 18),
            decoration: BoxDecoration(
              color: tintOf(color, 0.24),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    SquareIcon(glyph, color, size: 52),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            total ? '總預算' : name,
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: ink,
                            ),
                          ),
                          Text(
                            total
                                ? '這個月所有支出'
                                : tag
                                ? '標籤額度'
                                : '分類額度',
                            style: TextStyle(fontSize: 13, color: ink),
                          ),
                        ],
                      ),
                    ),
                    if (!total)
                      Material(
                        color: Hue.white,
                        borderRadius: BorderRadius.circular(14),
                        child: IconButton(
                          tooltip: '移除額度',
                          onPressed: () {
                            ledger.removeBudget(name);
                            Navigator.of(context).pop();
                          },
                          icon: const GlyphIcon(
                            Glyph.trash,
                            size: 18,
                            color: Hue.danger,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  '每月額度',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: ink,
                  ),
                ),
                AmountTap(
                  label: '每月額度 $_limit',
                  onTap: _calculate,
                  child: Text.rich(
                    TextSpan(
                      children: [
                        const TextSpan(
                          text: 'NT\$ ',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        TextSpan(
                          text: groupDigits(_limit),
                          style: const TextStyle(
                            fontSize: 44,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                LayoutBuilder(
                  builder: (context, box) {
                    final share = _limit == 0
                        ? 0.0
                        : (used / _limit).clamp(0.0, 1.0);
                    final line = box.maxWidth * _warning / 100;
                    return SizedBox(
                      height: 18,
                      child: Stack(
                        clipBehavior: Clip.none,
                        alignment: Alignment.centerLeft,
                        children: [
                          Container(
                            height: 10,
                            decoration: BoxDecoration(
                              color: Hue.white,
                              borderRadius: BorderRadius.circular(5),
                            ),
                          ),
                          FractionallySizedBox(
                            widthFactor: share,
                            child: Container(
                              height: 10,
                              decoration: BoxDecoration(
                                color: color,
                                borderRadius: BorderRadius.circular(5),
                              ),
                            ),
                          ),
                          Positioned(
                            left: (line - 1).clamp(0, box.maxWidth - 2),
                            top: 0,
                            bottom: 0,
                            child: Container(width: 2, color: Hue.ink),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text.rich(
                      TextSpan(
                        children: [
                          const TextSpan(text: '這個月已用 '),
                          TextSpan(
                            text: ledger.orDots(groupDigits(used)),
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                      style: TextStyle(fontSize: 13, color: ink),
                    ),
                    const Spacer(),
                    Text(
                      '$_warning% 時提醒',
                      style: TextStyle(fontSize: 13, color: ink),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            '用到幾成時提醒',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final (i, p) in _shares.indexed) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(
                  child: Material(
                    color: p == _warning ? Hue.accent : Hue.surface,
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => setState(() => _warning = p),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 48),
                        child: Center(
                          child: Text(
                            '$p%',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: p == _warning ? Hue.onAccent : Hue.ink,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          ColorCard(
            color: Hue.faint,
            amount: 0.15,
            radius: 18,
            onTap: () => setState(() => _carry = !_carry),
            padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
            child: Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '沒用完的留到下個月',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text('上個月剩的，加到這個月的額度', style: mutedSmall),
                    ],
                  ),
                ),
                TickSwitch(
                  value: _carry,
                  color: Hue.accent,
                  label: '沒用完的留到下個月',
                  onChanged: (on) => setState(() => _carry = on),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          PanelButton(
            '儲存',
            color: Hue.accent,
            onTap: () {
              ledger.setBudget(name, _limit, warning: _warning, carry: _carry);
              Navigator.of(context).pop();
            },
          ),
        ],
      ),
    );
  }
}
